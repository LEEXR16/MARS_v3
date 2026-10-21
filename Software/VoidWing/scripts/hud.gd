extends Control
## In-flight HUD, redrawn every frame: boresight + aim line, target brackets,
## lock diamond, off-screen arrows, missiles panel, shield / hull, timer.
## Black and white only: hostiles are told apart by shape, not colour.

const WHITE := Color(1, 1, 1, 0.92)
const DIM := Color(1, 1, 1, 0.45)
const ENEMY := Color(1, 1, 1, 0.95)
const GOLD := Color(0.88, 0.88, 0.88)
const BLUE := Color(0.72, 0.72, 0.72)
const PANEL := Color(0, 0, 0, 0.62)
const EDGE := Color(1, 1, 1, 0.28)

var game
var font: Font
var font_b: Font
var banner_text := ""
var banner_sub := ""
var banner_col := WHITE
var banner_t := 0.0
var banner_len := 3.0
var feed: Array = []
var flash := 0.0
var flash_hull := false
var hitmark := 0.0
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func banner(text: String, sub := "", col := WHITE, dur := 3.2) -> void:
	banner_text = text
	banner_sub = sub
	banner_col = col
	banner_t = dur
	banner_len = dur


func message(text: String) -> void:
	feed.push_front([text, 4.0])
	if feed.size() > 5:
		feed.pop_back()


func hit(hull_hit: bool) -> void:
	flash = 1.0
	flash_hull = hull_hit


func _process(dt: float) -> void:
	t += dt
	banner_t = maxf(0.0, banner_t - dt)
	flash = maxf(0.0, flash - dt * 2.5)
	hitmark = maxf(0.0, hitmark - dt * 4.0)
	for f in feed:
		f[1] -= dt
	while not feed.is_empty() and feed[-1][1] <= 0.0:
		feed.pop_back()
	queue_redraw()


