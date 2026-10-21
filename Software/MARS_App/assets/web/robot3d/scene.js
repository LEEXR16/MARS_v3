// MARS robot, live 3D: the CAD model (PERSEVERANCE_V1-3, re-jointed in Fusion 360) rigged as a joint
// chain, from HMI/frontend/scene.js. The joint directions were checked against the real robot.
// Driven by the app:  window.marsState = {live, theta1, enc: [th2, th3, th4], encOk: [..], mode}
// App <- page:        MarsView.postMessage('ready')  (JavaScript channel) once the model has loaded
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const container = document.getElementById('viewport');
const statusEl = document.getElementById('status');

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x16100b);
scene.fog = new THREE.Fog(0x16100b, 8, 16);

const camera = new THREE.PerspectiveCamera(42, container.clientWidth / container.clientHeight, 0.05, 50);
camera.position.set(2.6, 1.6, 3.2);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(container.clientWidth, container.clientHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
container.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0, 0.75, 0);
controls.enableDamping = true;
controls.minDistance = 1.2;
controls.maxDistance = 8;
controls.maxPolarAngle = Math.PI * 0.55;

// warm key light, cool fill, like the MARS GUI
scene.add(new THREE.HemisphereLight(0xf5e9d8, 0x2a1a0e, 1.1));
const key = new THREE.DirectionalLight(0xffe2c2, 2.2);
key.position.set(4, 7, 3);
scene.add(key);
const fill = new THREE.DirectionalLight(0x9fb4ff, 0.7);
fill.position.set(-5, 3, -4);
scene.add(fill);

const grid = new THREE.GridHelper(6, 24, 0x5a3f27, 0x2b1f14);
scene.add(grid);

// Node names come straight off the CAD export (PERSEVERANCE_V1-3.gltf, reassembled/rejointed
// in Fusion360 to fix the floating-arm issue in v6). GLTFLoader
// sanitizes them (THREE.PropertyBinding.sanitizeNodeName: whitespace -> "_", then strips
// reserved chars "[].:/") and de-dupes repeats with a "_<n>" suffix, so we replicate that
// here rather than hand-writing the sanitized strings.
function sanitizeName(raw) {
  return raw.replace(/\s/g, '_').replace(/[[\].:/]/g, '');
}
function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function namesToMatcher(rawNames) {
  const regexes = rawNames.map(
    (n) => new RegExp('^' + escapeRegExp(sanitizeName(n)) + '(_\\d+)?$')
  );
  return (name) => regexes.some((re) => re.test(name));
}

// Grouping worked out in MARS_HMI_v1.md against models/tree.txt (PERSEVERANCE_V1 v6 export).
const LINEAR_Y_NAMES = [
  'EXO7 v13',
  'Component43 (1)', 'Component44 (1)', 'Component45 (1)', 'Component46 (1)',
  'Component46(Mirror) (1) (1)', 'Component46(Mirror) (2)', 'Component46(Mirror)(Mirror) (1)',
  'TOP_PLATE (1)', 'MOTOR: AK10-9 (2)', 'Component182', 'Component183',
  'BOTTOM_PLATE (1)', 'LOAD_CELL_BLOCKS (1)',
  'loadcell v1(Mirror) (1) (1)', 'loadcell v1(Mirror) (2)', 'loadcell v1(Mirror)(Mirror) (1)',
  // Bearing carriage blocks — ride on the fixed rail but are mounted to (and travel with) the
  // moving platform. Was misclassified static in the v6 grouping table; only becomes visible
  // as a detached-looking pair once linActPos moves off 0.
  'SC16 SCS16UU Linear Rail Bearing v1 v1',
];
const DOF01_NAMES = ['BREAK PAD (1)', 'MOTOR_SHAFT'];
const DOF02_NAMES = [
  'BASE_MOUNT-01', 'BEARING_MOUNT', '61801.f3d  v1 (2)', '61801.f3d  v1 (3)',
  'Component148', 'DOF_2-SHAFT', 'CF2MOTORLNK BEARING-H v8 (1)',
  // Solenoid mechanism new in PERSEVERANCE_V1-3 export, rigidly mounted to the DOF02 arm segment.
  'H-SOLENOID ROD v1', 'CONFIG_SOL_HOLDER', 'Component1 (4)', 'M3 Cap Nut v2 (4)',
  'O-Ring v2 (4)', 'Plunger v1 (4)', 'Spring v3 (4)', 'Circlip v1 (4)', 'Coil v1 (4)',
];
const DOF03_NAMES = [
  'TUBE-CFRF_480MM', 'SHAFT LNK PLATE v4 (1)', 'SHAFTLNK BEARING-H v3 (2)', 'SHAFTLNK BEARING-H v3 (3)',
  '61802-2z.f3d  v1 (3)', '61802-2z.f3d  v1 (4)', 'DOF03_SHAFT', '2H SHAFT LNK HOLDER v1',
];
const DOF04_NAMES = [
  '2H SHAFT LNK END v7 (1)', '61802-2z.f3d  v1 (5)', '61802-2z.f3d  v1 (6)',
  'DOF04_SHAFT', 'FOREARM CUFF v2 (1)', 'TUBE-CFRF_300',
];

