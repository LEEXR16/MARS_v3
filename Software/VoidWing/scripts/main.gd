extends Node3D
## VOID WING: a space shooter for the MARS arm-support robot.
## The MARS GUI (CODE/MARS_GUI) streams the arm pose as UDP JSON to 127.0.0.1:5005;
## mouse + keyboard also work. The start screen sets the session length.
##
## Command line (after `--`): shot=<png> frames=<n[,n..]> state=menu|play|calib|end auto
## renders screenshots for checking the look without playing.
##
## Web build (inside the MARS tablet app): the arm comes from window.marsInput, session logs go to
## the app (MarsGame.postMessage, the app saves them) and leaving posts {"type": "exit"}.

const Space = preload("res://scripts/space.gd")
const PlayerS = preload("res://scripts/player.gd")
const FighterS = preload("res://scripts/fighter.gd")
const FrigateS = preload("res://scripts/frigate.gd")
const CombatS = preload("res://scripts/combat.gd")
const FxS = preload("res://scripts/fx.gd")
const HudS = preload("res://scripts/hud.gd")
const MenuS = preload("res://scripts/menu.gd")
const RobotS = preload("res://scripts/robot_input.gd")
const SfxS = preload("res://scripts/sfx.gd")
const VIGNETTE := preload("res://shaders/vignette.gdshader")

enum State { MENU, CALIB, PLAY, PAUSE, END }

const DIFF := [
	{"name": "EASY", "fighters": 3, "enemy_dmg": 3.0, "enemy_err": 0.07, "enemy_gap": 1.7,
		"turret_dmg": 3.0, "lock": 0.6, "assist": 0.16},
	{"name": "NORMAL", "fighters": 5, "enemy_dmg": 5.0, "enemy_err": 0.04, "enemy_gap": 1.1,
		"turret_dmg": 5.0, "lock": 0.9, "assist": 0.1},
	{"name": "HARD", "fighters": 7, "enemy_dmg": 8.0, "enemy_err": 0.022, "enemy_gap": 0.7,
		"turret_dmg": 7.0, "lock": 1.2, "assist": 0.06},
]
const ARENA := 2600.0
const SPAWN := Vector3(0, 40, 1100)
const SETTINGS_PATH := "user://settings.json"
const MOUSE_SENS := 1.0 / 380.0

var state := State.MENU
var settings := {"minutes": 5, "input": "robot" if OS.has_feature("web") else "mouse", "difficulty": 0,
	"screen": -1, "fullscreen": true}
var web := OS.has_feature("web")
var diff: Dictionary = DIFF[0]
var rng := RandomNumberGenerator.new()

var world: Node3D
var cam: Camera3D
var player
var combat
var fx
var hud
var menu
var robot
var sfx
var frigate = null
var fighters: Array = []
var hostiles: Array = []
var rocks := {}
var dust_mat: ShaderMaterial
var vignette: ColorRect
var vig := 0.3

var session_left := 300.0
var score := 0
var wave := 1
var stats := {}
var respawn_t := 0.0
var next_frigate_t := -1.0
var spawn_t := 0.0
var out_of_bounds := false
var bump_cd := 0.0
var mouse_aim := Vector2.ZERO
var cam_basis := Basis.IDENTITY
var end_slow := 0.0
var link_lost_t := 0.0
var launch_after_cal := false
var auto := false
var menu_t := 0.0
var trace: Array = []
var trace_t := 0.0
var last_cuff := Vector3.ZERO
var shot_path := ""
var shot_frames: Array = []
var shot_state := ""
var settings_override := ""
var debug_cam := Vector3.INF     # cam=x,y,z: fixed camera looking at the origin
var frame := 0


