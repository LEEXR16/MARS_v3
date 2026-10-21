extends RefCounted
## Ship models assembled from procedural parts (proc.gd). Forward is -Z.

const Proc = preload("res://scripts/proc.gd")
const HULL := preload("res://shaders/hull.gdshader")
const FLAME := preload("res://shaders/flame.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")


static func hull_mat(base: Color, panel := 1.5, metal := 0.3, rough := 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HULL
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("panel_scale", panel)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	return m


static func with_stripe(m: ShaderMaterial, axis: Vector3, a: float, b: float, col: Color,
		emit := 0.0) -> ShaderMaterial:
	var s := m.duplicate() as ShaderMaterial
	s.set_shader_parameter("stripe_axis", axis)
	s.set_shader_parameter("stripe_a", a)
	s.set_shader_parameter("stripe_b", b)
	s.set_shader_parameter("accent_color", col)
	s.set_shader_parameter("stripe_emit", emit)
	return s


static func glow_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func add_mat(col: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	return m


static func glass_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.7
	m.roughness = 0.04
	m.clearcoat_enabled = true
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.4
	return m


static func flame_mat(core: Color, edge: Color, intensity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAME
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("edge", edge)
	m.set_shader_parameter("intensity", intensity)
	return m


static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func cyl(r_top: float, r_bot: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func sphere(r: float, seg := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Unit exhaust cone: radius 1 at z = 0 (nozzle) down to 0 at z = 1 (scale the node).
static func flame_cone() -> ArrayMesh:
	return Proc.lathe(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.25, 0.8), Vector2(0.6, 0.45),
		Vector2(1.0, 0.0)]), 16, 1.0, 1.0, true, false)


static func marker(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Engine: nozzle bell, glowing disc, exhaust flame. Returns the flame.
static func engine(parent: Node3D, pos: Vector3, r: float, metal: Material, glow: Color,
		core: Color, flame_len: float, disc_energy := 2.6, flame_k := 1.2) -> MeshInstance3D:
	part(parent, Proc.lathe(PackedVector2Array([Vector2(0.0, r * 0.92), Vector2(r * 0.55, r * 1.05),
		Vector2(r * 1.1, r * 1.12)]), 24, 1.0, 1.0, true, false), metal, pos)
	part(parent, cyl(r * 0.86, r * 0.86, 0.05, 24), glow_mat(glow.lerp(core, 0.4), disc_energy),
		pos + Vector3(0, 0, r * 0.9), Vector3(PI / 2, 0, 0))
	var fl := part(parent, flame_cone(), flame_mat(core, glow, flame_k),
		pos + Vector3(0, 0, r * 0.95), Vector3.ZERO, Vector3(r * 0.82, r * 0.82, flame_len))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.set_meta("len", flame_len)
	return fl


## The player's ship, after the Ranger from Interstellar: a flat faceted lifting body
## with a black chamfered rim, a raised white deck with irregular polygon windows,
## a ribbed black engine block at the rear and RCS thruster clusters at the corners.
static func ranger() -> Node3D:
	var root := Node3D.new()
	var white := hull_mat(Color(0.79, 0.79, 0.77), 1.1, 0.12, 0.5)
	white.set_shader_parameter("grime", 0.75)
	var deck := white.duplicate() as ShaderMaterial
	deck.set_shader_parameter("glass_center", Vector2(0.0, 2.8))
	deck.set_shader_parameter("glass_radii", Vector2(1.75, 2.3))
	deck.set_shader_parameter("glass_cell", 0.82)
	deck.set_shader_parameter("glass_frame", 0.1)
	var side := hull_mat(Color(0.64, 0.64, 0.63), 1.4, 0.15, 0.55)
	side.set_shader_parameter("grime", 0.6)
	var rim := hull_mat(Color(0.075, 0.077, 0.085), 1.6, 0.35, 0.5)
	rim.set_shader_parameter("grime", 0.3)
	var belly := hull_mat(Color(0.46, 0.46, 0.45), 1.2, 0.2, 0.6)
	belly.set_shader_parameter("grime", 0.6)
	var black := hull_mat(Color(0.1, 0.1, 0.11), 2.6, 0.55, 0.42)
	var nozzle := hull_mat(Color(0.09, 0.09, 0.1), 3.0, 0.2, 0.8)   # rough: no sun glints
	var hole := glow_mat(Color(0.0, 0.0, 0.0), 0.0)
	hole.albedo_color = Color(0.01, 0.01, 0.012)

	# lower body: the full-width wedge with the black rim
	var body := Proc.loft([
		[-8.2, 1.55, 0.26, 0.22, 0.45, 0.35],
		[-7.3, 2.35, 0.40, 0.30, 0.62, 0.45],
		[-3.0, 2.95, 0.50, 0.34, 0.70, 0.50],
		[3.5, 3.35, 0.55, 0.36, 0.72, 0.52],
		[7.6, 3.35, 0.55, 0.36, 0.72, 0.52]])
	part(root, body.top, white)
	part(root, body.rim, rim)
	part(root, body.belly, belly)

	# raised deck with the windows
	var up := Proc.loft([
		[-5.7, 0.85, 0.08, 0.2, 0.25, 0.0],
		[-3.4, 1.85, 0.46, 0.2, 0.5, 0.0],
		[0.0, 2.32, 0.68, 0.2, 0.6, 0.0],
		[5.6, 2.45, 0.70, 0.2, 0.6, 0.0]])
	part(root, up.top, deck, Vector3(0, 0.46, 0))
	part(root, up.rim, side, Vector3(0, 0.46, 0))

	# cargo flap at the nose
	var flap := PackedVector2Array([Vector2(-1.55, -7.0), Vector2(1.55, -7.0), Vector2(1.95, -4.0),
		Vector2(-1.95, -4.0)])
	part(root, Proc.slab(flap, 0.07), white, Vector3(0, 0.47, 0), Vector3(-0.024, 0, 0))

	# ribbed engine block at the rear
	var blk := Proc.loft([
		[5.5, 3.3, 1.25, 0.38, 0.35, 0.3],
		[7.7, 3.3, 1.25, 0.38, 0.35, 0.3]])
	for k in ["top", "rim", "belly"]:
		part(root, blk[k], black)
	for i in 10:
		part(root, box(Vector3(5.6, 0.1, 0.09)), rim, Vector3(0, 1.3, 5.68 + i * 0.205))
	# side vents on the block
	for s in [-1.0, 1.0]:
		for i in 4:
			part(root, box(Vector3(0.04, 0.5, 0.14)), hole, Vector3(3.31 * s, 0.6, 5.9 + i * 0.35))

	# RCS clusters at the nose corners and the rear corners
	for s in [-1.0, 1.0]:
		var c := Vector3(2.05 * s, 0.1, -7.35)
		part(root, box(Vector3(0.8, 0.55, 1.4)), black, c)
		for row in 2:
			for col in 3:
				part(root, cyl(0.075, 0.075, 0.06, 10), hole,
					c + Vector3(0.41 * s, 0.12 - row * 0.24, -0.4 + col * 0.4), Vector3(0, 0, PI / 2))
		for row in 2:
			for col in 3:
				part(root, cyl(0.08, 0.08, 0.06, 10), hole,
					Vector3((3.31 + 0.02) * s, 0.0 - row * 0.2, 6.9 + col * 0.25 - 0.25), Vector3(0, 0, PI / 2))

	# main engines in the rear face
	var flames: Array = []
	for s in [-1.0, 1.0]:
		flames.append(engine(root, Vector3(1.75 * s, 0.42, 7.7), 0.5, nozzle, Color(0.4, 0.55, 1.0),
			Color(0.85, 0.92, 1.0), 2.6, 1.1, 0.45))
	flames.append(engine(root, Vector3(0.0, 0.42, 7.7), 0.36, nozzle, Color(0.4, 0.55, 1.0),
		Color(0.85, 0.92, 1.0), 1.9, 1.1, 0.45))

	# guns hidden under the nose
	var muzzles: Array = []
	for s in [-1.0, 1.0]:
		muzzles.append(marker(root, Vector3(1.2 * s, -0.15, -8.4)))

	# nav lights on the chines
	part(root, sphere(0.07, 8), glow_mat(Color(1.0, 0.15, 0.1), 5.0), Vector3(-3.36, 0.0, 4.8))
	part(root, sphere(0.07, 8), glow_mat(Color(0.2, 1.0, 0.4), 5.0), Vector3(3.36, 0.0, 4.8))
	part(root, sphere(0.06, 8), glow_mat(Color(1.0, 1.0, 1.0), 6.0), Vector3(0.0, 1.42, 7.6))

	root.set_meta("muzzles", muzzles)
	root.set_meta("flames", flames)
	return root


## Enemy interceptor: gunmetal pod, forward-swept blades with red light strips.
static func fighter() -> Node3D:
	var root := Node3D.new()
	var metal := hull_mat(Color(0.2, 0.21, 0.24), 2.2, 0.6, 0.35)
	var dark := hull_mat(Color(0.09, 0.09, 0.1), 3.0, 0.8, 0.3)
	var red := Color(1.0, 0.18, 0.08)
	part(root, Proc.lathe(PackedVector2Array([Vector2(-3.8, 0.0), Vector2(-3.3, 0.38), Vector2(-2.2, 0.8),
		Vector2(-0.4, 1.05), Vector2(1.3, 1.05), Vector2(2.5, 0.85), Vector2(3.0, 0.55), Vector2(3.1, 0.0)]),
		20, 1.0, 0.85), with_stripe(metal, Vector3(0, 0, 1), -1.2, -0.9, red, 3.0))
	part(root, sphere(0.5, 16), glass_mat(Color(0.6, 0.06, 0.04)), Vector3(0, 0.5, -1.9),
		Vector3.ZERO, Vector3(0.8, 0.6, 1.7))
	var blade := PackedVector2Array([Vector2(0.7, 0.4), Vector2(4.8, -1.8), Vector2(5.3, -1.4),
		Vector2(5.0, 1.6), Vector2(0.7, 2.1)])
	var wm := with_stripe(metal, Vector3(1, 0, 0), 3.6, 3.85, red, 4.0)
	var wm_l := with_stripe(metal, Vector3(-1, 0, 0), 3.6, 3.85, red, 4.0)
	part(root, Proc.slab(blade, 0.26, 0.4), wm, Vector3(0, 0, 0), Vector3(0, 0, -0.38))
	part(root, Proc.slab(Proc.mirror_x(blade), 0.26, 0.4), wm_l, Vector3(0, 0, 0), Vector3(0, 0, 0.38))
	var muzzles: Array = []
	for s in [-1.0, 1.0]:
		var tip := Vector3(4.95 * s, -1.85, -0.6)
		part(root, cyl(0.08, 0.12, 2.4, 8), dark, tip, Vector3(PI / 2, 0, 0))
		muzzles.append(marker(root, tip + Vector3(0, 0, -1.3)))
	var fl := engine(root, Vector3(0, 0, 3.1), 0.62, dark, Color(1.0, 0.3, 0.1), Color(1.0, 0.8, 0.5), 2.6)
	root.set_meta("muzzles", muzzles)
	root.set_meta("flames", [fl])
	return root


## Missile body (used by missile.gd).
static func missile() -> Node3D:
	var root := Node3D.new()
	var white := hull_mat(Color(0.92, 0.92, 0.9), 4.0, 0.1, 0.4)
	part(root, cyl(0.16, 0.16, 2.2, 10), with_stripe(white, Vector3(0, 1, 0), 0.4, 0.7,
		Color(0.98, 0.72, 0.16)), Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	part(root, cyl(0.0, 0.16, 0.5, 10), white, Vector3(0, 0, -1.35), Vector3(-PI / 2, 0, 0))
	part(root, sphere(0.3, 10), add_mat(Color(1.0, 0.75, 0.45), 3.5), Vector3(0, 0, 1.2))
	return root
