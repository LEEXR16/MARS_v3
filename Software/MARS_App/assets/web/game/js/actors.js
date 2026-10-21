// Everything that flies or shoots: the player's Ranger, interceptors, the frigate with its turrets
// and reactor core, missiles, and the lasers / bolts (combat). Ported from the Godot scripts with
// the same numbers (player.gd, fighter.gd, frigate.gd, turret.gd, core.gd, missile.gd, combat.gd).
import * as THREE from 'three';
import { ranger, fighter as fighterModel, frigateModel, turretModel, missileMesh, FRIGATE } from './ships.js';
import { clamp, damp, lerp, moveToward, wrapAngle, rand, lookQuat, segSphere, fwdOf, DEG } from './util.js';

const UP = new THREE.Vector3(0, 1, 0);
const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3(), _d = new THREE.Vector3();
const _q = new THREE.Quaternion(), _e = new THREE.Euler();
const angleTo = (u, v) => u.angleTo(v);

// ---------------- player (player.gd) ----------------
// Flight is horizon-locked for comfort: the arm sets yaw and pitch rates, pitch is limited to +-55
// deg and the camera never rolls. Banking into turns only tilts the model.

export class Player {
  static RATE_PITCH = 0.75;
  static RATE_YAW = 0.95;
  static PITCH_MAX = 0.96;
  static RATE_RESPONSE = 5.0;
  static GRIP = 2.2;
  static BANK_MAX = 0.62;
  static SPEED_MIN = 45;
  static SPEED_MAX = 175;
  static SPEED_BOOST = 270;
  static LASER_SPEED = 950;
  static MAX_MISSILES = 14;

  constructor(game) {
    this.game = game;
    this.obj = new THREE.Group();
    this.model = ranger();
    this.obj.add(this.model);
    this.muzzles = this.model.userData.muzzles;
    game.scene.add(this.obj);
    this.vel = new THREE.Vector3();
    this.radius = 4.5;
    this.reset(new THREE.Vector3(), new THREE.Vector3(0, 0, -1), true);
  }

  get pos() { return this.obj.position; }
  fwd(out = new THREE.Vector3()) { return fwdOf(this.obj, out); }
  velocity() { return this.vel; }

  reset(pos, lookAt, full = true) {
    this.obj.position.copy(pos);
    const d = _a.subVectors(lookAt, pos).normalize();
    this.yaw = Math.atan2(-d.x, -d.z);
    this.pitch = clamp(Math.asin(clamp(d.y, -1, 1)), -Player.PITCH_MAX, Player.PITCH_MAX);
    this._orient();
    this.speed = 100;
    this.fwd(this.vel).multiplyScalar(this.speed);
    this.throttle = 0.45;
    this.yawRate = 0; this.pitchRate = 0; this.bank = 0;
    this.model.rotation.set(0, 0, 0);
    this.hull = 100; this.shield = 100; this.boost = 1; this.boosting = false;
    this.alive = true;
    this.obj.visible = true;
    this.invuln = 3;
    this.sinceHit = 10;
    this.target = null; this.targetAng = Math.PI; this.lockT = 0; this.locked = false; this.beepT = 0;
    this.gunCd = 0; this.gunSide = 0; this.missileCd = 0;
    this.aimNow = new THREE.Vector2();
    if (full) this.missiles = Player.MAX_MISSILES;
  }

  _orient() { this.obj.quaternion.setFromEuler(_e.set(this.pitch, this.yaw, 0, 'YXZ')); }

