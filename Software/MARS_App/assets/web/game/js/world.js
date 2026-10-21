// The setting: a calm sky with Gargantua (black hole), a distant sun, a ringed gas giant, a sparse
// asteroid belt and faint space dust. The sky never moves, so it is rendered once into a cubemap:
// the tablet spends its frame time on the ships, not on noise in the background.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { rng, noise3 } from './util.js';

export const SUN_DIR = new THREE.Vector3(0.55, 0.42, 0.72).normalize();
export const BH_DIR = new THREE.Vector3(-0.45, 0.16, -0.88).normalize(); // Gargantua: ahead-left at the start
export const CLEAR_R = 430;     // no rocks this close to the frigate (origin)
export const GRID = 150;        // rock lookup cell size (m)

// ---------------- renderer + bloom, with a resolution that follows the frame rate ----------------

export function makeRenderer(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  return renderer;
}

export function hdrType(renderer) {
  const e = renderer.extensions;
  return e.has('EXT_color_buffer_half_float') || e.has('EXT_color_buffer_float') ? THREE.HalfFloatType : THREE.UnsignedByteType;
}

export class Frame {
  constructor(renderer, scene, camera) {
    this.renderer = renderer;
    this.scene = scene;
    this.camera = camera;
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    this.scale = 1.0;         // 0.6 .. 1: dropped while frames are slow, raised again when there is room
    // HDR (half float) when the GPU can render into it, else 8-bit: dimmer bloom, but never black
    const type = hdrType(renderer);
    this.composer = type === THREE.HalfFloatType ? new EffectComposer(renderer)
      : new EffectComposer(renderer, new THREE.WebGLRenderTarget(1, 1, { type }));
    this.composer.addPass(new RenderPass(scene, camera));
    // only HDR light blooms (engines, lasers, fire, the core): the sky and lit hulls stay crisp
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.5, 0.45, 1.15);
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());
    this.avg = 1 / 60;
    this.check = 0;
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    const pr = this.dpr * this.scale;
    this.renderer.setPixelRatio(pr);
    this.renderer.setSize(w, h, false);
    this.composer.setPixelRatio(pr);
    this.composer.setSize(w, h);
    this.bloom.setSize(Math.round(w * pr / 2), Math.round(h * pr / 2)); // bloom at half resolution
    this.camera.aspect = w / Math.max(h, 1);
    this.camera.updateProjectionMatrix();
  }

  render(dt) {
    this.composer.render(dt);
    // keep ~50 fps or better: a smaller drawing buffer is far less visible than a stutter
    this.avg += (dt - this.avg) * 0.05;
    this.check += dt;
    if (this.check > 2.0) {
      this.check = 0;
      const before = this.scale;
      if (this.avg > 1 / 45 && this.scale > 0.6) this.scale = Math.max(0.6, this.scale - 0.1);
      else if (this.avg < 1 / 58 && this.scale < 1) this.scale = Math.min(1, this.scale + 0.05);
      if (this.scale !== before) this.resize();
    }
  }
}

// ---------------- sky (sky.gdshader), baked into a cubemap ----------------

