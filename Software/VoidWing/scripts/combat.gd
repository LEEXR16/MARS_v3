extends Node3D
## Lasers and enemy bolts. Moved and hit-tested here as plain data; the visible
## bolts come from a node pool so firing never allocates.

const Proc = preload("res://scripts/proc.gd")
const Ships = preload("res://scripts/ships.gd")

var game
var shots: Array = []
var pool := {0: [], 1: []}
var meshes := {}
var mats := {}


func _ready() -> void:
	meshes[0] = Proc.lathe(PackedVector2Array([Vector2(-4.5, 0.0), Vector2(-3.8, 0.12), Vector2(3.8, 0.12),
		Vector2(4.5, 0.0)]), 6)
	meshes[1] = Proc.lathe(PackedVector2Array([Vector2(-3.2, 0.0), Vector2(-2.6, 0.24), Vector2(2.6, 0.24),
		Vector2(3.2, 0.0)]), 6)
	mats[0] = Ships.add_mat(Color(0.45, 0.75, 1.0), 9.0)
	mats[1] = Ships.add_mat(Color(1.0, 0.42, 0.12), 8.0)


func _node(team: int) -> MeshInstance3D:
	var list: Array = pool[team]
	if not list.is_empty():
		var n: MeshInstance3D = list.pop_back()
		n.visible = true
		return n
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[team]
	mi.material_override = mats[team]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func look_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT
	return Basis.looking_at(dir, up)


func fire(pos: Vector3, dir: Vector3, speed: float, team: int, dmg: float, inherit := Vector3.ZERO) -> void:
	var n := _node(team)
	var vel := dir.normalized() * speed + inherit
	n.global_transform = Transform3D(look_basis(vel), pos)
	shots.append({"n": n, "p": pos, "v": vel, "life": 1.7 if team == 0 else 2.4, "team": team, "dmg": dmg})


func clear() -> void:
	for s in shots:
		_release(s)
	shots.clear()


func _release(s: Dictionary) -> void:
	var n: MeshInstance3D = s.n
	n.visible = false
	pool[s.team].append(n)


static func seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var d := b - a
	var t := clampf((c - a).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
	return (a + d * t).distance_squared_to(c) < r * r


func _process(dt: float) -> void:
	var i := shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		var a: Vector3 = s.p
		var b: Vector3 = a + s.v * dt
		s.life -= dt
		if _test(s, a, b) or s.life <= 0.0:
			_release(s)
			shots.remove_at(i)
		else:
			s.p = b
			s.n.global_position = b
		i -= 1


func _test(s: Dictionary, a: Vector3, b: Vector3) -> bool:
	if s.team == 0:
		for h in game.hostiles:
			if h.alive and h.targetable() and seg_sphere(a, b, h.global_position, h.radius):
				h.hit(s.dmg, b)
				game.on_shot_hit()
				return true
		var f = game.frigate
		if f and f.alive:
			if f.shield_up and seg_sphere(a, b, f.core.global_position, f.shield_r):
				f.shield_hit(b)
				game.fx.sparks(b, Color(0.4, 0.7, 1.0))
				return true
			if f.seg_hit(a, b):
				game.fx.sparks(b)
				return true
	else:
		var p = game.player
		if p.alive and seg_sphere(a, b, p.global_position, p.radius):
			p.damage(s.dmg, a)
			return true
	if game.rock_seg_hit(a, b):
		game.fx.sparks(b, Color(1.0, 0.8, 0.6))
		return true
	return false