  /// one frame of flight. aim: -1..1 (x right, y up) = turn-rate demand
  fly(dt, aim, thrIn, strafe, wantBoost) {
    if (!this.alive) return;
    const a = aim.clone();
    if (a.length() > 1) a.normalize();
    this.aimNow.copy(a);
    const k = damp(Player.RATE_RESPONSE, dt);
    this.yawRate = lerp(this.yawRate, -a.x * Player.RATE_YAW, k);
    // near the pitch limit the climb fades out; with the stick centred the nose drifts back to level
    let wantP = a.y * Player.RATE_PITCH;
    if (Math.sign(wantP) === Math.sign(this.pitch)) wantP *= clamp((Player.PITCH_MAX - Math.abs(this.pitch)) / 0.3, 0, 1);
    if (Math.abs(a.y) < 0.06) wantP = -this.pitch * 0.2;
    this.pitchRate = lerp(this.pitchRate, wantP, k);
    this.yaw = wrapAngle(this.yaw + this.yawRate * dt);
    this.pitch = clamp(this.pitch + this.pitchRate * dt, -Player.PITCH_MAX, Player.PITCH_MAX);
    this._orient();

    this.throttle = clamp(this.throttle + thrIn * 0.6 * dt, 0, 1);
    this.boosting = wantBoost && this.boost > 0.05;
    this.boost = clamp(this.boost + (this.boosting ? -0.33 : 0.12) * dt, 0, 1);
    const targetSpeed = this.boosting ? Player.SPEED_BOOST : lerp(Player.SPEED_MIN, Player.SPEED_MAX, this.throttle);
    this.speed = moveToward(this.speed, targetSpeed, (this.boosting ? 120 : 45) * dt);

    const right = _b.set(1, 0, 0).applyQuaternion(this.obj.quaternion);
    const want = this.fwd(_a).multiplyScalar(this.speed).addScaledVector(right, strafe.x * 40).addScaledVector(UP, strafe.y * 40);
    this.vel.lerp(want, damp(Player.GRIP, dt));
    this.obj.position.addScaledVector(this.vel, dt);

    this.bank = lerp(this.bank, (this.yawRate / Player.RATE_YAW) * Player.BANK_MAX, damp(3, dt));
    this.model.rotation.z = this.bank;
    this.model.rotation.x = lerp(this.model.rotation.x, this.pitchRate * 0.1, damp(4, dt));

    this.sinceHit += dt;
    this.invuln = Math.max(0, this.invuln - dt);
    if (this.sinceHit > 3) this.shield = Math.min(100, this.shield + 14 * dt);
    this.gunCd -= dt;
    this.missileCd -= dt;
    this._updateTarget(dt);
  }

  _updateTarget(dt) {
    const g = this.game;
    let best = null, bestAng = 14 * DEG;
    const f = this.fwd(_c);
    for (const h of g.hostiles) {
      if (!h.alive || !h.targetable()) continue;
      const d = _d.subVectors(h.wpos(), this.pos);
      if (d.length() > 2600) continue;
      let ang = angleTo(f, d);
      if (h === this.target) ang *= 0.7; // sticky
      if (ang < bestAng) { bestAng = ang; best = h; }
    }
    if (best !== this.target) { this.target = best; this.lockT = 0; this.locked = false; }
    this.targetAng = Math.PI;
    if (!this.target) return;
    const d = _d.subVectors(this.target.wpos(), this.pos);
    this.targetAng = angleTo(f, d);
    const need = g.diff.lock;
    if (this.targetAng < 8 * DEG && d.length() < 2100) this.lockT += dt;
    else this.lockT = Math.max(0, this.lockT - dt * 2);
    if (!this.locked && this.lockT >= need) {
      this.locked = true;
      g.sfx.play('locked');
    } else if (!this.locked && this.lockT > 0) {
      this.beepT -= dt;
      if (this.beepT <= 0) { this.beepT = 0.18; g.sfx.play('beep'); }
    }
    if (this.locked && this.targetAng > 16 * DEG) { this.locked = false; this.lockT = 0; }
  }

  /// guns fire by themselves when a hostile sits inside the aim-assist cone and in range
  wantsFire() {
    if (!this.alive || !this.target || !this.target.alive) return false;
    return this.targetAng < this.game.diff.assist + 0.05 && this.pos.distanceTo(this.target.wpos()) < 1500;
  }

