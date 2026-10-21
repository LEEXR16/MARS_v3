// MARS robot, live 3D: the desktop GUI's 3D view (MARS_GUI/view3d.py) as a solid model.
// Geometry and frames are the GUI's kinematics.py:
//   world (mm): origin = motor centre, z = motor shaft, x = down in the start pose, y = z cross x
//   theta1 turns the robot plane about z; in-plane coordinates (x', z'), x' = the plane's "down";
//   link 1 at theta2, link 2 at theta2 + theta3, cuff axis at theta2 + theta3 + theta4 + 90
//   (all angles 0 = every link hanging straight down)
// Scene (m, Y up): the shaft is +X, the robot plane is a group turned about X by theta1, so in that
// group local (x, y) = (z', -x') and the joints turn about local Z (the plane normal).
// Driven by the app:  window.marsState = {live, theta1, enc: [th2, th3, th4], encOk: [..], mode, cal, armOk}
// App <- page:        MarsView.postMessage('ready')  (JavaScript channel) once the scene is up
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// ---- kinematics.py ----
const J2_X = 55, J2_Z = 75, R1 = 480, R2 = 300, CUFF_AXIS_DEG = 90;
const HUMAN = { shoulder_z: 300, upper_arm: 300, elbow_to_cuff: 200 }; // mars_config.json "human"
const MOTOR_H = 1.05;                // motor centre above the floor (m), for the picture only
const rad = THREE.MathUtils.degToRad;
const mm = (v) => v / 1000;

function fkPlane(t2, t3, t4) {
  const a2 = rad(t2), a23 = rad(t2 + t3);
  const p2 = [J2_X, J2_Z];
  const p3 = [p2[0] + R1 * Math.cos(a2), p2[1] + R1 * Math.sin(a2)];
  const p4 = [p3[0] + R2 * Math.cos(a23), p3[1] + R2 * Math.sin(a23)];
  return { p2, p3, p4, cuffAxis: t2 + t3 + t4 + CUFF_AXIS_DEG };
}

const planeToWorld = (xp, zp, t1) => [xp * Math.cos(rad(t1)), xp * Math.sin(rad(t1)), zp];

/// The GUI's stylised human arm: shoulder on the motor axis, two-link IK to the cuff, elbow on
/// the ground side. In-plane points + whether the cuff is within reach.
function humanArm(cuff) {
  const s = [0, HUMAN.shoulder_z];
  const dx = cuff[0] - s[0], dz = cuff[1] - s[1];
  const d = Math.hypot(dx, dz);
  const lu = HUMAN.upper_arm, lf = HUMAN.elbow_to_cuff;
  const ok = Math.abs(lu - lf) < d && d < lu + lf;
  const u = [dx / Math.max(d, 1e-6), dz / Math.max(d, 1e-6)];
  let e;
  if (!ok) {
    e = [s[0] + u[0] * lu, s[1] + u[1] * lu];
  } else {
    const a = (lu * lu - lf * lf + d * d) / (2 * d);
    const h = Math.sqrt(Math.max(lu * lu - a * a, 0));
    const n = [u[1], -u[0]];
    const e1 = [s[0] + a * u[0] + h * n[0], s[1] + a * u[1] + h * n[1]];
    const e2 = [s[0] + a * u[0] - h * n[0], s[1] + a * u[1] - h * n[1]];
    e = e1[0] > e2[0] ? e1 : e2; // larger x' = closer to the ground
  }
  return { s, e, c: cuff, ok };
}

/// in-plane (x', z') mm -> the plane group's local scene coordinates (m)
const local = (p) => new THREE.Vector3(mm(p[1]), -mm(p[0]), 0);

/// What the cuff / arm is doing, from telemetry only (view3d.py cuff_state)
function cuffState(s) {
  if (!s || !s.live) return 'none';
  if (s.cal === 2) return 'measuring';
  if (s.mode === 'ASSIST') return 'assist';
  if (s.armOk) return 'cuffed';
  return 'open';
}

