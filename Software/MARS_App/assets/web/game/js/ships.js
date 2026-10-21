// Ship models assembled from procedural parts (ships.gd + proc.gd). Forward is -Z.
// Parts of one ship that share a material are merged into one mesh, so a ship costs a few draw
// calls, not dozens (the Ranger has ~70 parts).
import * as THREE from 'three';

// ---------------- geometry (proc.gd) ----------------

/// Triangle soup with three.js's counter-clockwise front faces: `out` says which way a face looks.
class Soup {
  constructor() { this.p = []; }
  tri(a, b, c, out) {
    const n = new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(c, a));
    if (n.dot(out) < 0) [b, c] = [c, b];
    this.p.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
  }
  quad(a, b, c, d, out) { this.tri(a, b, c, out); this.tri(a, c, d, out); }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.p, 3));
    g.computeVertexNormals(); // separate triangles: flat (faceted) normals
    return g;
  }
}

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/// Surface of revolution along Z; profile = [z, radius] from the nose (-Z) to the tail.
/// sx / sy squash the cross-section; smooth = false gives a faceted hull.
export function lathe(profile, seg, sx = 1, sy = 1, smooth = true, caps = true) {
  const rings = profile.map(([z, r]) => {
    const ring = [];
    for (let i = 0; i < seg; i++) {
      const a = (Math.PI * 2 * (i + 0.5)) / seg;
      ring.push(V(Math.cos(a) * r * sx, Math.sin(a) * r * sy, z));
    }
    return ring;
  });
  if (smooth) {
    const pos = [], idx = [];
    for (const ring of rings) for (const v of ring) pos.push(v.x, v.y, v.z);
    for (let k = 0; k < rings.length - 1; k++) {
      for (let i = 0; i < seg; i++) {
        const j = (i + 1) % seg;
        const a = k * seg + i, b = k * seg + j, c = (k + 1) * seg + j, d = (k + 1) * seg + i;
        idx.push(a, c, d, a, b, c); // counter-clockwise seen from outside
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    if (caps) return mergeGeos([g.toNonIndexed(), latheCaps(profile, rings)]);
    return g.toNonIndexed();
  }
  const s = new Soup();
  for (let k = 0; k < rings.length - 1; k++) {
    const dz = profile[k + 1][0] - profile[k][0], dr = profile[k + 1][1] - profile[k][1];
    for (let i = 0; i < seg; i++) {
      const j = (i + 1) % seg;
      const a = (Math.PI * 2 * (i + 1)) / seg;
      const out = V(Math.cos(a) * dz * sy, Math.sin(a) * dz * sx, -dr);
      s.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], out);
    }
  }
  if (!caps) return s.geometry();
  return mergeGeos([s.geometry(), latheCaps(profile, rings)]);
}

function latheCaps(profile, rings) {
  const s = new Soup();
  const n = profile.length, seg = rings[0].length;
  if (profile[0][1] > 0) {
    const c0 = V(0, 0, profile[0][0]);
    for (let i = 0; i < seg; i++) s.tri(c0, rings[0][i], rings[0][(i + 1) % seg], V(0, 0, -1));
  }
  if (profile[n - 1][1] > 0) {
    const c1 = V(0, 0, profile[n - 1][0]);
    for (let i = 0; i < seg; i++) s.tri(c1, rings[n - 1][i], rings[n - 1][(i + 1) % seg], V(0, 0, 1));
  }
  return s.geometry();
}