  lockProgress() { return this.locked ? 1 : clamp(this.lockT / this.game.diff.lock, 0, 1); }

  fireGuns() {
    if (this.gunCd > 0 || !this.alive) return;
    const g = this.game;
    this.gunCd = 0.1;
    const from = this.muzzles[this.gunSide].getWorldPosition(new THREE.Vector3());
    this.gunSide = 1 - this.gunSide;
    const aimPt = this.fwd(_a).multiplyScalar(700).add(this.pos);
    if (this.target && this.targetAng < g.diff.assist) {
      const dist = this.pos.distanceTo(this.target.wpos());
      aimPt.copy(this.target.wpos()).addScaledVector(this.target.velocity(), dist / Player.LASER_SPEED);
    }
    g.combat.fire(from, aimPt.sub(from).normalize(), Player.LASER_SPEED, 0, 1, this.vel);
    g.stats.shots++;
    g.sfx.play('laser');
    g.fx.flash(from, 0x80c0ff, 2, 0, 0.06);
  }

  fireMissile() {
    if (this.missiles <= 0 || this.missileCd > 0 || !this.locked || !this.target || !this.alive) return;
    const g = this.game;
    this.missiles--;
    this.missileCd = 0.8;
    const down = _b.set(0, -1, 0).applyQuaternion(this.obj.quaternion);
    g.missiles.push(new Missile(g, this.pos.clone().add(down), this.fwd(), this.vel, this.target));
    g.stats.missiles++;
    g.sfx.play('missile');
    this.lockT = 0;
    this.locked = false;
  }

  damage(dmg) {
    if (!this.alive || this.invuln > 0) return;
    const g = this.game;
    this.sinceHit = 0;
    const s = Math.min(this.shield, dmg);
    this.shield -= s;
    const rest = dmg - s;
    this.hull -= rest;
    g.hud.hit(rest > 0);
    g.sfx.play(rest > 0 ? 'hit' : 'shield');
    g.stats.damage_taken += dmg;
    if (this.hull <= 0) this.die();
  }

  die() {
    this.alive = false;
    this.obj.visible = false;
    this.locked = false;
    this.game.fx.explode(this.pos, 2.2, true, this.game.camera);
    this.game.sfx.play('boom');
    this.game.onPlayerDead();
  }
}

// ---------------- interceptor (fighter.gd) ----------------

export class Fighter {
  static BOLT_SPEED = 620;
  constructor(game, pos, lookAt) {
    this.game = game;
    this.kind = 'FIGHTER';
    this.obj = new THREE.Group();
    this.model = fighterModel();
    this.obj.add(this.model);
    this.muzzles = this.model.userData.muzzles;
    this.flames = this.model.userData.flames;
    game.scene.add(this.obj);
    this.obj.position.copy(pos);
    lookQuat(_a.subVectors(lookAt, pos).normalize(), UP, this.obj.quaternion);
    this.speed = rand(105, 130);
    this.turn = rand(0.95, 1.25);
    this.vel = fwdOf(this.obj).multiplyScalar(this.speed);
    this.hp = 3; this.maxHp = 3; this.radius = 6.5;
    this.alive = true;
    this.mode = 0; this.modeT = 0; this.modeLen = 3;
    this.breakDir = new THREE.Vector3();
    this.gunCd = rand(2, 4);
    this.burst = 0;
  }
  wpos() { return this.obj.position; }
  velocity() { return this.vel; }
  targetable() { return this.alive; }

