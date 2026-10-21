extends Control
## Screens: start (session setup), arm calibration, pause and session results.
## Black and white: white text and thin lines on black.

const GOLD := Color(1, 1, 1, 0.55)        # key labels (grey)
const WHITE := Color(1, 1, 1)
const MUTED := Color(1, 1, 1, 0.62)
const RED := Color(1, 1, 1, 0.9)
const GREEN := Color(1, 1, 1)
const BLUE := Color(0.8, 0.8, 0.8)
const LINE := Color(1, 1, 1, 0.3)
const MINUTES := [1, 2, 3, 5, 8, 10, 15, 20, 30]

var game
var f_title: Font
var f_body: Font
var f_semi: Font
var f_hud: Font
var t := 0.0

var start: Control
var calib: Control
var pause: Control
var results: Control
var launch: Button
var time_lbl: Label
var link_lbl: Label
var cal_btn: Button
var controls: GridContainer
var input_btns := {}
var diff_btns: Array = []
var screen_btns: Array = []
var fs_btn: Button
var cal_title: Label
var cal_msg: Label
var cal_box: Control
var cal_bar: ProgressBar
var cal_go: Button
var pause_title: Label
var res_title: Label
var res_sub: Label
var res_grid: GridContainer
var res_note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	theme = _theme()
	start = _build_start()
	calib = _build_calib()
	pause = _build_pause()
	results = _build_results()
	show_screen("start")


## Fill the (stretched) viewport. Anchors alone do not size a Control under a CanvasLayer here.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


# ---------------- look ----------------

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font = f_body
	th.default_font_size = 20
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0.55)
	n.border_color = LINE
	n.set_border_width_all(1)
	n.set_content_margin_all(10)
	n.content_margin_left = 18
	n.content_margin_right = 18
	var h := n.duplicate() as StyleBoxFlat
	h.border_color = WHITE
	h.bg_color = Color(1, 1, 1, 0.08)
	var p := n.duplicate() as StyleBoxFlat
	p.border_color = WHITE
	p.bg_color = Color(1, 1, 1, 0.92)
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", h)
	th.set_stylebox("pressed", "Button", p)
	th.set_stylebox("hover_pressed", "Button", p)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", WHITE)
	th.set_color("font_hover_color", "Button", WHITE)
	th.set_color("font_pressed_color", "Button", Color.BLACK)
	th.set_color("font_hover_pressed_color", "Button", Color.BLACK)
	th.set_font("font", "Button", f_semi)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.86)
	panel.border_color = LINE
	panel.set_border_width_all(1)
	panel.set_content_margin_all(28)
	th.set_stylebox("panel", "PanelContainer", panel)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = WHITE
	th.set_stylebox("background", "ProgressBar", bg)
	th.set_stylebox("fill", "ProgressBar", fg)
	return th