const isLinearY = namesToMatcher(LINEAR_Y_NAMES);
const isDof01 = namesToMatcher(DOF01_NAMES);
const isDof02 = namesToMatcher(DOF02_NAMES);
const isDof03 = namesToMatcher(DOF03_NAMES);
const isDof04 = namesToMatcher(DOF04_NAMES);

// "CF2MOTOR LINK v2 (1)" is one reused CAD part instanced 4x (48 mesh nodes, 12 per
// instance) — the sanitized name is identical for all 4, so it can't disambiguate which
// joint a given instance rides on. Mesh index is stable per instance (unlike the loader's
// name-dedupe suffix, which depends on load order), so bucket by that instead.
const isCf2MotorLink = namesToMatcher(['CF2MOTOR LINK v2 (1)']);
const CF2_MESH_RANGES = {
  dof02: [[1068, 1079]],
  dof03: [[1088, 1099], [1331, 1342]],
  dof04: [[1347, 1358]],
};
function cf2Bucket(meshIndex) {
  for (const [bucket, ranges] of Object.entries(CF2_MESH_RANGES)) {
    if (ranges.some(([lo, hi]) => meshIndex >= lo && meshIndex <= hi)) return bucket;
  }
  return null;
}

// Joint pivots: bounding-box center of each shaft's geometry, in raw CAD (pre-rotation,
// pre-scale) space — see MARS_HMI_v1.md for how these were derived from accessor min/max.
const PIVOT_DOF01 = new THREE.Vector3(0.052797, 0.995836, 0.0);
const PIVOT_DOF02 = new THREE.Vector3(0.092808, 0.995836, 0.037998);
const PIVOT_DOF03 = new THREE.Vector3(0.092797, 0.495325, 0.045598);
const PIVOT_DOF04 = new THREE.Vector3(0.092797, 0.194336, 0.033998);

// Linear actuator travel, raw CAD units (this export is in meters): 200mm, retracted -> extended.
const LINEAR_TRAVEL = 0.2;

let linearGroup = null;
let dof01Group = null;
let dof02Group = null;
let dof03Group = null;
let dof04Group = null;
const armMeshes = [];

const loader = new GLTFLoader();
loader.load('models/mars_robot.gltf', (gltf) => {
  const model = gltf.scene;
  // Every part of this export carries the same node matrix: a 45 deg turn about Z with a sqrt(2)
  // stretch in X and Y (rounded values). The joint pivots below are in the parts' raw coordinates,
  // where the column stands along +Y and the arm hangs along -Y, so drop those matrices: otherwise
  // the robot leans 45 deg and the joints turn about the wrong points (the arm looks detached).
  model.traverse((o) => {
    if (o === model) return;
    o.position.set(0, 0, 0);
    o.quaternion.identity();
    o.scale.set(1, 1, 1);
  });

  linearGroup = new THREE.Group();
  model.add(linearGroup);

  dof01Group = new THREE.Group();
  dof01Group.position.copy(PIVOT_DOF01);
  linearGroup.add(dof01Group);

  dof02Group = new THREE.Group();
  dof02Group.position.copy(PIVOT_DOF02).sub(PIVOT_DOF01);
  dof01Group.add(dof02Group);

  dof03Group = new THREE.Group();
  dof03Group.position.copy(PIVOT_DOF03).sub(PIVOT_DOF02);
  dof02Group.add(dof03Group);

  dof04Group = new THREE.Group();
  dof04Group.position.copy(PIVOT_DOF04).sub(PIVOT_DOF03);
  dof03Group.add(dof04Group);

  // Collect first (matching by name while re-parenting mutates model's children live).
  const parts = [];
  model.traverse((obj) => {
    if (obj === linearGroup || obj === dof01Group || obj === dof02Group ||
        obj === dof03Group || obj === dof04Group) return;
    if (isLinearY(obj.name) || isDof01(obj.name) || isDof02(obj.name) ||
        isDof03(obj.name) || isDof04(obj.name) || isCf2MotorLink(obj.name)) {
      parts.push(obj);
    }
  });

  const groups = { linear_y: linearGroup, dof01: dof01Group, dof02: dof02Group, dof03: dof03Group, dof04: dof04Group };
  const pivots = { dof01: PIVOT_DOF01, dof02: PIVOT_DOF02, dof03: PIVOT_DOF03, dof04: PIVOT_DOF04 };
  for (const part of parts) {
    let bucket;
    if (isCf2MotorLink(part.name)) {
      const meshChild = part.children.find((c) => gltf.parser.associations.get(c));
      const assoc = gltf.parser.associations.get(part) || (meshChild && gltf.parser.associations.get(meshChild));
      bucket = assoc && cf2Bucket(assoc.meshes);
      if (!bucket) continue;
    } else if (isLinearY(part.name)) bucket = 'linear_y';
    else if (isDof01(part.name)) bucket = 'dof01';
    else if (isDof02(part.name)) bucket = 'dof02';
    else if (isDof03(part.name)) bucket = 'dof03';
    else bucket = 'dof04';
    if (pivots[bucket]) part.position.sub(pivots[bucket]);
    groups[bucket].add(part);
  }

  // the moving links: tinted amber while live data arrives
  dof02Group.traverse((o) => {
    if (o.isMesh) {
      o.material = o.material.clone();
      o.userData.base = o.material.color.clone();
      armMeshes.push(o);
    }
  });

  // PERSEVERANCE_V1-3 is already Y-up: the joint pivots run straight down Y (DOF01 y 1.0 -> DOF04 y 0.19),
  // i.e. the arm hangs along -Y in the start pose. (The HMI's -90 deg turn was for the older Z-up export.)
  const box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const scale = 2 / Math.max(size.x, size.y, size.z);
  model.scale.setScalar(scale);
  model.position.sub(center.multiplyScalar(scale));
  model.position.y += (size.y * scale) / 2;
  scene.add(model);

  document.getElementById('loading').remove();
  if (window.MarsView) window.MarsView.postMessage('ready');
}, undefined, (err) => {
  document.getElementById('loading').textContent = 'robot model failed to load: ' + err;
});