  update(dt) {
    if (!this.alive) return;
    const g = this.game, p = g.player;
    const toP = _a.subVectors(p.pos, this.obj.position);
    const dist = toP.length();
    let desired = _b;
    this.modeT += dt;
    if (this.mode === 0) {
      desired.copy(p.pos).addScaledVector(p.vel, clamp(dist / 700, 0, 1.2)).sub(this.obj.position).normalize();
      if (dist < 170 || this.modeT > 12 || !p.alive) {
        this.mode = 1; this.modeT = 0; this.modeLen = rand(2.5, 4.5);
        const side = _c.crossVectors(toP, UP).normalize();
        if (side.length() < 0.1) side.set(1, 0, 0);
        this.breakDir.copy(side).multiplyScalar(Math.random() < 0.5 ? 1 : -1).add(_d.set(0, rand(-0.6, 0.6), 0))
          .addScaledVector(toP.clone().normalize(), -0.3).normalize();
      }
    } else {
      desired.copy(this.breakDir);
      if (this.modeT > this.modeLen) { this.mode = 0; this.modeT = 0; }
    }
    const f = fwdOf(this.obj, _c);
    desired.addScaledVector(g.avoidVector(this.obj.position, f, 130), 1.5).normalize();
    if (this.obj.position.length() > g.ARENA - 200) desired.addScaledVector(this.obj.position.clone().normalize(), -1.2).normalize();
    this._turnToward(desired, dt);
    fwdOf(this.obj, this.vel).multiplyScalar(this.speed);
    this.obj.position.addScaledVector(this.vel, dt);
    for (const fl of this.flames) if (fl) fl.material.uniforms.t.value += dt;

    this.gunCd -= dt;
    if (this.mode === 0 && p.alive && dist < 1000 && angleTo(fwdOf(this.obj, _c), toP) < 0.22 && this.gunCd <= 0) {
      const m = this.muzzles[this.burst % 2].getWorldPosition(new THREE.Vector3());
      const aim = p.pos.clone().addScaledVector(p.vel, dist / Fighter.BOLT_SPEED);
      const e = g.diff.enemy_err;
      const dir = aim.sub(m).normalize().add(_d.set(rand(-e, e), rand(-e, e), rand(-e, e))).normalize();
      g.combat.fire(m, dir, Fighter.BOLT_SPEED, 1, g.diff.enemy_dmg);
      g.sfx.playAt('elaser', this.obj.position);
      this.burst++;
      this.gunCd = this.burst % 3 !== 0 ? 0.14 : g.diff.enemy_gap * rand(0.8, 1.6);
    }
  }

  _turnToward(desired, dt) {
    const f = fwdOf(this.obj, new THREE.Vector3());
    const ang = angleTo(f, desired);
    const axis = new THREE.Vector3().crossVectors(f, desired);
    if (ang > 1e-3 && axis.length() > 1e-5) f.applyAxisAngle(axis.normalize(), Math.min(ang, this.turn * dt));
    const up = Math.abs(f.y) < 0.95 ? UP : new THREE.Vector3(0, 1, 0).applyQuaternion(this.obj.quaternion);
    lookQuat(f, up, this.obj.quaternion);
    const localUp = new THREE.Vector3(0, 1, 0).applyQuaternion(this.obj.quaternion);
    const bank = clamp(axis.dot(localUp) * 6, -1.2, 1.2);
    this.model.rotation.z = lerp(this.model.rotation.z, bank, damp(3, dt));
  }

  hit(dmg, pos) {
    if (!this.alive) return;
    this.hp -= dmg;
    this.game.fx.sparks(pos);
    if (this.hp <= 0) {
      this.alive = false;
      this.game.fx.explode(this.obj.position, 1.4, true, this.game.camera);
      this.game.sfx.playAt('boom', this.obj.position);
      this.game.onKill(this);
      this.dispose();
    }
  }

  dispose() { this.game.scene.remove(this.obj); }
}

// ---------------- frigate, turrets, reactor core ----------------