const SKY_FRAG = /* glsl */`
uniform vec3 sun_dir;
uniform vec3 bh_dir;
varying vec3 vDir;
const float bh_size = 0.05;
const float bh_incl = 0.07;
const float milky = 0.035;

float hash13(vec3 p3) { p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
vec3 hash33(vec3 p3) { p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx); }
float vnoise(vec3 x) {
  vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.02 + vec3(3.1, 1.7, 5.3); a *= 0.5; } return s; }
vec3 stars(vec3 d, float scale, float density, float size, float bright) {
  vec3 p = d * scale; vec3 id = floor(p); vec3 f = fract(p);
  vec3 c = hash33(id) * 0.6 + 0.2;
  float present = step(1.0 - density, hash13(id + 3.7));
  float b = present * (1.0 - smoothstep(0.0, size, length(f - c)));
  vec3 col = mix(vec3(0.78, 0.85, 1.0), vec3(1.0, 0.9, 0.78), hash13(id + 9.1));
  float mag = pow(hash13(id + 1.3), 4.0) * 2.5 + 0.35;
  return col * b * b * mag * bright;
}
vec3 gargantua(vec3 d, out float occl) {
  occl = 0.0;
  vec3 f = normalize(bh_dir);
  float w = dot(d, f);
  if (w < 0.5) return vec3(0.0);
  vec3 rt = normalize(cross(f, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(rt, f);
  vec2 p = vec2(dot(d, rt), dot(d, up)) / w;
  float ca = cos(0.12), sa = sin(0.12);
  p = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) / bh_size;
  float r = length(p);
  occl = 1.0 - smoothstep(0.97, 1.03, r);
  vec3 hot = vec3(1.0, 0.86, 0.66), warm = vec3(1.0, 0.56, 0.26);
  float si = sin(bh_incl);
  float left = -p.x / max(r, 1e-3);
  float rho = sqrt(p.x * p.x + (p.y / si) * (p.y / si));
  float ring = smoothstep(1.55, 1.9, rho) * exp(-max(rho - 1.9, 0.0) * 1.0) * (1.0 - smoothstep(4.5, 6.5, rho));
  float streaks = 0.6 + 0.4 * vnoise(vec3(rho * 7.0, 0.0, 1.0)) + 0.15 * vnoise(vec3(rho * 23.0, 3.0, 0.0));
  float dopp = 1.0 + 0.5 * clamp(-p.x / max(rho, 1e-3), -1.0, 1.0);
  vec3 disk = mix(warm, hot, exp(-(rho - 1.6) * 0.7)) * ring * streaks * dopp * 2.4;
  vec3 front = p.y <= 0.0 ? disk : vec3(0.0);
  vec3 back = p.y > 0.0 ? disk : vec3(0.0);
  float ang = atan(p.y, p.x);
  float vert = pow(abs(p.y) / max(r, 1e-3), 2.0);
  float halo = exp(-pow((r - 1.18 - 0.22 * vert) / (0.08 + 0.26 * vert), 2.0)) * (0.05 + 0.95 * vert);
  halo *= 0.7 + 0.3 * vnoise(vec3(ang * 9.0, r * 6.0, 2.0));
  halo *= 1.0 + 0.35 * left;
  float photon = exp(-pow((r - 1.035) / 0.016, 2.0));
  float glow = exp(-max(r - 1.0, 0.0) * 1.6) * 0.06;
  vec3 lensed = (hot * halo * 1.2 + vec3(1.0, 0.92, 0.82) * photon * 2.0 + warm * glow) * (1.0 - occl);
  return front + back * (1.0 - occl) + lensed;
}
void main() {
  vec3 d = normalize(vDir);
  vec3 gal_n = normalize(vec3(0.3, 1.0, 0.25));
  float band = exp(-pow(dot(d, gal_n) * 3.2, 2.0));
  float n = fbm(d * 3.0 + vec3(3.1));
  float lanes = smoothstep(0.45, 0.7, fbm(d * 7.0 + 5.0));
  vec3 col = mix(vec3(0.55, 0.6, 0.75), vec3(0.85, 0.75, 0.62), n) * band * (0.4 + n) * (1.0 - 0.6 * lanes) * milky;
  float occl;
  vec3 bh = gargantua(d, occl);
  vec3 st = stars(d, 170.0, 0.05 + 0.08 * band, 0.28, 0.55);
  st += stars(d, 85.0, 0.035 + 0.03 * band, 0.2, 1.0);
  st += stars(d, 38.0, 0.022, 0.11, 2.4);
  col += st * (1.0 - occl);
  col = col * (1.0 - occl) + bh;
  float sd = max(dot(d, normalize(sun_dir)), 0.0);
  col += vec3(1.0, 0.94, 0.86) * (pow(sd, 6000.0) * 9.0 + pow(sd, 300.0) * 0.03);
  gl_FragColor = vec4(col * 0.75, 1.0);
}`;

