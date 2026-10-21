extends Node3D
## Enemy interceptor: attack run on the player, break away, come round again.

const Ships = preload("res://scripts/ships.gd")

const BOLT_SPEED := 620.0

var game
var model: Node3D
var muzzles: Array = []
var vel := Vector3.ZERO
var speed := 115.0
var turn := 1.1
var hp := 3.0
var max_hp := 3.0
var radius := 6.5
var kind := "FIGHTER"
var alive := true
var mode := 0           # 0 attack, 1 break away
var mode_t := 0.0
var mode_len := 3.0
var break_dir := Vector3.ZERO
var gun_cd := 2.5
var burst := 0


func setup(g, pos: Vector3, look_at_pos: Vector3) -> void:
	game = g
	model = Ships.fighter()
	add_child(model)
	muzzles = model.get_meta("muzzles")
	global_position = pos
	global_basis = Basis.looking_at((look_at_pos - pos).normalized(), Vector3.UP)
	speed = randf_range(105.0, 130.0)
	turn = randf_range(0.95, 1.25)
	vel = fwd() * speed
	gun_cd = randf_range(2.0, 4.0)


func fwd() -> Vector3:
	return -global_basis.z


func velocity() -> Vector3:
	return vel


func targetable() -> bool:
	return alive


func _process(dt: float) -> void:
	if not alive:
		return
	var p = game.player
	var to_p: Vector3 = p.global_position - global_position
	var dist := to_p.length()
	var desired: Vector3
	mode_t += dt
	if mode == 0:
		var lead: Vector3 = p.global_position + p.vel * clampf(dist / 700.0, 0.0, 1.2)
		desired = (lead - global_position).normalized()
		if dist < 170.0 or mode_t > 12.0 or not p.alive:
			mode = 1
			mode_t = 0.0
			mode_len = randf_range(2.5, 4.5)
			var side := to_p.cross(Vector3.UP).normalized()
			if side.length() < 0.1:
				side = Vector3.RIGHT
			break_dir = (side * (1.0 if randf() < 0.5 else -1.0) + Vector3(0, randf_range(-0.6, 0.6), 0)
				- to_p.normalized() * 0.3).normalized()
	else:
		desired = break_dir
		if mode_t > mode_len:
			mode = 0
			mode_t = 0.0
	desired = (desired + game.avoid_vector(global_position, fwd(), 130.0) * 1.5).normalized()
	if global_position.length() > game.ARENA - 200.0:
		desired = (desired - global_position.normalized() * 1.2).normalized()
	_turn_toward(desired, dt)
	vel = fwd() * speed
	global_position += vel * dt

	gun_cd -= dt
	if mode == 0 and p.alive and dist < 1000.0 and fwd().angle_to(to_p) < 0.22 and gun_cd <= 0.0:
		var m: Node3D = muzzles[burst % 2]
		var aim: Vector3 = p.global_position + p.vel * (dist / BOLT_SPEED)
		var e: float = game.diff.enemy_err
		var dir := (aim - m.global_position).normalized() + Vector3(randf_range(-e, e), randf_range(-e, e), randf_range(-e, e))
		game.combat.fire(m.global_position, dir.normalized(), BOLT_SPEED, 1, game.diff.enemy_dmg)
		game.sfx.play_at("elaser", global_position, -8.0)
		burst += 1
		gun_cd = 0.14 if burst % 3 != 0 else float(game.diff.enemy_gap) * randf_range(0.8, 1.6)


func _turn_toward(desired: Vector3, dt: float) -> void:
	var f := fwd()
	var ang := f.angle_to(desired)
	var axis := f.cross(desired)
	if ang > 1e-3 and axis.length() > 1e-5:
		f = f.rotated(axis.normalized(), minf(ang, turn * dt))
	var up := Vector3.UP if absf(f.y) < 0.95 else global_basis.y
	global_basis = Basis.looking_at(f, up)
	var bank := clampf(axis.dot(global_basis.y) * 6.0, -1.2, 1.2)
	model.rotation.z = lerpf(model.rotation.z, bank, 1.0 - exp(-3.0 * dt))


func hit(dmg: float, pos: Vector3) -> void:
	if not alive:
		return
	hp -= dmg
	game.fx.sparks(pos)
	if hp <= 0.0:
		alive = false
		game.fx.explode(global_position, 1.4)
		game.on_kill(self)
		queue_free()