class Turret {
  static BOLT_SPEED = 560;
  constructor(game, frigate, pos, rot, plate, dark) {
    this.game = game;
    this.frigate = frigate;
    this.kind = 'TURRET';
    const t = turretModel(plate, dark);
    this.obj = t.group;
    this.yawNode = t.yaw;
    this.pitchNode = t.pitch;
    this.muzzles = t.muzzles;
    this.obj.position.set(...pos);
    this.obj.rotation.set(rot[0], rot[1], rot[2], 'YXZ');
    this.hp = 10; this.maxHp = 10; this.radius = 6 * FRIGATE.SCALE;
    this.alive = true;
    this.gunCd = rand(2, 5);
    this.burst = 0;
    this._w = new THREE.Vector3();
  }
  wpos() { return this.obj.getWorldPosition(this._w); }
  velocity() { return new THREE.Vector3(); }
  targetable() { return this.alive; }

  update(dt) {
    const f = this.frigate, g = this.game, p = g.player;
    if (!this.alive || !f.alive || f.dying || !p.alive) return;
    const wp = this.wpos();
    const dist = wp.distanceTo(p.pos);
    if (dist > 1500) return;
    const lead = p.pos.clone().addScaledVector(p.vel, dist / Turret.BOLT_SPEED);
    const inv = this.obj.getWorldQuaternion(_q).invert();
    const local = lead.clone().sub(wp).applyQuaternion(inv);
    const yaw = Math.atan2(-local.x, -local.z);
    const pitch = Math.atan2(local.y, Math.hypot(local.x, local.z));
    const k = damp(2.5, dt);
    this.yawNode.rotation.y += wrapAngle(yaw - this.yawNode.rotation.y) * k;
    this.pitchNode.rotation.x = lerp(this.pitchNode.rotation.x, clamp(pitch, -0.05, 1.45), k);
    this.gunCd -= dt;
    const aligned = Math.abs(wrapAngle(this.yawNode.rotation.y - yaw)) < 0.12 && pitch > -0.1;
    if (aligned && dist < 1200 && this.gunCd <= 0) {
      const m = this.muzzles[this.burst % 2].getWorldPosition(new THREE.Vector3());
      const e = g.diff.enemy_err * 1.2;
      const dir = lead.sub(m).normalize().add(_d.set(rand(-e, e), rand(-e, e), rand(-e, e))).normalize();
      g.combat.fire(m, dir, Turret.BOLT_SPEED, 1, g.diff.turret_dmg);
      g.sfx.playAt('elaser', wp);
      this.burst++;
      this.gunCd = this.burst % 4 !== 0 ? 0.2 : g.diff.enemy_gap * rand(1.4, 2.4);
    }
  }

  hit(dmg, pos) {
    if (!this.alive) return;
    this.hp -= dmg;
    this.game.fx.sparks(pos);
    if (this.hp <= 0) {
      this.alive = false;
      this.game.fx.explode(this.wpos(), 1.8, true, this.game.camera);
      this.game.sfx.playAt('boom', this.wpos());
      this.yawNode.visible = false;
      this.game.onKill(this);
      this.frigate.onTurretDestroyed();
    }
  }
}

class Core {
  constructor(game, frigate, mesh) {
    this.game = game;
    this.frigate = frigate;
    this.mesh = mesh;
    this.kind = 'REACTOR CORE';
    this.hp = 40; this.maxHp = 40; this.radius = 8 * FRIGATE.SCALE;
    this.alive = true;
    this._w = new THREE.Vector3();
  }
  wpos() { return this.mesh.getWorldPosition(this._w); }
  velocity() { return new THREE.Vector3(); }
  targetable() { return this.alive && !this.frigate.shieldUp && !this.frigate.dying; }
  hit(dmg, pos) {
    if (!this.targetable()) return;
    this.hp -= dmg;
    this.game.fx.sparks(pos, 0xff9955);
    this.frigate.coreFlash = 1;
    if (this.hp <= 0) {
      this.alive = false;
      this.game.onKill(this);
      this.frigate.onCoreDestroyed();
    }
  }
}