function bakeSky(renderer, size) {
  const skyScene = new THREE.Scene();
  const mat = new THREE.ShaderMaterial({
    uniforms: { sun_dir: { value: SUN_DIR }, bh_dir: { value: BH_DIR } },
    vertexShader: 'varying vec3 vDir; void main() { vDir = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: SKY_FRAG,
    side: THREE.BackSide, depthWrite: false,
  });
  skyScene.add(new THREE.Mesh(new THREE.SphereGeometry(10, 64, 32), mat));
  const rt = new THREE.WebGLCubeRenderTarget(size, { type: hdrType(renderer), generateMipmaps: true,
    minFilter: THREE.LinearMipmapLinearFilter });
  const cube = new THREE.CubeCamera(0.1, 100, rt);
  cube.update(renderer, skyScene);
  mat.dispose();
  return rt;
}

// ---------------- gas giant + ring (planet.gdshader, planet_ring.gdshader) ----------------

const NOISE_GLSL = /* glsl */`
float hashp(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoisep(vec3 x) { vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hashp(i), hashp(i + vec3(1, 0, 0)), f.x), mix(hashp(i + vec3(0, 1, 0)), hashp(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hashp(i + vec3(0, 0, 1)), hashp(i + vec3(1, 0, 1)), f.x), mix(hashp(i + vec3(0, 1, 1)), hashp(i + vec3(1, 1, 1)), f.x), f.y), f.z); }
float fbmp(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vnoisep(p); p *= 2.05; a *= 0.5; } return s; }`;