/// Flat plate from a polygon in the XZ plane (x = span, z = chord), thickness along Y, thinning to
/// tip x thickness at the largest |x|.
export function slab(poly, thick, tip = 1) {
  const s = new Soup();
  const span = Math.max(...poly.map((p) => Math.abs(p[0])));
  const top = [], bot = [];
  for (const [x, z] of poly) {
    const h = thick * 0.5 * (1 + (tip - 1) * (Math.abs(x) / Math.max(span, 1e-3)));
    top.push(V(x, h, z));
    bot.push(V(x, -h, z));
  }
  const tris = THREE.ShapeUtils.triangulateShape(poly.map(([x, z]) => new THREE.Vector2(x, z)), []);
  for (const [a, b, c] of tris) {
    s.tri(top[a], top[b], top[c], V(0, 1, 0));
    s.tri(bot[a], bot[b], bot[c], V(0, -1, 0));
  }
  const cx = poly.reduce((t, p) => t + p[0], 0) / poly.length, cz = poly.reduce((t, p) => t + p[1], 0) / poly.length;
  for (let i = 0; i < poly.length; i++) {
    const j = (i + 1) % poly.length;
    const ex = poly[j][0] - poly[i][0], ez = poly[j][1] - poly[i][1];
    let nx = ez, nz = -ex;
    if (nx * ((poly[i][0] + poly[j][0]) / 2 - cx) + nz * ((poly[i][1] + poly[j][1]) / 2 - cz) < 0) { nx = -nx; nz = -nz; }
    s.quad(top[i], top[j], bot[j], bot[i], V(nx, 0, nz));
  }
  return s.geometry();
}
export const mirrorX = (poly) => poly.slice().reverse().map(([x, z]) => [-x, z]);

/// Faceted lifting body lofted along Z through stations [z, half_width, top, bottom, top_chamfer,
/// bottom_chamfer]: a flat hexagon cross-section. Returns {top, rim, belly} geometries.
export function loft(stations) {
  const parts = { top: new Soup(), rim: new Soup(), belly: new Soup() };
  const rings = stations.map(([z, hw, top, bot, ct, cb]) => [
    V(-(hw - ct), top, z), V(hw - ct, top, z), V(hw, 0, z), V(hw - cb, -bot, z), V(-(hw - cb), -bot, z), V(-hw, 0, z)]);
  const group = ['top', 'rim', 'rim', 'belly', 'rim', 'rim'];
  for (let k = 0; k < rings.length - 1; k++) {
    for (let i = 0; i < 6; i++) {
      const j = (i + 1) % 6;
      const mid = rings[k][i].clone().add(rings[k][j]).multiplyScalar(0.5);
      let out = V(mid.x, mid.y, 0);
      if (i === 0) out = V(0, 1, 0);
      else if (i === 3) out = V(0, -1, 0);
      parts[group[i]].quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], out);
    }
  }
  for (const end of [0, rings.length - 1]) {
    const r = rings[end];
    const out = V(0, 0, end === 0 ? -1 : 1);
    for (let i = 1; i < 5; i++) parts.rim.tri(r[0], r[i], r[i + 1], out);
  }
  return { top: parts.top.geometry(), rim: parts.rim.geometry(), belly: parts.belly.geometry() };
}

/// non-indexed geometries with position + normal -> one
export function mergeGeos(geos) {
  let n = 0;
  for (const g of geos) n += g.attributes.position.count;
  const pos = new Float32Array(n * 3), nrm = new Float32Array(n * 3);
  let o = 0;
  for (let g of geos) {
    if (g.index) g = g.toNonIndexed();
    if (!g.attributes.normal) g.computeVertexNormals();
    pos.set(g.attributes.position.array, o * 3);
    nrm.set(g.attributes.normal.array, o * 3);
    o += g.attributes.position.count;
  }
  const m = new THREE.BufferGeometry();
  m.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  m.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  return m;
}

export const box = (x, y, z) => new THREE.BoxGeometry(x, y, z);
export const cyl = (rt, rb, h, seg = 24) => new THREE.CylinderGeometry(rt, rb, h, seg, 1);
export const sphere = (r, seg = 24) => new THREE.SphereGeometry(r, seg, Math.max(4, seg >> 1));

// ---------------- materials ----------------

