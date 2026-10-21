// Explosions, sparks, flashes, warp-ins and missile smoke: two pooled particle systems (additive
// light, alpha-blended smoke), shockwave rings and two flash lights. Nothing allocates per frame.
import * as THREE from 'three';
import { rand } from './util.js';

const VERT = /* glsl */`
attribute float size; attribute float alpha; attribute vec3 tint;
uniform float px; varying float vA; varying vec3 vC;
void main() { vec4 mv = modelViewMatrix * vec4(position, 1.0); vA = alpha; vC = tint;
  gl_PointSize = clamp(size * px / max(-mv.z, 0.1), 0.0, 512.0); gl_Position = projectionMatrix * mv; }`;
const FRAG_ADD = /* glsl */`
varying float vA; varying vec3 vC;
void main() { float d = length(gl_PointCoord - 0.5) * 2.0; float a = pow(max(1.0 - d, 0.0), 1.8) * vA;
  gl_FragColor = vec4(vC * a, a); }`;
const FRAG_SMOKE = /* glsl */`
varying float vA; varying vec3 vC;
void main() { float d = length(gl_PointCoord - 0.5) * 2.0; float a = smoothstep(1.0, 0.2, d) * vA;
  gl_FragColor = vec4(vC, a); }`;

class Particles {
  constructor(scene, n, additive) {
    this.n = n;
    this.live = 0;
    this.pos = new Float32Array(n * 3);
    this.vel = new Float32Array(n * 3);
    this.c0 = new Float32Array(n * 3);
    this.c1 = new Float32Array(n * 3);
    this.tint = new Float32Array(n * 3);
    this.size = new Float32Array(n);
    this.s0 = new Float32Array(n);
    this.s1 = new Float32Array(n);
    this.alpha = new Float32Array(n);
    this.a0 = new Float32Array(n);
    this.life = new Float32Array(n);
    this.max = new Float32Array(n);
    this.drag = new Float32Array(n);
    const g = new THREE.BufferGeometry();
    this.aPos = new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage);
    this.aTint = new THREE.BufferAttribute(this.tint, 3).setUsage(THREE.DynamicDrawUsage);
    this.aSize = new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage);
    this.aAlpha = new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.aPos);
    g.setAttribute('tint', this.aTint);
    g.setAttribute('size', this.aSize);
    g.setAttribute('alpha', this.aAlpha);
    g.setDrawRange(0, 0);
    this.uniforms = { px: { value: 500 } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, vertexShader: VERT, fragmentShader: additive ? FRAG_ADD : FRAG_SMOKE,
      transparent: true, depthWrite: false, toneMapped: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = additive ? 3 : 1;
    this.geo = g;
    scene.add(this.points);
  }

  /// c0 -> c1 colour (THREE.Color, may be > 1 for bloom), s0 -> s1 size (m), life (s)
  emit(p, v, c0, c1, s0, s1, life, a0 = 1, drag = 0) {
    if (this.live >= this.n) return;
    const i = this.live++;
    this.pos.set([p.x, p.y, p.z], i * 3);
    this.vel.set([v.x, v.y, v.z], i * 3);
    this.c0.set([c0.r, c0.g, c0.b], i * 3);
    this.c1.set([c1.r, c1.g, c1.b], i * 3);
    this.s0[i] = s0; this.s1[i] = s1;
    this.a0[i] = a0;
    this.life[i] = life; this.max[i] = life;
    this.drag[i] = drag;
  }

  update(dt) {
    let i = 0;
    while (i < this.live) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) { this._kill(i); continue; }
      const u = 1 - this.life[i] / this.max[i];
      const k = Math.exp(-this.drag[i] * dt);
      for (let a = 0; a < 3; a++) {
        const j = i * 3 + a;
        this.vel[j] *= k;
        this.pos[j] += this.vel[j] * dt;
        this.tint[j] = this.c0[j] + (this.c1[j] - this.c0[j]) * u;
      }
      this.size[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * Math.sqrt(u);
      this.alpha[i] = this.a0[i] * (1 - u) * Math.min(1, u * 12 + 0.2);
      i++;
    }
    this.geo.setDrawRange(0, this.live);
    for (const a of [this.aPos, this.aTint, this.aSize, this.aAlpha]) {
      a.clearUpdateRanges();
      a.addUpdateRange(0, this.live * a.itemSize);
      a.needsUpdate = true;
    }
  }

  _kill(i) {
    const last = --this.live;
    if (i === last) return;
    for (const arr of [this.pos, this.vel, this.c0, this.c1, this.tint]) arr.copyWithin(i * 3, last * 3, last * 3 + 3);
    for (const arr of [this.size, this.s0, this.s1, this.alpha, this.a0, this.life, this.max, this.drag]) arr[i] = arr[last];
  }

  clear() { this.live = 0; this.geo.setDrawRange(0, 0); }
}

const col = (hex, k = 1) => new THREE.Color(hex).multiplyScalar(k);
const FIRE0 = col(0xffd9a0, 6), FIRE1 = col(0xff4a10, 1.2), EMBER = col(0xff7a2a, 4), DARK = col(0x150c08, 0.1);
const SMOKE0 = col(0x3a332e), SMOKE1 = col(0x0e0c0b);
const _v = new THREE.Vector3(), _d = new THREE.Vector3();
const randDir = (out) => out.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();