// ---- colours (theme.dart) ----
const C = {
  bg: 0x16100b, accent: 0xf2a254, accentDim: 0x8c5d2e, gold: 0xffdc8f, ok: 0x5fd38d,
  text: 0xf5e9d8, frame: 0x8a8580, frameDark: 0x3a3532, border: 0x2b1f14,
};

// ---- scene ----
const container = document.getElementById('viewport');
const scene = new THREE.Scene();
scene.background = new THREE.Color(C.bg);
scene.fog = new THREE.Fog(C.bg, 5, 11);

const camera = new THREE.PerspectiveCamera(38, 1, 0.05, 40);
camera.position.set(1.75, 1.55, 1.55);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
container.appendChild(renderer.domElement);
// soft studio reflections, so the metal parts read as metal instead of black
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.45;

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0.12, 0.72, -0.3);
controls.enableDamping = true;
controls.minDistance = 0.9;
controls.maxDistance = 5;
controls.maxPolarAngle = Math.PI * 0.52;

scene.add(new THREE.HemisphereLight(0xf5e9d8, 0x2a1a0e, 0.9));
const key = new THREE.DirectionalLight(0xffe2c2, 2.4);
key.position.set(2.2, 3.4, 1.6);
key.castShadow = true;
key.shadow.mapSize.set(1024, 1024);
Object.assign(key.shadow.camera, { left: -1.5, right: 1.5, top: 1.5, bottom: -1.5, near: 0.5, far: 8 });
key.shadow.bias = -0.0004;
key.shadow.radius = 4;
scene.add(key);
const rim = new THREE.DirectionalLight(0xffc89a, 0.6);
rim.position.set(-2.5, 1.8, -2.2);
scene.add(rim);

// floor: grid + soft shadow
const grid = new THREE.GridHelper(4, 40, 0x5a3f27, 0x2b1f14);
grid.material.transparent = true;
grid.material.opacity = 0.55;
scene.add(grid);
const floor = new THREE.Mesh(new THREE.PlaneGeometry(6, 6), new THREE.ShadowMaterial({ opacity: 0.35 }));
floor.rotation.x = -Math.PI / 2;
floor.position.y = 0.001;
floor.receiveShadow = true;
scene.add(floor);

// ---- materials ----
const std = (color, metalness, roughness, extra = {}) =>
  new THREE.MeshStandardMaterial({ color, metalness, roughness, ...extra });
