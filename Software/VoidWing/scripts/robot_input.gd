extends Node
## Arm input. Desktop: from the MARS GUI, UDP JSON on 127.0.0.1:5005, 50 Hz.
## Tablet (web build in the MARS app): the app sets window.marsInput (same JSON + "seq") ~25 Hz.
##   {"t", "th1".."th4" (deg), "cuff_mm": [x, y, z], "mode", "enc_ok"}
## Channels (see CODE/MARS_GUI/kinematics.py):
##   up / down    = th1, the lever angle (90 deg = arm horizontal)
##   left / right = cuff z, along the motor axis (sideways sweep of the hand)
##   reach        = cuff distance from the motor axis
## Steering uses the hand position, so it works even if the elbow and cuff
## joints move together. Each player calibrates once: neutral pose, then range.

const PORT := 5005
const CAL_PATH := "user://arm_cal.json"
const NEUTRAL_S := 3.0
const RANGE_S := 12.0
const DEAD := 0.08

var udp := PacketPeerUDP.new()
var bound := false
var last := {}
var last_ms := -100000
var raw := Vector3(0.0, 90.0, 0.0)     # x = sideways mm, y = th1 deg, z = reach mm
var aim := Vector2.ZERO
var reach := 0.0
var cal := {"x_c": 0.0, "x_lo": -150.0, "x_hi": 150.0, "y_c": 90.0, "y_lo": 70.0, "y_hi": 110.0,
	"r_lo": 450.0, "r_hi": 750.0, "inv_x": false, "inv_y": false, "done": false}
# calibration: 0 idle, 1 neutral, 2 range, 3 finished
var cal_state := 0
var cal_t := 0.0
var acc := Vector3.ZERO
var acc_n := 0
var mn := Vector3.ZERO
var mx := Vector3.ZERO


var web := OS.has_feature("web")
var _seq := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not web:
		bound = udp.bind(PORT, "127.0.0.1") == OK
	_load()


func live() -> bool:
	return Time.get_ticks_msec() - last_ms < 700


func enc_ok() -> bool:
	return bool(last.get("enc_ok", false))


func mode() -> String:
	return str(last.get("mode", "--"))


func _process(dt: float) -> void:
	if web:
		var js = JavaScriptBridge.eval("window.marsInput ? JSON.stringify(window.marsInput) : ''", true)
		if typeof(js) == TYPE_STRING and js != "":
			var d = JSON.parse_string(js)
			if typeof(d) == TYPE_DICTIONARY and int(d.get("seq", 0)) != _seq:
				_seq = int(d.get("seq", 0))
				_take(d)
	else:
		while udp.get_available_packet_count() > 0:
			_take(JSON.parse_string(udp.get_packet().get_string_from_utf8()))
	var tx := _norm(raw.x, cal.x_c, cal.x_lo, cal.x_hi) * (-1.0 if cal.inv_x else 1.0)
	var ty := _norm(raw.y, cal.y_c, cal.y_lo, cal.y_hi) * (-1.0 if cal.inv_y else 1.0)
	if not enc_ok():
		tx = 0.0            # without encoders only the lever angle is real
	aim = aim.lerp(Vector2(tx, ty), 1.0 - exp(-12.0 * dt))
	reach = clampf(inverse_lerp(cal.r_lo, cal.r_hi, raw.z), 0.0, 1.0) if enc_ok() else 0.5
	_calibrate(dt)


func _take(d) -> void:
	if typeof(d) != TYPE_DICTIONARY or not d.has("th1"):
		return
	last = d
	last_ms = Time.get_ticks_msec()
	var c = d.get("cuff_mm", [0.0, 0.0, 0.0])
	if typeof(c) == TYPE_ARRAY and c.size() == 3:
		raw = Vector3(float(c[2]), float(d.th1), Vector2(float(c[0]), float(c[1])).length())
	else:
		raw.y = float(d.th1)


func _norm(v: float, c: float, lo: float, hi: float) -> float:
	var n := (v - c) / maxf(hi - c, 1e-3) if v >= c else (v - c) / maxf(c - lo, 1e-3)
	n = signf(n) * maxf(absf(n) - DEAD, 0.0) / (1.0 - DEAD)
	return clampf(n, -1.0, 1.0)


# ---------------- calibration ----------------

func begin_calibration() -> void:
	cal_state = 1
	cal_t = 0.0
	acc = Vector3.ZERO
	acc_n = 0


func cancel_calibration() -> void:
	cal_state = 0


func cal_progress() -> float:
	if cal_state == 1:
		return cal_t / NEUTRAL_S
	if cal_state == 2:
		return cal_t / RANGE_S
	return 1.0 if cal_state == 3 else 0.0


func _calibrate(dt: float) -> void:
	if cal_state == 1:
		if live():
			cal_t += dt
			acc += raw
			acc_n += 1
		if cal_t >= NEUTRAL_S and acc_n > 0:
			var c := acc / acc_n
			cal.x_c = c.x
			cal.y_c = c.y
			mn = c
			mx = c
			cal_state = 2
			cal_t = 0.0
	elif cal_state == 2:
		if live():
			cal_t += dt
			mn = Vector3(minf(mn.x, raw.x), minf(mn.y, raw.y), minf(mn.z, raw.z))
			mx = Vector3(maxf(mx.x, raw.x), maxf(mx.y, raw.y), maxf(mx.z, raw.z))
		if cal_t >= RANGE_S:
			# keep a minimum range so a tiny movement does not become full deflection
			cal.x_lo = minf(mn.x, cal.x_c - 40.0)
			cal.x_hi = maxf(mx.x, cal.x_c + 40.0)
			cal.y_lo = minf(mn.y, cal.y_c - 5.0)
			cal.y_hi = maxf(mx.y, cal.y_c + 5.0)
			cal.r_lo = mn.z
			cal.r_hi = maxf(mx.z, mn.z + 40.0)
			cal.done = true
			cal_state = 3
			save()


func save() -> void:
	var f := FileAccess.open(CAL_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cal))


func _load() -> void:
	if not FileAccess.file_exists(CAL_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(CAL_PATH))
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			if cal.has(k):
				cal[k] = d[k]