export class Frigate {
  constructor(game, yaw) {
    this.game = game;
    const m = frigateModel();
    this.m = m;
    this.obj = m.root;
    this.obj.rotation.y = yaw;
    game.scene.add(this.obj);
    this.alive = true; this.dying = false; this.dieT = 0; this.boomT = 0;
    this.shieldUp = true; this.shieldFlash = 0; this.shieldFade = 1; this.coreFlash = 0; this.t = 0;
    this.shieldR = FRIGATE.SHIELD_R * FRIGATE.SCALE;
    this.turrets = FRIGATE.TURRETS.map(([p, r]) => {
      const tu = new Turret(game, this, p, r, m.plate, m.dark);
      this.obj.add(tu.obj);
      return tu;
    });
    this.core = new Core(game, this, m.core);
    // collision volume, local (pre-scale) spheres
    this.hullSpheres = [];
    for (let z = -110; z <= 110; z += 20) this.hullSpheres.push([new THREE.Vector3(0, 0, z), Math.abs(z) < 100 ? 16 : 12]);
    for (const z of [0, 22, 44]) {
      this.hullSpheres.push([new THREE.Vector3(-36, -2, z), 8]);
      this.hullSpheres.push([new THREE.Vector3(36, -2, z), 8]);
    }
    this.hullSpheres.push([new THREE.Vector3(0, 22, 64), 14], [new THREE.Vector3(0, 0, 112), 20], [new THREE.Vector3(0, 17, 0), 9]);
    this._inv = new THREE.Matrix4();
  }

  targets() { return [...this.turrets, this.core]; }
  turretsLeft() { return this.turrets.filter((t) => t.alive).length; }
  _toLocal(p, out) { return out.copy(p).applyMatrix4(this._inv); }

  segHit(a, b) {
    const la = this._toLocal(a, _a), lb = this._toLocal(b, _b);
    for (const [c, r] of this.hullSpheres) if (segSphere(la, lb, c, r)) return true;
    return false;
  }

  /// push-out vector (world) if p is inside the hull with margin, else null
  pushOut(p, margin) {
    const lp = this._toLocal(p, _a);
    for (const [c, r0] of this.hullSpheres) {
      const r = r0 + margin / FRIGATE.SCALE;
      const d = _b.subVectors(lp, c);
      if (d.lengthSq() < r * r) {
        const n = d.length() > 0.01 ? d.clone().normalize() : new THREE.Vector3(0, 1, 0);
        return n.multiplyScalar((r - d.length()) * FRIGATE.SCALE).applyQuaternion(this.obj.quaternion);
      }
    }
    return null;
  }

  shieldHit() {
    this.shieldFlash = 1;
    this.game.sfx.playAt('shield', this.core.wpos());
  }

  onTurretDestroyed() {
    const left = this.turretsLeft();
    const g = this.game;
    if (left > 0) { g.hud.message(`TURRET DESTROYED  ·  ${left} LEFT`); return; }
    this.shieldUp = false;
    g.fx.flash(this.core.wpos(), 0x80ccff, 40, 600, 1.2);
    g.sfx.play('alarm');
    g.hud.banner('REACTOR SHIELD DOWN', 'DESTROY THE REACTOR CORE');
  }

  onCoreDestroyed() {
    this.dying = true;
    this.dieT = 0;
    this.game.fx.explode(this.core.wpos(), 4, true, this.game.camera);
    this.game.sfx.play('bigboom');
    this.m.core.visible = false;
    this.game.hud.banner('REACTOR BREACH', 'FRIGATE GOING DOWN');
  }