const M = {
  frame: std(C.frame, 0.55, 0.35),           // anodised aluminium extrusions
  dark: std(C.frameDark, 0.3, 0.55),
  motor: std(0x2a2725, 0.6, 0.35),
  accentRing: std(C.accent, 0.4, 0.35, { emissive: C.accentDim, emissiveIntensity: 0.25 }),
  link: std(C.accent, 0.45, 0.3),            // the carbon tubes, in the GUI's link colour
  joint: std(C.text, 0.2, 0.35),
  cell: std(0xc9c3ba, 0.7, 0.28),
};
const shadowed = (m) => { m.castShadow = true; m.receiveShadow = true; return m; };
const mesh = (geo, mat, parent, pos) => {
  const m = shadowed(new THREE.Mesh(geo, mat));
  if (pos) m.position.copy(pos);
  parent.add(m);
  return m;
};
/// a cylinder along +X / +Z / -Y between two local points
function cylAlong(r, a, b, mat, parent, seg = 20) {
  const d = new THREE.Vector3().subVectors(b, a);
  const m = mesh(new THREE.CylinderGeometry(r, r, d.length(), seg), mat, parent);
  m.position.copy(a).addScaledVector(d, 0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
  return m;
}

// ---- fixed frame: load platform, column (height actuator), motor ----
const frame = new THREE.Group();
scene.add(frame);
const colX = -0.24;
mesh(new THREE.BoxGeometry(0.56, 0.035, 0.5), M.dark, frame, new THREE.Vector3(colX + 0.05, 0.06, -0.05));
for (const [dx, dz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
  mesh(new THREE.CylinderGeometry(0.032, 0.032, 0.045, 20), M.cell, frame,
    new THREE.Vector3(colX + 0.05 + dx * 0.22, 0.022, -0.05 + dz * 0.19)); // the four load cells
}
const colH = MOTOR_H + 0.14;
mesh(new THREE.BoxGeometry(0.085, colH, 0.085), M.frame, frame, new THREE.Vector3(colX, 0.078 + colH / 2, 0));
mesh(new THREE.BoxGeometry(0.02, colH - 0.1, 0.04), M.dark, frame, new THREE.Vector3(colX + 0.052, 0.13 + colH / 2, 0)); // rail
mesh(new THREE.BoxGeometry(0.13, 0.2, 0.13), M.dark, frame, new THREE.Vector3(colX + 0.02, MOTOR_H, 0)); // carriage
mesh(new THREE.BoxGeometry(0.12, 0.07, 0.09), M.frame, frame, new THREE.Vector3(colX + 0.13, MOTOR_H, 0)); // arm to motor
// AK10-9 motor along the shaft (scene X), from x = -110 mm to 0, with the brake disc behind it
const motorGroup = new THREE.Group();
motorGroup.position.set(0, MOTOR_H, 0);
frame.add(motorGroup);
const xCyl = (r, len, x, mat, seg = 36) => {
  const m = mesh(new THREE.CylinderGeometry(r, r, len, seg), mat, motorGroup);
  m.rotation.z = Math.PI / 2;
  m.position.x = x;
  return m;
};
xCyl(0.06, 0.1, -0.06, M.motor);
xCyl(0.062, 0.012, -0.012, M.accentRing);
xCyl(0.05, 0.012, -0.116, M.dark);
// the shaft axis line, like the GUI
const axisLine = new THREE.Line(
  new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(-0.35, 0, 0), new THREE.Vector3(1.0, 0, 0)]),
  new THREE.LineBasicMaterial({ color: C.accent, transparent: true, opacity: 0.25 }));
motorGroup.add(axisLine);

// ---- the robot plane, turned by theta1 ----
const plane = new THREE.Group();
motorGroup.add(plane);
// translucent sheet, view3d.py's quad (0,-150) .. (900, 800) in (x', z')
const sheet = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 0.9),
  new THREE.MeshBasicMaterial({ color: C.accent, transparent: true, opacity: 0.07, side: THREE.DoubleSide, depthWrite: false }));
sheet.position.set(mm(325), -mm(450), 0);
plane.add(sheet);
const sheetEdge = new THREE.LineSegments(new THREE.EdgesGeometry(sheet.geometry),
  new THREE.LineBasicMaterial({ color: C.accent, transparent: true, opacity: 0.22 }));
sheetEdge.position.copy(sheet.position);
plane.add(sheetEdge);

// hub on the shaft and the bracket out to DOF 2
const hub = mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.03, 32), M.frame, plane);
hub.rotation.z = Math.PI / 2;
hub.position.x = 0.015;
const j2 = local([J2_X, J2_Z]);
cylAlong(0.016, new THREE.Vector3(0.015, 0, 0), new THREE.Vector3(j2.x, 0, 0), M.frame, plane);
cylAlong(0.016, new THREE.Vector3(j2.x, 0, 0), j2, M.frame, plane);

/// a joint housing: a short cylinder along the plane normal (local Z)
function joint(parent, r = 0.03) {
  const m = mesh(new THREE.CylinderGeometry(r, r, 0.07, 28), M.joint, parent);
  m.rotation.x = Math.PI / 2;
  return m;
}
function link(parent, length) {
  cylAlong(0.017, new THREE.Vector3(0, -0.02, 0), new THREE.Vector3(0, -length + 0.02, 0), M.link, parent);
  // clamps at both ends
  mesh(new THREE.BoxGeometry(0.05, 0.05, 0.05), M.dark, parent, new THREE.Vector3(0, -0.045, 0));
  mesh(new THREE.BoxGeometry(0.05, 0.05, 0.05), M.dark, parent, new THREE.Vector3(0, -length + 0.045, 0));
}

