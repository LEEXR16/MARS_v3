extends Node3D
## Enemy frigate: faceted capital ship with six defence turrets that power a
## shield around the reactor core. Turrets down -> shield collapses -> core.

const Proc = preload("res://scripts/proc.gd")
const Ships = preload("res://scripts/ships.gd")
const TurretS = preload("res://scripts/turret.gd")
const CoreS = preload("res://scripts/core.gd")
const SHIELD := preload("res://shaders/shield.gdshader")

const SHIELD_R := 19.0       # local units
const SCALE := 2.0          # the whole ship is built at half size, then scaled
const CORE_POS := Vector3(0, 27, 0)
const TURRETS := [
	[Vector3(0, 15.0, -76), Vector3(0, 0, 0)],
	[Vector3(-17, 13.2, -32), Vector3(0, 0, 0)],
	[Vector3(17, 13.2, -32), Vector3(0, 0, 0)],
	[Vector3(0, -14.0, -50), Vector3(PI, 0, 0)],
	[Vector3(-40.5, -2, 36), Vector3(0, 0, PI / 2)],
	[Vector3(40.5, -2, 36), Vector3(0, 0, -PI / 2)],
]

var game
var alive := true
var dying := false
var die_t := 0.0
var boom_t := 0.0
var shield_up := true
var shield_flash := 0.0
var shield_fade := 1.0
var core_flash := 0.0
var turrets: Array = []
var core
var core_mat: StandardMaterial3D
var shield_mat: ShaderMaterial
var shield_mi: MeshInstance3D
var ring: Node3D
var hull_spheres: Array = []     # [local centre, radius]
var shield_r := SHIELD_R * SCALE  # world units
var lights: Array = []
var t := 0.0


func build(g) -> void:
	game = g
	scale = Vector3.ONE * SCALE
	var hull := Ships.hull_mat(Color(0.38, 0.39, 0.42), 0.22, 0.5, 0.42)
	hull.set_shader_parameter("window_amount", 0.07)
	var hull_red := Ships.with_stripe(hull, Vector3(0, 0, 1), -96.0, -88.0, Color(0.55, 0.07, 0.05), 0.4)
	var plate := Ships.hull_mat(Color(0.33, 0.34, 0.37), 0.35, 0.55, 0.45)
	var dark := Ships.hull_mat(Color(0.1, 0.1, 0.11), 0.8, 0.8, 0.35)
	var bridge := Ships.hull_mat(Color(0.3, 0.31, 0.34), 0.5, 0.5, 0.45)
	bridge.set_shader_parameter("window_amount", 0.45)

	# main hull, faceted
	Ships.part(self, Proc.lathe(PackedVector2Array([Vector2(-130, 0), Vector2(-124, 5), Vector2(-108, 11),
		Vector2(-80, 17), Vector2(-40, 21), Vector2(20, 22), Vector2(70, 21), Vector2(100, 19),
		Vector2(112, 16), Vector2(116, 0)]), 8, 1.55, 0.62, false), hull_red)
	# dorsal ridge and keel
	Ships.part(self, Proc.lathe(PackedVector2Array([Vector2(-92, 0), Vector2(-80, 4), Vector2(-30, 7.5),
		Vector2(60, 7.5), Vector2(86, 0)]), 6, 1.3, 1.0, false), plate, Vector3(0, 11, 0))
	Ships.part(self, Proc.lathe(PackedVector2Array([Vector2(-70, 0), Vector2(-60, 3), Vector2(50, 3.5),
		Vector2(70, 0)]), 6, 1.4, 1.0, false), plate, Vector3(0, -11, 0))
	# bridge tower
	Ships.part(self, Ships.box(Vector3(14, 16, 24)), plate, Vector3(0, 20, 64))
	Ships.part(self, Ships.box(Vector3(26, 5, 9)), bridge, Vector3(0, 30, 58))
	Ships.part(self, Ships.cyl(0.4, 0.6, 16, 8), dark, Vector3(5, 38, 66))
	Ships.part(self, Ships.cyl(0.3, 0.5, 10, 8), dark, Vector3(-4, 36, 70))
	# side sponsons and deck plates
	for s in [-1.0, 1.0]:
		Ships.part(self, Ships.box(Vector3(8, 10, 64)), plate, Vector3(36 * s, -2, 22))
		Ships.part(self, Ships.box(Vector3(14, 2.5, 40)), plate, Vector3(16 * s, 12, -40))
		Ships.part(self, Ships.box(Vector3(3, 3, 42)), dark, Vector3(9 * s, -5, -118))
	# engine block
	Ships.part(self, Ships.box(Vector3(56, 24, 22)), plate, Vector3(0, -1, 112))
	for x in [-18.0, 0.0, 18.0]:
		var fl := Ships.engine(self, Vector3(x, -1, 123), 7.0, dark, Color(1.0, 0.45, 0.15),
			Color(1.0, 0.85, 0.55), 26.0)
		fl.set_instance_shader_parameter("throttle", 0.7)
	# hangar glow
	Ships.part(self, Ships.box(Vector3(22, 0.4, 3)), Ships.glow_mat(Color(0.4, 0.8, 1.0), 3.0), Vector3(0, -13.2, -20))
	# running lights
	for p in [Vector3(-36, 3.5, -6), Vector3(36, 3.5, -6), Vector3(-36, 3.5, 52), Vector3(36, 3.5, 52),
			Vector3(0, 46, 66), Vector3(-28, 11, 112), Vector3(28, 11, 112)]:
		lights.append(Ships.part(self, Ships.sphere(0.9, 8), Ships.glow_mat(Color(1.0, 0.15, 0.08), 8.0), p))

	# reactor
	Ships.part(self, Ships.box(Vector3(16, 6, 16)), plate, Vector3(0, 17, 0))
	for s in [-1.0, 1.0]:
		Ships.part(self, Ships.box(Vector3(2, 14, 4)), dark, Vector3(10 * s, 22, 0))
	ring = Node3D.new()
	ring.position = CORE_POS
	add_child(ring)
	var tm := TorusMesh.new()
	tm.inner_radius = 9.5
	tm.outer_radius = 11.0
	tm.rings = 48
	tm.ring_segments = 12
	Ships.part(ring, tm, dark, Vector3.ZERO, Vector3(0, 0, PI / 2))
	core_mat = Ships.glow_mat(Color(1.0, 0.45, 0.15), 5.0)
	core = CoreS.new()
	core.game = g
	core.frigate = self
	core.position = CORE_POS
	core.radius *= SCALE
	add_child(core)
	Ships.part(core, Ships.sphere(6.5, 32), core_mat)
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = SHIELD
	shield_mi = Ships.part(self, Ships.sphere(SHIELD_R, 48), shield_mat, CORE_POS)
	shield_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# turrets
	for d in TURRETS:
		var tu := TurretS.new()
		tu.position = d[0]
		tu.rotation = d[1]
		add_child(tu)
		tu.setup(g, self, plate, dark)
		tu.radius *= SCALE
		turrets.append(tu)

	# collision volume
	for z in range(-110, 111, 20):
		var r := 16.0 if absf(z) < 100 else 12.0
		hull_spheres.append([Vector3(0, 0, z), r])
	for z in [0.0, 22.0, 44.0]:
		hull_spheres.append([Vector3(-36, -2, z), 8.0])
		hull_spheres.append([Vector3(36, -2, z), 8.0])
	hull_spheres.append([Vector3(0, 22, 64), 14.0])
	hull_spheres.append([Vector3(0, 0, 112), 20.0])
	hull_spheres.append([Vector3(0, 17, 0), 9.0])