  update(dt) {
    const g = this.game;
    this.obj.updateMatrixWorld();
    this._inv.copy(this.obj.matrixWorld).invert();
    this.t += dt;
    this.shieldFlash = Math.max(0, this.shieldFlash - dt * 3);
    if (!this.shieldUp) this.shieldFade = Math.max(0, this.shieldFade - dt * 1.5);
    const su = this.m.shieldMat.uniforms;
    su.strength.value = this.shieldFade;
    su.flash.value = this.shieldFlash;
    su.t.value = this.t;
    this.m.shield.visible = this.shieldFade > 0.01;
    this.coreFlash = Math.max(0, this.coreFlash - dt * 4);
    this.m.coreMat.color.set(0xff731f).multiplyScalar(4 + 1.5 * Math.sin(this.t * 4) + this.coreFlash * 6);
    this.m.ring.rotation.x += dt * (this.shieldUp ? 0.6 : 2.5);
    this.m.lights.visible = (this.t % 1.6) < 0.12;
    for (const fl of this.m.flames) if (fl) { fl.material.uniforms.t.value = this.t; fl.material.uniforms.throttle.value = 0.7; }
    for (const tu of this.turrets) tu.update(dt);
    if (this.dying) {
      this.dieT += dt;
      this.boomT -= dt;
      if (this.boomT <= 0) {
        this.boomT = rand(0.12, 0.3);
        const [c, r] = this.hullSpheres[Math.floor(Math.random() * this.hullSpheres.length)];
        const p = c.clone().add(_c.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).multiplyScalar(r)).applyMatrix4(this.obj.matrixWorld);
        g.fx.explode(p, rand(1.5, 3), Math.random() < 0.5, g.camera);
        g.sfx.playAt('boom', p);
      }
      if (this.dieT > 3.2) {
        g.fx.explode(this.obj.position, 8, true, g.camera);
        g.fx.explode(new THREE.Vector3(0, 0, -70).applyMatrix4(this.obj.matrixWorld), 5, false, g.camera);
        g.fx.explode(new THREE.Vector3(0, 0, 80).applyMatrix4(this.obj.matrixWorld), 5, false, g.camera);
        g.sfx.play('bigboom');
        this.alive = false;
        this.dispose();
        g.onFrigateDestroyed();
      }
    }
  }

  dispose() { this.game.scene.remove(this.obj); }
}

// ---------------- missile (missile.gd) ----------------

export class Missile {
  constructor(game, pos, dir, inherit, target) {
    this.game = game;
    this.target = target;
    this.obj = missileMesh();
    game.scene.add(this.obj);
    this.obj.position.copy(pos);
    this.speed = 160;
    this.vel = dir.clone().multiplyScalar(this.speed).add(inherit);
    lookQuat(this.vel, UP, this.obj.quaternion);
    this.life = 7;
    this.dmg = 6;
    this.dead = false;
    this.puff = 0;
  }

  _targetOk() { return this.target && this.target.alive && this.target.targetable(); }

  update(dt) {
    const g = this.game;
    this.life -= dt;
    this.speed = Math.min(this.speed + 380 * dt, 560);
    const f = this.vel.clone().normalize();
    const ok = this._targetOk();
    if (ok) {
      const tp = this.target.wpos().clone();
      const d = tp.distanceTo(this.obj.position);
      tp.addScaledVector(this.target.velocity(), clamp(d / this.speed, 0, 1.5));
      const want = tp.sub(this.obj.position).normalize();
      f.lerp(want, clamp(4 * dt, 0, 1)).normalize();
    }
    this.vel.copy(f).multiplyScalar(this.speed);
    const a = this.obj.position;
    const b = _d.copy(a).addScaledVector(this.vel, dt);
    if (ok && segSphere(a, b, this.target.wpos(), this.target.radius + 4)) {
      this.target.hit(this.dmg, b);
      g.stats.missile_hits++;
      return this._boom(b);
    }
    const fr = g.frigate;
    if (fr && fr.alive) {
      if (fr.shieldUp && segSphere(a, b, fr.core.wpos(), fr.shieldR)) { fr.shieldHit(); return this._boom(b); }
      if (fr.segHit(a, b)) return this._boom(b);
    }
    if (g.rockSegHit(a, b) || this.life <= 0) return this._boom(b);
    this.obj.position.copy(b);
    lookQuat(this.vel, UP, this.obj.quaternion);
    this.puff -= dt;
    if (this.puff <= 0) {
      this.puff = 0.025;
      g.fx.trail(_c.set(0, 0, 1.3).applyQuaternion(this.obj.quaternion).add(this.obj.position), this.vel);
    }
  }

