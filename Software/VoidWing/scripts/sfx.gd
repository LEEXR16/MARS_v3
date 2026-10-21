extends Node
## Sound: every effect is synthesised at start-up (no audio files), plus an
## engine hum and a slow ambient pad.

const RATE := 22050

var streams := {}
var players: Array = []
var engine: AudioStreamPlayer
var music: AudioStreamPlayer
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 7
	streams["laser"] = _laser(1700.0, 380.0, 0.14)
	streams["elaser"] = _laser(760.0, 220.0, 0.18)
	streams["boom"] = _boom(1.3, 1200.0)
	streams["boom_big"] = _boom(2.8, 700.0)
	streams["hit"] = _crunch(0.18)
	streams["shield"] = _zap(0.22)
	streams["missile"] = _whoosh(1.0)
	streams["beep"] = _tone(1150.0, 0.05, 0.22)
	streams["locked"] = _tone(1560.0, 0.28, 0.22)
	streams["click"] = _tone(2300.0, 0.025, 0.2)
	streams["alarm"] = _alarm()
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	engine = AudioStreamPlayer.new()
	engine.stream = _engine_loop()
	engine.volume_db = -60.0
	add_child(engine)
	music = AudioStreamPlayer.new()
	music.volume_db = -15.0
	add_child(music)
	engine.play()
	WorkerThreadPool.add_task(func(): _start_music.call_deferred(_pad()))


func _start_music(stream: AudioStreamWAV) -> void:
	music.stream = stream
	music.play()


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var best: AudioStreamPlayer = players[0]
	var best_pos := -1.0
	for p in players:
		if not p.playing:
			best = p
			break
		if p.get_playback_position() > best_pos:
			best_pos = p.get_playback_position()
			best = p
	best.stream = streams[name]
	best.volume_db = db
	best.pitch_scale = pitch
	best.play()


## Plays quieter with distance from the camera.
func play_at(name: String, pos: Vector3, db := 0.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(pos) if cam else 0.0
	var att := 20.0 * log(maxf(1.0, d / 90.0)) / log(10.0)
	if db - att < -38.0:
		return
	play(name, db - att, rng.randf_range(0.92, 1.08))


func set_engine(on: bool, speed01: float, boosting: bool) -> void:
	var target := -13.0 + speed01 * 5.0 + (3.0 if boosting else 0.0) if on else -60.0
	engine.volume_db = lerpf(engine.volume_db, target, 0.1)
	engine.pitch_scale = 0.75 + speed01 * 0.5 + (0.15 if boosting else 0.0)


# ---------------- synthesis ----------------

func _make(s: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _laser(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, pow(t, 0.6))
		ph += f / RATE
		var sq := 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		var sn := sin(ph * TAU)
		s[i] = (sn * 0.6 + sq * 0.25 + rng.randf_range(-0.1, 0.1)) * pow(1.0 - t, 2.0) * 0.55
	return _make(s)


func _boom(dur: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var c := cutoff * (1.0 - t * 0.85)
		var a := clampf(TAU * c / RATE, 0.0, 1.0)
		lp += (rng.randf_range(-1, 1) - lp) * a
		lp2 += (lp - lp2) * a
		var thump := sin(TAU * 48.0 * i / RATE * (1.0 - t * 0.5)) * exp(-t * 7.0)
		var env := exp(-t * 4.5) * minf(1.0, t * 200.0)
		s[i] = (lp2 * 2.2 + thump * 0.8) * env * 0.8
	return _make(s)


func _crunch(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var hold := 0.0
	for i in n:
		var t := float(i) / n
		if i % 6 == 0:
			hold = rng.randf_range(-1, 1)
		s[i] = (hold * 0.6 + sin(TAU * 90.0 * i / RATE) * 0.4) * pow(1.0 - t, 2.0) * 0.7
	return _make(s)


func _zap(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / n
		var f := 300.0 + 900.0 * t
		s[i] = sin(TAU * f * i / RATE + sin(TAU * 37.0 * i / RATE) * 3.0) * pow(1.0 - t, 1.5) * 0.4
	return _make(s)


func _whoosh(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var a := 0.05 + 0.25 * (1.0 - t)
		lp += (rng.randf_range(-1, 1) - lp) * a
		s[i] = lp * minf(1.0, t * 12.0) * pow(1.0 - t, 1.3) * 1.6
	return _make(s)


func _tone(f: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / n
		s[i] = sin(TAU * f * i / RATE) * vol * minf(1.0, t * 40.0) * minf(1.0, (1.0 - t) * 15.0)
	return _make(s)


func _alarm() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / n
		var f := 700.0 if t < 0.5 else 520.0
		s[i] = (1.0 if fmod(f * i / RATE, 1.0) < 0.5 else -1.0) * 0.12 * minf(1.0, (1.0 - t) * 10.0)
	return _make(s)


func _engine_loop() -> AudioStreamWAV:
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.03
		var saw := fmod(55.0 * t, 1.0) * 2.0 - 1.0
		s[i] = saw * 0.18 + sin(TAU * 110.0 * t) * 0.15 + lp * 0.9
	# blend the ends so the loop has no click
	var f := 400
	for i in f:
		var k := float(i) / f
		s[i] = s[i] * k + s[n - f + i] * (1.0 - k)
	return _make(s.slice(0, n - f), true)


## 16 s ambient pad: four slow chords.
func _pad() -> AudioStreamWAV:
	var rate := 8000
	var chords := [[110.0, 164.8, 220.0, 261.6], [87.3, 130.8, 174.6, 220.0],
		[98.0, 146.8, 196.0, 246.9], [82.4, 123.5, 164.8, 207.7]]
	var seg := 4 * rate
	var n := seg * 4
	var s := PackedFloat32Array()
	s.resize(n)
	for c in 4:
		for v in chords[c].size():
			var f: float = chords[c][v]
			for k in [0.997, 1.003]:
				var w: float = TAU * f * k / rate
				var start := c * seg - rate
				for i in range(seg + 2 * rate):
					var j := (start + i + n) % n
					var e := sin(PI * float(i) / (seg + 2 * rate))
					s[j] += sin(w * i) * e * e * 0.045
	return _make(s, true, rate)