func _text(pos: Vector2, s: String, size_px: int, col: Color, align := 0, f: Font = null) -> void:
	var fnt := f if f else font
	var w := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	draw_string(fnt, Vector2(x + 1.5, pos.y + 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
		Color(0, 0, 0, col.a * 0.6))
	draw_string(fnt, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


func _draw() -> void:
	if game == null or not (game.state == game.State.PLAY or game.state == game.State.PAUSE):
		return
	var sz := get_viewport_rect().size
	var cam: Camera3D = game.cam
	var p = game.player

	if flash > 0.0:
		var c := Color(1, 1, 1, (0.14 if flash_hull else 0.06) * flash)
		draw_rect(Rect2(Vector2.ZERO, sz), c)
		if flash_hull:
			draw_rect(Rect2(Vector2(6, 6), sz - Vector2(12, 12)), Color(1, 1, 1, 0.5 * flash), false, 3.0)

	if p.alive:
		_draw_targets(cam, p, sz)
		_draw_reticle(cam, p, sz)
	_draw_top(sz)
	_draw_missiles(p, sz)
	_draw_status(p, sz)
	if game.settings.input == "robot":
		_draw_arm(sz)
	_draw_feed(sz)
	_draw_banner(sz)
	if not p.alive:
		_text(Vector2(sz.x * 0.5, sz.y * 0.55), "HULL BREACH  ·  RELAUNCHING IN %d" % ceili(game.respawn_t),
			26, ENEMY, 1, font_b)
	elif game.out_of_bounds:
		if fmod(t, 0.8) < 0.55:
			_text(Vector2(sz.x * 0.5, sz.y * 0.68), "RETURN TO THE COMBAT AREA", 26, ENEMY, 1, font_b)


func _draw_reticle(cam: Camera3D, p, sz: Vector2) -> void:
	var bore_w: Vector3 = p.global_position + p.fwd() * 500.0
	if cam.is_position_behind(bore_w):
		return
	var bp := cam.unproject_position(bore_w)
	draw_arc(bp, 22.0, 0, TAU, 48, WHITE, 2.0, true)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(bp + d * 22.0, bp + d * 32.0, WHITE, 2.0, true)
	draw_circle(bp, 2.0, WHITE)
	if hitmark > 0.0:
		var c := Color(1, 1, 1, hitmark)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(bp + d * 9.0, bp + d * 16.0, c, 2.0, true)
	# aim cursor (mouse / arm) and the line to the boresight
	var cur: Vector2 = sz * 0.5 + Vector2(p.aim_now.x, -p.aim_now.y) * sz.y * 0.3
	var dv := cur - bp
	if dv.length() > 34.0:
		draw_line(bp + dv.normalized() * 24.0, cur - dv.normalized() * 9.0, Color(1, 1, 1, 0.7), 1.5, true)
	draw_arc(cur, 8.0, 0, TAU, 24, Color(1, 1, 1, 0.85), 2.0, true)


func _draw_targets(cam: Camera3D, p, sz: Vector2) -> void:
	var center := sz * 0.5
	var inv := cam.global_transform.affine_inverse()
	var objective = game.objective()
	for h in game.hostiles:
		if not is_instance_valid(h) or not h.alive:
			continue
		var is_obj: bool = h == objective
		if not h.targetable() and not is_obj:
			continue
		var wp: Vector3 = h.global_position
		var dist: float = p.global_position.distance_to(wp)
		if dist > 3200.0:
			continue
		var col := BLUE if is_obj and h.kind != "FIGHTER" else ENEMY
		var sp := cam.unproject_position(wp)
		var on := not cam.is_position_behind(wp) and Rect2(Vector2(40, 40), sz - Vector2(80, 80)).has_point(sp)
		if not on:
			if h.kind == "FIGHTER" and dist > 1800.0:
				continue
			var lv := inv * wp
			var d := Vector2(lv.x, -lv.y)
			if d.length() < 0.001:
				d = Vector2.UP
			d = d.normalized()
			var e := center + Vector2(d.x * (sz.x * 0.5 - 70.0), d.y * (sz.y * 0.5 - 70.0))
			var tip := e + d * 12.0
			var nrm := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([tip, e - d * 6.0 + nrm * 9.0, e - d * 6.0 - nrm * 9.0]), col)
			if is_obj:
				_text(e - d * 26.0 + Vector2(0, 6), h.kind.split(" ")[-1], 15, col, 1, font_b)
			continue
		var r: float = clampf(h.radius * 1100.0 / maxf(dist, 1.0), 10.0, 70.0)
		var is_t: bool = h == p.target
		var c := col if is_t else Color(col, 0.55)
		var k := r * 0.35
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := sp + Vector2(sx, sy) * r
				draw_line(corner, corner - Vector2(sx * k, 0), c, 1.6, true)
				draw_line(corner, corner - Vector2(0, sy * k), c, 1.6, true)
		if is_obj and not is_t:
			_text(sp + Vector2(0, -r - 8.0), h.kind, 14, c, 1, font_b)
		if is_t:
			_text(sp + Vector2(0, -r - 22.0), h.kind, 18, col, 1, font_b)
			draw_line(sp + Vector2(-r, -r - 16.0), sp + Vector2(-r + 2.0 * r * h.hp / h.max_hp, -r - 16.0), col, 3.0)
			_text(sp + Vector2(0, r + 22.0), "%d m" % int(dist), 15, Color(col, 0.85), 1)
			# lead pip
			var lead: Vector3 = wp + h.velocity() * (dist / p.LASER_SPEED)
			if not cam.is_position_behind(lead):
				draw_arc(cam.unproject_position(lead), 5.0, 0, TAU, 16, Color(col, 0.8), 1.5, true)
			# lock diamond
			var lp: float = p.lock_progress()
			if lp > 0.0:
				var ds: float = lerpf(r * 2.4, r * 1.05, lp)
				var rot: float = (1.0 - lp) * PI * 0.5
				var pts := PackedVector2Array()
				for i in 5:
					var a := rot + i * PI * 0.5
					pts.append(sp + Vector2(cos(a), sin(a)) * ds)
				draw_polyline(pts, ENEMY if p.locked else Color(ENEMY, 0.6), 2.0 if p.locked else 1.4, true)
				if p.locked:
					_text(sp + Vector2(ds + 10.0, 6.0), "LOCK", 16, ENEMY, 0, font_b)
					_text(Vector2(center.x, center.y + 90.0), "MISSILE LOCK", 20, ENEMY, 1, font_b)


func _draw_top(sz: Vector2) -> void:
	var left: float = maxf(game.session_left, 0.0)
	var mm := int(left) / 60
	var ss := int(left) % 60
	_text(Vector2(sz.x * 0.5, 54), "%02d:%02d" % [mm, ss], 36, WHITE if left > 30.0 else GOLD, 1, font_b)
	_text(Vector2(sz.x * 0.5, 82), game.objective_text(), 17, GOLD, 1, font_b)
	_text(Vector2(sz.x * 0.5, 104), "HOSTILE FIGHTERS  %d" % game.fighters.size(), 14, DIM, 1)
	_text(Vector2(sz.x - 40, 54), "%s" % _thousands(game.score), 32, WHITE, 2, font_b)
	_text(Vector2(sz.x - 40, 78), "SCORE  ·  WAVE %d" % game.wave, 14, DIM, 2)


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _draw_missiles(p, sz: Vector2) -> void:
	var r := Rect2(sz.x - 400.0, sz.y - 175.0, 360.0, 135.0)
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 1.0)
	_text(r.position + Vector2(20, 34), "MISSILES", 17, WHITE, 0, font_b)
	_text(Vector2(r.end.x - 20, r.position.y + 46), str(p.missiles), 44, WHITE, 2, font_b)
	for i in p.MAX_MISSILES:
		var x: float = r.position.x + 22.0 + i * 16.0
		var c := WHITE if i < p.missiles else Color(1, 1, 1, 0.15)
		draw_rect(Rect2(x, r.position.y + 62.0, 8.0, 26.0), c)
		draw_rect(Rect2(x, r.position.y + 58.0, 8.0, 5.0), Color(c, c.a * 0.7))
	var status := "NO TARGET"
	var sc := DIM
	if p.target:
		if p.locked:
			status = "LOCKED  ·  " + p.target.kind
			sc = ENEMY
		else:
			status = "ACQUIRING  %d%%" % int(p.lock_progress() * 100.0)
			sc = GOLD
	_text(r.position + Vector2(20, 118), status, 16, sc, 0, font_b)


