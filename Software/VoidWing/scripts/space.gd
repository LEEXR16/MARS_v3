extends RefCounted
## The setting: a calm sky with Gargantua (black hole), a distant sun, a ringed gas
## giant, a sparse asteroid belt and faint space dust.

const Proc = preload("res://scripts/proc.gd")
const SKY := preload("res://shaders/sky.gdshader")
const ROCK := preload("res://shaders/rock.gdshader")
const PLANET := preload("res://shaders/planet.gdshader")
const RING := preload("res://shaders/planet_ring.gdshader")
const DUST := preload("res://shaders/dust.gdshader")

const SUN_DIR := Vector3(0.55, 0.42, 0.72)
const BH_DIR := Vector3(-0.45, 0.16, -0.88)    # Gargantua: ahead-left at the start
const CLEAR_R := 430.0          # no rocks this close to the frigate (origin)
const GRID := 150.0             # rock lookup cell size (m)


static func build(main: Node3D, world: Node3D, rng: RandomNumberGenerator, spawn: Vector3,
		arena: float) -> Dictionary:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	sky_mat.set_shader_parameter("bh_dir", BH_DIR.normalized())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.2, 0.22)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.tonemap_white = 8.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 0.8, 0.6, 0.7, 0.4, 0.25, 0.0][i])
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	main.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.84)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	main.add_child(sun)
	sun.basis = Basis.looking_at(-SUN_DIR.normalized(), Vector3.UP)
	# warm light from Gargantua's accretion disk
	var disk := DirectionalLight3D.new()
	disk.light_color = Color(1.0, 0.74, 0.48)
	disk.light_energy = 0.55
	main.add_child(disk)
	disk.basis = Basis.looking_at(-BH_DIR.normalized(), Vector3.UP)

	_planet(world)
	var rocks := _asteroids(world, rng, spawn, arena)
	var dust := _dust(world, rng)
	return {"rocks": rocks, "dust": dust}


static func _planet(world: Node3D) -> void:
	var dir := Vector3(0.8, -0.28, 0.55).normalized()
	var center := dir * 20000.0
	var r := 1900.0
	var m := ShaderMaterial.new()
	m.shader = PLANET
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	pm.radial_segments = 128
	pm.rings = 64
	var p := MeshInstance3D.new()
	p.mesh = pm
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(p)
	p.global_transform = Transform3D(Basis(Vector3(0, 0, 1), 0.35).scaled(Vector3.ONE * r), center)

	var rm := ShaderMaterial.new()
	rm.shader = RING
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	var ring := MeshInstance3D.new()
	ring.mesh = plane
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ring)
	var rb := Basis(Vector3(0, 0, 1), 0.35) * Basis(Vector3(1, 0, 0), 0.5)
	ring.global_transform = Transform3D(rb.scaled(Vector3.ONE * r * 2.3), center)


## Rock field: six mesh variants as MultiMeshes, plus a lookup grid for collisions.
static func _asteroids(world: Node3D, rng: RandomNumberGenerator, spawn: Vector3, arena: float) -> Dictionary:
	var meshes: Array = []
	for i in 6:
		meshes.append(Proc.asteroid(1000 + i * 37, 3 if OS.has_feature("web") else 4))   # 1280 vs 5120 triangles
	var mat := ShaderMaterial.new()
	mat.shader = ROCK
	var pos := PackedVector3Array()
	var rad := PackedFloat32Array()
	var grid := {}
	var per := [[], [], [], [], [], []]
	# play-area rocks (they collide)
	var tries := 0
	while pos.size() < 420 and tries < 20000:
		tries += 1
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) * 0.35, rng.randf_range(-1, 1)) * arena
		if p.length() > arena or p.length() < CLEAR_R or p.distance_to(spawn) < 180.0:
			continue
		var s := 2.0 + 34.0 * pow(rng.randf(), 4.0)
		if rng.randf() < 0.04:
			s = rng.randf_range(45.0, 85.0)
		var v := rng.randi() % 6
		per[v].append([p, s])
		pos.append(p)
		rad.append(s * 0.92)
		var key := Vector3i(floori(p.x / GRID), floori(p.y / GRID), floori(p.z / GRID))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		var cell: PackedInt32Array = grid[key]
		cell.append(pos.size() - 1)
		grid[key] = cell
	# distant scenery (no collisions)
	for i in 240:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) * 0.3, rng.randf_range(-1, 1)).normalized()
		var p := d * rng.randf_range(arena + 300.0, arena * 2.6)
		per[rng.randi() % 6].append([p, rng.randf_range(10.0, 90.0)])

	for v in 6:
		var list: Array = per[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var b := Basis(axis, rng.randf_range(0, TAU)).scaled(Vector3.ONE * float(list[i][1]))
			mm.set_instance_transform(i, Transform3D(b, list[i][0]))
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		world.add_child(mmi)
	return {"pos": pos, "rad": rad, "grid": grid}


static func _dust(world: Node3D, rng: RandomNumberGenerator) -> ShaderMaterial:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = 380
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
			Vector3(rng.randf(), rng.randf(), rng.randf()) * 240.0))
	var m := ShaderMaterial.new()
	m.shader = DUST
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	world.add_child(mmi)
	return m
