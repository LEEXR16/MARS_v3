extends Node3D
## The player's ship (the Ranger): flight model, twin lasers, lock-on missiles, shield and hull.
##
## Flight is horizon-locked for comfort: the arm (or mouse) sets yaw and pitch rates,
## pitch is limited to +-55 deg and the ship never rolls the view. Banking into turns
## and the dodge roll only tilt the model, never the camera.

const Ships = preload("res://scripts/ships.gd")
const MissileS = preload("res://scripts/missile.gd")

const RATE_PITCH := 0.75     # rad/s at full deflection
const RATE_YAW := 0.95
const PITCH_MAX := 0.96      # rad (55 deg)
const RATE_RESPONSE := 5.0   # 1/s: how fast the turn rate follows the stick
const GRIP := 2.2            # 1/s: how fast the velocity swings to the nose (lower = more drift)
const BANK_MAX := 0.62       # rad of model bank at full yaw rate
const SPEED_MIN := 45.0
const SPEED_MAX := 175.0
const SPEED_BOOST := 270.0
const LASER_SPEED := 950.0
const MAX_MISSILES := 14

var game
var model: Node3D
var muzzles: Array = []
var flames: Array = []
var vel := Vector3.ZERO
var speed := 110.0
var throttle := 0.45
var boost := 1.0
var boosting := false
var yaw := 0.0
var pitch := 0.0
var yaw_rate := 0.0
var pitch_rate := 0.0
var bank := 0.0
var roll_t := 0.0            # dodge roll: time left
var roll_dir := 0.0
var aim_now := Vector2.ZERO
var alive := true
var invuln := 0.0
var hull := 100.0
var shield := 100.0
var since_hit := 10.0
var missiles := MAX_MISSILES
var gun_cd := 0.0
var gun_side := 0
var missile_cd := 0.0
var target = null
var target_ang := PI
var lock_t := 0.0
var locked := false
var beep_t := 0.0
var radius := 4.5
const ROLL_TIME := 0.75


func setup() -> void:
	model = Ships.ranger()
	add_child(model)
	muzzles = model.get_meta("muzzles")
	flames = model.get_meta("flames")


func fwd() -> Vector3:
	return -global_basis.z


func velocity() -> Vector3:
	return vel


func reset(pos: Vector3, look_at_pos: Vector3, full := true) -> void:
	global_position = pos
	var d := (look_at_pos - pos).normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -PITCH_MAX, PITCH_MAX)
	global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))
	speed = 100.0
	vel = fwd() * speed
	throttle = 0.45
	yaw_rate = 0.0
	pitch_rate = 0.0
	bank = 0.0
	roll_t = 0.0
	if model:
		model.rotation = Vector3.ZERO
	hull = 100.0
	shield = 100.0
	boost = 1.0
	alive = true
	visible = true
	invuln = 3.0
	target = null
	lock_t = 0.0
	locked = false
	if full:
		missiles = MAX_MISSILES


## One frame of flight. aim: -1..1 (x right, y up) = turn rate demand.
## roll_in: a dodge roll to that side (mouse + keys only).
func fly(dt: float, aim: Vector2, roll_in: float, thr_in: float, strafe: Vector2, want_boost: bool) -> void:
	if not alive:
		return
	var a := aim
	if a.length() > 1.0:
		a = a.normalized()
	aim_now = a
	var k := 1.0 - exp(-RATE_RESPONSE * dt)
	yaw_rate = lerpf(yaw_rate, -a.x * RATE_YAW, k)
	# near the pitch limit the climb fades out instead of hitting a wall; with the
	# stick centred the nose drifts back to level very slowly
	var want_p := a.y * RATE_PITCH
	if signf(want_p) == signf(pitch):
		want_p *= clampf((PITCH_MAX - absf(pitch)) / 0.3, 0.0, 1.0)
	if absf(a.y) < 0.06:
		want_p = -pitch * 0.2
	pitch_rate = lerpf(pitch_rate, want_p, k)
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	pitch = clampf(pitch + pitch_rate * dt, -PITCH_MAX, PITCH_MAX)
	global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))

	throttle = clampf(throttle + thr_in * 0.6 * dt, 0.0, 1.0)
	boosting = want_boost and boost > 0.05
	boost = clampf(boost + (-0.33 if boosting else 0.12) * dt, 0.0, 1.0)
	var target_speed := SPEED_BOOST if boosting else lerpf(SPEED_MIN, SPEED_MAX, throttle)
	speed = move_toward(speed, target_speed, (120.0 if boosting else 45.0) * dt)

	# dodge roll: a quick sideways jink while the model spins (the camera stays level)
	if roll_t <= 0.0 and absf(roll_in) > 0.5:
		roll_t = ROLL_TIME
		roll_dir = signf(roll_in)
		game.sfx.play("missile", -14.0, 1.6)
	var jink := 0.0
	var spin := 0.0
	if roll_t > 0.0:
		roll_t = maxf(0.0, roll_t - dt)
		var u := 1.0 - roll_t / ROLL_TIME
		spin = -roll_dir * TAU * (u * u * (3.0 - 2.0 * u))
		jink = roll_dir * 55.0 * sin(PI * u)
	var side := global_basis.x * (strafe.x * 40.0 + jink) + Vector3.UP * strafe.y * 40.0
	vel = vel.lerp(fwd() * speed + side, 1.0 - exp(-GRIP * dt))
	global_position += vel * dt

	bank = lerpf(bank, yaw_rate / RATE_YAW * BANK_MAX, 1.0 - exp(-3.0 * dt))
	model.rotation.z = bank + spin
	model.rotation.x = lerpf(model.rotation.x, pitch_rate * 0.1, 1.0 - exp(-4.0 * dt))
	var s01 := clampf(speed / SPEED_MAX, 0.0, 1.6)
	# no plume from the chase camera: seen from behind it only blooms into a blob
	for fl in flames:
		fl.visible = false
		fl.set_instance_shader_parameter("throttle", 0.55 + 0.45 * s01 + (0.5 if boosting else 0.0))
		fl.scale.z = float(fl.get_meta("len")) * (0.55 + 0.6 * s01)

	since_hit += dt
	invuln = maxf(0.0, invuln - dt)
	if since_hit > 3.0:
		shield = minf(100.0, shield + 14.0 * dt)
	gun_cd -= dt
	missile_cd -= dt
	_update_target(dt)


