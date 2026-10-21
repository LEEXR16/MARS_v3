// VOID WING: a space shooter for the MARS arm-support robot, in three.js for the tablet app.
// The same game as the Godot version in Software/VoidWing (rules, numbers, logs); this one is built
// for a tablet's GPU and has no engine to boot.
//   app -> game:  window.marsInput = {seq, t, th1..th4, cuff_mm, mode, enc_ok}   (input.js)
//   game -> app:  MarsGame.postMessage(JSON)  {type: 'session', ...} = logs to save, {type: 'exit'}
// Test options (desktop browser): ?auto  ?state=play|end  ?input=touch|robot  ?cam=x,y,z  ?seed=n  ?feed
import * as THREE from 'three';
import { makeRenderer, Frame, buildWorld } from './world.js';
import { Player, Fighter, Frigate, Combat } from './actors.js';
import { Fx } from './fx.js';
import { Hud } from './hud.js';
import { Menu, MINUTES } from './menu.js';
import { RobotInput, TouchInput } from './input.js';
import { Sfx } from './sfx.js';
import { clamp, damp, lerp, rand, segSphere, DEG } from './util.js';

const DIFF = [
  { name: 'EASY', fighters: 3, enemy_dmg: 3, enemy_err: 0.07, enemy_gap: 1.7, turret_dmg: 3, lock: 0.6, assist: 0.16 },
  { name: 'NORMAL', fighters: 5, enemy_dmg: 5, enemy_err: 0.04, enemy_gap: 1.1, turret_dmg: 5, lock: 0.9, assist: 0.1 },
  { name: 'HARD', fighters: 7, enemy_dmg: 8, enemy_err: 0.022, enemy_gap: 0.7, turret_dmg: 7, lock: 1.2, assist: 0.06 },
];
const ARENA = 2600;
const SPAWN = new THREE.Vector3(0, 40, 1100);
const SETTINGS_KEY = 'voidwing.settings';
const SUMMARY_HEADER = 'stamp,minutes_set,played_s,input,difficulty,score,fighters,turrets,frigates,shots,hits,' +
  'missiles,missile_hits,on_target_s,deaths,t1_min,t1_max,reach_range_mm,hand_path_mm';
const TRACE_HEADER = 't_s,th1,th2,th3,th4,cuff_x,cuff_y,cuff_z,aim_x,aim_y,score,hull,shield';
const q = new URLSearchParams(location.search);
const LITE = /Android|Mobile|iPad/i.test(navigator.userAgent);
const _a = new THREE.Vector3(), _b = new THREE.Vector3();

class Game {
  constructor() {
    this.ARENA = ARENA;
    this.state = 'menu';
    this.settings = { minutes: 5, input: 'robot', difficulty: 0 };
    try {
      const d = JSON.parse(localStorage.getItem(SETTINGS_KEY) || 'null');
      if (d) for (const k in d) if (k in this.settings) this.settings[k] = d[k];
    } catch (_) { /* defaults */ }
    if (!MINUTES.includes(this.settings.minutes)) this.settings.minutes = 5;
    this.settings.difficulty = clamp(this.settings.difficulty | 0, 0, 2);
    if (q.get('input')) this.settings.input = q.get('input');
    this.auto = q.has('auto');
    this.debugCam = q.has('cam') ? new THREE.Vector3(...q.get('cam').split(',').map(Number)) : null;
    this.diff = DIFF[0];

    const canvas = document.getElementById('gl');
    this.renderer = makeRenderer(canvas);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(68, 1, 0.5, 60000);
    this.frame = new Frame(this.renderer, this.scene, this.camera);
    const env = buildWorld(this.renderer, this.scene, +(q.get('seed') || 7), SPAWN, ARENA, LITE);
    this.rocks = env.rocks;
    this.dustMat = env.dustMat;

    this.sfx = new Sfx(() => this.player.pos);
    this.robot = new RobotInput();
    this.touch = new TouchInput(canvas);
    this.fx = new Fx(this.scene);
    this.combat = new Combat(this);
    this.hud = new Hud(document.getElementById('hud'), this);
    this.player = new Player(this);
    this.menu = new Menu(this);
    this.fighters = [];
    this.hostiles = [];
    this.missiles = [];
    this.frigate = null;
    this.camQ = new THREE.Quaternion();
    this.menuT = 0;
    this.score = 0;
    this.wave = 1;
    this.stats = {};
    this.trace = [];
    this.sessionLeft = 300;
    this.respawnT = 0;
    this.outOfBounds = false;
    this.linkLostT = 0;
    this.launchAfterCal = false;

    window.addEventListener('pointerdown', () => this.sfx.unlock(), { once: false });
    document.addEventListener('visibilitychange', () => { if (document.hidden) this.pauseGame('PAUSED'); });
    window.addEventListener('keydown', (e) => this._key(e));
    this.toMenu();
    if (q.get('state') === 'play' || q.get('state') === 'end') this.startSession();
    this.clock = new THREE.Clock();
    // warm up the shaders before the curtain lifts, so the first second does not stutter
    this.renderer.compile(this.scene, this.camera);
    const boot = document.getElementById('boot');
    requestAnimationFrame(() => { boot.style.opacity = '0'; setTimeout(() => boot.remove(), 900); });
    this.renderer.setAnimationLoop(() => this.tick());
  }

  saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(this.settings)); } catch (_) { /* not kept */ } }

  _key(e) {
    if (e.code === 'Escape' || e.code === 'KeyP') {
      if (this.state === 'play') this.pauseGame('PAUSED');
      else if (this.state === 'pause') this.resume();
    } else if (e.code === 'Enter' && (this.state === 'menu' || this.state === 'end')) this.launch();
  }

  /// a message to the MARS app (inside the app's WebView only)
  post(msg) { if (window.MarsGame) window.MarsGame.postMessage(JSON.stringify(msg)); }

  // ---------------- screens ----------------

  toMenu() {
    this._clearBattle();
    this._showcase();
    this.state = 'menu';
    this.menu.show('start');
  }

  launch() {
    if (this.settings.input === 'robot' && !this.robot.cal.done && !q.has('state') && !this.auto) {
      this.launchAfterCal = true;
      this.beginCalibration();
      return;
    }
    this.startSession();
  }

  beginCalibration() {
    this.state = 'calib';
    this.robot.cancelCalibration();
    this.menu.show('calib');
  }

  endCalibration() {
    this.robot.cancelCalibration();
    if (this.launchAfterCal && this.robot.cal.done) {
      this.launchAfterCal = false;
      this.startSession();
    } else {
      this.launchAfterCal = false;
      this.state = 'menu';
      this.menu.show('start');
    }
  }

  pauseGame(title) {
    if (this.state !== 'play') return;
    this.state = 'pause';
    this.menu.setPauseTitle(title);
    this.menu.show('pause');
  }

  resume() {
    if (this.state !== 'pause') return;
    this.state = 'play';
    this.linkLostT = 0;
    this.menu.show('');
  }

  // ---------------- session ----------------

  startSession() {
    this.diff = DIFF[this.settings.difficulty];
    this._clearBattle();
    this.sessionLeft = this.settings.minutes * 60;
    this.score = 0;
    this.wave = 1;
    this.endSlow = 0;
    this.timeScale = 1;
    this.respawnT = 0;
    this.nextFrigateT = -1;
    this.linkLostT = 0;
    this.trace = [];
    this.traceT = 0;
    this.stats = { shots: 0, hits: 0, missiles: 0, missile_hits: 0, damage_taken: 0, kills_f: 0, kills_t: 0, cores: 0,
      frigates: 0, deaths: 0, on_target: 0, t1_min: 999, t1_max: -999, r_min: 1e9, r_max: -1e9, path_mm: 0, time: 0 };
    this.lastCuff = null;
    this.player.reset(SPAWN, new THREE.Vector3(0, 0, 0), true);
    this.camQ.copy(this.player.obj.quaternion);
    this.camera.fov = 70;
    this.camera.updateProjectionMatrix();
    this._spawnFrigate(false);
    for (let i = 0; i < this.diff.fighters; i++) {
      const d = new THREE.Vector3(rand(-1, 1), rand(-0.3, 0.3), rand(-1, 1)).normalize();
      this._spawnFighter(d.multiplyScalar(rand(350, 650)), false);
    }
    this.spawnT = 6;
    this.state = 'play';
    this.menu.show('');
    this.hud.banner('FRIGATE STRIKE', 'DESTROY THE SIX DEFENCE TURRETS', 4);
  }

  finishSession() {
    if (this.state !== 'play' && this.state !== 'pause') return;
    this.timeScale = 1;
    const saved = q.has('state') ? '' : this._writeLogs(); // test runs leave no logs
    const st = this.stats;
    const acc = (100 * st.hits) / Math.max(1, st.shots);
    const tot = Math.trunc(st.on_target);
    const tiles = [['SCORE', this.score.toLocaleString('en-US')], ['FIGHTERS', st.kills_f], ['TURRETS', st.kills_t],
      ['FRIGATES', st.frigates], ['ACCURACY', `${Math.trunc(acc)}%`], ['MISSILE HITS', `${st.missile_hits} / ${st.missiles}`],
      ['TIME ON TARGET', `${Math.floor(tot / 60)}:${String(tot % 60).padStart(2, '0')}`], ['DEATHS', st.deaths]];
    if (this.settings.input === 'robot' && st.t1_max > -999) {
      tiles.push(['ARM LIFT', `${st.t1_min.toFixed(0)}° – ${st.t1_max.toFixed(0)}°`],
        ['REACH RANGE', `${Math.max(0, st.r_max - st.r_min).toFixed(0)} mm`], ['HAND PATH', `${(st.path_mm / 1000).toFixed(1)} m`]);
    }
    const played = Math.trunc(st.time);
    const sub = `${Math.floor(played / 60)}:${String(played % 60).padStart(2, '0')} PLAYED  ·  ${this.diff.name}  ·  ${this.settings.input === 'robot' ? 'ROBOT ARM' : 'TOUCH'}`;
    this._clearBattle();
    this._showcase();
    this.state = 'end';
    this.menu.showResults('SESSION COMPLETE', sub, tiles, saved ? 'Saved to ' + saved : '');
  }

  _clearBattle() {
    this.combat.clear();
    for (const f of this.fighters) f.dispose();
    this.fighters = [];
    if (this.frigate) this.frigate.dispose();
    this.frigate = null;
    this.hostiles = [];
    for (const m of this.missiles) m.dispose();
    this.missiles = [];
    this.fx.clear();
  }

  _spawnFrigate(warp) {
    const yaw = this.wave === 1 ? Math.PI / 2 : rand(0, Math.PI * 2);
    const f = new Frigate(this, yaw);
    this.frigate = f;
    this.hostiles.push(...f.targets());
    if (warp) {
      f.warpFrom = new THREE.Vector3(0, 0, 1).applyAxisAngle(new THREE.Vector3(0, 1, 0), yaw).multiplyScalar(1600);
      f.warpT = 0;
      f.obj.position.copy(f.warpFrom);
      this.fx.warp(new THREE.Vector3(), 3, this.camera);
    }
  }

  _spawnFighter(pos, warp = true) {
    const f = new Fighter(this, pos, this.player.pos);
    this.fighters.push(f);
    this.hostiles.push(f);
    if (warp) this.fx.warp(pos, 0.6, this.camera);
  }

  _fighterSpawnPoint() {
    for (let i = 0; i < 20; i++) {
      const d = new THREE.Vector3(rand(-1, 1), rand(-0.35, 0.35), rand(-1, 1)).normalize();
      const p = d.multiplyScalar(rand(1300, 1800)).add(this.player.pos);
      if (p.length() < ARENA - 300 && !this._nearRock(p, 40)) return p;
    }
    return new THREE.Vector3(rand(-400, 400), 200, rand(-400, 400));
  }

  // ---------------- callbacks ----------------

  onShotHit() { this.stats.hits++; this.hud.hitmark = 1; }

  onKill(h) {
    this.hostiles = this.hostiles.filter((x) => x !== h);
    this.hud.hitmark = 1;
    if (h.kind === 'FIGHTER') {
      this.fighters = this.fighters.filter((x) => x !== h);
      this.score += 100;
      this.stats.kills_f++;
      this.hud.message('FIGHTER DESTROYED  +100');
    } else if (h.kind === 'TURRET') {
      this.score += 250;
      this.stats.kills_t++;
    } else {
      this.score += 1000;
      this.stats.cores++;
      this.hud.message('REACTOR CORE DESTROYED  +1000');
    }
  }

  onPlayerDead() {
    this.stats.deaths++;
    this.score = Math.max(0, this.score - 200);
    this.respawnT = 3;
  }

  onFrigateDestroyed() {
    this.hostiles = this.hostiles.filter((h) => h.kind === 'FIGHTER');
    this.frigate = null;
    this.score += 5000;
    this.stats.frigates++;
    this.wave++;
    this.hud.banner('FRIGATE DESTROYED', '+5000  ·  HULL REPAIRED  ·  MISSILES RESTOCKED', 4);
    this.player.hull = Math.min(100, this.player.hull + 40);
    this.player.missiles = Math.min(Player.MAX_MISSILES, this.player.missiles + 6);
    this.nextFrigateT = 9;
  }

  objective() {
    const f = this.frigate;
    if (!f || !f.alive || f.dying) return null;
    if (!f.shieldUp) return f.core;
    let best = null, bd = Infinity;
    for (const tu of f.turrets) {
      if (!tu.alive) continue;
      const d = tu.wpos().distanceTo(this.player.pos);
      if (d < bd) { bd = d; best = tu; }
    }
    return best;
  }

  objectiveText() {
    const f = this.frigate;
    if (!f) return this.nextFrigateT > 0 ? 'ENEMY FRIGATE INBOUND' : '';
    if (f.dying) return 'FRIGATE GOING DOWN';
    if (f.shieldUp) return `DESTROY THE DEFENCE TURRETS   ${6 - f.turretsLeft()} / 6`;
    return 'DESTROY THE REACTOR CORE';
  }

  // ---------------- world queries ----------------

  *_rocksAround(p) {
    const g = 150;
    const cx = Math.floor(p.x / g), cy = Math.floor(p.y / g), cz = Math.floor(p.z / g);
    for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) for (let dz = -1; dz <= 1; dz++) {
      const cell = this.rocks.grid.get(`${cx + dx},${cy + dy},${cz + dz}`);
      if (cell) yield* cell;
    }
  }

  rockSegHit(a, b) {
    for (const i of this._rocksAround(b)) if (segSphere(a, b, this.rocks.pos[i], this.rocks.rad[i])) return true;
    return false;
  }

  _nearRock(p, margin) {
    for (const i of this._rocksAround(p)) if (p.distanceTo(this.rocks.pos[i]) < this.rocks.rad[i] + margin) return true;
    return false;
  }

  /// steering push away from the frigate and from rocks ahead (for the AI)
  avoidVector(pos, fwd, look) {
    const acc = new THREE.Vector3();
    const f = this.frigate;
    if (f && f.alive) {
      const d = _a.subVectors(pos, f.obj.position);
      const l = d.length();
      if (l < 380) acc.addScaledVector(d.normalize(), ((380 - l) / 380) * 2);
    }
    const probe = _b.copy(fwd).multiplyScalar(look).add(pos);
    for (const i of this._rocksAround(probe)) {
      const d = probe.clone().sub(this.rocks.pos[i]);
      if (d.length() < this.rocks.rad[i] + 40) acc.addScaledVector(d.normalize(), 1.5);
    }
    return acc;
  }

  // ---------------- frame ----------------

  tick() {
    const rawDt = this.clock.getDelta();
    const realDt = Math.min(rawDt, 0.05); // a long frame never makes the world jump
    this.robot.update(realDt);
    this.touch.update();
    if (this.state === 'play') this._play(realDt * (this.timeScale || 1), realDt);
    else if (this.state !== 'pause') this._showcaseCam(realDt); // paused: everything holds still
    if (this.state === 'play' || this.state === 'menu' || this.state === 'end' || this.state === 'calib') {
      const dt = this.state === 'play' ? realDt * (this.timeScale || 1) : realDt;
      this.combat.update(dt);
      for (const f of this.fighters) f.update(dt);
      if (this.frigate) this._frigateUpdate(dt);
      for (const m of this.missiles) m.update(dt);
      this.missiles = this.missiles.filter((m) => !m.dead);
      this.fx.update(dt, this.camera);
      this.hud.update(dt);
    }
    this.dustMat.uniforms.cam.value.copy(this.camera.position);
    this.dustMat.uniforms.px.value = this.renderer.getPixelRatio();
    this.fx.setViewport(window.innerHeight * this.renderer.getPixelRatio(), this.camera.fov);
    this.sfx.setEngine(this.state === 'play' && this.player.alive, this.player.speed / Player.SPEED_MAX, this.player.boosting);
    this.menu.update();
    this.frame.render(rawDt); // the resolution follows the real frame time
    this.hud.draw();
  }

  _frigateUpdate(dt) {
    const f = this.frigate;
    if (f.warpFrom) {
      f.warpT += dt / 1.8;
      const u = Math.min(1, f.warpT);
      const e = u >= 1 ? 1 : 1 - Math.pow(2, -10 * u); // ease out, expo
      f.obj.position.copy(f.warpFrom).multiplyScalar(1 - e);
      if (u >= 1) f.warpFrom = null;
    }
    f.update(dt);
  }

  _play(dt, realDt) {
    const st = this.stats;
    st.time += dt;
    if (this.endSlow > 0) {
      this.endSlow -= realDt;
      if (this.endSlow <= 0) { this.finishSession(); return; }
    } else {
      this.sessionLeft -= dt;
      if (this.sessionLeft <= 0 || (q.get('state') === 'end' && st.time > 4)) {
        this.sessionLeft = 0;
        this.endSlow = 1.8;
        this.timeScale = 0.35;
        this.hud.banner('TIME', 'SESSION COMPLETE', 2);
      }
    }

    const p = this.player;
    let aim = new THREE.Vector2(), thr = 0, boost = false;
    if (this.settings.input === 'robot') {
      aim.copy(this.robot.aim);
      p.throttle = lerp(p.throttle, 0.35 + 0.65 * this.robot.reach, damp(2, dt));
      if (!this.robot.live() && !this.auto) {
        this.linkLostT += realDt;
        if (this.linkLostT > 1) { this.pauseGame('ROBOT LINK LOST'); return; }
      } else this.linkLostT = 0;
    } else {
      aim.copy(this.touch.aim);
      p.throttle = lerp(p.throttle, 0.55, damp(2, dt));
      boost = this.touch.boost;
    }
    if (this.auto) aim = this._autopilot();

    // keep inside the arena
    const dist = p.pos.length();
    this.outOfBounds = dist > ARENA;
    if (dist > ARENA + 200) {
      const home = _a.copy(p.pos).normalize().negate().applyQuaternion(p.obj.quaternion.clone().invert());
      const want = home.z < 0 || Math.abs(home.x) > 0.1 ? new THREE.Vector2(home.x, home.y).normalize() : new THREE.Vector2(1, 0);
      aim.lerp(want, 0.8);
    }

    if (p.alive) {
      p.fly(dt, aim, thr, new THREE.Vector2(), boost);
      // shooting is automatic: guns on a target in the sights, a missile once it locks
      if (p.wantsFire()) p.fireGuns();
      if (p.locked) p.fireMissile();
      this._collidePlayer(dt);
      if (p.target && p.targetAng < 5 * DEG) st.on_target += dt;
    } else {
      this.respawnT -= dt;
      if (this.respawnT <= 0) {
        p.reset(SPAWN, new THREE.Vector3(), false);
        this.camQ.copy(p.obj.quaternion);
      }
    }
    this._chaseCam(dt);

    // reinforcements
    this.spawnT -= dt;
    const want = this.diff.fighters + this.wave - 1;
    if (this.fighters.length < want && this.spawnT <= 0) {
      this._spawnFighter(this._fighterSpawnPoint());
      this.spawnT = 5;
    }
    if (this.nextFrigateT > 0) {
      this.nextFrigateT -= dt;
      if (this.nextFrigateT <= 0) {
        this._spawnFrigate(true);
        this.hud.banner('ENEMY FRIGATE', `WAVE ${this.wave}  ·  DESTROY THE DEFENCE TURRETS`, 3.5);
      }
    }
    this._record(dt);
  }

  _collidePlayer(dt) {
    const p = this.player;
    this.bumpCd = (this.bumpCd || 0) - dt;
    for (const i of this._rocksAround(p.pos)) {
      const d = _a.subVectors(p.pos, this.rocks.pos[i]);
      const r = this.rocks.rad[i] + p.radius;
      if (d.length() < r) {
        const n = d.normalize();
        p.pos.copy(this.rocks.pos[i]).addScaledVector(n, r);
        p.vel.reflect(n).multiplyScalar(0.5);
        this._bump(this.rocks.pos[i].clone().addScaledVector(n, this.rocks.rad[i]));
        return;
      }
    }
    const f = this.frigate;
    if (f && f.alive) {
      const push = f.pushOut(p.pos, p.radius);
      if (push) {
        p.pos.add(push);
        p.vel.reflect(push.clone().normalize()).multiplyScalar(0.5);
        this._bump(p.pos.clone());
      }
    }
  }

  _bump(at) {
    this.fx.sparks(at);
    if (this.bumpCd <= 0) {
      this.bumpCd = 0.6;
      this.player.damage(clamp(this.player.speed * 0.12, 6, 30));
      this.player.speed *= 0.6;
    }
  }

  /// chase camera: follows yaw and most of the pitch with a soft lag, never rolls
  _chaseCam(dt) {
    const p = this.player, cam = this.camera;
    const want = new THREE.Quaternion().setFromEuler(new THREE.Euler(p.pitch * 0.8, p.yaw, 0, 'YXZ'));
    this.camQ.slerp(want, damp(4.5, dt));
    const fov = lerp(cam.fov, 70 + (p.boosting ? 3 : 0), damp(2, dt));
    if (Math.abs(fov - cam.fov) > 0.01) { cam.fov = fov; cam.updateProjectionMatrix(); }
    cam.position.set(0, 7, 23).applyQuaternion(this.camQ).add(p.pos);
    const look = new THREE.Vector3(0, 2.5, -45).applyQuaternion(this.camQ).add(p.pos);
    cam.up.set(0, 1, 0);
    cam.lookAt(look);
    if (this.debugCam) { cam.position.copy(this.debugCam); cam.lookAt(0, 0, 0); }
  }

  /// the menus' showcase: the ship flying left-away, the ringed planet behind
  _showcase() {
    const p = this.player;
    const at = SPAWN.clone().add(new THREE.Vector3(0, 80, 400));
    p.reset(at, at.clone().add(new THREE.Vector3(-0.95, -0.05, -0.45)), true);
    p.speed = 70;
    this.camera.fov = 50;
    this.camera.updateProjectionMatrix();
  }

  _showcaseCam(dt) {
    this.menuT += dt;
    const p = this.player, cam = this.camera;
    const at = SPAWN.clone().add(new THREE.Vector3(0, 80, 400));
    p.pos.copy(at).add(new THREE.Vector3(0, Math.sin(this.menuT * 0.7) * 0.4, 0));
    const f = new THREE.Vector3(-0.95, -0.05, -0.45).normalize();
    const m = new THREE.Matrix4().lookAt(new THREE.Vector3(), f, new THREE.Vector3(0, 1, 0));
    p.obj.quaternion.setFromRotationMatrix(m);
    p.model.rotation.set(0, 0, 0.12 + Math.sin(this.menuT * 0.5) * 0.05);
    const off = new THREE.Vector3(13, 3.2, 18).applyAxisAngle(new THREE.Vector3(0, 1, 0), 0.12 * Math.sin(this.menuT * 0.15));
    cam.position.copy(at).add(off);
    cam.lookAt(at.clone().add(new THREE.Vector3(-9.5, -1, -5)));
  }

  _autopilot() {
    const p = this.player;
    let tgt = this.objective(), best = Infinity;
    for (const f of this.fighters) {
      const d = f.wpos().distanceTo(p.pos);
      if (d < best && d < 900) { best = d; tgt = f; }
    }
    if (!tgt) return new THREE.Vector2();
    const lv = tgt.wpos().clone().sub(p.pos).normalize().applyQuaternion(p.obj.quaternion.clone().invert());
    let a = new THREE.Vector2(lv.x, lv.y).multiplyScalar(3);
    if (lv.z > 0) a = new THREE.Vector2(Math.abs(lv.x) > 0.05 ? Math.sign(lv.x) : 1, 0);
    if (a.length() > 1) a.normalize();
    return a;
  }

  _record(dt) {
    const st = this.stats, r = this.robot;
    if (this.settings.input === 'robot' && r.live()) {
      st.t1_min = Math.min(st.t1_min, r.raw.y);
      st.t1_max = Math.max(st.t1_max, r.raw.y);
      st.r_min = Math.min(st.r_min, r.raw.z);
      st.r_max = Math.max(st.r_max, r.raw.z);
      const c = r.last.cuff_mm || [0, 0, 0];
      const cv = new THREE.Vector3(+c[0], +c[1], +c[2]);
      if (this.lastCuff) st.path_mm += cv.distanceTo(this.lastCuff);
      this.lastCuff = cv;
    }
    this.traceT -= dt;
    if (this.traceT <= 0) {
      this.traceT = 0.1;
      const l = r.live() ? r.last : {};
      const c = l.cuff_mm || [0, 0, 0];
      const p = this.player;
      this.trace.push([st.time.toFixed(2), l.th1 ?? '', l.th2 ?? '', l.th3 ?? '', l.th4 ?? '', c[0], c[1], c[2],
        p.aimNow.x.toFixed(3), p.aimNow.y.toFixed(3), this.score, Math.trunc(p.hull), Math.trunc(p.shield)]);
    }
  }

  /// the app saves both files on the tablet (Android/data/.../MARS/game/), as the desktop game does
  _writeLogs() {
    const st = this.stats, s = this.settings;
    const d = new Date(), z = (n) => String(n).padStart(2, '0');
    const stamp = `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}_${z(d.getHours())}-${z(d.getMinutes())}-${z(d.getSeconds())}`;
    const arm = s.input === 'robot' && st.t1_max > -999;
    const row = [stamp, s.minutes, Math.trunc(st.time), s.input, this.diff.name, this.score, st.kills_f, st.kills_t,
      st.frigates, st.shots, st.hits, st.missiles, st.missile_hits, st.on_target.toFixed(1), st.deaths,
      arm ? st.t1_min.toFixed(1) : '', arm ? st.t1_max.toFixed(1) : '',
      arm ? Math.trunc(st.r_max - st.r_min) : '', arm ? Math.trunc(st.path_mm) : ''].join(',');
    const trace = [TRACE_HEADER, ...this.trace.map((r) => r.join(','))].join('\n') + '\n';
    this.post({ type: 'session', stamp, summary_header: SUMMARY_HEADER, summary_row: row, trace });
    return `the tablet: MARS/game/session_${stamp}.csv`;
  }
}

// ?feed: a fake robot (a slow figure-eight of the arm), for checking robot mode in a browser
if (q.has('feed')) {
  let seq = 0;
  const t0 = performance.now();
  setInterval(() => {
    const t = (performance.now() - t0) / 1000;
    const th1 = 90 + 18 * Math.sin(t * 0.5);
    window.marsInput = { seq: ++seq, t, th1, th2: 20, th3: -60, th4: 0, enc_ok: true, mode: 'WINDOW',
      cuff_mm: [600 * Math.cos(th1 * DEG), 600 * Math.sin(th1 * DEG), 120 * Math.sin(t * 0.9)] };
  }, 40);
}

window.game = new Game();
