extends Node3D
## Explosions, sparks, flashes, shockwaves and smoke trails.
## Particle materials are built once per size and shared.

const PART_ADD := preload("res://shaders/particle_add.gdshader")
const PART_MIX := preload("res://shaders/particle_mix.gdshader")
const SHOCK := preload("res://shaders/shockwave.gdshader")

var game
var quad: QuadMesh
var mat_fire: ShaderMaterial
var mat_spark: ShaderMaterial
var mat_smoke: ShaderMaterial
var mat_shock: ShaderMaterial
var sets := {}          # size key -> {fire, smoke, spark}
var pm_trail: ParticleProcessMaterial
var pm_hit: ParticleProcessMaterial


func _ready() -> void:
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	mat_fire = _pmat(PART_ADD, 3.2)
	mat_spark = _pmat(PART_ADD, 7.0)
	mat_smoke = _pmat(PART_MIX, 1.0)
	mat_shock = ShaderMaterial.new()
	mat_shock.shader = SHOCK

	pm_trail = _proc(0.5, 2.0, 1.4, 2.4, 1.0, _grad([Color(0.85, 0.7, 0.5, 0.6), Color(0.38, 0.38, 0.4, 0.35),
		Color(0.25, 0.25, 0.27, 0.0)]), _curve([0.4, 1.0, 1.6]), 0.2)
	pm_hit = _proc(25.0, 70.0, 0.25, 0.5, 6.0, _grad([Color(1.0, 0.9, 0.7, 1.0), Color(1.0, 0.5, 0.2, 0.8),
		Color(0.6, 0.2, 0.1, 0.0)]), _curve([1.0, 0.6, 0.0]), 0.3)


func _pmat(shader: Shader, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	if shader == PART_ADD:
		m.set_shader_parameter("energy", energy)
	return m


func _grad(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	return g


func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 2.0
	for i in pts.size():
		c.add_point(Vector2(float(i) / (pts.size() - 1), pts[i]))
	return c


func _proc(vmin: float, vmax: float, smin: float, smax: float, damping: float, ramp: Gradient,
		scurve: Curve, radius: float) -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius, 0.01)
	p.direction = Vector3(0, 0, -1)
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3.ZERO
	p.damping_min = damping
	p.damping_max = damping * 1.4
	p.scale_min = smin
	p.scale_max = smax
	var ct := CurveTexture.new()
	ct.curve = scurve
	p.scale_curve = ct
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	p.color_ramp = gt
	return p


func _size_set(size: float) -> Dictionary:
	var k := snappedf(clampf(size, 0.5, 8.0), 0.5)
	if sets.has(k):
		return sets[k]
	var s := {
		"fire": _proc(6.0 * k, 26.0 * k, 3.0 * k, 6.5 * k, 3.0, _grad([Color(1.0, 0.95, 0.8, 1.0),
			Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.22, 0.06, 0.8), Color(0.2, 0.05, 0.02, 0.0)]),
			_curve([0.5, 1.0, 1.2, 0.9]), 1.5 * k),
		"smoke": _proc(4.0 * k, 14.0 * k, 4.0 * k, 8.0 * k, 1.5, _grad([Color(0.25, 0.22, 0.2, 0.0),
			Color(0.2, 0.18, 0.17, 0.55), Color(0.12, 0.12, 0.13, 0.0)]), _curve([0.4, 1.0, 1.5]), 2.0 * k),
		"spark": _proc(40.0 * k, 120.0 * k, 0.35 * k, 0.8 * k, 2.0, _grad([Color(1.0, 0.95, 0.8, 1.0),
			Color(1.0, 0.6, 0.25, 1.0), Color(1.0, 0.3, 0.1, 0.0)]), _curve([1.0, 0.8, 0.0]), 0.5 * k),
	}
	sets[k] = s
	return s


func _emit(pos: Vector3, pm: ParticleProcessMaterial, mat: Material, amount: int, life: float,
		size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = quad
	p.material_override = mat
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3.ONE * -80.0 * size, Vector3.ONE * 160.0 * size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


func explode(pos: Vector3, size := 1.0, sound := true) -> void:
	var s := _size_set(size)
	_emit(pos, s.fire, mat_fire, int(36 + 10 * size), 1.0 + 0.15 * size, size)
	_emit(pos, s.smoke, mat_smoke, int(20 + 6 * size), 2.6 + 0.3 * size, size)
	_emit(pos, s.spark, mat_spark, int(40 + 10 * size), 0.9, size)
	flash(pos, Color(1.0, 0.6, 0.3), 10.0 * size, 50.0 * size, 0.5 + 0.1 * size)
	_shock(pos, size)
	if sound and game:
		game.sfx.play_at("boom_big" if size >= 3.0 else "boom", pos, 2.0 if size >= 3.0 else -2.0)


func sparks(pos: Vector3, col := Color(1.0, 0.7, 0.4)) -> void:
	var p := _emit(pos, pm_hit, mat_spark, 14, 0.45, 1.0)
	p.explosiveness = 1.0
	flash(pos, col, 3.0, 14.0, 0.15)


func flash(pos: Vector3, col: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)


func _shock(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat_shock
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 4.0 * size
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 40.0 * size, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("t", v), 0.0, 1.0, 0.7)
	tw.chain().tween_callback(mi.queue_free)


## Smoke trail that follows `parent`; call detach_trail() when the parent dies.
func trail(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.process_material = pm_trail
	p.draw_pass_1 = quad
	p.material_override = mat_smoke
	p.amount = 90
	p.lifetime = 1.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3.ONE * -600.0, Vector3.ONE * 1200.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = Vector3(0, 0, 1.4)
	p.emitting = true
	return p


func detach_trail(p: GPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	p.reparent(self)
	p.emitting = false
	get_tree().create_timer(p.lifetime + 0.2, false).timeout.connect(p.queue_free)


## Hyperspace arrival: bright flash and a ring.
func warp(pos: Vector3, size := 1.0) -> void:
	flash(pos, Color(0.6, 0.8, 1.0), 14.0 * size, 80.0 * size, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var m := mat_shock.duplicate() as ShaderMaterial
	m.set_shader_parameter("color", Color(0.5, 0.75, 1.0))
	mi.material_override = m
	add_child(mi)
	mi.global_position = pos
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 30.0 * size, 0.9).from(Vector3.ONE * 2.0)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("t", v), 0.0, 1.0, 0.9)
	tw.chain().tween_callback(mi.queue_free)
