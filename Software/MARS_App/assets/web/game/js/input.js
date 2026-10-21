// Arm input (robot_input.gd). The MARS app sets window.marsInput ~25 times a second:
//   {seq, t, th1..th4 (deg), cuff_mm: [x, y, z], mode, enc_ok}
// Channels (MARS_GUI/kinematics.py):
//   up / down    = th1, the lever angle (90 deg = arm horizontal)
//   left / right = cuff z, along the motor axis (sideways sweep of the hand)
//   reach        = cuff distance from the motor axis
// Steering uses the hand position, so it works even if the elbow and cuff joints move together.
// Each player calibrates once: neutral pose, then range. Also: a touch stick, and keys for testing.
import * as THREE from 'three';
import { clamp, damp } from './util.js';

const CAL_KEY = 'voidwing.arm_cal';
export const NEUTRAL_S = 3.0;
export const RANGE_S = 12.0;
export const DEAD = 0.08;

const DEFAULT_CAL = { x_c: 0, x_lo: -150, x_hi: 150, y_c: 90, y_lo: 70, y_hi: 110, r_lo: 450, r_hi: 750,
  inv_x: false, inv_y: false, done: false };

function norm(v, c, lo, hi) {
  let n = v >= c ? (v - c) / Math.max(hi - c, 1e-3) : (v - c) / Math.max(c - lo, 1e-3);
  n = Math.sign(n) * Math.max(Math.abs(n) - DEAD, 0) / (1 - DEAD);
  return clamp(n, -1, 1);
}

export class RobotInput {
  constructor() {
    this.last = {};
    this.lastMs = -1e9;
    this.seq = -1;
    this.raw = new THREE.Vector3(0, 90, 0); // x = sideways mm, y = th1 deg, z = reach mm
    this.aim = new THREE.Vector2();
    this.reach = 0;
    this.cal = { ...DEFAULT_CAL };
    this.calState = 0; // 0 idle, 1 neutral, 2 range, 3 finished
    this.calT = 0;
    this.acc = new THREE.Vector3();
    this.accN = 0;
    this.mn = new THREE.Vector3();
    this.mx = new THREE.Vector3();
    try {
      const d = JSON.parse(localStorage.getItem(CAL_KEY) || 'null');
      if (d) for (const k in d) if (k in this.cal) this.cal[k] = d[k];
    } catch (_) { /* no storage: calibrate again */ }
  }

  live() { return performance.now() - this.lastMs < 700; }
  encOk() { return !!this.last.enc_ok; }
  mode() { return String(this.last.mode ?? '--'); }

  update(dt) {
    const d = window.marsInput;
    if (d && typeof d === 'object' && d.seq !== this.seq && 'th1' in d) {
      this.seq = d.seq;
      this.last = d;
      this.lastMs = performance.now();
      const c = d.cuff_mm;
      if (Array.isArray(c) && c.length === 3) this.raw.set(+c[2], +d.th1, Math.hypot(+c[0], +c[1]));
      else this.raw.y = +d.th1;
    }
    const cal = this.cal;
    let tx = norm(this.raw.x, cal.x_c, cal.x_lo, cal.x_hi) * (cal.inv_x ? -1 : 1);
    const ty = norm(this.raw.y, cal.y_c, cal.y_lo, cal.y_hi) * (cal.inv_y ? -1 : 1);
    if (!this.encOk()) tx = 0; // without encoders only the lever angle is real
    this.aim.lerp(new THREE.Vector2(tx, ty), damp(12, dt));
    this.reach = this.encOk() ? clamp((this.raw.z - cal.r_lo) / Math.max(cal.r_hi - cal.r_lo, 1e-3), 0, 1) : 0.5;
    this._calibrate(dt);
  }

  beginCalibration() { this.calState = 1; this.calT = 0; this.acc.set(0, 0, 0); this.accN = 0; }
  cancelCalibration() { this.calState = 0; }
  calProgress() {
    if (this.calState === 1) return this.calT / NEUTRAL_S;
    if (this.calState === 2) return this.calT / RANGE_S;
    return this.calState === 3 ? 1 : 0;
  }

  _calibrate(dt) {
    const r = this.raw;
    if (this.calState === 1) {
      if (this.live()) { this.calT += dt; this.acc.add(r); this.accN++; }
      if (this.calT >= NEUTRAL_S && this.accN > 0) {
        const c = this.acc.clone().divideScalar(this.accN);
        this.cal.x_c = c.x;
        this.cal.y_c = c.y;
        this.mn.copy(c);
        this.mx.copy(c);
        this.calState = 2;
        this.calT = 0;
      }
    } else if (this.calState === 2) {
      if (this.live()) { this.calT += dt; this.mn.min(r); this.mx.max(r); }
      if (this.calT >= RANGE_S) {
        // a minimum range, so a tiny movement does not become full deflection
        const c = this.cal;
        c.x_lo = Math.min(this.mn.x, c.x_c - 40);
        c.x_hi = Math.max(this.mx.x, c.x_c + 40);
        c.y_lo = Math.min(this.mn.y, c.y_c - 5);
        c.y_hi = Math.max(this.mx.y, c.y_c + 5);
        c.r_lo = this.mn.z;
        c.r_hi = Math.max(this.mx.z, this.mn.z + 40);
        c.done = true;
        this.calState = 3;
        this.save();
      }
    }
  }

  save() { try { localStorage.setItem(CAL_KEY, JSON.stringify(this.cal)); } catch (_) { /* not kept */ } }
}

/// Touch: drag anywhere to steer (a virtual stick around where the finger landed). Desktop testing:
/// arrow keys / WASD steer, Shift boosts.
export class TouchInput {
  constructor(el) {
    this.aim = new THREE.Vector2();
    this.origin = null;
    this.cur = new THREE.Vector2();
    this.id = null;
    this.keys = new Set();
    el.addEventListener('pointerdown', (e) => {
      if (this.id !== null) return;
      this.id = e.pointerId;
      this.origin = new THREE.Vector2(e.clientX, e.clientY);
      this.cur.copy(this.origin);
    });
    el.addEventListener('pointermove', (e) => { if (e.pointerId === this.id) this.cur.set(e.clientX, e.clientY); });
    const up = (e) => { if (e.pointerId === this.id) { this.id = null; this.origin = null; } };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    window.addEventListener('keydown', (e) => this.keys.add(e.code));
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
  }

  get boost() { return this.keys.has('ShiftLeft') || this.keys.has('ShiftRight'); }

  update() {
    const k = (a, b) => (this.keys.has(a) || this.keys.has(b) ? 1 : 0);
    const kx = k('ArrowRight', 'KeyD') - k('ArrowLeft', 'KeyA');
    const ky = k('ArrowUp', 'KeyW') - k('ArrowDown', 'KeyS');
    if (this.origin) {
      const r = Math.min(window.innerWidth, window.innerHeight) * 0.16;
      this.aim.set((this.cur.x - this.origin.x) / r, -(this.cur.y - this.origin.y) / r);
      if (this.aim.length() > 1) this.aim.normalize();
    } else {
      this.aim.set(kx, ky);
      if (this.aim.length() > 1) this.aim.normalize();
    }
  }
}