func _update_target(dt: float) -> void:
	var best = null
	var best_ang := deg_to_rad(14.0)
	var f := fwd()
	for h in game.hostiles:
		if not h.alive or not h.targetable():
			continue
		var d: Vector3 = h.global_position - global_position
		if d.length() > 2600.0:
			continue
		var ang := f.angle_to(d)
		if h == target:
			ang *= 0.7   # sticky: keep the current target unless another is clearly better
		if ang < best_ang:
			best_ang = ang
			best = h
	if best != target:
		target = best
		lock_t = 0.0
		locked = false
	target_ang = PI
	if target:
		var d: Vector3 = target.global_position - global_position
		target_ang = f.angle_to(d)
		var need: float = game.diff.lock
		if target_ang < deg_to_rad(8.0) and d.length() < 2100.0:
			lock_t += dt
		else:
			lock_t = maxf(0.0, lock_t - dt * 2.0)
		if not locked and lock_t >= need:
			locked = true
			game.sfx.play("locked", -6.0)
		elif not locked and lock_t > 0.0:
			beep_t -= dt
			if beep_t <= 0.0:
				beep_t = 0.18
				game.sfx.play("beep", -12.0)
		if locked and target_ang > deg_to_rad(16.0):
			locked = false
			lock_t = 0.0


## Guns fire by themselves when a hostile sits inside the aim-assist cone and in range.
func wants_fire() -> bool:
	if not alive or target == null or not is_instance_valid(target):
		return false
	return target_ang < float(game.diff.assist) + 0.05 and 		global_position.distance_to(target.global_position) < 1500.0


func lock_progress() -> float:
	return 1.0 if locked else clampf(lock_t / float(game.diff.lock), 0.0, 1.0)


func fire_guns() -> void:
	if gun_cd > 0.0 or not alive:
		return
	gun_cd = 0.1
	var m: Node3D = muzzles[gun_side]
	gun_side = 1 - gun_side
	var from := m.global_position
	var aim_pt := global_position + fwd() * 700.0
	if target and is_instance_valid(target) and target_ang < float(game.diff.assist):
		var dist := global_position.distance_to(target.global_position)
		aim_pt = target.global_position + target.velocity() * (dist / LASER_SPEED)
	game.combat.fire(from, (aim_pt - from).normalized(), LASER_SPEED, 0, 1.0, vel)
	game.stats.shots += 1
	game.sfx.play("laser", -10.0, randf_range(0.95, 1.05))
	game.fx.flash(from, Color(0.5, 0.75, 1.0), 2.0, 8.0, 0.06)


func fire_missile() -> void:
	if missiles <= 0 or missile_cd > 0.0 or not locked or target == null or not alive:
		return
	missiles -= 1
	missile_cd = 0.8
	var m := MissileS.new()
	game.world.add_child(m)
	m.launch(game, global_position - global_basis.y * 1.0, fwd(), vel, target)
	game.stats.missiles += 1
	game.sfx.play("missile", -4.0)
	lock_t = 0.0
	locked = false


func damage(dmg: float, _from: Vector3) -> void:
	if not alive or invuln > 0.0:
		return
	since_hit = 0.0
	var s := minf(shield, dmg)
	shield -= s
	var rest := dmg - s
	hull -= rest
	game.hud.hit(rest > 0.0)
	game.sfx.play("hit" if rest > 0.0 else "shield", -6.0)
	game.stats.damage_taken += dmg
	if hull <= 0.0:
		die()


func die() -> void:
	alive = false
	visible = false
	locked = false
	game.fx.explode(global_position, 2.2)
	game.on_player_dead()
