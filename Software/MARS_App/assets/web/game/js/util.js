// Small helpers shared by the game: seeded random numbers, value noise, Godot-style math.
import * as THREE from 'three';

/// mulberry32: a seeded generator, 0..1
export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hash3(x, y, z) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/// smooth 3D value noise with 4 octaves, about 0..1
export function noise3(x, y, z) {
  let s = 0, a = 0.5, f = 1;
  for (let o = 0; o < 4; o++) {
    const X = x * f, Y = y * f, Z = z * f;
    const ix = Math.floor(X), iy = Math.floor(Y), iz = Math.floor(Z);
    let fx = X - ix, fy = Y - iy, fz = Z - iz;
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy); fz = fz * fz * (3 - 2 * fz);
    const c = (dx, dy, dz) => hash3(ix + dx, iy + dy, iz + dz + o * 31);
    const l = (a0, b0, t) => a0 + (b0 - a0) * t;
    s += a * l(l(l(c(0, 0, 0), c(1, 0, 0), fx), l(c(0, 1, 0), c(1, 1, 0), fx), fy),
               l(l(c(0, 0, 1), c(1, 0, 1), fx), l(c(0, 1, 1), c(1, 1, 1), fx), fy), fz);
    a *= 0.5;
    f *= 2.03;
  }
  return s / 0.9375;
}

export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;
/// frame-rate independent lerp factor: 1 - e^(-rate dt)
export const damp = (rate, dt) => 1 - Math.exp(-rate * dt);
export const moveToward = (v, to, d) => (Math.abs(to - v) <= d ? to : v + Math.sign(to - v) * d);
export const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));
export const rand = (a, b) => a + Math.random() * (b - a);
export const DEG = Math.PI / 180;

const _m = new THREE.Matrix4();
const ZERO = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);
const RIGHT = new THREE.Vector3(1, 0, 0);
/// Godot's Basis.looking_at: -Z along dir
export function lookQuat(dir, up = UP, out = new THREE.Quaternion()) {
  const u = Math.abs(dir.clone().normalize().dot(up)) > 0.98 ? RIGHT : up;
  _m.lookAt(ZERO, dir, u);
  return out.setFromRotationMatrix(_m);
}

/// segment a-b against a sphere
export function segSphere(a, b, c, r) {
  const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z;
  const l2 = Math.max(dx * dx + dy * dy + dz * dz, 1e-6);
  const t = clamp(((c.x - a.x) * dx + (c.y - a.y) * dy + (c.z - a.z) * dz) / l2, 0, 1);
  const px = a.x + dx * t - c.x, py = a.y + dy * t - c.y, pz = a.z + dz * t - c.z;
  return px * px + py * py + pz * pz < r * r;
}

export const fwdOf = (obj, out = new THREE.Vector3()) => out.set(0, 0, -1).applyQuaternion(obj.quaternion);

export function thousands(n) {
  return String(Math.trunc(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}