const HULL_VERT_HEAD = 'varying vec3 vObj;\nvarying vec3 vObjN;\n';
const HULL_FRAG_HEAD = /* glsl */`
varying vec3 vObj;
varying vec3 vObjN;
uniform float uPanel; uniform float uGrime; uniform float uWindows;
uniform vec3 uStripeAxis; uniform vec2 uStripe; uniform vec3 uAccent; uniform float uStripeEmit;
uniform vec2 uGlassC; uniform vec2 uGlassR; uniform float uGlassCell;
float hh(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float vn(vec3 x) { vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z); }
vec2 planar(vec3 p, vec3 n) { vec3 a = abs(n); return a.x > a.y && a.x > a.z ? p.zy : (a.y > a.z ? p.xz : p.xy); }
`;
const HULL_FRAG_COLOR = /* glsl */`
  vec2 pp = planar(vObj, normalize(vObjN)) * uPanel;
  vec2 pc = floor(pp + vec2(0.0, floor(pp.x) * 0.5));
  vec2 pf = abs(fract(pp + vec2(0.0, floor(pp.x) * 0.5)) - 0.5);
  float seam = smoothstep(0.455, 0.49, max(pf.x, pf.y));
  float tone = 0.93 + 0.12 * hh(vec3(pc, 1.7));
  float grime = mix(1.0, 0.72 + 0.4 * vn(vObj * 0.9), uGrime);
  diffuseColor.rgb *= tone * grime * (1.0 - 0.42 * seam);
  float sd = dot(vObj, uStripeAxis);
  float stripe = step(uStripe.x, sd) * step(sd, uStripe.y);
  diffuseColor.rgb = mix(diffuseColor.rgb, uAccent, stripe);
  // small lit windows, scattered on panels
  float win = uWindows > 0.0 ? step(1.0 - uWindows, hh(vec3(pc, 9.1))) * step(max(pf.x, pf.y * 2.2), 0.2) : 0.0;
  // the Ranger's cockpit glass: irregular panes in an ellipse on the deck
  float glass = 0.0;
  if (uGlassR.x > 0.0 && vObjN.y > 0.5) {
    vec2 q = (vObj.xz - uGlassC) / uGlassR;
    if (dot(q, q) < 1.0) {
      vec2 g = vObj.xz / uGlassCell; vec2 gi = floor(g); float d1 = 9.0, d2 = 9.0;
      for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec2 c = gi + vec2(x, y); vec2 o = vec2(hh(vec3(c, 3.1)), hh(vec3(c, 5.7))) * 0.8 + 0.1;
        float d = length(g - c - o); if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d; }
      glass = step(uGlassCell * 0.0 + 0.12, d2 - d1) * (1.0 - smoothstep(0.85, 1.0, dot(q, q)));
    }
  }
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.012, 0.014, 0.02), glass);
`;

/// Panelled hull (hull.gdshader): seams, panel tones, grime, an optional accent stripe and windows.
export function hullMat(color, { panel = 1.5, metal = 0.3, rough = 0.42, grime = 0.5, windows = 0,
  stripe = null, glass = null } = {}) {
  const m = new THREE.MeshStandardMaterial({ color, metalness: metal, roughness: rough });
  const u = {
    uPanel: { value: panel }, uGrime: { value: grime }, uWindows: { value: windows },
    uStripeAxis: { value: new THREE.Vector3(0, 0, 1) }, uStripe: { value: new THREE.Vector2(1e9, -1e9) },
    uAccent: { value: new THREE.Color(0, 0, 0) }, uStripeEmit: { value: 0 },
    uGlassC: { value: new THREE.Vector2() }, uGlassR: { value: new THREE.Vector2(0, 0) }, uGlassCell: { value: 0.8 },
  };
  if (stripe) {
    u.uStripeAxis.value.copy(stripe.axis);
    u.uStripe.value.set(stripe.a, stripe.b);
    u.uAccent.value.set(stripe.color);
    u.uStripeEmit.value = stripe.emit || 0;
  }
  if (glass) {
    u.uGlassC.value.set(...glass.center);
    u.uGlassR.value.set(...glass.radii);
    u.uGlassCell.value = glass.cell;
  }
  m.userData.u = u;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u);
    sh.vertexShader = HULL_VERT_HEAD + sh.vertexShader.replace('#include <begin_vertex>',
      '#include <begin_vertex>\nvObj = position;\nvObjN = normal;');
    sh.fragmentShader = HULL_FRAG_HEAD + sh.fragmentShader
      .replace('#include <color_fragment>', '#include <color_fragment>\n' + HULL_FRAG_COLOR)
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = mix(roughnessFactor, 0.06, glass);')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n' +
        'totalEmissiveRadiance += uAccent * stripe * uStripeEmit + vec3(1.0, 0.86, 0.62) * win * 2.2;');
  };
  m.customProgramCacheKey = () => 'hull';
  return m;
}

