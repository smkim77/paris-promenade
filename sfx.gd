extends Node
## Placeholder sound effects. The web version synthesises everything live with Web Audio;
## here each effect is rendered once at start-up into a short PCM clip and played from a
## small pool of players. The hard-mode riot piece is rendered the same way, on a worker
## thread, into one seamless loop. The normal-mode waltz and the ambience are not ported yet.

const RATE := 22050

var clips := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var muted := false
var music: AudioStreamPlayer
var riot: AudioStreamWAV
var want_music := false


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	music.volume_db = -5.0
	add_child(music)
	_build()
	WorkerThreadPool.add_task(_build_riot)


func play(sound: String) -> void:
	if muted or not clips.has(sound):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = clips[sound]
	p.play()


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	if muted:
		for p in players:
			p.stop()
	return muted


func music_play() -> void:
	want_music = true
	music.stream_paused = false
	if riot:
		music.stream = riot
		music.play()


func music_stop() -> void:
	want_music = false
	music.stop()


func music_pause(on: bool) -> void:
	music.stream_paused = on


func _riot_ready(w: AudioStreamWAV) -> void:
	riot = w
	if want_music:
		music_play()


func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## riot: D minor, 4/4 at a running pace. Layers build up over 16 bars and drop back on the loop:
## bass ostinato and kick → snare and a dark chord → hi-hats and a creeping half-step motif → sirens
func _build_riot() -> void:
	var e := 0.21
	var steps := 128
	var b := _buf(steps * e + 4.0)
	var roots := [38, 38, 34, 33]
	var chords := [[62, 65, 69], [62, 65, 69], [58, 62, 65], [57, 61, 64]]
	var ost := [0, 0, 12, 0, 3, 0, 1, 0]
	for bar in 16:
		var s0 := bar * 8
		var root: int = roots[bar % 4]
		for k in 8:      # the growling bass: two buzzing saws through a closing lowpass
			var f := _hz(root + ost[k])
			var g := 0.11 if k % 4 == 0 else 0.08
			_voice(b, (s0 + k) * e, e * 0.9, f, f, "saw", g, 0.006, 700.0, 220.0)
			_voice(b, (s0 + k) * e, e * 0.9, f * 1.0052, f * 1.0052, "saw", g, 0.006, 700.0, 220.0)
		for k in [0, 3, 4]:
			_voice(b, (s0 + k) * e, 0.28, 130.0, 42.0, "sine", 0.5, 0.003)
		if bar >= 4:
			for k in [2, 6]:
				_snare(b, (s0 + k) * e, 0.22)
			for m in chords[bar % 4]:
				_voice(b, s0 * e, e * 8, _hz(m), _hz(m), "saw", 0.03, 0.0, 900.0, 900.0, true)
		if bar % 8 == 7:
			for k in [4, 5, 6, 7]:
				_snare(b, (s0 + k) * e, 0.16)
				_snare(b, (s0 + k + 0.5) * e, 0.12)
		if bar >= 8:
			for k in range(1, 8, 2):
				_hpnoise(b, (s0 + k) * e, 0.04, 0.08, 7000.0)
		if bar >= 12 and bar % 2 == 0:      # a French police "pin-pon" in the distance
			_voice(b, s0 * e, e * 16, 435.0, 435.0, "tri", 0.025, 0.0, 0.0, 0.0, true, 0.0, 580.0)
	var motif := [[74, 2], [73, 2], [74, 2], [77, 2], [76, 4], [69, 4], [74, 2], [73, 2], [74, 2], [82, 2], [81, 8]]
	for start in [8, 12]:
		var st: int = start * 8
		for nt in motif:
			_voice(b, st * e, e * nt[1] * 0.95, _hz(nt[0]), _hz(nt[0]), "saw", 0.05, 0.06, 2500.0, 2500.0, false, 0.006)
			st += nt[1]
	# fold the tail back onto the start so the loop is seamless, then normalise
	var n := int(steps * e * RATE)
	for i in range(n, b.size()):
		b[i - n] += b[i]
	b.resize(n)
	var peak := 0.001
	for v in b:
		peak = maxf(peak, absf(v))
	for i in n:
		b[i] *= 0.6 / peak
	var w := _wav(b)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	call_deferred("_riot_ready", w)


## one note: an exponential glide f0 → f1, an optional lowpass sweeping cut0 → cut1, a
## plucked (attack + decay) or swelling envelope, vibrato, and for the siren a second pitch
## it alternates with every half second
func _voice(b: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, wave: String, gain: float,
		attack: float, cut0 := 0.0, cut1 := 0.0, swell := false, vib := 0.0, alt := 0.0) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var f := f0
	var fk := pow(f1 / f0, 1.0 / n)
	var c := cut0
	var ck := pow(cut1 / cut0, 1.0 / n) if cut0 > 0.0 else 1.0
	var ph := 0.0
	var y := 0.0
	var att := maxf(1.0, attack * RATE)
	var half := int(0.5 * RATE)
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		var u := float(i) / n
		var fi := f
		if alt > 0.0 and (i / half) % 2 == 1:
			fi = alt
		if vib > 0.0:
			fi *= 1.0 + vib * sin(TAU * 5.5 * i / RATE)
		ph += fi / RATE
		var fr := ph - floorf(ph)
		var s: float
		match wave:
			"saw": s = 2.0 * fr - 1.0
			"tri": s = 4.0 * absf(fr - 0.5) - 1.0
			_: s = sin(TAU * fr)
		if cut0 > 0.0:
			y += minf(1.0, TAU * c / RATE) * (s - y)
			s = y
			c *= ck
		var env: float
		if swell:
			env = u / 0.3 if u < 0.3 else (1.0 - u) / 0.7
		else:
			env = minf(1.0, i / att) * (1.0 - u) * sqrt(1.0 - u)
		b[j] += s * gain * env
		f *= fk