func _ready() -> void:
	rng.randomize()
	_parse_args()
	_input_map()
	_load_settings()
	if settings_override != "":
		settings.input = settings_override
	process_mode = Node.PROCESS_MODE_ALWAYS

	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var env: Dictionary = Space.build(self, world, rng, SPAWN, ARENA)
	rocks = env.rocks
	dust_mat = env.dust

	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.3
	cam.far = 60000.0
	add_child(cam)
	cam.current = true

	sfx = SfxS.new()
	add_child(sfx)
	robot = RobotS.new()
	add_child(robot)
	fx = FxS.new()
	fx.game = self
	world.add_child(fx)
	combat = CombatS.new()
	combat.game = self
	world.add_child(combat)
	player = PlayerS.new()
	player.game = self
	world.add_child(player)
	player.setup()

	# the imported font resource: an export packs that, not the raw .ttf. The web build has no
	# system fallback fonts, so use only characters Montserrat has (no θ, ○, ●)
	var body: FontFile = load("res://fonts/Montserrat.ttf")
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var display := FontVariation.new()      # thin, widely spaced titles
	display.base_font = body
	display.variation_opentype = {wght: 300}
	display.spacing_glyph = 14
	var title_b := FontVariation.new()
	title_b.base_font = body
	title_b.variation_opentype = {wght: 700}
	title_b.spacing_glyph = 1
	var semi := FontVariation.new()
	semi.base_font = body
	semi.variation_opentype = {wght: 600}
	var body_r := FontVariation.new()
	body_r.base_font = body
	body_r.variation_opentype = {wght: 400}

	var vl := CanvasLayer.new()
	vl.layer = 0
	add_child(vl)
	vignette = ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE
	vignette.material = vm
	vl.add_child(vignette)

	var hl := CanvasLayer.new()
	hl.layer = 1
	add_child(hl)
	hud = HudS.new()
	hud.game = self
	hud.font = semi
	hud.font_b = title_b
	hl.add_child(hud)
	var ml := CanvasLayer.new()
	ml.layer = 2
	add_child(ml)
	menu = MenuS.new()
	menu.game = self
	menu.f_title = display
	menu.f_body = body_r
	menu.f_semi = semi
	menu.f_hud = title_b
	ml.add_child(menu)

	_showcase()
	apply_display()
	to_menu()
	if shot_state == "play" or shot_state == "end":
		launch()
	elif shot_state == "calib":
		begin_calibration()


# ---------------- settings, input ----------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot_path = a.substr(5)
		elif a.begins_with("frames="):
			for f in a.substr(7).split(","):
				shot_frames.append(int(f))
		elif a.begins_with("state="):
			shot_state = a.substr(6)
		elif a.begins_with("cam="):
			var c := a.substr(4).split(",")
			debug_cam = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a.begins_with("input="):
			settings_override = a.substr(6)
		elif a == "auto":
			auto = true
		elif a.begins_with("seed="):
			rng.seed = int(a.substr(5))


func _input_map() -> void:
	var keys := {"thr_up": [KEY_W], "thr_down": [KEY_S], "strafe_l": [KEY_A], "strafe_r": [KEY_D],
		"up": [KEY_SPACE], "down": [KEY_CTRL], "roll_l": [KEY_Q], "roll_r": [KEY_E], "boost": [KEY_SHIFT]}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				if settings.has(k):
					settings[k] = d[k]
	settings.minutes = int(settings.minutes)
	settings.difficulty = clampi(int(settings.difficulty), 0, 2)
	settings.screen = int(settings.screen)
	settings.fullscreen = bool(settings.fullscreen)


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and state == State.PLAY and settings.input == "mouse":
		mouse_aim += e.relative * Vector2(1, -1) * MOUSE_SENS
		if mouse_aim.length() > 1.0:
			mouse_aim = mouse_aim.normalized()
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: int = e.physical_keycode
	if k == KEY_F11:
		set_display(int(settings.screen), not settings.fullscreen)
		return
	if k == KEY_F10:
		set_display((DisplayServer.window_get_current_screen() + 1) % DisplayServer.get_screen_count(),
			settings.fullscreen)
		return
	match state:
		State.MENU:
			if k == KEY_ENTER or k == KEY_KP_ENTER:
				launch()
			elif k == KEY_ESCAPE:
				leave()
			elif k == KEY_LEFT:
				menu._step_time(-1)
			elif k == KEY_RIGHT:
				menu._step_time(1)
		State.CALIB:
			if k == KEY_ESCAPE:
				end_calibration()
		State.PLAY:
			if k == KEY_ESCAPE or k == KEY_P or (k == KEY_SPACE and settings.input == "robot"):
				pause_game("PAUSED")
		State.PAUSE:
			if k == KEY_ESCAPE or k == KEY_P or k == KEY_SPACE or k == KEY_ENTER:
				resume()
		State.END:
			if k == KEY_ENTER or k == KEY_KP_ENTER:
				launch()
			elif k == KEY_ESCAPE:
				to_menu()