const dof2 = new THREE.Group(); // shoulder joint (encoder 1)
dof2.position.copy(j2);
plane.add(dof2);
joint(dof2, 0.034);
link(dof2, mm(R1));
const dof3 = new THREE.Group(); // elbow joint (encoder 2)
dof3.position.set(0, -mm(R1), 0);
dof2.add(dof3);
joint(dof3);
link(dof3, mm(R2));
const dof4 = new THREE.Group(); // cuff joint (encoder 3)
dof4.position.set(0, -mm(R2), 0);
dof3.add(dof4);
joint(dof4, 0.026);

// the cuff: a C-shaped band around the forearm axis (local +X of dof4); the gap closes as it locks
const cuffPivot = new THREE.Group();
dof4.add(cuffPivot);
cuffPivot.rotation.y = Math.PI / 2; // torus axis (Z) -> local X
const cuffMat = std(C.accent, 0.3, 0.4, { emissive: C.accent, emissiveIntensity: 0.15 });
let cuffMesh = null;
let cuffGapShown = -1;
function buildCuff(gap) {
  if (cuffMesh) {
    cuffPivot.remove(cuffMesh);
    cuffMesh.geometry.dispose();
  }
  cuffMesh = shadowed(new THREE.Mesh(new THREE.TorusGeometry(0.052, 0.011, 10, 40, Math.PI * 2 - gap), cuffMat));
  cuffMesh.rotation.z = Math.PI / 2 + gap / 2; // the opening faces up, away from the link
  cuffMesh.scale.set(1, 1, 3.2); // a band, not a wire
  cuffPivot.add(cuffMesh);
}

// ---- stylised human arm (in the robot plane) ----
const armMat = new THREE.MeshStandardMaterial({ color: C.gold, metalness: 0.0, roughness: 0.65,
  transparent: true, opacity: 0.0, depthWrite: false });