function onResize() {
  camera.aspect = container.clientWidth / Math.max(container.clientHeight, 1);
  camera.updateProjectionMatrix();
  renderer.setSize(container.clientWidth, container.clientHeight);
}
window.addEventListener('resize', onResize);

// Joint angles ease towards the newest values (the app sends ~20 per second; the screen runs at 60)
const shown = { theta1: 0, enc: [0, 0, 0] };
let lastLive = null;
const amber = new THREE.Color(0xf2a254);

// ?demo: a moving test pose, for checking the page in a desktop browser without the robot
// ?zero: the start pose, all joints 0;  ?cam=x,y,z: camera position (both for checking only)
const q = new URLSearchParams(location.search);
if (q.has('cam')) camera.position.set(...q.get('cam').split(',').map(Number));
if (q.has('zero')) window.marsState = { live: true, theta1: 0, enc: [0, 0, 0], encOk: [true, true, true], mode: 'OFF' };
if (location.search.includes('demo')) {
  const t0 = performance.now();
  setInterval(() => {
    const t = (performance.now() - t0) / 1000;
    window.marsState = { live: true, theta1: 90 + 25 * Math.sin(t * 0.6), enc: [20 * Math.sin(t * 0.4), -50 + 15 * Math.sin(t * 0.5), 10],
                         encOk: [true, true, true], mode: 'WINDOW' };
  }, 50);
}

function animate() {
  requestAnimationFrame(animate);
  const s = window.marsState;
  const live = !!(s && s.live);
  if (s && live) {
    const k = 0.25;
    shown.theta1 += (s.theta1 - shown.theta1) * k;
    for (let i = 0; i < 3; i++) {
      if (s.encOk && s.encOk[i]) shown.enc[i] += (s.enc[i] - shown.enc[i]) * k;
    }
  }
  if (dof01Group) {
    linearGroup.position.y = 0;
    dof01Group.rotation.x = THREE.MathUtils.degToRad(-shown.theta1); // + theta1 raises the arm
    dof02Group.rotation.z = THREE.MathUtils.degToRad(shown.enc[0]);
    dof03Group.rotation.z = THREE.MathUtils.degToRad(shown.enc[1]);
    dof04Group.rotation.z = THREE.MathUtils.degToRad(shown.enc[2]);
    if (live !== lastLive) {
      for (const m of armMeshes) m.material.color.copy(m.userData.base).lerp(amber, live ? 0.35 : 0);
      lastLive = live;
    }
  }
  statusEl.textContent = !s ? '' : live
    ? `θ1 ${s.theta1.toFixed(1)}°   θ2 ${s.enc[0].toFixed(0)}°  θ3 ${s.enc[1].toFixed(0)}°  θ4 ${s.enc[2].toFixed(0)}°   ${s.mode}`
    : 'no live data · drag to turn, pinch to zoom';
  controls.update();
  renderer.render(scene, camera);
}
animate();
