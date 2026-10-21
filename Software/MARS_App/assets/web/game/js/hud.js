// In-flight HUD (hud.gd), redrawn every frame on a 2D canvas: boresight + aim line, target brackets,
// lock diamond, off-screen arrows, missiles panel, shield / hull, timer, arm panel.
// Black and white only: hostiles are told apart by shape, not colour. Sizes follow the screen height.
import * as THREE from 'three';
import { thousands, clamp } from './util.js';
import { DEAD } from './input.js';

const W = (a) => `rgba(255,255,255,${a})`;
const WHITE = W(0.92), DIM = W(0.45), PANEL = 'rgba(0,0,0,0.62)', EDGE = W(0.28);
const _v = new THREE.Vector3(), _c = new THREE.Vector3();

export class Hud {
  constructor(canvas, game) {
    this.cv = canvas;
    this.g = canvas.getContext('2d');
    this.game = game;
    this.bannerText = ''; this.bannerSub = ''; this.bannerT = 0; this.bannerLen = 3;
    this.feed = [];
    this.flash = 0; this.flashHull = false; this.hitmark = 0; this.t = 0;
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.cv.width = Math.round(this.w * this.dpr);
    this.cv.height = Math.round(this.h * this.dpr);
    this.cv.style.width = this.w + 'px';
    this.cv.style.height = this.h + 'px';
    this.s = this.h / 1000; // layout unit: the Godot HUD was laid out for ~1000 px tall
  }

  banner(text, sub = '', dur = 3.2) { this.bannerText = text; this.bannerSub = sub; this.bannerT = dur; this.bannerLen = dur; }
  message(text) { this.feed.unshift([text, 4]); if (this.feed.length > 5) this.feed.pop(); }
  hit(hull) { this.flash = 1; this.flashHull = hull; }

  update(dt) {
    this.t += dt;
    this.bannerT = Math.max(0, this.bannerT - dt);
    this.flash = Math.max(0, this.flash - dt * 2.5);
    this.hitmark = Math.max(0, this.hitmark - dt * 4);
    for (const f of this.feed) f[1] -= dt;
    while (this.feed.length && this.feed[this.feed.length - 1][1] <= 0) this.feed.pop();
  }