const armJointMat = armMat.clone();
const capsule = (r) => {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, 1, 6, 16), armMat);
  plane.add(m);
  return m;
};
const upperArm = capsule(0.042);
const foreArm = capsule(0.034);
const hand = capsule(0.03);
const shoulderBall = new THREE.Mesh(new THREE.SphereGeometry(0.055, 20, 14), armJointMat);
plane.add(shoulderBall);
function placeCapsule(m, a, b) {
  const d = new THREE.Vector3().subVectors(b, a);
  const len = Math.max(d.length(), 1e-4);
  m.position.copy(a).addScaledVector(d, 0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
  m.scale.set(1, len, 1); // CapsuleGeometry(r, 1): the straight part scales with the length
}

function onResize() {
  const w = container.clientWidth, h = Math.max(container.clientHeight, 1);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
}
window.addEventListener('resize', onResize);
onResize();

// ?demo: a moving test pose, for checking the page in a desktop browser without the robot
// ?zero: the start pose, all joints 0;  ?cam=x,y,z: camera position;  ?state=open|measuring|cuffed|assist
const q = new URLSearchParams(location.search);
if (q.has('cam')) camera.position.set(...q.get('cam').split(',').map(Number));
const fakeState = q.get('state') || 'cuffed';
const fake = (theta1, enc) => ({ live: true, theta1, enc, encOk: [true, true, true],
  mode: fakeState === 'assist' ? 'ASSIST' : 'WINDOW', cal: fakeState === 'measuring' ? 2 : 0, armOk: fakeState !== 'open' });
if (q.has('zero')) window.marsState = fake(0, [0, 0, 0]);
if (q.has('pose')) window.marsState = fake(...(() => { const v = q.get('pose').split(',').map(Number); return [v[0], v.slice(1)]; })());
if (q.has('demo')) {
  const t0 = performance.now();
  setInterval(() => {
    const t = (performance.now() - t0) / 1000;
    window.marsState = fake(90 + 22 * Math.sin(t * 0.6), [25 + 20 * Math.sin(t * 0.4), -60 + 15 * Math.sin(t * 0.5), -10]);
  }, 50);
}

// ---- frame loop: ease towards the newest telemetry (the app sends 10 per second) ----
const shown = { t1: 0, enc: [0, 0, 0], closed: 0, armAlpha: 0 };
const cuffEl = document.getElementById('cuff');
const stateEl = document.getElementById('state');
const statusEl = document.getElementById('status');
const LABEL = { none: 'NO DATA', open: 'CUFF OPEN', measuring: 'CUFF LOCKED · MEASURING ARM',
  cuffed: 'CUFF LOCKED', assist: 'CUFF LOCKED · ASSIST' };
const COLOR = { none: '#6e5a45', open: '#f2a254', measuring: '#ffdc8f', cuffed: '#5fd38d', assist: '#5fd38d' };
const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);
  const dt = Math.min(clock.getDelta(), 0.1);
  const now = clock.elapsedTime;
  const s = window.marsState;
  const live = !!(s && s.live);
  const k = 1 - Math.exp(-10 * dt);
  // no data: the start pose, as the GUI shows it
  shown.t1 += ((live ? s.theta1 : 0) - shown.t1) * k;
  for (let i = 0; i < 3; i++) {
    const want = live ? (s.encOk && s.encOk[i] ? s.enc[i] : shown.enc[i]) : 0;
    shown.enc[i] += (want - shown.enc[i]) * k;
  }
  const [t2, t3, t4] = shown.enc;
  plane.rotation.x = rad(shown.t1);
  dof2.rotation.z = rad(t2);
  dof3.rotation.z = rad(t3);
  dof4.rotation.z = rad(t4);

  const state = cuffState(s);
  const closedWant = state === 'none' || state === 'open' ? 0 : 1;
  shown.closed += (closedWant - shown.closed) * Math.min(1, dt * 4);
  shown.armAlpha += ((closedWant ? 0.95 : 0.18) - shown.armAlpha) * Math.min(1, dt * 3);
  const gap = Math.round(rad(140) * (1 - shown.closed) * 40) / 40; // rebuild only when it visibly changes
  if (gap !== cuffGapShown) {
    buildCuff(gap);
    cuffGapShown = gap;
  }
  const pulse = state === 'measuring' ? 1 + 0.12 * Math.sin(now * 8) : 1;
  cuffPivot.scale.setScalar(pulse);
  cuffMat.color.set(shown.closed < 0.5 ? C.accent : state === 'measuring' ? C.gold : C.ok);
  cuffMat.emissive.copy(cuffMat.color);

  // the human arm follows the cuff
  const f = fkPlane(t2, t3, t4);
  const arm = humanArm(f.p4);
  const ca = rad(f.cuffAxis);
  const handEnd = [f.p4[0] + 120 * Math.cos(ca), f.p4[1] + 120 * Math.sin(ca)];
  placeCapsule(upperArm, local(arm.s), local(arm.e));
  placeCapsule(foreArm, local(arm.e), local(arm.c));
  placeCapsule(hand, local(arm.c), local(handEnd));
  shoulderBall.position.copy(local(arm.s));
  armMat.opacity = shown.armAlpha * 0.55;
  armJointMat.opacity = shown.armAlpha * 0.8;
  const armVisible = shown.armAlpha > 0.02;
  for (const m of [upperArm, foreArm, hand, shoulderBall]) m.visible = armVisible;
  M.link.color.set(live ? C.accent : C.accentDim);

  const cw = planeToWorld(f.p4[0], f.p4[1], shown.t1);
  cuffEl.textContent = `CUFF  x y z [mm] ${cw.map((v) => v.toFixed(0).padStart(7)).join('  ')}`;
  stateEl.textContent = LABEL[state] + (arm.ok || state === 'none' ? '' : '  ·  ARM OUT OF REACH (stylised)');
  stateEl.style.color = COLOR[state];
  statusEl.textContent = live
    ? `θ1 ${s.theta1.toFixed(1)}°   θ2 ${t2.toFixed(0)}°  θ3 ${t3.toFixed(0)}°  θ4 ${t4.toFixed(0)}°   ${s.mode}`
    : 'drag to turn · pinch to zoom';
  controls.update();
  renderer.render(scene, camera);
}
animate();
if (window.MarsView) window.MarsView.postMessage('ready');