/// unlit glow (lights, engine discs): brighter than white, so the bloom picks it up
export function glowMat(color, energy) {
  const c = new THREE.Color(color).multiplyScalar(energy);
  return new THREE.MeshBasicMaterial({ color: c, toneMapped: false });
}
export function addMat(color, energy) {
  const c = new THREE.Color(color).multiplyScalar(energy);
  return new THREE.MeshBasicMaterial({ color: c, toneMapped: false, transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false });
}

/// exhaust plume: additive, fading along its length and at the edges
export function flameMat(core, edge, intensity) {
  return new THREE.ShaderMaterial({
    uniforms: { core: { value: new THREE.Color(core) }, edge: { value: new THREE.Color(edge) },
      k: { value: intensity }, throttle: { value: 1 }, t: { value: 0 } },
    vertexShader: `varying vec2 vUv; varying float vF; void main() { vUv = uv;
      vec3 n = normalize(normalMatrix * normal); vec4 mv = modelViewMatrix * vec4(position, 1.0);
      vF = abs(dot(n, normalize(-mv.xyz))); gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform vec3 core; uniform vec3 edge; uniform float k; uniform float throttle; uniform float t;
      varying vec2 vUv; varying float vF;
      void main() { float along = vUv.y; float flick = 0.85 + 0.15 * sin(t * 40.0 + along * 20.0);
        float a = pow(along, 1.6) * pow(vF, 1.5) * throttle * flick;
        vec3 c = mix(edge, core, pow(along, 3.0)) * k * 2.2;
        gl_FragColor = vec4(c * a, a); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, toneMapped: false,
  });
}

// ---------------- assembly ----------------

const _e = new THREE.Euler();
const _q = new THREE.Quaternion();
const _m = new THREE.Matrix4();

/// Collects parts; static parts with the same material end up in one merged mesh.
class Builder {
  constructor() { this.root = new THREE.Group(); this.byMat = new Map(); }
  /// rot = Godot-style Euler (x, y, z), YXZ order
  part(geo, mat, pos = [0, 0, 0], rot = [0, 0, 0], scl = [1, 1, 1]) {
    _e.set(rot[0], rot[1], rot[2], 'YXZ');
    _m.compose(V(...pos), _q.setFromEuler(_e), V(...scl));
    const g = (geo.index ? geo.toNonIndexed() : geo.clone()).applyMatrix4(_m);
    if (!this.byMat.has(mat)) this.byMat.set(mat, []);
    this.byMat.get(mat).push(g);
  }
  /// a separate mesh (it moves, blinks or hides on its own)
  own(geo, mat, pos = [0, 0, 0], rot = [0, 0, 0], scl = [1, 1, 1], parent = this.root) {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(...pos);
    m.rotation.set(rot[0], rot[1], rot[2], 'YXZ');
    m.scale.set(...scl);
    parent.add(m);
    return m;
  }
  marker(pos, parent = this.root) { const o = new THREE.Object3D(); o.position.set(...pos); parent.add(o); return o; }
  build() {
    for (const [mat, geos] of this.byMat) this.root.add(new THREE.Mesh(mergeGeos(geos), mat));
    this.byMat.clear();
    return this.root;
  }
}

/// unit flame cone: base at z = 0 (nozzle), tip at z = 1
const FLAME_GEO = (() => {
  const g = new THREE.ConeGeometry(1, 1, 16, 1, true);
  g.rotateX(-Math.PI / 2); // tip towards +z (backwards)
  g.translate(0, 0, 0.5);
  // uv.y: 1 at the nozzle, 0 at the tip
  const uv = g.attributes.uv, p = g.attributes.position;
  for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - p.getZ(i));
  return g;
})();

/// nozzle bell, glowing disc, exhaust flame. Returns the flame mesh (or null).
function engine(b, pos, r, metal, glow, core, flameLen, disc = 2.6, flameK = 1.2, flame = true) {
  b.part(lathe([[0, r * 0.92], [r * 0.55, r * 1.05], [r * 1.1, r * 1.12]], 24, 1, 1, true, false), metal, pos);
  b.part(cyl(r * 0.86, r * 0.86, 0.05, 24), glowMat(new THREE.Color(glow).lerp(new THREE.Color(core), 0.4), disc),
    [pos[0], pos[1], pos[2] + r * 0.9], [Math.PI / 2, 0, 0]);
  if (!flame) return null;
  const fl = b.own(FLAME_GEO, flameMat(core, glow, flameK), [pos[0], pos[1], pos[2] + r * 0.95], [0, 0, 0],
    [r * 0.82, r * 0.82, flameLen]);
  fl.userData.len = flameLen;
  return fl;
}

/// The player's ship, after the Ranger from Interstellar: a flat faceted lifting body with a black
/// chamfered rim, a raised white deck with irregular windows, a ribbed engine block and RCS clusters.
export function ranger() {
  const b = new Builder();
  const white = hullMat(0xcacac4, { panel: 1.1, metal: 0.12, rough: 0.5, grime: 0.75 });
  const deck = hullMat(0xcacac4, { panel: 1.1, metal: 0.12, rough: 0.5, grime: 0.75,
    glass: { center: [0, -2.8], radii: [1.75, 2.3], cell: 0.82 } });
  const side = hullMat(0xa4a4a1, { panel: 1.4, metal: 0.15, rough: 0.55, grime: 0.6 });
  const rim = hullMat(0x141518, { panel: 1.6, metal: 0.35, rough: 0.5, grime: 0.3 });
  const belly = hullMat(0x75756f, { panel: 1.2, metal: 0.2, rough: 0.6, grime: 0.6 });
  const black = hullMat(0x1a1a1d, { panel: 2.6, metal: 0.55, rough: 0.42, grime: 0.2 });
  const nozzle = hullMat(0x17171a, { panel: 3.0, metal: 0.2, rough: 0.8, grime: 0 });
  const hole = new THREE.MeshBasicMaterial({ color: 0x030303 });

  const body = loft([[-8.2, 1.55, 0.26, 0.22, 0.45, 0.35], [-7.3, 2.35, 0.40, 0.30, 0.62, 0.45],
    [-3.0, 2.95, 0.50, 0.34, 0.70, 0.50], [3.5, 3.35, 0.55, 0.36, 0.72, 0.52], [7.6, 3.35, 0.55, 0.36, 0.72, 0.52]]);
  b.part(body.top, white); b.part(body.rim, rim); b.part(body.belly, belly);
  const up = loft([[-5.7, 0.85, 0.08, 0.2, 0.25, 0.0], [-3.4, 1.85, 0.46, 0.2, 0.5, 0.0],
    [0.0, 2.32, 0.68, 0.2, 0.6, 0.0], [5.6, 2.45, 0.70, 0.2, 0.6, 0.0]]);
  b.part(up.top, deck, [0, 0.46, 0]); b.part(up.rim, side, [0, 0.46, 0]);
  b.part(slab([[-1.55, -7.0], [1.55, -7.0], [1.95, -4.0], [-1.95, -4.0]], 0.07), white, [0, 0.47, 0], [-0.024, 0, 0]);
  const blk = loft([[5.5, 3.3, 1.25, 0.38, 0.35, 0.3], [7.7, 3.3, 1.25, 0.38, 0.35, 0.3]]);
  for (const k of ['top', 'rim', 'belly']) b.part(blk[k], black);
  for (let i = 0; i < 10; i++) b.part(box(5.6, 0.1, 0.09), rim, [0, 1.3, 5.68 + i * 0.205]);
  for (const s of [-1, 1]) for (let i = 0; i < 4; i++) b.part(box(0.04, 0.5, 0.14), hole, [3.31 * s, 0.6, 5.9 + i * 0.35]);
  for (const s of [-1, 1]) {
    const c = [2.05 * s, 0.1, -7.35];
    b.part(box(0.8, 0.55, 1.4), black, c);
    for (let row = 0; row < 2; row++) for (let col = 0; col < 3; col++) {
      b.part(cyl(0.075, 0.075, 0.06, 10), hole, [c[0] + 0.41 * s, c[1] + 0.12 - row * 0.24, c[2] - 0.4 + col * 0.4], [0, 0, Math.PI / 2]);
      b.part(cyl(0.08, 0.08, 0.06, 10), hole, [3.33 * s, -row * 0.2, 6.65 + col * 0.25], [0, 0, Math.PI / 2]);
    }
  }
  // the nozzles glow blue; no plume (seen from the chase camera it only blooms into a blob)
  const blue = 0x3f66ff, white2 = 0x9fb8ff;
  for (const [x, r] of [[1.75, 0.5], [-1.75, 0.5], [0, 0.36]]) {
    engine(b, [x, 0.42, 7.7], r, nozzle, blue, white2, 2.6, 0.32, 0.45, false);
    b.part(sphere(r * 0.28, 10), glowMat(white2, 3.2), [x, 0.42, 7.7 + r * 0.85]); // hot core: this blooms
  }
  const muzzles = [b.marker([1.2, -0.15, -8.4]), b.marker([-1.2, -0.15, -8.4])];
  b.part(sphere(0.07, 8), glowMat(0xff2618, 5), [-3.36, 0, 4.8]);
  b.part(sphere(0.07, 8), glowMat(0x33ff66, 5), [3.36, 0, 4.8]);
  b.part(sphere(0.06, 8), glowMat(0xffffff, 6), [0, 1.42, 7.6]);
  const root = b.build();
  root.userData.muzzles = muzzles;
  return root;
}

/// Enemy interceptor: gunmetal pod, forward-swept blades with red light strips.
export function fighter() {
  const b = new Builder();
  const red = 0xff2e14;
  const pod = hullMat(0x33353d, { panel: 2.2, metal: 0.6, rough: 0.35, stripe: { axis: V(0, 0, 1), a: -1.2, b: -0.9, color: red, emit: 3 } });
  const dark = hullMat(0x17171a, { panel: 3, metal: 0.8, rough: 0.3 });
  const wingR = hullMat(0x33353d, { panel: 2.2, metal: 0.6, rough: 0.35, stripe: { axis: V(1, 0, 0), a: 3.6, b: 3.85, color: red, emit: 4 } });
  const wingL = hullMat(0x33353d, { panel: 2.2, metal: 0.6, rough: 0.35, stripe: { axis: V(-1, 0, 0), a: 3.6, b: 3.85, color: red, emit: 4 } });
  b.part(lathe([[-3.8, 0], [-3.3, 0.38], [-2.2, 0.8], [-0.4, 1.05], [1.3, 1.05], [2.5, 0.85], [3.0, 0.55], [3.1, 0]], 20, 1, 0.85), pod);
  b.part(sphere(0.5, 16), new THREE.MeshStandardMaterial({ color: 0x991008, metalness: 0.7, roughness: 0.05,
    emissive: 0x991008, emissiveIntensity: 0.4 }), [0, 0.5, -1.9], [0, 0, 0], [0.8, 0.6, 1.7]);
  const blade = [[0.7, 0.4], [4.8, -1.8], [5.3, -1.4], [5.0, 1.6], [0.7, 2.1]];
  b.part(slab(blade, 0.26, 0.4), wingR, [0, 0, 0], [0, 0, -0.38]);
  b.part(slab(mirrorX(blade), 0.26, 0.4), wingL, [0, 0, 0], [0, 0, 0.38]);
  const muzzles = [];
  for (const s of [-1, 1]) {
    const tip = [4.95 * s, -1.85, -0.6];
    b.part(cyl(0.08, 0.12, 2.4, 8), dark, tip, [Math.PI / 2, 0, 0]);
    muzzles.push(b.marker([tip[0], tip[1], tip[2] - 1.3]));
  }
  const fl = engine(b, [0, 0, 3.1], 0.62, dark, 0xff4d1a, 0xffcc80, 2.6);
  const root = b.build();
  root.userData.muzzles = muzzles;
  root.userData.flames = [fl];
  return root;
}

export function missileMesh() {
  const b = new Builder();
  const white = hullMat(0xebebe6, { panel: 4, metal: 0.1, rough: 0.4, stripe: { axis: V(0, 0, 1), a: -0.7, b: -0.4, color: 0xfab829 } });
  b.part(cyl(0.16, 0.16, 2.2, 10), white, [0, 0, 0], [-Math.PI / 2, 0, 0]);
  b.part(cyl(0, 0.16, 0.5, 10), white, [0, 0, -1.35], [-Math.PI / 2, 0, 0]);
  b.part(sphere(0.3, 10), addMat(0xffbf73, 3.5), [0, 0, 1.2]);
  return b.build();
}

// ---------------- frigate (frigate.gd) ----------------

export const FRIGATE = {
  SCALE: 2,
  SHIELD_R: 19,
  CORE_POS: [0, 27, 0],
  TURRETS: [
    [[0, 15, -76], [0, 0, 0]], [[-17, 13.2, -32], [0, 0, 0]], [[17, 13.2, -32], [0, 0, 0]],
    [[0, -14, -50], [Math.PI, 0, 0]], [[-40.5, -2, 36], [0, 0, Math.PI / 2]], [[40.5, -2, 36], [0, 0, -Math.PI / 2]],
  ],
};

export function frigateModel() {
  const b = new Builder();
  const hullRed = hullMat(0x61636b, { panel: 0.22, metal: 0.5, rough: 0.42, windows: 0.07,
    stripe: { axis: V(0, 0, 1), a: -96, b: -88, color: 0x8c120d, emit: 0.4 } });
  const plate = hullMat(0x54565e, { panel: 0.35, metal: 0.55, rough: 0.45 });
  const dark = hullMat(0x1a1a1c, { panel: 0.8, metal: 0.8, rough: 0.35 });
  const bridge = hullMat(0x4d4f57, { panel: 0.5, metal: 0.5, rough: 0.45, windows: 0.45 });
  b.part(lathe([[-130, 0], [-124, 5], [-108, 11], [-80, 17], [-40, 21], [20, 22], [70, 21], [100, 19], [112, 16], [116, 0]], 8, 1.55, 0.62, false), hullRed);
  b.part(lathe([[-92, 0], [-80, 4], [-30, 7.5], [60, 7.5], [86, 0]], 6, 1.3, 1, false), plate, [0, 11, 0]);
  b.part(lathe([[-70, 0], [-60, 3], [50, 3.5], [70, 0]], 6, 1.4, 1, false), plate, [0, -11, 0]);
  b.part(box(14, 16, 24), plate, [0, 20, 64]);
  b.part(box(26, 5, 9), bridge, [0, 30, 58]);
  b.part(cyl(0.4, 0.6, 16, 8), dark, [5, 38, 66]);
  b.part(cyl(0.3, 0.5, 10, 8), dark, [-4, 36, 70]);
  for (const s of [-1, 1]) {
    b.part(box(8, 10, 64), plate, [36 * s, -2, 22]);
    b.part(box(14, 2.5, 40), plate, [16 * s, 12, -40]);
    b.part(box(3, 3, 42), dark, [9 * s, -5, -118]);
  }
  b.part(box(56, 24, 22), plate, [0, -1, 112]);
  const flames = [];
  for (const x of [-18, 0, 18]) flames.push(engine(b, [x, -1, 123], 7, dark, 0xff731f, 0xffd98c, 26));
  b.part(box(22, 0.4, 3), glowMat(0x66ccff, 3), [0, -13.2, -20]);
  const lightMat = glowMat(0xff2614, 8);
  const lights = new THREE.Group();
  for (const p of [[-36, 3.5, -6], [36, 3.5, -6], [-36, 3.5, 52], [36, 3.5, 52], [0, 46, 66], [-28, 11, 112], [28, 11, 112]]) {
    b.own(sphere(0.9, 8), lightMat, p, [0, 0, 0], [1, 1, 1], lights);
  }
  b.root.add(lights);
  // reactor
  b.part(box(16, 6, 16), plate, [0, 17, 0]);
  for (const s of [-1, 1]) b.part(box(2, 14, 4), dark, [10 * s, 22, 0]);
  const ring = new THREE.Group();
  ring.position.set(...FRIGATE.CORE_POS);
  b.root.add(ring);
  b.own(new THREE.TorusGeometry(10.25, 0.75, 12, 48), dark, [0, 0, 0], [0, Math.PI / 2, 0], [1, 1, 1], ring);
  const coreMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xff731f).multiplyScalar(5), toneMapped: false });
  const core = b.own(sphere(6.5, 32), coreMat, FRIGATE.CORE_POS);
  const shieldMat = new THREE.ShaderMaterial({
    uniforms: { strength: { value: 1 }, flash: { value: 0 }, t: { value: 0 } },
    vertexShader: `varying vec3 vN; varying vec3 vV; varying vec3 vP; void main() { vP = position;
      vec4 mv = modelViewMatrix * vec4(position, 1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz);
      gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform float strength; uniform float flash; uniform float t; varying vec3 vN; varying vec3 vV; varying vec3 vP;
      void main() { float f = pow(1.0 - abs(dot(normalize(vN), normalize(vV))), 2.5);
        vec3 p = normalize(vP); float hex = abs(sin(p.x * 30.0 + t) * sin(p.y * 30.0) * sin(p.z * 30.0 - t * 0.7));
        float a = (f * 0.9 + 0.06 + hex * 0.05) * strength + flash * (0.25 + f);
        gl_FragColor = vec4(vec3(0.45, 0.75, 1.0) * a * 1.6, a); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, toneMapped: false,
  });
  const shield = b.own(sphere(FRIGATE.SHIELD_R, 48), shieldMat, FRIGATE.CORE_POS);
  shield.renderOrder = 2;
  const root = b.build();
  root.scale.setScalar(FRIGATE.SCALE);
  return { root, ring, core, coreMat, shield, shieldMat, lights, flames, plate, dark };
}

/// A defence turret: base, yaw head, pitching twin barrels and a red eye.
export function turretModel(plate, dark) {
  const g = new THREE.Group();
  const b = new Builder();
  b.part(cyl(3.4, 3.8, 1.6, 20), dark, [0, 0.8, 0]);
  g.add(b.build());
  const yaw = new THREE.Group();
  yaw.position.set(0, 1.6, 0);
  g.add(yaw);
  const hb = new Builder();
  hb.part(sphere(2.8, 20), plate, [0, 0, 0], [0, 0, 0], [1, 0.7, 1]);
  yaw.add(hb.build());
  const pitch = new THREE.Group();
  pitch.position.set(0, 0.9, 0);
  yaw.add(pitch);
  const pb = new Builder();
  const muzzles = [];
  for (const s of [-0.7, 0.7]) {
    pb.part(cyl(0.3, 0.38, 6, 10), dark, [s, 0, -3.2], [Math.PI / 2, 0, 0]);
    muzzles.push(pb.marker([s, 0, -6.4], pitch));
  }
  pb.part(sphere(0.45, 10), glowMat(0xff3319, 7), [0, 0.6, -1.9]);
  pitch.add(pb.build());
  return { group: g, yaw, pitch, muzzles };
}