# ---------------- display ----------------

func screen_count() -> int:
	return DisplayServer.get_screen_count()


## Puts the game on monitor `screen` (-1 = where it is now), full screen or in a window.
func set_display(screen: int, fullscreen: bool) -> void:
	settings.screen = screen
	settings.fullscreen = fullscreen
	save_settings()
	apply_display()
	menu.refresh()


## Quit (desktop) or hand back to the MARS app (web).
func leave() -> void:
	if web:
		_post({"type": "exit"})
	else:
		get_tree().quit()


## A message to the MARS app (web build only).
func _post(msg: Dictionary) -> void:
	if web:
		JavaScriptBridge.eval("window.MarsGame && window.MarsGame.postMessage(%s)" % JSON.stringify(JSON.stringify(msg)))


func apply_display() -> void:
	if web or DisplayServer.get_name() == "headless" or shot_path != "":
		return      # test runs keep the window the command line asked for
	var n := screen_count()
	var scr: int = int(settings.screen)
	if scr < 0 or scr >= n:
		scr = DisplayServer.window_get_current_screen()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var r := DisplayServer.screen_get_usable_rect(scr)
	var size := Vector2i(Vector2(r.size) * 0.8)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(r.position + (r.size - size) / 2)
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Clicking another window (e.g. the MARS GUI) frees the mouse. In mouse mode the
## game also pauses; with the robot it keeps running so the GUI can be used during play.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAY:
		if settings.input == "mouse":
			pause_game("PAUSED")
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------- screens ----------------

func to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_battle()
	_showcase()
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show_screen("start")


func launch() -> void:
	if settings.input == "robot" and not robot.cal.done and shot_state == "":
		launch_after_cal = true
		begin_calibration()
		return
	start_session()


func begin_calibration() -> void:
	state = State.CALIB
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	robot.cancel_calibration()
	menu.show_screen("calib")


func end_calibration() -> void:
	robot.cancel_calibration()
	if launch_after_cal and robot.cal.done:
		launch_after_cal = false
		start_session()
	else:
		launch_after_cal = false
		state = State.MENU
		menu.show_screen("start")


func pause_game(title: String) -> void:
	if state != State.PLAY:
		return
	state = State.PAUSE
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.pause_title.text = title
	menu.show_screen("pause")


func resume() -> void:
	if state != State.PAUSE:
		return
	get_tree().paused = false
	state = State.PLAY
	link_lost_t = 0.0
	if settings.input == "mouse":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu.show_screen("")


# ---------------- session ----------------

func start_session() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	diff = DIFF[int(settings.difficulty)]
	_clear_battle()
	session_left = float(settings.minutes) * 60.0
	score = 0
	wave = 1
	end_slow = 0.0
	respawn_t = 0.0
	next_frigate_t = -1.0
	link_lost_t = 0.0
	trace.clear()
	trace_t = 0.0
	stats = {"shots": 0, "hits": 0, "missiles": 0, "missile_hits": 0, "damage_taken": 0.0, "kills_f": 0,
		"kills_t": 0, "cores": 0, "frigates": 0, "deaths": 0, "on_target": 0.0, "t1_min": 999.0,
		"t1_max": -999.0, "r_min": 1e9, "r_max": -1e9, "path_mm": 0.0, "time": 0.0}
	last_cuff = Vector3.INF
	player.reset(SPAWN, Vector3.ZERO, true)
	cam_basis = player.global_basis
	mouse_aim = Vector2.ZERO
	_spawn_frigate(false)
	for i in diff.fighters:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		_spawn_fighter(d * rng.randf_range(350.0, 650.0), false)
	spawn_t = 6.0
	state = State.PLAY
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if settings.input == "mouse" and shot_state == "" else Input.MOUSE_MODE_VISIBLE
	menu.show_screen("")
	hud.banner("FRIGATE STRIKE", "DESTROY THE SIX DEFENCE TURRETS", hud.GOLD, 4.0)