func _lbl(text: String, font: Font, size_px: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size_px
	s.font_color = col
	if outline > 0:
		s.shadow_color = Color(0, 0, 0, 0.6)
		s.shadow_size = outline
		s.shadow_offset = Vector2(2, 2)
	l.label_settings = s
	return l


func _btn(text: String, cb: Callable, size_px := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size_px)
	b.pressed.connect(func():
		game.sfx.play("click", -8.0)
		cb.call())
	return b


func _line(w: float, col: Color, h := 3.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(w, h)
	return r


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---------------- start screen ----------------

func _build_start() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# darken the left side so the text reads over the scene
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.0)])
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.62, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(120, 110)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	col.add_child(_lbl("VOID WING", f_title, 120, WHITE, 6))
	var ul := HBoxContainer.new()
	ul.add_theme_constant_override("separation", 10)
	ul.add_child(_line(620, WHITE, 2))
	ul.add_child(_line(48, Color(1, 1, 1, 0.45), 2))
	col.add_child(ul)
	col.add_child(_gap(8))
	col.add_child(_lbl("RANGER   //   GARGANTUA BELT", f_body, 26, MUTED, 2))
	col.add_child(_gap(40))
	launch = Button.new()
	launch.text = "PRESS ENTER OR CLICK TO LAUNCH"
	launch.flat = true
	launch.alignment = HORIZONTAL_ALIGNMENT_LEFT
	launch.add_theme_font_override("font", f_semi)
	launch.add_theme_font_size_override("font_size", 34)
	launch.add_theme_color_override("font_color", WHITE)
	launch.add_theme_color_override("font_hover_color", WHITE)
	launch.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	launch.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	launch.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	launch.pressed.connect(func(): game.launch())
	col.add_child(launch)
	col.add_child(_gap(30))

	# session settings
	col.add_child(_header("SESSION"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)

	grid.add_child(_key("LENGTH"))
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	tr.add_child(_btn("◀", func(): _step_time(-1)))
	time_lbl = _lbl("05:00", f_hud, 30, WHITE)
	time_lbl.custom_minimum_size = Vector2(120, 0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tr.add_child(time_lbl)
	tr.add_child(_btn("▶", func(): _step_time(1)))
	grid.add_child(tr)

	grid.add_child(_key("CONTROL"))
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 10)
	var ig := ButtonGroup.new()
	for k in [["robot", "ROBOT ARM"], ["mouse", "MOUSE + KEYS"]]:
		var b := _btn(k[1], func(): _set_input(k[0]), 18)
		b.toggle_mode = true
		b.button_group = ig
		input_btns[k[0]] = b
		ir.add_child(b)
	grid.add_child(ir)

	grid.add_child(_key("DIFFICULTY"))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 10)
	var dg := ButtonGroup.new()
	for i in 3:
		var b := _btn(["EASY", "NORMAL", "HARD"][i], func(): _set_diff(i), 18)
		b.toggle_mode = true
		b.button_group = dg
		diff_btns.append(b)
		dr.add_child(b)
	grid.add_child(dr)

	var dk := _key("DISPLAY")
	grid.add_child(dk)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	var sg := ButtonGroup.new()
	for i in game.screen_count():
		var b := _btn("SCREEN %d" % (i + 1), func(): game.set_display(i, game.settings.fullscreen), 18)
		b.toggle_mode = true
		b.button_group = sg
		screen_btns.append(b)
		sr.add_child(b)
	fs_btn = _btn("FULL SCREEN", func(): game.set_display(int(game.settings.screen), fs_btn.button_pressed), 18)
	fs_btn.toggle_mode = true
	sr.add_child(fs_btn)
	grid.add_child(sr)
	if game.web:   # one screen on a tablet, and the app owns it
		dk.visible = false
		sr.visible = false

	grid.add_child(_key("ROBOT LINK"))
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 18)
	link_lbl = _lbl("", f_semi, 18, MUTED)
	link_lbl.custom_minimum_size = Vector2(330, 0)
	lr.add_child(link_lbl)
	cal_btn = _btn("CALIBRATE ARM", func(): game.begin_calibration(), 18)
	lr.add_child(cal_btn)
	grid.add_child(lr)

	col.add_child(_gap(26))
	col.add_child(_header("CONTROLS"))
	controls = GridContainer.new()
	controls.columns = 2
	controls.add_theme_constant_override("h_separation", 60)
	controls.add_theme_constant_override("v_separation", 4)
	col.add_child(controls)

	# mission briefing, bottom right
	var brief := PanelContainer.new()
	brief.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	brief.custom_minimum_size = Vector2(560, 0)
	brief.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	brief.grow_vertical = Control.GROW_DIRECTION_BEGIN
	brief.offset_left = -680
	brief.offset_top = -330
	brief.offset_right = -110
	brief.offset_bottom = -110
	root.add_child(brief)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	brief.add_child(bv)
	bv.add_child(_lbl("MISSION BRIEFING", f_semi, 22, WHITE))
	var body := _lbl("An enemy frigate holds the debris belt in Gargantua's shadow, escorted by " +
		"interceptors. Fly the Ranger in, knock out its six defence turrets to collapse the reactor " +
		"shield, then destroy the reactor core. Your guns and missiles fire by themselves: keep the " +
		"target in your sights. Watch the rocks.", f_body, 19, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	bv.add_child(body)
	var hint := _lbl("BACK  LEAVE THE GAME" if game.web else "ESC  QUIT   ·   F11  FULL SCREEN / WINDOW   ·   F10  NEXT SCREEN",
		f_semi, 14, Color(1, 1, 1, 0.35))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 120
	hint.offset_top = -34
	root.add_child(hint)
	return root


func _header(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_lbl(text, f_semi, 17, Color(1, 1, 1, 0.65)))
	v.add_child(_line(500, Color(1, 1, 1, 0.18), 1))
	return v


func _key(text: String) -> Label:
	var l := _lbl(text, f_semi, 19, GOLD)
	l.custom_minimum_size = Vector2(170, 0)
	return l


func _step_time(d: int) -> void:
	var i := MINUTES.find(int(game.settings.minutes))
	i = clampi((i if i >= 0 else 3) + d, 0, MINUTES.size() - 1)
	game.settings.minutes = MINUTES[i]
	game.save_settings()
	refresh()


func _set_input(k: String) -> void:
	game.settings.input = k
	game.save_settings()
	refresh()


func _set_diff(i: int) -> void:
	game.settings.difficulty = i
	game.save_settings()
	refresh()


func refresh() -> void:
	time_lbl.text = "%02d:00" % int(game.settings.minutes)
	input_btns[game.settings.input].button_pressed = true
	diff_btns[int(game.settings.difficulty)].button_pressed = true
	var cur := DisplayServer.window_get_current_screen()
	if cur >= 0 and cur < screen_btns.size():
		screen_btns[cur].set_pressed_no_signal(true)
	fs_btn.set_pressed_no_signal(bool(game.settings.fullscreen))
	for c in controls.get_children():
		c.queue_free()
	var rows := [["ARM UP / DOWN", "Climb / dive  ·  lift the lever"], ["ARM LEFT / RIGHT", "Turn  ·  sweep the hand"],
		["REACH OUT", "Faster"], ["TARGET IN SIGHTS", "Guns fire by themselves"],
		["HOLD IT STEADY", "Missile locks and launches"], ["SPACE / ESC", "Pause"]]
	if game.settings.input == "mouse":
		rows = [["MOUSE", "Steer the ship"], ["W / S", "Throttle up / down"], ["A / D", "Strafe left / right"],
			["SPACE / CTRL", "Thrust up / down"], ["Q / E", "Dodge roll"], ["SHIFT", "Boost"],
			["TARGET IN SIGHTS", "Guns fire by themselves"], ["HOLD IT STEADY", "Missile locks and launches"],
			["ESC", "Pause"]]
	for r in rows:
		var k := _lbl(r[0], f_semi, 18, GOLD)
		k.custom_minimum_size = Vector2(230, 0)
		controls.add_child(k)
		controls.add_child(_lbl(r[1], f_body, 18, WHITE))


func _process(dt: float) -> void:
	t += dt
	if start.visible:
		launch.modulate.a = 0.65 + 0.35 * sin(t * 3.0)
		var r = game.robot
		if r.live():
			var enc := "ENC OK" if r.enc_ok() else "ENC OFF (LIFT ONLY)"
			link_lbl.text = "LIVE   LIFT %.0f°   %s   %s" % [r.raw.y, r.mode(), enc]
			link_lbl.label_settings.font_color = GREEN if r.enc_ok() else GOLD
		else:
			link_lbl.text = "NO DATA   (connect the robot in the app)" if game.web else "NO DATA   (GUI → GAME, UDP %d)" % r.PORT
			link_lbl.label_settings.font_color = MUTED if game.settings.input == "mouse" else RED
		cal_btn.text = "RECALIBRATE ARM" if r.cal.done else "CALIBRATE ARM"
	if calib.visible:
		_update_calib()


# ---------------- calibration ----------------

func _build_calib() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var pnl := PanelContainer.new()
	pnl.custom_minimum_size = Vector2(820, 0)
	c.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pnl.add_child(v)
	cal_title = _lbl("ARM CALIBRATION", f_title, 44, WHITE)
	v.add_child(cal_title)
	cal_msg = _lbl("", f_body, 22, MUTED)
	cal_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cal_msg.custom_minimum_size = Vector2(760, 90)
	v.add_child(cal_msg)
	cal_box = Control.new()
	cal_box.custom_minimum_size = Vector2(760, 300)
	cal_box.draw.connect(_draw_cal_box)
	v.add_child(cal_box)
	cal_bar = ProgressBar.new()
	cal_bar.custom_minimum_size = Vector2(760, 8)
	cal_bar.show_percentage = false
	cal_bar.max_value = 1.0
	v.add_child(cal_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	cal_go = _btn("START", func(): game.robot.begin_calibration())
	row.add_child(cal_go)
	row.add_child(_btn("FLIP LEFT / RIGHT", func():
		game.robot.cal.inv_x = not game.robot.cal.inv_x
		game.robot.save()))
	row.add_child(_btn("FLIP UP / DOWN", func():
		game.robot.cal.inv_y = not game.robot.cal.inv_y
		game.robot.save()))
	row.add_child(_btn("DONE", func(): game.end_calibration()))
	v.add_child(row)
	return c


func _update_calib() -> void:
	var r = game.robot
	cal_bar.value = r.cal_progress()
	cal_go.disabled = r.cal_state in [1, 2]
	match r.cal_state:
		0:
			cal_msg.text = ("Sit comfortably with the arm in the cuff. Press START, relax for 3 seconds, " +
				"then move the arm around as far as is comfortable: up, down, left, right, and reach out.")
		1:
			cal_msg.text = "RELAX  ·  hold your neutral position  (%d s)" % ceili(r.NEUTRAL_S - r.cal_t)
		2:
			cal_msg.text = "MOVE  ·  up, down, left, right, reach out  (%d s)" % ceili(r.RANGE_S - r.cal_t)
		3:
			cal_msg.text = ("Done. The dot should follow your hand: test it below. Use FLIP if a " +
				"direction is reversed, then press DONE.")
	if not r.live():
		cal_msg.text = "No robot data. In the MARS GUI: connect, then GAME (or tick UDP out)."
	cal_box.queue_redraw()


func _draw_cal_box() -> void:
	var r = game.robot
	var s := cal_box.size
	var box := Rect2(Vector2((s.x - 280.0) * 0.5, 10.0), Vector2(280, 280))
	cal_box.draw_rect(box, Color(1, 1, 1, 0.05))
	cal_box.draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
	var c := box.get_center()
	cal_box.draw_line(Vector2(box.position.x, c.y), Vector2(box.end.x, c.y), Color(1, 1, 1, 0.12))
	cal_box.draw_line(Vector2(c.x, box.position.y), Vector2(c.x, box.end.y), Color(1, 1, 1, 0.12))
	var dot := c + Vector2(r.aim.x, -r.aim.y) * 130.0
	cal_box.draw_circle(dot, 9.0, GOLD if r.live() else RED)
	var f := f_semi
	var x := box.end.x + 30
	cal_box.draw_string(f, Vector2(x, box.position.y + 30), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	var lines := ["lift  %.1f°" % r.raw.y, "side  %.0f mm" % r.raw.x, "reach  %.0f mm" % r.raw.z]
	for i in lines.size():
		cal_box.draw_string(f, Vector2(x, box.position.y + 56 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, WHITE)
	cal_box.draw_string(f, Vector2(box.end.x + 30, box.position.y + 140),
		"lift %.0f° … %.0f°" % [r.cal.y_lo, r.cal.y_hi], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
	cal_box.draw_string(f, Vector2(box.end.x + 30, box.position.y + 164),
		"side %.0f … %.0f mm" % [r.cal.x_lo, r.cal.x_hi], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)


# ---------------- pause ----------------

func _build_pause() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	pause_title = _lbl("PAUSED", f_title, 90, WHITE, 4)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pause_title)
	var b1 := _btn("RESUME", func(): game.resume(), 24)
	var b2 := _btn("END SESSION", func(): game.finish_session(), 24)
	v.add_child(b1)
	v.add_child(b2)
	return c


# ---------------- results ----------------

func _build_results() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var pnl := PanelContainer.new()
	pnl.custom_minimum_size = Vector2(1000, 0)
	c.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pnl.add_child(v)
	res_title = _lbl("SESSION COMPLETE", f_title, 64, WHITE)
	v.add_child(res_title)
	res_sub = _lbl("", f_semi, 20, GOLD)
	v.add_child(res_sub)
	v.add_child(_line(940, Color(1, 1, 1, 0.18), 1))
	res_grid = GridContainer.new()
	res_grid.columns = 4
	res_grid.add_theme_constant_override("h_separation", 30)
	res_grid.add_theme_constant_override("v_separation", 18)
	v.add_child(res_grid)
	res_note = _lbl("", f_body, 15, MUTED)
	res_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_note.custom_minimum_size = Vector2(940, 0)
	v.add_child(res_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_btn("PLAY AGAIN", func(): game.launch(), 22))
	row.add_child(_btn("MAIN MENU", func(): game.to_menu(), 22))
	v.add_child(row)
	return c


func show_results(title: String, sub: String, tiles: Array, note: String) -> void:
	res_title.text = title
	res_sub.text = sub
	res_note.text = note
	for ch in res_grid.get_children():
		ch.queue_free()
	for tile in tiles:
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(215, 0)
		v.add_child(_lbl(str(tile[1]), f_hud, 36, WHITE))
		v.add_child(_lbl(tile[0], f_semi, 15, GOLD))
		res_grid.add_child(v)
	show_screen("results")


func show_screen(which: String) -> void:
	start.visible = which == "start"
	calib.visible = which == "calib"
	pause.visible = which == "pause"
	results.visible = which == "results"
	if which == "start":
		refresh()