func targets() -> Array:
	return turrets + [core]


func turrets_left() -> int:
	var n := 0
	for tu in turrets:
		if tu.alive:
			n += 1
	return n


## Segment against the hull spheres (world coordinates).
func seg_hit(a: Vector3, b: Vector3) -> bool:
	var la := to_local(a)
	var lb := to_local(b)
	var d := lb - la
	for s in hull_spheres:
		var c: Vector3 = s[0]
		var r: float = s[1]
		var k := clampf((c - la).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
		if (la + d * k).distance_squared_to(c) < r * r:
			return true
	return false


## Push-out vector (world) if `p` is inside the hull with `margin`, else zero.
func push_out(p: Vector3, margin: float) -> Vector3:
	var lp := to_local(p)
	for s in hull_spheres:
		var c: Vector3 = s[0]
		var r: float = s[1] + margin
		var d := lp - c
		if d.length_squared() < r * r:
			var n := d.normalized() if d.length() > 0.01 else Vector3.UP
			return global_basis * (n * (r - d.length()))
	return Vector3.ZERO


func shield_hit(_p: Vector3) -> void:
	shield_flash = 1.0
	game.sfx.play_at("shield", core.global_position, -2.0)


func on_turret_destroyed() -> void:
	var left := turrets_left()
	if left > 0:
		game.hud.message("TURRET DESTROYED  ·  %d LEFT" % left)
		return
	shield_up = false
	game.fx.flash(core.global_position, Color(0.5, 0.8, 1.0), 20.0, 200.0, 1.2)
	game.sfx.play("alarm", -6.0)
	game.hud.banner("REACTOR SHIELD DOWN", "DESTROY THE REACTOR CORE", game.hud.BLUE)


func on_core_destroyed() -> void:
	dying = true
	die_t = 0.0
	game.fx.explode(core.global_position, 4.0)
	core.visible = false
	game.hud.banner("REACTOR BREACH", "FRIGATE GOING DOWN", game.hud.GOLD)


func _process(dt: float) -> void:
	t += dt
	shield_flash = maxf(0.0, shield_flash - dt * 3.0)
	if not shield_up:
		shield_fade = maxf(0.0, shield_fade - dt * 1.5)
	shield_mat.set_shader_parameter("strength", shield_fade)
	shield_mat.set_shader_parameter("flash", shield_flash)
	shield_mi.visible = shield_fade > 0.01
	core_flash = maxf(0.0, core_flash - dt * 4.0)
	core_mat.emission_energy_multiplier = 4.0 + 1.5 * sin(t * 4.0) + core_flash * 6.0
	ring.rotation.x += dt * (0.6 if shield_up else 2.5)
	var blink := fmod(t, 1.6) < 0.12
	for l in lights:
		l.visible = blink
	if dying:
		die_t += dt
		boom_t -= dt
		if boom_t <= 0.0:
			boom_t = randf_range(0.12, 0.3)
			var s: Array = hull_spheres[randi() % hull_spheres.size()]
			var p: Vector3 = to_global(s[0] + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s[1])
			game.fx.explode(p, randf_range(1.5, 3.0), randf() < 0.5)
		if die_t > 3.2:
			game.fx.explode(global_position, 8.0)
			game.fx.explode(to_global(Vector3(0, 0, -70)), 5.0, false)
			game.fx.explode(to_global(Vector3(0, 0, 80)), 5.0, false)
			alive = false
			visible = false
			game.on_frigate_destroyed()
			queue_free()