func _snare(b: PackedFloat32Array, t0: float, gain: float) -> void:
	_hpnoise(b, t0, 0.14, gain, 1400.0)
	_voice(b, t0, 0.08, 190.0, 190.0, "tri", gain * 0.5, 0.002)


## white noise minus its lowpassed part: a highpass
func _hpnoise(b: PackedFloat32Array, t0: float, dur: float, gain: float, cutoff: float) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var a := minf(1.0, TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		var w := randf() * 2.0 - 1.0
		y += a * (w - y)
		var u := float(i) / n
		b[j] += (w - y) * gain * (1.0 - u) * (1.0 - u)


func _build() -> void:
	var b := _buf(0.16)
	_tone(b, 320.0, 680.0, 0.16, "tri", 0.35)
	clips["jump"] = _wav(b)

	b = _buf(0.3)
	_noise(b, 0.25, 0.5, 600.0)
	_tone(b, 140.0, 60.0, 0.3, "sine", 0.45)
	clips["splat"] = _wav(b)

	b = _buf(0.4)
	_noise(b, 0.4, 0.35, 2500.0)
	_tone(b, 500.0, 300.0, 0.25, "sine", 0.15)
	clips["pee"] = _wav(b)

	b = _buf(0.5)
	_tone(b, 190.0, 210.0, 0.5, "saw", 0.12)
	_tone(b, 230.0, 200.0, 0.5, "saw", 0.08)
	clips["flies"] = _wav(b)

	b = _buf(0.25)
	_tone(b, 950.0, 280.0, 0.18, "square", 0.12)
	_noise(b, 0.22, 0.4, 1200.0, 0.02)
	clips["birdHit"] = _wav(b)

	b = _buf(0.9)
	_tone(b, 1500.0, 450.0, 0.9, "sine", 0.12)
	clips["drop"] = _wav(b)

	b = _buf(0.45)
	_tone(b, 400.0, 400.0, 0.2, "square", 0.12)
	_tone(b, 500.0, 500.0, 0.2, "square", 0.1)
	_tone(b, 400.0, 400.0, 0.22, "square", 0.12, 0.22)
	_tone(b, 500.0, 500.0, 0.22, "square", 0.1, 0.22)
	clips["honk"] = _wav(b)

	b = _buf(0.35)
	_tone(b, 150.0, 105.0, 0.35, "saw", 0.22)
	clips["grumble"] = _wav(b)

	b = _buf(0.35)
	_noise(b, 0.3, 0.55, 1800.0)
	_tone(b, 210.0, 80.0, 0.3, "tri", 0.3)
	clips["crash"] = _wav(b)

	b = _buf(0.5)
	_tone(b, 880.0, 880.0, 0.3, "sine", 0.2)
	_tone(b, 1320.0, 1320.0, 0.35, "sine", 0.16, 0.12)
	clips["plate"] = _wav(b)

	b = _buf(0.55)
	for k in 3:
		_tone(b, [523.0, 659.0, 784.0][k], [523.0, 659.0, 784.0][k], 0.25, "tri", 0.25, k * 0.11)
	clips["start"] = _wav(b)

	b = _buf(0.9)
	for k in 3:
		_tone(b, [392.0, 330.0, 262.0][k], [392.0, 330.0, 247.0][k], 0.35, "tri", 0.28, k * 0.22)
	clips["over"] = _wav(b)

	b = _buf(0.55)
	_noise(b, 0.45, 0.4, 4000.0)
	_tone(b, 1800.0, 2600.0, 0.4, "sine", 0.06)
	clips["spray"] = _wav(b)

	# hard mode
	b = _buf(0.45)
	_tone(b, 220.0, 520.0, 0.4, "sine", 0.1)
	_noise(b, 0.4, 0.25, 1500.0)
	clips["throw"] = _wav(b)

	b = _buf(0.5)
	_noise(b, 0.12, 0.6, 9000.0)
	for k in 5:
		_tone(b, 2400.0 + k * 700.0, 2300.0 + k * 650.0, 0.25, "sine", 0.08, 0.01 + k * 0.035)
	_noise(b, 0.35, 0.3, 700.0, 0.05)
	clips["shatter"] = _wav(b)

	b = _buf(0.7)
	_noise(b, 0.7, 0.5, 450.0)
	for k in 6:
		_noise(b, 0.03, 0.5, 6000.0, randf() * 0.6)    # crackle
	_tone(b, 300.0, 180.0, 0.25, "saw", 0.12)
	clips["burn"] = _wav(b)


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## a tone gliding from f0 to f1 with a quick attack and a falling envelope
func _tone(b: PackedFloat32Array, f0: float, f1: float, dur: float, wave := "sine", gain := 0.2, delay := 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		var t := float(i) / n
		ph += f0 * pow(f1 / f0, t) / RATE
		var f := fmod(ph, 1.0)
		var s: float
		match wave:
			"square": s = 1.0 if f < 0.5 else -1.0
			"saw": s = 2.0 * f - 1.0
			"tri": s = 4.0 * absf(f - 0.5) - 1.0
			_: s = sin(TAU * ph)
		b[j] += s * gain * minf(1.0, i / (0.005 * RATE)) * pow(1.0 - t, 2.0)


## white noise through a one-pole lowpass
func _noise(b: PackedFloat32Array, dur: float, gain: float, cutoff: float, delay := 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		y += a * (randf() * 2.0 - 1.0 - y)
		var t := float(i) / n
		b[j] += y * gain * minf(1.0, i / (0.004 * RATE)) * pow(1.0 - t, 1.5)


func _wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