  _boom(p) {
    this.game.fx.explode(p, 0.8, false, this.game.camera);
    this.game.sfx.playAt('boom', p);
    this.dispose();
  }

  dispose() { this.dead = true; this.game.scene.remove(this.obj); }
}

// ---------------- lasers and enemy bolts (combat.gd) ----------------
// Moved and hit-tested here as plain data; drawn as two instanced meshes.

export class Combat {
  static MAX = 220;
  constructor(game) {
    this.game = game;
    this.shots = [];
    const geo = (len, r) => {
      const g = new THREE.CylinderGeometry(r, r, len, 6, 1);
      g.rotateX(Math.PI / 2); // along Z
      return g;
    };
    const mk = (g, color, k) => {
      const m = new THREE.InstancedMesh(g, new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(k),
        toneMapped: false, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }), Combat.MAX);
      m.count = 0;
      m.frustumCulled = false;
      m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      game.scene.add(m);
      return m;
    };
    this.meshes = [mk(geo(9, 0.14), 0x73bfff, 4.5), mk(geo(6.4, 0.22), 0xff6b1f, 3.2)];
    this._m = new THREE.Matrix4();
    this._s = new THREE.Vector3(1, 1, 1);
  }

  fire(pos, dir, speed, team, dmg, inherit = null) {
    if (this.shots.length >= Combat.MAX * 2) return;
    const v = dir.clone().normalize().multiplyScalar(speed);
    if (inherit) v.add(inherit);
    this.shots.push({ p: pos.clone(), v, life: team === 0 ? 1.7 : 2.4, team, dmg, q: lookQuat(v) });
  }

  clear() { this.shots.length = 0; for (const m of this.meshes) m.count = 0; }

  update(dt) {
    const b = new THREE.Vector3();
    for (let i = this.shots.length - 1; i >= 0; i--) {
      const s = this.shots[i];
      b.copy(s.p).addScaledVector(s.v, dt);
      s.life -= dt;
      if (this._test(s, s.p, b) || s.life <= 0) this.shots.splice(i, 1);
      else s.p.copy(b);
    }
    const n = [0, 0];
    for (const s of this.shots) {
      const m = this.meshes[s.team];
      if (n[s.team] >= Combat.MAX) continue;
      m.setMatrixAt(n[s.team]++, this._m.compose(s.p, s.q, this._s));
    }
    for (let t = 0; t < 2; t++) {
      this.meshes[t].count = n[t];
      this.meshes[t].instanceMatrix.needsUpdate = true;
    }
  }

  _test(s, a, b) {
    const g = this.game;
    if (s.team === 0) {
      for (const h of g.hostiles) {
        if (h.alive && h.targetable() && segSphere(a, b, h.wpos(), h.radius)) {
          h.hit(s.dmg, b);
          g.onShotHit();
          return true;
        }
      }
      const f = g.frigate;
      if (f && f.alive) {
        if (f.shieldUp && segSphere(a, b, f.core.wpos(), f.shieldR)) {
          f.shieldHit();
          g.fx.sparks(b, 0x66b3ff);
          return true;
        }
        if (f.segHit(a, b)) { g.fx.sparks(b); return true; }
      }
    } else {
      const p = g.player;
      if (p.alive && segSphere(a, b, p.pos, p.radius)) { p.damage(s.dmg); return true; }
    }
    if (g.rockSegHit(a, b)) { g.fx.sparks(b, 0xffccaa); return true; }
    return false;
  }
}
