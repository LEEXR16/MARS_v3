extends RefCounted
## Procedural meshes. Everything in the game is built from code: no imported models.


class MB:
	var st := SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func smooth(on: bool) -> void:
		st.set_smooth_group(0 if on else -1)

	## Adds a triangle whose front face points along `out`.
	func tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
		if (c - a).cross(b - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
		tri(a, b, c, out)
		tri(a, c, d, out)

	func commit() -> ArrayMesh:
		st.generate_normals()
		return st.commit()


## Surface of revolution along Z. profile = (z, radius) pairs from the nose (-Z,
## forward) to the tail, z never decreasing. sx / sy squash the cross-section;
## smooth = false gives a faceted hull. caps closes ends with a non-zero radius.
static func lathe(profile: PackedVector2Array, seg: int, sx := 1.0, sy := 1.0,
		smooth := true, caps := true) -> ArrayMesh:
	var mb := MB.new()
	mb.smooth(smooth)
	var rings: Array = []
	for p in profile:
		var ring := PackedVector3Array()
		for i in seg:
			var a := TAU * (i + 0.5) / seg
			ring.append(Vector3(cos(a) * p.y * sx, sin(a) * p.y * sy, p.x))
		rings.append(ring)
	for k in profile.size() - 1:
		var r0: PackedVector3Array = rings[k]
		var r1: PackedVector3Array = rings[k + 1]
		# outward normal of this profile segment in the (radius, z) plane
		var dz := profile[k + 1].x - profile[k].x
		var dr := profile[k + 1].y - profile[k].y
		for i in seg:
			var j := (i + 1) % seg
			var a := TAU * (i + 1.0) / seg
			var out := Vector3(cos(a) * dz * sy, sin(a) * dz * sx, -dr)
			mb.quad(r0[i], r0[j], r1[j], r1[i], out)
	if caps:
		var n := profile.size()
		if profile[0].y > 0.0:
			var c0 := Vector3(0, 0, profile[0].x)
			var first: PackedVector3Array = rings[0]
			for i in seg:
				mb.tri(c0, first[i], first[(i + 1) % seg], Vector3.FORWARD)
		if profile[n - 1].y > 0.0:
			var c1 := Vector3(0, 0, profile[n - 1].x)
			var last: PackedVector3Array = rings[n - 1]
			for i in seg:
				mb.tri(c1, last[i], last[(i + 1) % seg], Vector3.BACK)
	return mb.commit()


## Flat-shaded plate from a polygon in the XZ plane (x = span, z = chord, -z is
## forward), thickness along Y, thinning to `tip` x thickness at the largest |x|.
static func slab(poly: PackedVector2Array, thick: float, tip := 1.0) -> ArrayMesh:
	var mb := MB.new()
	mb.smooth(false)
	var span := 0.0
	for p in poly:
		span = maxf(span, absf(p.x))
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	for p in poly:
		var h := thick * 0.5 * lerpf(1.0, tip, absf(p.x) / maxf(span, 1e-3))
		top.append(Vector3(p.x, h, p.y))
		bot.append(Vector3(p.x, -h, p.y))
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		mb.tri(top[idx[t]], top[idx[t + 1]], top[idx[t + 2]], Vector3.UP)
		mb.tri(bot[idx[t]], bot[idx[t + 1]], bot[idx[t + 2]], Vector3.DOWN)
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= poly.size()
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var e := poly[j] - poly[i]
		var nrm := Vector2(e.y, -e.x)
		if nrm.dot((poly[i] + poly[j]) * 0.5 - cen) < 0.0:
			nrm = -nrm
		mb.quad(top[i], top[j], bot[j], bot[i], Vector3(nrm.x, 0.0, nrm.y))
	return mb.commit()


## Faceted lifting body lofted along Z through stations [z, half_width, top, bottom,
## top_chamfer, bottom_chamfer] (nose first, -z forward). The cross-section is a flat
## hexagon: top deck, two chamfers to a sharp side chine at y = 0, flat belly.
## Returns {"top": deck, "rim": chamfers + end caps, "belly": underside} so each
## part can get its own material.
static func loft(stations: Array) -> Dictionary:
	var parts := {"top": MB.new(), "rim": MB.new(), "belly": MB.new()}
	for k in parts:
		parts[k].smooth(false)
	var rings: Array = []
	for s in stations:
		var z: float = s[0]
		var hw: float = s[1]
		var top: float = s[2]
		var bot: float = s[3]
		var ct: float = s[4]
		var cb: float = s[5]
		rings.append([Vector3(-(hw - ct), top, z), Vector3(hw - ct, top, z), Vector3(hw, 0.0, z),
			Vector3(hw - cb, -bot, z), Vector3(-(hw - cb), -bot, z), Vector3(-hw, 0.0, z)])
	var group := ["top", "rim", "rim", "belly", "rim", "rim"]
	for k in rings.size() - 1:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for i in 6:
			var j := (i + 1) % 6
			var mid: Vector3 = (r0[i] + r0[j]) * 0.5
			var out := Vector3(mid.x, mid.y, 0.0)
			if i == 0:
				out = Vector3.UP
			elif i == 3:
				out = Vector3.DOWN
			parts[group[i]].quad(r0[i], r0[j], r1[j], r1[i], out)
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		var out := Vector3.FORWARD if end == 0 else Vector3.BACK
		for i in range(1, 5):
			parts.rim.tri(r[0], r[i], r[i + 1], out)
	return {"top": parts.top.commit(), "rim": parts.rim.commit(), "belly": parts.belly.commit()}


static func mirror_x(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(Vector2(-poly[i].x, poly[i].y))
	return out


## Lumpy cratered rock from a subdivided icosahedron, radius about 1.
static func asteroid(seed_v: int, subdiv := 4) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9],
		[5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6],
		[3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var cache := {}
		var nf: Array = []
		for f in faces:
			var a := _mid(verts, cache, f[0], f[1])
			var b := _mid(verts, cache, f[1], f[2])
			var c := _mid(verts, cache, f[2], f[0])
			nf.append([f[0], a, c])
			nf.append([f[1], b, a])
			nf.append([f[2], c, b])
			nf.append([a, b, c])
		faces = nf

	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var stretch := Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.62, 0.92), rng.randf_range(0.8, 1.35))
	var craters: Array = []
	for i in rng.randi_range(4, 9):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		craters.append([d, rng.randf_range(0.16, 0.42), rng.randf_range(0.05, 0.14)])

	var pos := PackedVector3Array()
	for v in verts:
		var r := 1.0 + noise.get_noise_3dv(v) * 0.34 + noise.get_noise_3dv(v * 3.1 + Vector3(5, 5, 5)) * 0.07
		for c in craters:
			var k: float = v.angle_to(c[0]) / c[1]
			if k < 1.0:
				r += (k * k - 1.0) * c[2]
			elif k < 1.4:
				r += sin(PI * (k - 1.0) / 0.4) * c[2] * 0.35
		pos.append(v * r * stretch)

	var idx := PackedInt32Array()
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var n := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		if n.dot(pos[a] + pos[b] + pos[c]) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		idx.append(a)
		idx.append(b)
		idx.append(c)
		nrm[a] += n
		nrm[b] += n
		nrm[c] += n
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _mid(verts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