func finish_session() -> void:
	if state != State.PLAY and state != State.PAUSE:
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	var saved := _write_logs() if shot_state == "" else ""   # screenshot test runs leave no logs
	var acc: float = 100.0 * stats.hits / maxf(1.0, stats.shots)
	var tot := int(stats.on_target)
	var tiles := [["SCORE", hud._thousands(score)], ["FIGHTERS", stats.kills_f], ["TURRETS", stats.kills_t],
		["FRIGATES", stats.frigates], ["ACCURACY", "%d%%" % int(acc)],
		["MISSILE HITS", "%d / %d" % [stats.missile_hits, stats.missiles]],
		["TIME ON TARGET", "%d:%02d" % [tot / 60, tot % 60]], ["DEATHS", stats.deaths]]
	if settings.input == "robot" and stats.t1_max > -999.0:
		tiles += [["ARM LIFT", "%.0f° – %.0f°" % [stats.t1_min, stats.t1_max]],
			["REACH RANGE", "%.0f mm" % maxf(0.0, stats.r_max - stats.r_min)],
			["HAND PATH", "%.1f m" % (stats.path_mm / 1000.0)]]
	var played := int(stats.time)
	var sub := "%d:%02d PLAYED  ·  %s  ·  %s" % [played / 60, played % 60, diff.name,
		"ROBOT ARM" if settings.input == "robot" else "MOUSE + KEYS"]
	_clear_battle()
	_showcase()
	state = State.END
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show_results("SESSION COMPLETE", sub, tiles, ("Saved to " + saved) if saved != "" else "")


func _clear_battle() -> void:
	combat.clear()
	for f in fighters:
		if is_instance_valid(f):
			f.queue_free()
	fighters.clear()
	if frigate and is_instance_valid(frigate):
		frigate.queue_free()
	frigate = null
	hostiles.clear()
	for c in world.get_children():
		if c.get_script() == preload("res://scripts/missile.gd"):
			c.queue_free()


func _spawn_frigate(warp: bool) -> void:
	frigate = FrigateS.new()
	world.add_child(frigate)
	frigate.build(self)
	var yaw := PI / 2.0 if wave == 1 else rng.randf_range(0, TAU)
	var b := Basis(Vector3.UP, yaw)
	frigate.global_transform = Transform3D(b, Vector3.ZERO)
	hostiles += frigate.targets()
	if warp:
		frigate.global_position = b.z * 1600.0
		var tw: Tween = frigate.create_tween()
		tw.tween_property(frigate, "global_position", Vector3.ZERO, 1.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		fx.warp(Vector3.ZERO, 3.0)


func _spawn_fighter(pos: Vector3, warp := true) -> void:
	var f := FighterS.new()
	world.add_child(f)
	f.setup(self, pos, player.global_position)
	fighters.append(f)
	hostiles.append(f)
	if warp:
		fx.warp(pos, 0.6)


func _fighter_spawn_point() -> Vector3:
	for i in 20:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 0.35), rng.randf_range(-1, 1)).normalized()
		var p: Vector3 = player.global_position + d * rng.randf_range(1300.0, 1800.0)
		if p.length() < ARENA - 300.0 and not _near_rock(p, 40.0):
			return p
	return Vector3(rng.randf_range(-400, 400), 200, rng.randf_range(-400, 400))