func _bar(pos: Vector2, w: float, v: float, col: Color, label: String) -> void:
	_text(pos, label, 14, DIM, 0, font_b)
	draw_rect(Rect2(pos + Vector2(80, -11), Vector2(w, 10)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(pos + Vector2(80, -11), Vector2(w * clampf(v, 0.0, 1.0), 10)), col)


func _draw_status(p, sz: Vector2) -> void:
	var r := Rect2(40.0, sz.y - 175.0, 380.0, 135.0)
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 1.0)
	_bar(r.position + Vector2(20, 36), 260.0, p.shield / 100.0, WHITE, "SHIELD")
	var low: bool = p.hull < 35.0 and fmod(t, 0.6) < 0.3
	_bar(r.position + Vector2(20, 66), 260.0, p.hull / 100.0, DIM if low else WHITE, "HULL")
	_bar(r.position + Vector2(20, 96), 260.0, p.boost, Color(1, 1, 1, 0.6), "BOOST")
	_text(r.position + Vector2(20, 124), "SPEED  %d m/s" % int(p.speed), 14, DIM, 0, font_b)


func _draw_arm(sz: Vector2) -> void:
	var robot = game.robot
	var r := Rect2(40.0, sz.y - 420.0, 170.0, 170.0)
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 1.0)
	var c := r.get_center()
	draw_line(Vector2(r.position.x + 10, c.y), Vector2(r.end.x - 10, c.y), Color(1, 1, 1, 0.15), 1.0)
	draw_line(Vector2(c.x, r.position.y + 10), Vector2(c.x, r.end.y - 10), Color(1, 1, 1, 0.15), 1.0)
	draw_arc(c, 70.0 * game.robot.DEAD, 0, TAU, 24, Color(1, 1, 1, 0.2), 1.0, true)
	var dot := c + Vector2(robot.aim.x, -robot.aim.y) * 70.0
	draw_circle(dot, 6.0, GOLD if robot.live() else ENEMY)
	_text(r.position + Vector2(10, -10), "ARM", 14, DIM, 0, font_b)
	var line := "LIFT %.0f°  REACH %d%%" % [robot.raw.y, int(robot.reach * 100.0)] if robot.live() else "NO ROBOT DATA"
	_text(Vector2(r.position.x + 10, r.end.y + 20), line, 13, GOLD if robot.live() else ENEMY, 0, font_b)
	if robot.live() and not robot.enc_ok():
		_text(Vector2(r.position.x + 10, r.end.y + 38), "ENCODERS OFF · LIFT ONLY", 12, ENEMY, 0, font_b)


func _draw_feed(sz: Vector2) -> void:
	var y := 130.0
	for f in feed:
		_text(Vector2(sz.x - 40, y), f[0], 15, Color(WHITE, clampf(f[1], 0.0, 1.0)), 2, font_b)
		y += 24.0


func _draw_banner(sz: Vector2) -> void:
	if banner_t <= 0.0:
		return
	var a := clampf(banner_t, 0.0, 1.0) * clampf((banner_len - banner_t) * 4.0, 0.0, 1.0)
	var y := sz.y * 0.3
	_text(Vector2(sz.x * 0.5, y), banner_text, 44, Color(banner_col, a), 1, font_b)
	var w := 320.0
	draw_line(Vector2(sz.x * 0.5 - w, y + 18), Vector2(sz.x * 0.5 + w, y + 18), Color(banner_col, a * 0.6), 2.0)
	if banner_sub != "":
		_text(Vector2(sz.x * 0.5, y + 50), banner_sub, 20, Color(WHITE, a * 0.85), 1)
