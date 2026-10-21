extends Node3D
## Homing missile with a smoke trail. Proximity fuse on its target.

const Ships = preload("res://scripts/ships.gd")
const Combat = preload("res://scripts/combat.gd")

var game
var target = null
var vel := Vector3.ZERO
var speed := 160.0
var life := 7.0
var dmg := 6.0
var trail: GPUParticles3D


func launch(g, pos: Vector3, dir: Vector3, inherit: Vector3, tgt) -> void:
	game = g
	target = tgt
	add_child(Ships.missile())
	global_position = pos
	vel = dir * speed + inherit
	global_basis = Combat.look_basis(vel)
	trail = game.fx.trail(self)


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and target.alive and target.targetable()


func _process(dt: float) -> void:
	life -= dt
	speed = minf(speed + 380.0 * dt, 560.0)
	var f := vel.normalized()
	var ok := _target_ok()
	if ok:
		var tp: Vector3 = target.global_position
		var d := tp.distance_to(global_position)
		tp += target.velocity() * clampf(d / speed, 0.0, 1.5)
		var want := (tp - global_position).normalized()
		f = f.slerp(want, clampf(4.0 * dt, 0.0, 1.0)).normalized()
	vel = f * speed
	var a := global_position
	var b := a + vel * dt
	if ok and Combat.seg_sphere(a, b, target.global_position, target.radius + 4.0):
		target.hit(dmg, b)
		game.stats.missile_hits += 1
		_boom(b)
		return
	var fr = game.frigate
	if fr and fr.alive:
		if fr.shield_up and Combat.seg_sphere(a, b, fr.core.global_position, fr.shield_r):
			fr.shield_hit(b)
			_boom(b)
			return
		if fr.seg_hit(a, b):
			_boom(b)
			return
	if game.rock_seg_hit(a, b) or life <= 0.0:
		_boom(b)
		return
	global_position = b
	global_basis = Combat.look_basis(vel)


func _boom(p: Vector3) -> void:
	game.fx.explode(p, 0.8)
	game.fx.detach_trail(trail)
	queue_free()