# ---------------- callbacks from ships ----------------

func on_shot_hit() -> void:
	stats.hits += 1
	hud.hitmark = 1.0


func on_kill(h) -> void:
	hostiles.erase(h)
	hud.hitmark = 1.0
	match h.kind:
		"FIGHTER":
			fighters.erase(h)
			score += 100
			stats.kills_f += 1
			hud.message("FIGHTER DESTROYED  +100")
		"TURRET":
			score += 250
			stats.kills_t += 1
		_:
			score += 1000
			stats.cores += 1
			hud.message("REACTOR CORE DESTROYED  +1000")


func on_player_dead() -> void:
	stats.deaths += 1
	score = maxi(0, score - 200)
	respawn_t = 3.0


func on_frigate_destroyed() -> void:
	for h in hostiles.duplicate():
		if h.kind != "FIGHTER":
			hostiles.erase(h)
	frigate = null
	score += 5000
	stats.frigates += 1
	wave += 1
	hud.banner("FRIGATE DESTROYED", "+5000  ·  HULL REPAIRED  ·  MISSILES RESTOCKED", hud.GOLD, 4.0)
	player.hull = minf(100.0, player.hull + 40.0)
	player.missiles = mini(player.MAX_MISSILES, player.missiles + 6)
	next_frigate_t = 9.0


func objective():
	if frigate == null or not frigate.alive or frigate.dying:
		return null
	if not frigate.shield_up:
		return frigate.core
	var best = null
	var bd := INF
	for tu in frigate.turrets:
		if tu.alive:
			var d: float = tu.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = tu
	return best


func objective_text() -> String:
	if frigate == null:
		return "ENEMY FRIGATE INBOUND" if next_frigate_t > 0.0 else ""
	if frigate.dying:
		return "FRIGATE GOING DOWN"
	if frigate.shield_up:
		return "DESTROY THE DEFENCE TURRETS   %d / 6" % (6 - frigate.turrets_left())
	return "DESTROY THE REACTOR CORE"


# ---------------- world queries ----------------

func _cells_around(p: Vector3) -> Array:
	var out: Array = []
	var g: float = Space.GRID
	var c := Vector3i(floori(p.x / g), floori(p.y / g), floori(p.z / g))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := c + Vector3i(dx, dy, dz)
				if rocks.grid.has(key):
					out.append(rocks.grid[key])
	return out


func rock_seg_hit(a: Vector3, b: Vector3) -> bool:
	for cell in _cells_around(b):
		for i in cell:
			if CombatS.seg_sphere(a, b, rocks.pos[i], rocks.rad[i]):
				return true
	return false


func _near_rock(p: Vector3, margin: float) -> bool:
	for cell in _cells_around(p):
		for i in cell:
			if p.distance_to(rocks.pos[i]) < rocks.rad[i] + margin:
				return true
	return false


## Steering push away from the frigate and from rocks ahead (for the AI).
func avoid_vector(pos: Vector3, fwd: Vector3, look: float) -> Vector3:
	var acc := Vector3.ZERO
	if frigate and frigate.alive:
		var d: Vector3 = pos - frigate.global_position
		var l := d.length()
		if l < 380.0:
			acc += d.normalized() * (380.0 - l) / 380.0 * 2.0
	var probe := pos + fwd * look
	for cell in _cells_around(probe):
		for i in cell:
			var d: Vector3 = probe - rocks.pos[i]
			if d.length() < rocks.rad[i] + 40.0:
				acc += d.normalized() * 1.5
	return acc


# ---------------- frame ----------------