function planet(scene) {
  const dir = new THREE.Vector3(0.8, -0.28, 0.55).normalize();
  const center = dir.clone().multiplyScalar(20000);
  const r = 1900;
  const tilt = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), 0.35);
  const mat = new THREE.ShaderMaterial({
    uniforms: { sun: { value: SUN_DIR } },
    vertexShader: `varying vec3 lp; varying vec3 wn; varying vec3 vd;
      void main() { lp = normalize(position); wn = normalize(mat3(modelMatrix) * normal);
        vec4 w = modelMatrix * vec4(position, 1.0); vd = normalize(cameraPosition - w.xyz);
        gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: NOISE_GLSL + `
      uniform vec3 sun; varying vec3 lp; varying vec3 wn; varying vec3 vd;
      void main() {
        vec3 c1 = vec3(0.62, 0.50, 0.37), c2 = vec3(0.38, 0.28, 0.20), c3 = vec3(0.75, 0.68, 0.58), atmo = vec3(0.95, 0.72, 0.50);
        float warp = fbmp(lp * vec3(3.0, 9.0, 3.0)) * 0.22;
        float lat = lp.y + warp;
        float b = sin(lat * 26.0) * 0.5 + 0.5, b2 = sin(lat * 61.0 + 1.3) * 0.5 + 0.5;
        vec3 col = mix(c2, c1, b);
        col = mix(col, c3, b2 * 0.35 * smoothstep(0.2, 0.9, fbmp(lp * 6.0)));
        float lit = clamp(dot(normalize(wn), sun), 0.0, 1.0);
        float fres = pow(1.0 - clamp(dot(normalize(wn), vd), 0.0, 1.0), 4.0);
        gl_FragColor = vec4(col * (0.04 + 1.6 * lit) + atmo * fres * 0.35 * (0.2 + lit), 1.0);
      }`,
    fog: false,
  });
  const p = new THREE.Mesh(new THREE.SphereGeometry(1, 96, 48), mat);
  p.position.copy(center);
  p.quaternion.copy(tilt);
  p.scale.setScalar(r);
  scene.add(p);
  const ringMat = new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `varying vec2 vUv;
      void main() {
        vec2 p = vUv * 2.0 - 1.0; float r = length(p); float inner = 0.52;
        if (r < inner || r > 1.0) discard;
        float t = (r - inner) / (1.0 - inner);
        float bands = 0.5 + 0.25 * sin(t * 95.0) + 0.25 * sin(t * 37.0 + 1.0);
        float gap = (1.0 - smoothstep(0.0, 0.025, abs(t - 0.63))) + (1.0 - smoothstep(0.0, 0.012, abs(t - 0.86))) * 0.7;
        vec3 col = mix(vec3(0.42, 0.34, 0.25), vec3(0.82, 0.70, 0.52), bands) * 0.8;
        float a = (0.25 + 0.6 * bands) * smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.92, 1.0, t)) * (1.0 - gap);
        gl_FragColor = vec4(col, clamp(a, 0.0, 1.0));
      }`,
    transparent: true, side: THREE.DoubleSide, depthWrite: false,
  });
  const ring = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), ringMat);
  ring.position.copy(center);
  ring.quaternion.copy(tilt).multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), 0.5 - Math.PI / 2));
  ring.scale.setScalar(r * 2.3);
  scene.add(ring);
}

// ---------------- asteroids (proc.gd asteroid) ----------------

/// IcosahedronGeometry comes as separate triangles; share the corners so the rock shades smoothly
function indexedSphere(subdiv) {
  const src = new THREE.IcosahedronGeometry(1, subdiv).attributes.position;
  const map = new Map(), verts = [], idx = [];
  for (let i = 0; i < src.count; i++) {
    const key = `${src.getX(i).toFixed(4)},${src.getY(i).toFixed(4)},${src.getZ(i).toFixed(4)}`;
    let j = map.get(key);
    if (j === undefined) { j = verts.length / 3; map.set(key, j); verts.push(src.getX(i), src.getY(i), src.getZ(i)); }
    idx.push(j);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
  g.setIndex(idx);
  return g;
}

function asteroidGeometry(seed, subdiv) {
  const R = rng(seed);
  const geo = indexedSphere(subdiv);
  const pos = geo.attributes.position;
  const stretch = [0.8 + R() * 0.5, 0.62 + R() * 0.3, 0.8 + R() * 0.55];
  const craters = [];
  const nc = 4 + Math.floor(R() * 6);
  for (let i = 0; i < nc; i++) {
    const d = new THREE.Vector3(R() * 2 - 1, R() * 2 - 1, R() * 2 - 1).normalize();
    craters.push([d, 0.16 + R() * 0.26, 0.05 + R() * 0.09]);
  }
  const v = new THREE.Vector3();
  const colors = new Float32Array(pos.count * 3);
  const off = seed * 0.37;
  for (let i = 0; i < pos.count; i++) {
    v.fromBufferAttribute(pos, i).normalize();
    let r = 1 + noise3(v.x * 0.9 + off, v.y * 0.9, v.z * 0.9) * 0.34 * 2 - 0.34
      + (noise3(v.x * 2.8 + 5, v.y * 2.8 + 5, v.z * 2.8 + off) - 0.5) * 0.14;
    let dark = 0;
    for (const [cd, size, depth] of craters) {
      const k = v.angleTo(cd) / size;
      if (k < 1) { r += (k * k - 1) * depth; dark += (1 - k) * 0.35; }
      else if (k < 1.4) r += Math.sin(Math.PI * (k - 1) / 0.4) * depth * 0.35;
    }
    pos.setXYZ(i, v.x * r * stretch[0], v.y * r * stretch[1], v.z * r * stretch[2]);
    const g = 0.55 + 0.45 * noise3(v.x * 4 + off, v.y * 4, v.z * 4) - dark;
    colors[i * 3] = g * 1.0; colors[i * 3 + 1] = g * 0.93; colors[i * 3 + 2] = g * 0.86;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geo.computeVertexNormals();
  return geo;
}

function asteroids(scene, R, spawn, arena, lite) {
  const near = [], far = [];
  for (let i = 0; i < 6; i++) {
    near.push(asteroidGeometry(1000 + i * 37, lite ? 3 : 4));
    far.push(asteroidGeometry(1000 + i * 37, 2));
  }
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, color: 0x8a8178, roughness: 0.92, metalness: 0.05 });
  const pos = [], rad = [];
  const grid = new Map();
  const per = [[], [], [], [], [], []];
  const perFar = [[], [], [], [], [], []];
  const p = new THREE.Vector3();
  let tries = 0;
  while (pos.length < 420 && tries < 20000) {
    tries++;
    p.set(R() * 2 - 1, (R() * 2 - 1) * 0.35, R() * 2 - 1).multiplyScalar(arena);
    if (p.length() > arena || p.length() < CLEAR_R || p.distanceTo(spawn) < 180) continue;
    let s = 2 + 34 * Math.pow(R(), 4);
    if (R() < 0.04) s = 45 + R() * 40;
    per[Math.floor(R() * 6)].push([p.clone(), s]);
    pos.push(p.clone());
    rad.push(s * 0.92);
    const key = cellKey(p.x, p.y, p.z);
    if (!grid.has(key)) grid.set(key, []);
    grid.get(key).push(pos.length - 1);
  }
  for (let i = 0; i < 240; i++) {   // distant scenery, no collisions
    const d = new THREE.Vector3(R() * 2 - 1, (R() * 2 - 1) * 0.3, R() * 2 - 1).normalize();
    perFar[Math.floor(R() * 6)].push([d.multiplyScalar(arena + 300 + R() * (arena * 1.6 - 300)), 10 + R() * 80]);
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(), axis = new THREE.Vector3();
  const tint = new THREE.Color();
  const place = (lists, geos) => {
    for (let v = 0; v < 6; v++) {
      const list = lists[v];
      if (!list.length) continue;
      const im = new THREE.InstancedMesh(geos[v], mat, list.length);
      for (let i = 0; i < list.length; i++) {
        axis.set(R() * 2 - 1, R() * 2 - 1, R() * 2 - 1).normalize();
        q.setFromAxisAngle(axis, R() * Math.PI * 2);
        sc.setScalar(list[i][1]);
        im.setMatrixAt(i, m4.compose(list[i][0], q, sc));
        const w = 0.75 + R() * 0.45;
        im.setColorAt(i, tint.setRGB(w, w * (0.94 + R() * 0.06), w * (0.86 + R() * 0.1)));
      }
      im.instanceMatrix.needsUpdate = true;
      scene.add(im);
    }
  };
  place(per, near);
  place(perFar, far);
  return { pos, rad, grid };
}

export const cellKey = (x, y, z) => `${Math.floor(x / GRID)},${Math.floor(y / GRID)},${Math.floor(z / GRID)}`;

// ---------------- dust: specks that wrap around the camera (dust.gdshader) ----------------

function dust(scene, R) {
  const n = 420;
  const a = new Float32Array(n * 3);
  for (let i = 0; i < n * 3; i++) a[i] = R() * 240;
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(a, 3));
  const mat = new THREE.ShaderMaterial({
    uniforms: { cam: { value: new THREE.Vector3() }, px: { value: 1 } },
    vertexShader: `uniform vec3 cam; uniform float px; varying float vA;
      void main() {
        vec3 p = mod(position - cam, 240.0) - 120.0 + cam;
        vec4 mv = viewMatrix * vec4(p, 1.0);
        float d = -mv.z;
        vA = smoothstep(120.0, 60.0, d) * smoothstep(2.0, 8.0, d);
        gl_PointSize = px * clamp(60.0 / d, 1.0, 4.0);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `varying float vA;
      void main() { vec2 c = gl_PointCoord - 0.5; float a = smoothstep(0.5, 0.0, length(c)) * vA * 0.5;
        gl_FragColor = vec4(vec3(0.85, 0.82, 0.78) * a, a); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  const pts = new THREE.Points(g, mat);
  pts.frustumCulled = false;
  scene.add(pts);
  return mat;
}

// ---------------- build ----------------

export function buildWorld(renderer, scene, seed, spawn, arena, lite) {
  const sky = bakeSky(renderer, lite ? 1024 : 1536);
  scene.background = sky.texture;
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromCubemap(sky.texture).texture;
  scene.environmentIntensity = 0.6;
  pmrem.dispose();

  scene.add(new THREE.AmbientLight(0x3a3c44, 1.6));
  // a soft fill from behind the chase camera, so the ships never turn into black silhouettes
  const fill = new THREE.HemisphereLight(0x9aa6c8, 0x2a2018, 0.55);
  scene.add(fill);
  const sun = new THREE.DirectionalLight(0xfff0d8, 2.6);
  sun.position.copy(SUN_DIR).multiplyScalar(1000);
  scene.add(sun);
  const disk = new THREE.DirectionalLight(0xffbd7a, 0.7);   // warm light from Gargantua's accretion disk
  disk.position.copy(BH_DIR).multiplyScalar(1000);
  scene.add(disk);

  const R = rng(seed);
  planet(scene);
  const rocks = asteroids(scene, R, spawn, arena, lite);
  const dustMat = dust(scene, R);
  return { rocks, dustMat };
}
