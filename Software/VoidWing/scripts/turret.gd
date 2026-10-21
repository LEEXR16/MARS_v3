extends Node3D
## Frigate defence turret: tracks the player and fires bursts. Six of them hold
## up the reactor shield.

const Ships = preload("res://scripts/ships.gd")

const BOLT_SPEED := 560.0

var game
var frigate
var hp := 10.0
var max_hp := 10.0
var radius := 6.0
var kind := "TURRET"
var alive := true
var yaw_node: Node3D
var pitch_node: Node3D
var muzzles: Array = []
var eye: MeshInstance3D
var gun_cd := 3.0
var burst := 0


func setup(g, f, metal: Material, dark: Material) -> void:
	game = g
	frigate = f
	Ships.part(self, Ships.cyl(3.4, 3.8, 1.6, 20), dark, Vector3(0, 0.8, 0))
	yaw_node = Node3D.new()
	yaw_node.position = Vector3(0, 1.6, 0)
	add_child(yaw_node)
	Ships.part(yaw_node, Ships.sphere(2.8, 20), metal, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.7, 1))
	pitch_node = Node3D.new()
	pitch_node.position = Vector3(0, 0.9, 0)
	yaw_node.add_child(pitch_node)
	for s in [-0.7, 0.7]:
		Ships.part(pitch_node, Ships.cyl(0.3, 0.38, 6.0, 10), dark, Vector3(s, 0, -3.2), Vector3(PI / 2, 0, 0))
		muzzles.append(Ships.marker(pitch_node, Vector3(s, 0, -6.4)))
	eye = Ships.part(pitch_node, Ships.sphere(0.45, 10), Ships.glow_mat(Color(1.0, 0.2, 0.1), 7.0),
		Vector3(0, 0.6, -1.9))
	gun_cd = randf_range(2.0, 5.0)


func targetable() -> bool:
	return alive


func velocity() -> Vector3:
	return Vector3.ZERO


func _process(dt: float) -> void:
	if not alive or not frigate.alive or frigate.dying:
		return
	var p = game.player
	if not p.alive:
		return
	var dist: float = global_position.distance_to(p.global_position)
	if dist > 1500.0:
		return
	var lead: Vector3 = p.global_position + p.vel * (dist / BOLT_SPEED)
	var local := global_basis.inverse() * (lead - global_position)
	var yaw := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	var k := 1.0 - exp(-2.5 * dt)
	yaw_node.rotation.y = lerp_angle(yaw_node.rotation.y, yaw, k)
	pitch_node.rotation.x = lerpf(pitch_node.rotation.x, clampf(pitch, -0.05, 1.45), k)
	gun_cd -= dt
	var aligned := absf(angle_difference(yaw_node.rotation.y, yaw)) < 0.12 and pitch > -0.1
	if aligned and dist < 1200.0 and gun_cd <= 0.0:
		var m: Node3D = muzzles[burst % 2]
		var e: float = game.diff.enemy_err * 1.2
		var dir := (lead - m.global_position).normalized() + Vector3(randf_range(-e, e), randf_range(-e, e), randf_range(-e, e))
		game.combat.fire(m.global_position, dir.normalized(), BOLT_SPEED, 1, game.diff.turret_dmg)
		game.sfx.play_at("elaser", global_position, -4.0)
		burst += 1
		gun_cd = 0.2 if burst % 4 != 0 else float(game.diff.enemy_gap) * randf_range(1.4, 2.4)


func hit(dmg: float, pos: Vector3) -> void:
	if not alive:
		return
	hp -= dmg
	game.fx.sparks(pos)
	if hp <= 0.0:
		alive = false
		game.fx.explode(global_position, 1.8)
		yaw_node.visible = false
		eye.visible = false
		game.on_kill(self)
		frigate.on_turret_destroyed()