func _process(dt: float) -> void:
	frame += 1
	match state:
		State.MENU, State.CALIB, State.END:
			_showcase_cam(dt)
		State.PLAY:
			_play(dt)
	var v: Vector3 = player.vel if state == State.PLAY else -player.global_basis.z * 35.0
	var vs: Vector2 = get_viewport().get_visible_rect().size
	vignette.size = vs
	vignette.material.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	var turn := 0.0
	if state == State.PLAY and player.alive:
		turn = clampf(absf(player.yaw_rate) / player.RATE_YAW + absf(player.pitch_rate) / player.RATE_PITCH * 0.6, 0.0, 1.0)
	vig = lerpf(vig, 0.26 + 0.34 * turn, 1.0 - exp(-4.0 * dt))
	vignette.material.set_shader_parameter("strength", vig)
	dust_mat.set_shader_parameter("cam_pos", cam.global_position)
	dust_mat.set_shader_parameter("vel", v)
	sfx.set_engine(state == State.PLAY and player.alive, player.speed / player.SPEED_MAX, player.boosting)
	if shot_path != "" and not shot_frames.is_empty() and frame >= int(shot_frames[0]):
		shot_frames.pop_front()
		var path := shot_path.replace(".png", "_%d.png" % frame)
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(path)
		if shot_state == "end" and state == State.PLAY:
			finish_session()
		if shot_frames.is_empty():
			get_tree().quit()