  // ---- drawing helpers (in CSS pixels) ----
  text(x, y, s, px, color, align = 0, weight = 600) {
    const g = this.g;
    g.font = `${weight} ${Math.round(px * this.s)}px Montserrat, sans-serif`;
    g.textAlign = align === 1 ? 'center' : align === 2 ? 'right' : 'left';
    g.fillStyle = 'rgba(0,0,0,0.55)';
    g.fillText(s, x + 1.5, y + 1.5);
    g.fillStyle = color;
    g.fillText(s, x, y);
  }
  line(x0, y0, x1, y1, color, w) { const g = this.g; g.strokeStyle = color; g.lineWidth = w; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke(); }
  circle(x, y, r, color, w = 2, fill = false) {
    const g = this.g; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2);
    if (fill) { g.fillStyle = color; g.fill(); } else { g.strokeStyle = color; g.lineWidth = w; g.stroke(); }
  }
  rect(x, y, w, h, fill, stroke) {
    const g = this.g;
    if (fill) { g.fillStyle = fill; g.fillRect(x, y, w, h); }
    if (stroke) { g.strokeStyle = stroke; g.lineWidth = 1; g.strokeRect(x + 0.5, y + 0.5, w, h); }
  }
  /// world -> screen (CSS px); null when behind the camera
  project(p) {
    const cam = this.game.camera;
    _c.copy(p).applyMatrix4(cam.matrixWorldInverse);
    if (_c.z > -0.1) return null;
    _v.copy(p).project(cam);
    return [(_v.x * 0.5 + 0.5) * this.w, (-_v.y * 0.5 + 0.5) * this.h];
  }

  draw() {
    const g = this.g, game = this.game;
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    g.clearRect(0, 0, this.w, this.h);
    if (!(game.state === 'play' || game.state === 'pause')) return;
    g.lineCap = 'round';
    const p = game.player;
    if (this.flash > 0) {
      this.rect(0, 0, this.w, this.h, W((this.flashHull ? 0.14 : 0.06) * this.flash));
      if (this.flashHull) { g.strokeStyle = W(0.5 * this.flash); g.lineWidth = 3; g.strokeRect(6, 6, this.w - 12, this.h - 12); }
    }
    if (p.alive) { this._targets(p); this._reticle(p); }
    this._top();
    this._missiles(p);
    this._status(p);
    if (game.settings.input === 'robot') this._arm();
    this._feed();
    this._banner();
    const S = this.s;
    if (!p.alive) {
      this.text(this.w / 2, this.h * 0.55, `HULL BREACH  ·  RELAUNCHING IN ${Math.ceil(game.respawnT)}`, 26, WHITE, 1, 700);
    } else if (game.outOfBounds && this.t % 0.8 < 0.55) {
      this.text(this.w / 2, this.h * 0.68, 'RETURN TO THE COMBAT AREA', 26, WHITE, 1, 700);
    }
    void S;
  }

  _reticle(p) {
    const S = this.s;
    const bp = this.project(_v.copy(p.fwd()).multiplyScalar(500).add(p.pos).clone());
    if (!bp) return;
    const [x, y] = bp;
    const r = 22 * S;
    this.circle(x, y, r, WHITE, 2);
    for (const [dx, dy] of [[-1, 0], [1, 0], [0, 1]]) this.line(x + dx * r, y + dy * r, x + dx * (r + 10 * S), y + dy * (r + 10 * S), WHITE, 2);
    this.circle(x, y, 2, WHITE, 0, true);
    if (this.hitmark > 0) {
      for (const [dx, dy] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
        this.line(x + dx * 9 * S, y + dy * 9 * S, x + dx * 16 * S, y + dy * 16 * S, W(this.hitmark), 2);
      }
    }
    // aim cursor (arm / touch) and the line to the boresight
    const cx = this.w / 2 + p.aimNow.x * this.h * 0.3, cy = this.h / 2 - p.aimNow.y * this.h * 0.3;
    const dx = cx - x, dy = cy - y, dl = Math.hypot(dx, dy);
    if (dl > 34 * S) this.line(x + (dx / dl) * 24 * S, y + (dy / dl) * 24 * S, cx - (dx / dl) * 9 * S, cy - (dy / dl) * 9 * S, W(0.7), 1.5);
    this.circle(cx, cy, 8 * S, W(0.85), 2);
  }

  _targets(p) {
    const game = this.game, S = this.s, g = this.g;
    const cam = game.camera;
    const objective = game.objective();
    for (const h of game.hostiles) {
      if (!h.alive) continue;
      const isObj = h === objective;
      if (!h.targetable() && !isObj) continue;
      const wp = h.wpos();
      const dist = p.pos.distanceTo(wp);
      if (dist > 3200) continue;
      const col = isObj && h.kind !== 'FIGHTER' ? W(0.75) : W(0.95);
      const sp = this.project(wp);
      const on = sp && sp[0] > 40 && sp[0] < this.w - 40 && sp[1] > 40 && sp[1] < this.h - 40;
      if (!on) {
        if (h.kind === 'FIGHTER' && dist > 1800) continue;
        _c.copy(wp).applyMatrix4(cam.matrixWorldInverse);
        let dx = _c.x, dy = -_c.y;
        const l = Math.hypot(dx, dy) || 1;
        dx /= l; dy /= l;
        const ex = this.w / 2 + dx * (this.w / 2 - 70 * S), ey = this.h / 2 + dy * (this.h / 2 - 70 * S);
        const nx = -dy, ny = dx;
        g.fillStyle = col;
        g.beginPath();
        g.moveTo(ex + dx * 12 * S, ey + dy * 12 * S);
        g.lineTo(ex - dx * 6 * S + nx * 9 * S, ey - dy * 6 * S + ny * 9 * S);
        g.lineTo(ex - dx * 6 * S - nx * 9 * S, ey - dy * 6 * S - ny * 9 * S);
        g.fill();
        if (isObj) this.text(ex - dx * 26 * S, ey - dy * 26 * S + 6 * S, h.kind.split(' ').pop(), 15, col, 1, 700);
        continue;
      }
      const [x, y] = sp;
      const r = clamp((h.radius * 1100 * S) / Math.max(dist, 1), 10 * S, 70 * S);
      const isT = h === p.target;
      const c = isT ? col : W(0.5);
      const k = r * 0.35;
      for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
        const qx = x + sx * r, qy = y + sy * r;
        this.line(qx, qy, qx - sx * k, qy, c, 1.6);
        this.line(qx, qy, qx, qy - sy * k, c, 1.6);
      }
      if (isObj && !isT) this.text(x, y - r - 8 * S, h.kind, 14, c, 1, 700);
      if (isT) {
        this.text(x, y - r - 22 * S, h.kind, 18, col, 1, 700);
        this.line(x - r, y - r - 16 * S, x - r + 2 * r * Math.max(0, h.hp) / h.maxHp, y - r - 16 * S, col, 3);
        this.text(x, y + r + 22 * S, `${Math.trunc(dist)} m`, 15, W(0.85), 1, 600);
        const lead = this.project(wp.clone().addScaledVector(h.velocity(), dist / 950));
        if (lead) this.circle(lead[0], lead[1], 5 * S, W(0.8), 1.5);
        const lp = p.lockProgress();
        if (lp > 0) {
          const ds = r * 2.4 + (r * 1.05 - r * 2.4) * lp;
          const rot = (1 - lp) * Math.PI * 0.5;
          g.strokeStyle = p.locked ? W(0.95) : W(0.6);
          g.lineWidth = p.locked ? 2 : 1.4;
          g.beginPath();
          for (let i = 0; i < 5; i++) {
            const a = rot + i * Math.PI * 0.5;
            if (i === 0) g.moveTo(x + Math.cos(a) * ds, y + Math.sin(a) * ds); else g.lineTo(x + Math.cos(a) * ds, y + Math.sin(a) * ds);
          }
          g.stroke();
          if (p.locked) {
            this.text(x + ds + 10 * S, y + 6 * S, 'LOCK', 16, W(0.95), 0, 700);
            this.text(this.w / 2, this.h / 2 + 90 * S, 'MISSILE LOCK', 20, W(0.95), 1, 700);
          }
        }
      }
    }
  }

  _top() {
    const game = this.game, S = this.s;
    const left = Math.max(game.sessionLeft, 0);
    const mm = Math.floor(left / 60), ss = Math.floor(left % 60);
    this.text(this.w / 2, 54 * S, `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`, 36, left > 30 ? WHITE : W(0.8), 1, 700);
    this.text(this.w / 2, 82 * S, game.objectiveText(), 17, W(0.85), 1, 700);
    this.text(this.w / 2, 104 * S, `HOSTILE FIGHTERS  ${game.fighters.length}`, 14, DIM, 1, 600);
    const rx = this.w - 40 * S - 80 * S; // leave room for the pause button
    this.text(rx, 54 * S, thousands(game.score), 32, WHITE, 2, 700);
    this.text(rx, 78 * S, `SCORE  ·  WAVE ${game.wave}`, 14, DIM, 2, 600);
  }

  _missiles(p) {
    const S = this.s;
    const x = this.w - 400 * S, y = this.h - 175 * S, w = 360 * S, h = 135 * S;
    this.rect(x, y, w, h, PANEL, EDGE);
    this.text(x + 20 * S, y + 34 * S, 'MISSILES', 17, WHITE, 0, 700);
    this.text(x + w - 20 * S, y + 46 * S, String(p.missiles), 44, WHITE, 2, 700);
    for (let i = 0; i < 14; i++) {
      const bx = x + 22 * S + i * 16 * S;
      const c = i < p.missiles ? WHITE : W(0.15);
      this.rect(bx, y + 62 * S, 8 * S, 26 * S, c);
    }
    let status = 'NO TARGET', sc = DIM;
    if (p.target) {
      if (p.locked) { status = 'LOCKED  ·  ' + p.target.kind; sc = W(0.95); }
      else { status = `ACQUIRING  ${Math.trunc(p.lockProgress() * 100)}%`; sc = W(0.8); }
    }
    this.text(x + 20 * S, y + 118 * S, status, 16, sc, 0, 700);
  }

  _bar(x, y, w, v, col, label) {
    const S = this.s;
    this.text(x, y, label, 14, DIM, 0, 700);
    this.rect(x + 80 * S, y - 11 * S, w, 10 * S, W(0.12));
    this.rect(x + 80 * S, y - 11 * S, w * clamp(v, 0, 1), 10 * S, col);
  }

  _status(p) {
    const S = this.s;
    const x = 40 * S, y = this.h - 175 * S;
    this.rect(x, y, 380 * S, 135 * S, PANEL, EDGE);
    this._bar(x + 20 * S, y + 36 * S, 260 * S, p.shield / 100, WHITE, 'SHIELD');
    const low = p.hull < 35 && this.t % 0.6 < 0.3;
    this._bar(x + 20 * S, y + 66 * S, 260 * S, p.hull / 100, low ? DIM : WHITE, 'HULL');
    this._bar(x + 20 * S, y + 96 * S, 260 * S, p.boost, W(0.6), 'BOOST');
    this.text(x + 20 * S, y + 124 * S, `SPEED  ${Math.trunc(p.speed)} m/s`, 14, DIM, 0, 700);
  }

  _arm() {
    const S = this.s, r = this.game.robot;
    const x = 40 * S, y = this.h - 420 * S, w = 170 * S;
    this.rect(x, y, w, w, PANEL, EDGE);
    const cx = x + w / 2, cy = y + w / 2;
    this.line(x + 10 * S, cy, x + w - 10 * S, cy, W(0.15), 1);
    this.line(cx, y + 10 * S, cx, y + w - 10 * S, W(0.15), 1);
    this.circle(cx, cy, 70 * S * DEAD, W(0.2), 1);
    this.circle(cx + r.aim.x * 70 * S, cy - r.aim.y * 70 * S, 6 * S, r.live() ? W(0.88) : W(0.95), 0, true);
    this.text(x + 10 * S, y - 10 * S, 'ARM', 14, DIM, 0, 700);
    const line = r.live() ? `LIFT ${r.raw.y.toFixed(0)}°  REACH ${Math.trunc(r.reach * 100)}%` : 'NO ROBOT DATA';
    this.text(x + 10 * S, y + w + 20 * S, line, 13, r.live() ? W(0.88) : W(0.95), 0, 700);
    if (r.live() && !r.encOk()) this.text(x + 10 * S, y + w + 38 * S, 'ENCODERS OFF · LIFT ONLY', 12, W(0.95), 0, 700);
  }

  _feed() {
    const S = this.s;
    let y = 130 * S;
    for (const [text, life] of this.feed) {
      this.text(this.w - 40 * S, y, text, 15, W(0.92 * clamp(life, 0, 1)), 2, 700);
      y += 24 * S;
    }
  }

  _banner() {
    if (this.bannerT <= 0) return;
    const S = this.s;
    const a = clamp(this.bannerT, 0, 1) * clamp((this.bannerLen - this.bannerT) * 4, 0, 1);
    const y = this.h * 0.3;
    this.text(this.w / 2, y, this.bannerText, 44, W(0.95 * a), 1, 700);
    this.line(this.w / 2 - 320 * S, y + 18 * S, this.w / 2 + 320 * S, y + 18 * S, W(0.6 * a), 2);
    if (this.bannerSub) this.text(this.w / 2, y + 50 * S, this.bannerSub, 20, W(0.85 * a), 1, 500);
  }
}