export class Fx {
  constructor(scene) {
    this.scene = scene;
    this.add = new Particles(scene, 2600, true);
    this.smoke = new Particles(scene, 1400, false);
    this.rings = [];
    const ringGeo = new THREE.RingGeometry(0.85, 1, 48);
    for (let i = 0; i < 8; i++) {
      const m = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0,
        blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
      m.visible = false;
      scene.add(m);
      this.rings.push({ m, t: 0, dur: 1, r: 1 });
    }
    this.lights = [];
    for (let i = 0; i < 2; i++) {
      const l = new THREE.PointLight(0xffa060, 0, 300, 1.6);
      scene.add(l);
      this.lights.push({ l, t: 0, dur: 1, peak: 0 });
    }
    this.nextLight = 0;
  }

  setViewport(heightPx, fovDeg) {
    const px = heightPx / (2 * Math.tan((fovDeg * Math.PI) / 360));
    this.add.uniforms.px.value = px;
    this.smoke.uniforms.px.value = px;
  }

  _light(p, color, peak, range, dur) {
    const s = this.lights[this.nextLight++ % this.lights.length];
    s.l.position.copy(p);
    s.l.color.set(color);
    s.l.distance = range;
    s.peak = peak;
    s.t = dur;
    s.dur = dur;
  }

  _ring(p, color, r, dur, camera) {
    const s = this.rings.find((x) => x.t <= 0) || this.rings[0];
    s.m.position.copy(p);
    s.m.material.color.set(color).multiplyScalar(2.5);
    if (camera) s.m.quaternion.copy(camera.quaternion);
    s.t = dur; s.dur = dur; s.r = r;
    s.m.visible = true;
  }

  /// scale ~1 = a fighter; `debris` adds glowing chunks that fly out
  explode(p, scale = 1, debris = true, camera = null) {
    this.flash(p, 0xffc890, 14 * scale, 0, 0.18);
    for (let i = 0; i < 22 * Math.sqrt(scale); i++) {
      randDir(_d);
      _v.copy(_d).multiplyScalar(rand(4, 22) * scale);
      this.add.emit(_d.multiplyScalar(rand(0, 2) * scale).add(p), _v, FIRE0, DARK, rand(3, 6) * scale, rand(9, 16) * scale,
        rand(0.5, 1.1), 1, 2.2);
    }
    for (let i = 0; i < 14 * Math.sqrt(scale); i++) {
      randDir(_d);
      _v.copy(_d).multiplyScalar(rand(3, 10) * scale);
      this.smoke.emit(_d.multiplyScalar(rand(0, 3) * scale).add(p), _v, SMOKE0, SMOKE1, rand(5, 8) * scale, rand(14, 24) * scale,
        rand(1.6, 3.2), 0.55, 0.9);
    }
    if (debris) {
      for (let i = 0; i < 26; i++) {
        randDir(_v).multiplyScalar(rand(30, 90) * Math.sqrt(scale));
        this.add.emit(p, _v, EMBER, DARK, rand(0.5, 1.0) * scale, 0.1, rand(0.7, 1.6), 1, 0.8);
      }
    }
    this._ring(p, 0xffb070, 30 * scale, 0.7, camera);
    this._light(p, 0xffa060, 18 * scale, 260 * scale, 0.6);
  }

  sparks(p, color = 0xffcc88) {
    const c = col(color, 5);
    for (let i = 0; i < 9; i++) {
      randDir(_v).multiplyScalar(rand(20, 60));
      this.add.emit(p, _v, c, DARK, rand(0.4, 0.8), 0.05, rand(0.2, 0.45), 1, 2);
    }
    this.add.emit(p, _v.set(0, 0, 0), c, DARK, 3, 5, 0.12, 0.8);
  }

  /// a single glow at p (muzzle flashes, shield collapse); range > 0 also lights the scene
  flash(p, color, size, range, dur) {
    this.add.emit(p, _v.set(0, 0, 0), col(color, 4), col(color, 0.5), size, size * 1.4, dur, 1);
    if (range > 0) this._light(p, color, 10, range, dur);
  }

  warp(p, scale, camera = null) {
    this.flash(p, 0x9cc8ff, 30 * scale, 400, 0.5);
    this._ring(p, 0x8cbcff, 60 * scale, 0.9, camera);
    for (let i = 0; i < 30; i++) {
      randDir(_v).multiplyScalar(rand(60, 160) * scale);
      this.add.emit(p, _v, col(0xbcd8ff, 4), DARK, rand(1, 2) * scale, 0.2, rand(0.3, 0.7), 1, 3);
    }
  }

  /// missile smoke, one puff per call
  trail(p, vel) {
    _v.copy(vel).multiplyScalar(-0.05);
    this.smoke.emit(p, _v, col(0x8a8580), SMOKE1, 0.8, 4.5, 1.4, 0.45, 0.5);
    this.add.emit(p, _v, col(0xffc080, 4), DARK, 0.9, 0.3, 0.12, 1, 0);
  }

  update(dt, camera) {
    this.add.update(dt);
    this.smoke.update(dt);
    for (const r of this.rings) {
      if (r.t <= 0) continue;
      r.t -= dt;
      const u = 1 - r.t / r.dur;
      r.m.scale.setScalar(Math.max(0.01, r.r * Math.sqrt(u)));
      r.m.material.opacity = (1 - u) * 0.8;
      r.m.quaternion.copy(camera.quaternion);
      if (r.t <= 0) r.m.visible = false;
    }
    for (const s of this.lights) {
      if (s.t <= 0) { s.l.intensity = 0; continue; }
      s.t -= dt;
      s.l.intensity = s.peak * Math.max(0, s.t / s.dur) * 1000;
    }
  }

  clear() {
    this.add.clear();
    this.smoke.clear();
    for (const r of this.rings) { r.t = 0; r.m.visible = false; }
    for (const s of this.lights) { s.t = 0; s.l.intensity = 0; }
  }
}