func _play(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	stats.time += dt
	if end_slow > 0.0:
		end_slow -= real_dt
		if end_slow <= 0.0:
			finish_session()
			return
	else:
		session_left -= dt
		if session_left <= 0.0:
			session_left = 0.0
			end_slow = 1.8
			Engine.time_scale = 0.35
			hud.banner("TIME", "SESSION COMPLETE", hud.GOLD, 2.0)

	# input
	var aim := Vector2.ZERO
	var roll := 0.0
	var thr := 0.0
	var strafe := Vector2.ZERO
	var boost := false
	if settings.input == "robot":
		aim = robot.aim
		if not robot.enc_ok():
			aim.x += Input.get_axis("strafe_l", "strafe_r")
		player.throttle = lerpf(player.throttle, 0.35 + 0.65 * robot.reach, 1.0 - exp(-2.0 * dt))
		if not robot.live() and not auto:
			link_lost_t += dt
			if link_lost_t > 1.0:
				pause_game("ROBOT LINK LOST")
				return
		else:
			link_lost_t = 0.0
	else:
		aim = mouse_aim
		roll = Input.get_axis("roll_l", "roll_r")
		thr = Input.get_axis("thr_down", "thr_up")
		strafe = Vector2(Input.get_axis("strafe_l", "strafe_r"), Input.get_axis("down", "up"))
		boost = Input.is_action_pressed("boost")
	if auto:
		aim = _autopilot()

	# keep inside the arena
	var dist: float = player.global_position.length()
	out_of_bounds = dist > ARENA
	if dist > ARENA + 200.0:
		var home: Vector3 = player.global_basis.inverse() * (-player.global_position.normalized())
		aim = aim.lerp(Vector2(home.x, home.y).normalized() if home.z < 0.0 or absf(home.x) > 0.1 else Vector2(1, 0), 0.8)

	if player.alive:
		player.fly(dt, aim, roll, thr, strafe, boost)
		# shooting is automatic: guns on a target in the sights, a missile once it locks
		if player.wants_fire():
			player.fire_guns()
		if player.locked:
			player.fire_missile()
		_collide_player(dt)
		if player.target and player.target_ang < deg_to_rad(5.0):
			stats.on_target += dt
	else:
		respawn_t -= dt
		if respawn_t <= 0.0:
			player.reset(SPAWN, Vector3.ZERO, false)
			cam_basis = player.global_basis
			mouse_aim = Vector2.ZERO
	_chase_cam(dt)
	if debug_cam != Vector3.INF:
		cam.global_position = debug_cam
		cam.global_basis = Basis.looking_at(-debug_cam.normalized(), Vector3.UP)

	# reinforcements
	spawn_t -= dt
	var want: int = int(diff.fighters) + wave - 1
	if fighters.size() < want and spawn_t <= 0.0:
		_spawn_fighter(_fighter_spawn_point())
		spawn_t = 5.0
	if next_frigate_t > 0.0:
		next_frigate_t -= dt
		if next_frigate_t <= 0.0:
			_spawn_frigate(true)
			hud.banner("ENEMY FRIGATE", "WAVE %d  ·  DESTROY THE DEFENCE TURRETS" % wave, hud.ENEMY, 3.5)

	_record(dt)


func _collide_player(dt: float) -> void:
	bump_cd -= dt
	var p: Vector3 = player.global_position
	for cell in _cells_around(p):
		for i in cell:
			var d: Vector3 = p - rocks.pos[i]
			var r: float = rocks.rad[i] + player.radius
			if d.length() < r:
				var n := d.normalized()
				player.global_position = rocks.pos[i] + n * r
				player.vel = player.vel.bounce(n) * 0.5
				_bump(rocks.pos[i] + n * rocks.rad[i])
				return
	if frigate and frigate.alive:
		var push: Vector3 = frigate.push_out(p, player.radius)
		if push != Vector3.ZERO:
			player.global_position += push
			player.vel = player.vel.bounce(push.normalized()) * 0.5
			_bump(p)


func _bump(at: Vector3) -> void:
	fx.sparks(at)
	if bump_cd <= 0.0:
		bump_cd = 0.6
		player.damage(clampf(player.speed * 0.12, 6.0, 30.0), at)
		player.speed *= 0.6


## Chase camera: follows yaw and most of the pitch with a soft lag, never rolls
## (world up is always up), and keeps the field of view almost constant.
func _chase_cam(dt: float) -> void:
	var want := Basis.from_euler(Vector3(player.pitch * 0.8, player.yaw, 0.0))
	cam_basis = cam_basis.slerp(want, 1.0 - exp(-4.5 * dt)).orthonormalized()
	var boost_k: float = 1.0 if player.boosting else 0.0
	cam.fov = lerpf(cam.fov, 70.0 + 3.0 * boost_k, 1.0 - exp(-2.0 * dt))
	cam.global_position = player.global_position + cam_basis * Vector3(0, 7.0, 23.0)
	var look: Vector3 = player.global_position + cam_basis * Vector3(0, 2.5, -45.0)
	cam.global_basis = Basis.looking_at((look - cam.global_position).normalized(), Vector3.UP)


## Showcase pose for the menus: ship flying left-away, ringed planet behind.
func _showcase() -> void:
	player.reset(SPAWN + Vector3(0, 80, 400), SPAWN + Vector3(0, 80, 400) + Vector3(-0.95, -0.05, -0.45), true)
	player.visible = true
	player.speed = 70.0
	for fl in player.flames:
		fl.visible = false      # the plume blooms into blobs; the glowing nozzles show thrust
		fl.set_instance_shader_parameter("throttle", 1.0)
	cam.fov = 50.0


func _showcase_cam(dt: float) -> void:
	menu_t += dt
	var p: Vector3 = SPAWN + Vector3(0, 80, 400)
	var bob := Vector3(0, sin(menu_t * 0.7) * 0.4, 0)
	player.global_position = p + bob
	var f := Vector3(-0.95, -0.05, -0.45).normalized()
	player.global_basis = Basis.looking_at(f, Vector3.UP) * Basis(Vector3(0, 0, 1), 0.12 + sin(menu_t * 0.5) * 0.05)
	var orbit := 0.12 * sin(menu_t * 0.15)
	var off := Vector3(13.0, 3.2, 18.0).rotated(Vector3.UP, orbit)
	cam.global_position = p + off
	var look := p + Vector3(-9.5, -1.0, -5.0)
	cam.global_basis = Basis.looking_at((look - cam.global_position).normalized(), Vector3.UP)


func _autopilot() -> Vector2:
	var tgt = objective()
	var best := INF
	for f in fighters:
		var d: float = f.global_position.distance_to(player.global_position)
		if d < best and d < 900.0:
			best = d
			tgt = f
	if tgt == null:
		return Vector2.ZERO
	var lv: Vector3 = player.global_basis.inverse() * (tgt.global_position - player.global_position).normalized()
	var a := Vector2(lv.x, lv.y) * 3.0
	if lv.z > 0.0:
		a = Vector2(signf(lv.x) if absf(lv.x) > 0.05 else 1.0, 0.0)
	return a.limit_length(1.0)


func _record(dt: float) -> void:
	if settings.input == "robot" and robot.live():
		var th1: float = robot.raw.y
		stats.t1_min = minf(stats.t1_min, th1)
		stats.t1_max = maxf(stats.t1_max, th1)
		stats.r_min = minf(stats.r_min, robot.raw.z)
		stats.r_max = maxf(stats.r_max, robot.raw.z)
		var c = robot.last.get("cuff_mm", [0, 0, 0])
		var cv := Vector3(float(c[0]), float(c[1]), float(c[2]))
		if last_cuff != Vector3.INF:
			stats.path_mm += cv.distance_to(last_cuff)
		last_cuff = cv
	trace_t -= dt
	if trace_t <= 0.0:
		trace_t = 0.1
		var l: Dictionary = robot.last if robot.live() else {}
		var c = l.get("cuff_mm", [0, 0, 0])
		trace.append([snappedf(stats.time, 0.01), l.get("th1", ""), l.get("th2", ""), l.get("th3", ""),
			l.get("th4", ""), c[0], c[1], c[2], snappedf(player.aim_now.x, 0.001), snappedf(player.aim_now.y, 0.001),
			score, int(player.hull), int(player.shield)])


const SUMMARY_HEADER := "stamp,minutes_set,played_s,input,difficulty,score,fighters,turrets,frigates,shots,hits," + \
	"missiles,missile_hits,on_target_s,deaths,t1_min,t1_max,reach_range_mm,hand_path_mm"
const TRACE_HEADER := "t_s,th1,th2,th3,th4,cuff_x,cuff_y,cuff_z,aim_x,aim_y,score,hull,shield"


func _write_logs() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var arm: bool = settings.input == "robot" and stats.t1_max > -999.0
	var row := ",".join(PackedStringArray([stamp, str(settings.minutes), str(int(stats.time)), settings.input,
		diff.name, str(score), str(stats.kills_f), str(stats.kills_t), str(stats.frigates), str(stats.shots),
		str(stats.hits), str(stats.missiles), str(stats.missile_hits), str(snappedf(stats.on_target, 0.1)),
		str(stats.deaths), str(snappedf(stats.t1_min, 0.1)) if arm else "", str(snappedf(stats.t1_max, 0.1)) if arm else "",
		str(int(stats.r_max - stats.r_min)) if arm else "", str(int(stats.path_mm)) if arm else ""]))
	var lines := PackedStringArray([TRACE_HEADER])
	for r in trace:
		var cells := PackedStringArray()
		for v in r:
			cells.append(str(v))
		lines.append(",".join(cells))
	if web:
		# the app saves both files on the tablet (Android/data/.../MARS/game/)
		_post({"type": "session", "stamp": stamp, "summary_header": SUMMARY_HEADER, "summary_row": row,
			"trace": "\n".join(lines) + "\n"})
		return "the tablet: MARS/game/session_%s.csv" % stamp
	var base := "user://logs" if OS.has_feature("template") else "res://logs"
	var dir := ProjectSettings.globalize_path(base)
	DirAccess.make_dir_recursive_absolute(dir)
	# .gdignore: Godot would otherwise import these CSVs as translations and pack them into exports
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE)
	var summary := dir.path_join("sessions.csv")
	var new_file := not FileAccess.file_exists(summary)
	var f := FileAccess.open(summary, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if f == null:
		return ""
	f.seek_end()
	if new_file:
		f.store_line(SUMMARY_HEADER)
	f.store_line(row)
	f.close()
	var tr := FileAccess.open(dir.path_join("session_%s.csv" % stamp), FileAccess.WRITE)
	if tr:
		for l in lines:
			tr.store_line(l)
		tr.close()
	return "logs/session_%s.csv" % stamp
