extends Node
## All sound is synthesised in code, like the web version's Web Audio:
## - effects: short clips, played from a pool of players
## - music: The Skaters' Waltz (normal mode) and the riot piece (hard mode), each one seamless loop
## - ambience: looping beds (spray, flies, traffic, café chatter, fire) whose volume and stereo
##   position follow what is near the walker (see game.gd update_ambience)
## The synthesis takes several seconds of GDScript, too slow to run at start-up in a browser
## (web builds have no worker threads), so tools/render_audio.gd renders everything once into
## audio/*.wav, which Godot imports QOA-compressed; at runtime this script only loads them.
## Re-run that tool after changing any sound.

const RATE := 22050
const MASTER := 1.2          # the web version's master gain (0.6), doubled so the game isn't too quiet
const MUSIC := 0.22          # background music level, kept low
const AUDIO_DIR := "res://audio/"
const EFFECTS := ["splat", "pee", "flies", "birdHit", "honk", "throw", "shatter", "burn", "crash", "spray",
	"jump", "plate", "over", "start", "grumble0", "grumble1", "grumble2", "grumble3",
	"drop15", "drop16", "drop17", "drop18", "drop19", "drop20", "drop21", "drop22", "drop23", "drop24", "drop25"]
const AMB_BUS := {"spray": "AmbLeft", "flies": "Master", "road": "AmbCar", "engine": "AmbCar",
	"chat": "AmbRight", "murmur": "AmbRight", "fire": "AmbFire"}

var clips := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var muted := false
var music: AudioStreamPlayer
var tracks := {}             # "waltz" / "riot" -> AudioStream
var amb := {}                # channel -> {"player", "level", "target"}
var amb_on := false
var bus_car := -1
var bus_fire := -1


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	bus_car = _bus("AmbCar", 0.0)
	bus_fire = _bus("AmbFire", 0.0)
	_bus("AmbLeft", -0.55)
	_bus("AmbRight", 0.55)
	for e in EFFECTS:
		clips[e] = load(AUDIO_DIR + e + ".wav")
	for t in ["waltz", "riot"]:
		tracks[t] = load(AUDIO_DIR + t + ".wav")
	for ch in AMB_BUS:
		var p := AudioStreamPlayer.new()
		p.stream = load(AUDIO_DIR + "amb_" + ch + ".wav")
		p.bus = AMB_BUS[ch]
		p.volume_db = -80.0
		add_child(p)
		amb[ch] = {"player": p, "level": 0.0, "target": 0.0}


## render every sound into dir as .wav (run by tools/render_audio.gd, not by the game)
func render_all(dir: String) -> void:
	_build_effects()
	for k in clips:
		clips[k].save_to_wav(dir + k + ".wav")
	_waltz().save_to_wav(dir + "waltz.wav")
	_riot().save_to_wav(dir + "riot.wav")
	var loops := _ambience_loops()
	for ch in loops:
		loops[ch].save_to_wav(dir + "amb_" + ch + ".wav")


func _bus(bus_name: String, pan: float) -> int:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	var p := AudioEffectPanner.new()
	p.pan = pan
	AudioServer.add_bus_effect(idx, p)
	return idx


# ======================================================================
# public API
# ======================================================================

func play(sound: String, arg := 0.0) -> void:
	if muted:
		return
	var key := sound
	if sound == "drop":      # the falling whistle lasts as long as the dropping takes to land
		key = "drop%d" % clampi(roundi(arg * 20.0), 15, 25)
	elif sound == "grumble":
		key = "grumble%d" % (randi() % 4)
	if not clips.has(key):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = clips[key]
	p.play()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, muted)


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


## start a piece ("waltz" / "riot"), from the top; it begins as soon as it has been rendered
func music_play(track: String) -> void:
	music.stream_paused = false
	music.stream = tracks[track]
	music.play()


func music_resume() -> void:
	music.stream_paused = false
	amb_on = true


## silence music and ambience at once (pause, game over); music_resume carries on
func quiet() -> void:
	music.stream_paused = true
	amb_on = false
	for ch in amb.values():
		ch.level = 0.0
		ch.player.volume_db = -80.0


func music_stop() -> void:
	music.stop()


func ambience_start() -> void:
	amb_on = true


## lv: spray, flies, car, car_pan, chatter, fire, fire_pan — the levels the web version passes
func ambient(lv: Dictionary) -> void:
	if amb.is_empty():
		return
	_target("spray", lv.spray)
	_target("flies", lv.flies)
	_target("road", lv.car)
	_target("engine", lv.car * 0.25)
	_target("chat", lv.chatter)
	_target("murmur", lv.chatter * 0.5)
	_target("fire", lv.fire)
	amb.engine.player.pitch_scale = (58.0 + lv.car * 90.0) / 62.0
	(AudioServer.get_bus_effect(bus_car, 0) as AudioEffectPanner).pan = lv.car_pan
	(AudioServer.get_bus_effect(bus_fire, 0) as AudioEffectPanner).pan = lv.fire_pan


func _target(ch: String, v: float) -> void:
	amb[ch].target = v


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta / 0.08)
	for ch in amb.values():
		var p: AudioStreamPlayer = ch.player
		ch.level += ((ch.target if amb_on else 0.0) - ch.level) * k
		if ch.level < 0.0005:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * p.stream.get_length())
		p.volume_db = linear_to_db(ch.level * MASTER)


# ======================================================================
# synthesis building blocks (used by render_all)
# ======================================================================

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## biquad coefficients [b0, b1, b2, a1, a2] (RBJ cookbook; bandpass with 0 dB peak, like Web Audio)
func _bq(kind: String, f: float, q: float) -> PackedFloat64Array:
	var w0 := TAU * clampf(f, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	match kind:
		"highpass":
			return PackedFloat64Array([(1.0 + cw) / 2.0 / a0, -(1.0 + cw) / a0, (1.0 + cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])
		"bandpass":
			return PackedFloat64Array([alpha / a0, 0.0, -alpha / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])
		_:
			return PackedFloat64Array([(1.0 - cw) / 2.0 / a0, (1.0 - cw) / a0, (1.0 - cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])


func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func _wave(kind: String, ph: float) -> float:
	var f := ph - floorf(ph)
	match kind:
		"sawtooth": return 2.0 * f - 1.0
		"square": return 1.0 if f < 0.5 else -1.0
		"triangle": return 4.0 * absf(f - 0.5) - 1.0
	return sin(TAU * f)


## One voice, covering everything the web version builds from oscillators:
##   t, dur, f, f1 (exponential glide over glide seconds), wave, dets (cents, one oscillator
##   each), vib (vibrato depth in cents at 5.5 Hz), wob / wob_hz (frequency wobble: Hz deep, at Hz), alt (a second
##   pitch alternated every half second: the siren), filter/cut/cut1/q (biquad, swept),
##   gain, attack, hold (fraction of dur the note holds before fading), swell (rise to 30% then fade)
func _voice(b: PackedFloat32Array, o: Dictionary) -> void:
	var t0: float = o.get("t", 0.0)
	var dur: float = o.dur
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - start)
	if n <= 0:
		return
	var f0: float = o.f
	var f1: float = maxf(1.0, o.get("f1", f0))
	var glide_n := maxi(1, int(o.get("glide", dur) * RATE))
	var fk := pow(f1 / f0, 1.0 / glide_n)
	var wave: String = o.get("wave", "sine")
	var dets: Array = o.get("dets", [0.0])
	var mults := PackedFloat64Array()
	for d in dets:
		mults.append(pow(2.0, d / 1200.0))
	var phs := PackedFloat64Array()
	phs.resize(mults.size())
	var vib: float = o.get("vib", 0.0)
	var wob: float = o.get("wob", 0.0)
	var wob_hz: float = o.get("wob_hz", 31.0)
	var alt: float = o.get("alt", 0.0)
	var filter: String = o.get("filter", "")
	var cut: float = o.get("cut", 1000.0)
	var cut1: float = o.get("cut1", cut)
	var q: float = o.get("q", 0.8)
	var ck := pow(cut1 / cut, 64.0 / n)
	var co := _bq(filter, cut, q) if filter != "" else PackedFloat64Array()
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var gain: float = o.gain
	var na := maxi(1, int(o.get("attack", 0.005) * RATE))
	var swell: bool = o.get("swell", false)
	if swell:
		na = maxi(1, int(n * 0.3))
	var hold_n := int(o.get("hold", 0.0) * n)
	var rel_start := maxi(na, hold_n)
	var ka := pow(gain / 0.0001, 1.0 / na)
	var kd := pow(0.0001 / gain, 1.0 / maxi(1, n - rel_start))
	var env := 0.0001
	var f := f0
	var half := int(0.5 * RATE)
	var inv := 1.0 / mults.size()
	for i in n:
		if filter != "" and cut1 != cut and i % 64 == 0 and i > 0:
			cut *= ck
			co = _bq(filter, cut, q)
		var fi := f
		if alt > 0.0 and (i / half) % 2 == 1:
			fi = alt
		if vib > 0.0:
			fi *= 1.0 + vib / 1731.0 * sin(TAU * 5.5 * i / RATE)
		if wob > 0.0:
			fi += wob * sin(TAU * wob_hz * i / RATE)
		var s := 0.0
		for k in mults.size():
			phs[k] += fi * mults[k] / RATE
			s += _wave(wave, phs[k])
		s *= inv
		if filter != "":
			var y := co[0] * s + co[1] * x1 + co[2] * x2 - co[3] * y1 - co[4] * y2
			x2 = x1
			x1 = s
			y2 = y1
			y1 = y
			s = y
		if i < na:
			env *= ka
		elif i >= rel_start:
			env *= kd
		b[start + i] += s * env
		if i < glide_n:
			f *= fk


## filtered noise burst (splats, splashes, spray), the web version's noise()
func _noise(b: PackedFloat32Array, o: Dictionary) -> void:
	var start := int(o.get("delay", 0.0) * RATE)
	var dur: float = o.dur
	var n := mini(int(dur * RATE), b.size() - start)
	if n <= 0:
		return
	var cut: float = o.get("freq", 1000.0)
	var cut1: float = maxf(20.0, o.get("freq1", cut))
	var ck := pow(cut1 / cut, 32.0 / n)
	var kind: String = o.get("filter", "lowpass")
	var q: float = o.get("q", 0.8)
	var co := _bq(kind, cut, q)
	var gain: float = o.get("gain", 0.3)
	var na := maxi(1, int(o.get("attack", 0.004) * RATE))
	var ka := pow(gain / 0.0001, 1.0 / na)
	var kd := pow(0.0001 / gain, 1.0 / maxi(1, n - na))
	var env := 0.0001
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		if i % 32 == 0 and i > 0 and cut1 != cut:
			cut *= ck
			co = _bq(kind, cut, q)
		var s := randf() * 2.0 - 1.0
		var y := co[0] * s + co[1] * x1 + co[2] * x2 - co[3] * y1 - co[4] * y2
		x2 = x1
		x1 = s
		y2 = y1
		y1 = y
		env = env * ka if i < na else env * kd
		b[start + i] += y * env


## a tone with the web version's tone() defaults
func _tone(b: PackedFloat32Array, o: Dictionary) -> void:
	var v := o.duplicate()
	v["t"] = o.get("delay", 0.0)
	v["f"] = o.f0
	if o.has("f1"):
		v["f1"] = o.f1
	if not v.has("gain"):
		v["gain"] = 0.2
	_voice(b, v)


func _wav(b: PackedFloat32Array, scale := MASTER, loop_end := 0) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i] * scale, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop_end > 0:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = loop_end
	return w


## fold everything past `length` seconds back onto the start, so the loop joins seamlessly
func _fold(b: PackedFloat32Array, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	for i in range(n, b.size()):
		b[i - n] += b[i]
	b.resize(n)
	return b


## for looped beds that aren't periodic: crossfade the extra tail over the start
func _xfade(b: PackedFloat32Array, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var fade := b.size() - n
	for i in fade:
		var u := float(i) / fade
		b[i] = b[i] * u + b[n + i] * (1.0 - u)
	b.resize(n)
	return b


# ======================================================================
# effects (the web version's SOUNDS)
# ======================================================================

const VOWELS := [[730.0, 1090.0], [530.0, 1840.0], [300.0, 2250.0], [570.0, 840.0], [320.0, 800.0], [500.0, 1500.0]]


func _build_effects() -> void:
	var b := _buf(0.3)
	_splat(b)
	clips["splat"] = _wav(b)

	b = _buf(0.45)
	_noise(b, {"dur": 0.4, "gain": 0.35, "freq": 2600.0, "freq1": 1200.0, "filter": "bandpass", "q": 1.2})
	for i in 3:
		_tone(b, {"f0": 500.0 + i * 120, "f1": 900.0 + i * 150, "dur": 0.07, "gain": 0.12, "delay": 0.05 + i * 0.06})
	clips["pee"] = _wav(b)

	b = _buf(0.55)
	for i in 6:
		_tone(b, {"f0": 210.0 + (i % 2) * 30, "f1": 240.0 - (i % 2) * 30, "dur": 0.09, "wave": "sawtooth", "gain": 0.08, "delay": i * 0.07})
	_splat(b)
	clips["flies"] = _wav(b)

	b = _buf(0.22)
	_noise(b, {"dur": 0.18, "gain": 0.35, "freq": 3000.0, "freq1": 900.0, "filter": "highpass"})
	_tone(b, {"f0": 900.0, "f1": 260.0, "dur": 0.16, "gain": 0.25})
	clips["birdHit"] = _wav(b)

	for k in range(15, 26):      # drop(T) for T = 0.75 … 1.25 s
		var T := k / 20.0
		b = _buf(T + 0.05)
		_tone(b, {"f0": 1600.0, "f1": 520.0, "dur": T, "wave": "triangle", "gain": 0.06, "attack": 0.05})
		clips["drop%d" % k] = _wav(b)

	# car horn "빵빵": two short blasts of a brassy two-tone horn, plus the bump
	b = _buf(0.5)
	_noise(b, {"dur": 0.2, "gain": 0.35, "freq": 500.0, "freq1": 150.0})
	for d in [0.0, 0.24]:
		for f in [415.0, 523.0]:
			var l := 0.22 if d > 0 else 0.17
			_tone(b, {"f0": f, "dur": l, "wave": "sawtooth", "gain": 0.09, "attack": 0.008, "delay": d})
			_tone(b, {"f0": f * 2, "dur": l, "wave": "square", "gain": 0.025, "attack": 0.008, "delay": d})
	clips["honk"] = _wav(b)

	for v in 4:      # a few takes of the cyclist's grumbling "oh la la…"
		clips["grumble%d" % v] = _wav(_grumble())

	b = _buf(0.75)      # Molotov: a whoosh as it flies
	_noise(b, {"dur": 0.7, "gain": 0.1, "freq": 500.0, "freq1": 2200.0, "filter": "bandpass", "q": 1.4, "attack": 0.1})
	clips["throw"] = _wav(b)

	b = _buf(0.8)       # glass smashing and a whump of flame
	_noise(b, {"dur": 0.12, "gain": 0.22, "freq": 5000.0, "filter": "highpass", "q": 0.7})
	for i in 6:
		_tone(b, {"f0": 2600.0 + randf() * 2600, "dur": 0.1 + randf() * 0.12, "wave": "triangle", "gain": 0.04, "delay": randf() * 0.09})
	_noise(b, {"dur": 0.7, "gain": 0.3, "freq": 250.0, "freq1": 1400.0, "delay": 0.04, "attack": 0.07})
	clips["shatter"] = _wav(b)

	b = _buf(0.55)      # caught by the flames: a hot whoosh and a thud
	_noise(b, {"dur": 0.5, "gain": 0.28, "freq": 400.0, "freq1": 2600.0, "filter": "bandpass", "q": 0.8, "attack": 0.02})
	_tone(b, {"f0": 190.0, "f1": 90.0, "dur": 0.3, "gain": 0.18})
	clips["burn"] = _wav(b)

	b = _buf(0.62)
	_noise(b, {"dur": 0.22, "gain": 0.4, "freq": 1800.0, "freq1": 400.0})
	for fd in [[1250.0, 0.0], [1720.0, 0.04], [2150.0, 0.09]]:
		_tone(b, {"f0": fd[0], "dur": 0.5, "wave": "triangle", "gain": 0.1, "delay": fd[1]})
	clips["crash"] = _wav(b)

	b = _buf(0.62)
	_noise(b, {"dur": 0.6, "gain": 0.25, "freq": 900.0, "freq1": 3500.0, "filter": "bandpass", "q": 0.7, "attack": 0.03})
	clips["spray"] = _wav(b)

	b = _buf(0.18)
	_tone(b, {"f0": 280.0, "f1": 720.0, "dur": 0.16, "wave": "triangle", "gain": 0.18})
	clips["jump"] = _wav(b)

	b = _buf(0.85)
	_tone(b, {"f0": 880.0, "dur": 0.5, "gain": 0.12})
	_tone(b, {"f0": 1318.5, "dur": 0.7, "gain": 0.1, "delay": 0.12})
	clips["plate"] = _wav(b)

	b = _buf(0.85)
	var fs := [523.3, 466.2, 392.0, 311.1]
	for i in 4:
		_tone(b, {"f0": fs[i], "dur": 0.32, "wave": "triangle", "gain": 0.18, "delay": i * 0.17})
	clips["over"] = _wav(b)

	b = _buf(0.45)
	fs = [523.3, 659.3, 784.0]
	for i in 3:
		_tone(b, {"f0": fs[i], "dur": 0.25, "wave": "triangle", "gain": 0.14, "delay": i * 0.08})
	clips["start"] = _wav(b)


func _splat(b: PackedFloat32Array) -> void:
	_noise(b, {"dur": 0.28, "gain": 0.5, "freq": 1200.0, "freq1": 250.0})
	_tone(b, {"f0": 210.0, "f1": 70.0, "dur": 0.18, "gain": 0.35})


## bumped a cyclist: a bump, then a gruff, falling mutter: a growling sawtooth through two
## vowel formants, syllable by syllable
func _grumble() -> PackedFloat32Array:
	var b := _buf(1.4)
	_noise(b, {"dur": 0.15, "gain": 0.05, "freq": 700.0, "freq1": 200.0})
	var base := 115.0 + randf() * 35.0
	var n := 4 + randi() % 2
	var t := 0.1
	var ph := 0.0
	var f := base * 1.2
	var g := 0.0
	var fa := 570.0
	var fb := 840.0
	var c1 := _bq("bandpass", fa, 5.0)
	var c2 := _bq("bandpass", fb, 7.0)
	var s1 := [0.0, 0.0, 0.0, 0.0]
	var s2 := [0.0, 0.0, 0.0, 0.0]
	for k in n:
		var vw: Array = VOWELS[[3, 0, 5, 4, 1][randi() % 5]]
		var d := 0.34 if k == n - 1 else 0.1 + randf() * 0.1
		var f_t := base * (1.2 - 0.45 * k / n) * (0.94 + randf() * 0.12)
		var i0 := int(t * RATE)
		var i1 := int((t + d) * RATE)
		for i in range(i0, mini(i1, b.size())):
			var into := float(i - i0) / RATE
			f += (f_t - f) / (0.03 * RATE)
			fa += (vw[0] - fa) / (0.02 * RATE)
			fb += (vw[1] - fb) / (0.02 * RATE)
			var g_t := 0.125 if into < d * 0.75 else 0.01
			g += (g_t - g) / ((0.015 if g_t > 0.1 else 0.025) * RATE)
			if i % 32 == 0:
				c1 = _bq("bandpass", fa, 5.0)
				c2 = _bq("bandpass", fb, 7.0)
			ph += (f + 7.0 * sin(TAU * 31.0 * i / RATE)) / RATE
			var s := 2.0 * (ph - floorf(ph)) - 1.0
			var y1: float = c1[0] * s + c1[1] * s1[0] + c1[2] * s1[1] - c1[3] * s1[2] - c1[4] * s1[3]
			s1 = [s, s1[0], y1, s1[2]]
			var y2: float = c2[0] * s + c2[1] * s2[0] + c2[2] * s2[1] - c2[3] * s2[2] - c2[4] * s2[3]
			s2 = [s, s2[0], y2, s2[2]]
			b[i] += (y1 + y2) * g
		t += d
	# let the last syllable die away
	for i in range(int(t * RATE), b.size()):
		g *= 0.9985
		ph += f / RATE
		b[i] += (2.0 * (ph - floorf(ph)) - 1.0) * g * 0.3
	return b


# ======================================================================
# music
# ======================================================================

# The Skaters' Waltz (Les Patineurs, Émile Waldteufel, 1882, public domain) — the web version's
# quiet accordion arrangement of Waltz No. 1: the main theme (A major) twice, the second strain
# (D major) twice, then the high, bouncy middle twice. 3/4: bass on beat 1, chord on beats 2 and 3.
const M_BEAT := 0.3
const M_THEME := [[73, 3], [76, 2], [78, 1], [78, 6], [74, 3], [78, 2], [80, 1], [80, 6],
	[83, 3], [81, 2], [73, 1], [76, 3], [78, 2], [73, 1], [80, 3], [80, 3], [81, 4], [null, 2]]
const M_THEME_UNDER := [[null, 33], [74, 2], [null, 1], [73, 3], [71, 3], [69, 4], [null, 2]]
const M_RUN_UP := [[66, 0.5], [69, 0.5], [74, 0.5], [78, 0.5]]
const M_STRAIN := [[83, 1], [null, 1], [81, 1], [null, 1], [93, 1], [null, 1],
	[61, 4], [67, 0.5], [69, 0.5], [73, 0.5], [76, 0.5],
	[83, 1], [null, 1], [81, 1], [null, 1], [93, 1], [null, 1],
	[62, 4], [66, 0.5], [69, 0.5], [74, 0.5], [78, 0.5],
	[83, 1], [null, 1], [81, 1], [null, 1], [93, 1], [null, 1],
	[61, 4], [85, 1], [null, 1], [65, 4], [89, 1], [null, 1], [66, 4], [null, 2]]
const M_THEME_BARS := [[45, "A"], [49, "A"], [47, "E7"], [40, "E7"], [47, "E7"], [40, "E7"], [49, "A"], [49, "A"],
	[42, "F#m"], [42, "F#m"], [47, "Bm"], [47, "Bm"], [40, "E7"], [40, "E7"], [45, "A"], [45, "A", "end"]]
const M_STRAIN_BARS := [[38, "D"], [45, "D"], [40, "A7"], [45, "A7"], [40, "A7"], [45, "A7"], [38, "D"], [45, "D"],
	[38, "D"], [38, "D"], [49, "F#m"], [49, "F#m"], [49, "C#7"], [37, "C#7"], [42, "F#m"], [42, "F#m", "end"]]
const M_BOUNCE_BARS := [[45, "A"], [40, "A"], [47, "E7"], [40, "E7"], [44, "E7"], [40, "E7"], [45, "A"], [49, "A"],
	[45, "A"], [45, "A"], [44, "E"], [44, "E"], [44, "G#7"], [44, "G#7"], [45, "A"], [40, "E7"]]
const M_CHORD := {"A": [57, 61, 64], "E7": [56, 62, 64], "F#m": [57, 61, 66], "Bm": [57, 62, 66],
	"D": [57, 62, 66], "A7": [55, 57, 61], "C#7": [56, 59, 61], "E": [56, 59, 64], "G#7": [56, 60, 63]}


func _waltz() -> AudioStreamWAV:
	# the bouncy middle, as a high line over the chords it bounces off
	var hi := []
	var lo := []
	var CE := [85, 88]
	var CF := [85, 90]
	var DE := [86, 88]
	var DF := [86, 90]
	var hop := func(x, y, top) -> void:
		for c in [x, y, x]:
			lo.append_array([[c, 0.5], [null, 0.5]])
			hi.append_array([[null, 0.5], [top, 0.5]])
	var stab := func(q, top, inner) -> void:
		lo.append_array([[q, 1], [inner, 0.5], [null, 0.5], [inner, 0.5], [null, 0.5]])
		hi.append_array([[null, 1], [top, 0.5], [null, 0.5], [top, 0.5], [null, 0.5]])
	var trill := func(under: Array, last := 93) -> void:
		for u in under:
			lo.append([u, 1])
		hi.append_array([[92, 0.5], [93, 0.5], [92, 0.5], [93, 0.5], [92, 0.5], [last, 0.5]])
	hop.call(CE, CF, 93); hop.call(CF, CE, 93); stab.call(DE, 92, 86); stab.call(DE, 92, 86)
	hop.call(DE, DF, 95); hop.call(DF, DE, 95); stab.call(CE, 93, 85); stab.call(CE, 93, 85)
	hop.call(CE, CF, 93); hop.call(CF, CE, 93); stab.call(CE, 92, 88); stab.call([83, 88], 92, 88)
	trill.call([84, 87, 84]); trill.call([87, 84, 87]); trill.call([85, 88, 85]); trill.call([88, 86, 88], 95)

	# lay the whole loop out: notes by half-beat step, harmony by bar
	var notes := {}
	var bars := []
	var put := func(list: Array, at: int, gain: float) -> void:
		var hh := float(at)
		for it in list:
			if it[0] != null:
				for m in (it[0] if it[0] is Array else [it[0]]):
					var key := int(hh)
					if not notes.has(key):
						notes[key] = []
					notes[key].append([m, it[1], gain * 0.7 if m > 88 else gain])
			hh += it[1] * 2.0
	var h := 0
	for k in 2:
		put.call(M_THEME, h, 0.085)
		put.call(M_THEME_UNDER, h, 0.05)
		bars.append_array(M_THEME_BARS)
		h += 96
	for k in 2:
		put.call(M_RUN_UP, h - 4, 0.085)
		put.call(M_STRAIN, h, 0.085)
		bars.append_array(M_STRAIN_BARS)
		h += 96
	for k in 2:
		if k == 0:
			put.call([[null, 0.5], [93, 0.5], [null, 0.5], [93, 0.5]], h - 4, 0.085)
			put.call([[CE, 0.5], [null, 0.5], [CF, 0.5], [null, 0.5]], h - 4, 0.045)
		put.call(hi, h, 0.085)
		put.call(lo, h, 0.045)
		bars.append_array(M_BOUNCE_BARS)
		h += 96
	var step := M_BEAT / 2.0
	var length := h * step
	var b := _buf(length + 3.0)
	for i in h:
		var t := i * step
		if i % 2 == 0:       # on the beat: oom-pah-pah
			var beat := (i / 2) % 3
			var bar: Array = bars[i / 6]
			if beat == 0:
				_voice(b, {"t": t, "dur": 0.45, "f": _hz(bar[0]), "wave": "triangle", "gain": 0.5, "attack": 0.01})
			elif bar.size() < 3:
				for m in M_CHORD[bar[1]]:
					_reed(b, m, t, M_BEAT * 0.55, 0.035)
		if notes.has(i):
			for nt in notes[i]:
				_reed(b, nt[0], t, M_BEAT * nt[1] * 0.95, nt[2])
	return _wav(_fold(b, length), MASTER * MUSIC, int(length * RATE))


## two slightly detuned reeds through a soft lowpass: a quiet accordion
func _reed(b: PackedFloat32Array, m: float, t: float, dur: float, gain: float) -> void:
	_voice(b, {"t": t, "dur": dur, "f": _hz(m), "wave": "sawtooth", "dets": [0.0, 6.9], "filter": "lowpass", "cut": 1500.0,
		"gain": gain * 2.0, "attack": 0.04, "hold": 0.7})


## riot: an original piece in D minor, 4/4 at a running pace. Layers build up over 16 bars:
## bass ostinato and kick → snare and a dark chord → hi-hats and a creeping half-step motif → sirens
func _riot() -> AudioStreamWAV:
	var e := 0.21
	var length := 128 * e
	var b := _buf(length + 4.0)
	var roots := [38, 38, 34, 33]
	var chords := [[62, 65, 69], [62, 65, 69], [58, 62, 65], [57, 61, 64]]
	var ost := [0, 0, 12, 0, 3, 0, 1, 0]
	for bar in 16:
		var s0 := bar * 8
		var root: int = roots[bar % 4]
		for k in 8:      # the growl: two buzzing saws through a closing lowpass
			_voice(b, {"t": (s0 + k) * e, "dur": e * 0.9, "f": _hz(root + ost[k]), "wave": "sawtooth", "dets": [0.0, 9.0],
				"filter": "lowpass", "cut": 700.0, "cut1": 220.0, "gain": (0.11 if k % 4 == 0 else 0.08) * 2.0, "attack": 0.006})
		for k in [0, 3, 4]:
			_voice(b, {"t": (s0 + k) * e, "dur": 0.28, "f": 130.0, "f1": 42.0, "glide": 0.18, "gain": 0.5, "attack": 0.003})
		if bar >= 4:
			for k in [2, 6]:
				_snare(b, (s0 + k) * e, 0.22)
			for m in chords[bar % 4]:
				_voice(b, {"t": s0 * e, "dur": e * 8, "f": _hz(m), "wave": "sawtooth", "dets": [-6.0, 6.0],
					"filter": "lowpass", "cut": 900.0, "gain": 0.03 * 2.0, "swell": true})
		if bar % 8 == 7:
			for k in [4, 5, 6, 7]:
				_snare(b, (s0 + k) * e, 0.16)
				_snare(b, (s0 + k + 0.5) * e, 0.12)
		if bar >= 8:
			for k in range(1, 8, 2):
				_noise(b, {"delay": (s0 + k) * e, "dur": 0.04, "gain": 0.08, "freq": 7000.0, "filter": "highpass", "attack": 0.001})
		if bar >= 12 and bar % 2 == 0:      # a French police "pin-pon" in the distance
			_voice(b, {"t": s0 * e, "dur": e * 16, "f": 435.0, "alt": 580.0, "wave": "triangle", "gain": 0.025, "swell": true})
	var motif := [[74, 2], [73, 2], [74, 2], [77, 2], [76, 4], [69, 4], [74, 2], [73, 2], [74, 2], [82, 2], [81, 8]]
	for start in [8, 12]:
		var st: int = start * 8
		for nt in motif:      # bowed: soft attack, a little vibrato, bright but filtered
			_voice(b, {"t": st * e, "dur": e * nt[1] * 0.95, "f": _hz(nt[0]), "wave": "sawtooth", "dets": [0.0, 7.0], "vib": 14.0,
				"filter": "lowpass", "cut": 2600.0, "gain": 0.05 * 2.0, "attack": 0.06, "hold": 0.75})
			st += nt[1]
	return _wav(_fold(b, length), MASTER * MUSIC, int(length * RATE))


func _snare(b: PackedFloat32Array, t: float, gain: float) -> void:
	_noise(b, {"delay": t, "dur": 0.14, "gain": gain, "freq": 1400.0, "filter": "highpass", "attack": 0.002})
	_voice(b, {"t": t, "dur": 0.08, "f": 190.0, "wave": "triangle", "gain": gain * 0.5, "attack": 0.002})


# ======================================================================
# ambience beds
# ======================================================================

func _ambience_loops() -> Dictionary:
	var loops := {}
	# hiss of water on stone
	var b := _buf(2.3)
	_bed_noise(b, [["bandpass", 2400.0, 0.5], ["highpass", 700.0, 0.7]], 1.0)
	loops["spray"] = _wav(_xfade(b, 2.0), 1.0, int(2.0 * RATE))
	# buzzing wings: a sawtooth wobbling at 11 Hz
	b = _buf(2.3)
	_voice(b, {"dur": 2.3, "f": 215.0, "wob": 28.0, "wob_hz": 11.0, "wave": "sawtooth", "filter": "lowpass", "cut": 1500.0,
		"gain": 1.0, "attack": 0.001, "hold": 1.0})
	loops["flies"] = _wav(_xfade(b, 2.0), 1.0, int(2.0 * RATE))
	# tyres on the road, and the engine hum (pitched up with the level in ambient())
	b = _buf(2.3)
	_bed_noise(b, [["lowpass", 520.0, 0.7]], 1.0)
	loops["road"] = _wav(_xfade(b, 2.0), 1.0, int(2.0 * RATE))
	b = _buf(1.0)
	_voice(b, {"dur": 1.0, "f": 62.0, "wave": "sawtooth", "filter": "lowpass", "cut": 300.0, "gain": 1.0, "attack": 0.001, "hold": 1.0})
	loops["engine"] = _wav(b, 1.0, int(1.0 * RATE))
	# café chatter: four people talking in syllables and phrases, a bit muffled, over a murmur
	b = _buf(10.3)
	for base in [112.0, 138.0, 198.0, 236.0]:
		_talker(b, base)
	_filter_in_place(b, "lowpass", 2300.0)
	loops["chat"] = _wav(_xfade(b, 10.0), 1.0, int(10.0 * RATE))
	b = _buf(2.3)
	_bed_noise(b, [["bandpass", 420.0, 1.1]], 1.0)
	loops["murmur"] = _wav(_xfade(b, 2.0), 1.0, int(2.0 * RATE))
	# fire: a breathy roar, a low rumble and crackling pops
	b = _buf(3.3)
	_bed_noise(b, [["bandpass", 1800.0, 0.5]], 0.5)
	_bed_noise(b, [["lowpass", 200.0, 0.7]], 1.4)
	for i in 45:
		_noise(b, {"delay": randf() * 3.2, "dur": 0.015 + randf() * 0.03, "gain": 0.6 + randf(), "freq": 1500.0 + randf() * 3500.0,
			"filter": "bandpass", "q": 2.5, "attack": 0.002})
	loops["fire"] = _wav(_xfade(b, 3.0), 1.0, int(3.0 * RATE))
	return loops


## white noise through a chain of biquads, added to b at the given gain
func _bed_noise(b: PackedFloat32Array, chain: Array, gain: float) -> void:
	var n := PackedFloat32Array()
	n.resize(b.size())
	for i in n.size():
		n[i] = randf() * 2.0 - 1.0
	for f in chain:
		_filter_in_place(n, f[0], f[1], f[2])
	for i in b.size():
		b[i] += n[i] * gain


func _filter_in_place(b: PackedFloat32Array, kind: String, f: float, q := 0.7) -> void:
	var co := _bq(kind, f, q)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var s := b[i]
		var y := co[0] * s + co[1] * x1 + co[2] * x2 - co[3] * y1 - co[4] * y2
		x2 = x1
		x1 = s
		y2 = y1
		y1 = y
		b[i] = y


## one café voice: a buzzy pitch shaped by two vowel formants, spoken in syllables and
## phrases with pauses
func _talker(b: PackedFloat32Array, base: float) -> void:
	var t := randf() * 0.5
	var talking := randf() < 0.5
	var phrase_end := t + 0.5 + randf()
	var ph := 0.0
	var f := base
	var g := 0.0
	var fa := 500.0
	var fb := 1500.0
	var s1 := [0.0, 0.0, 0.0, 0.0]
	var s2 := [0.0, 0.0, 0.0, 0.0]
	var c1 := _bq("bandpass", fa, 6.0)
	var c2 := _bq("bandpass", fb, 9.0)
	var lift := 1.15 if base > 170 else 1.0
	while t < b.size() / float(RATE):
		if t >= phrase_end:      # switch between saying something and listening
			talking = not talking
			phrase_end = t + (0.8 + randf() * 2.2 if talking else 0.5 + randf() * 1.6)
		var d := 0.11 + randf() * 0.15
		var g_on := 0.8 + randf() * 0.4 if talking else 0.0
		var vw: Array = VOWELS[randi() % VOWELS.size()]
		var f_t := base * (0.9 + randf() * 0.25)
		var i0 := int(t * RATE)
		var i1 := mini(int((t + d) * RATE), b.size())
		for i in range(i0, i1):
			var into := float(i - i0) / RATE
			f += (f_t - f) / (0.05 * RATE)
			fa += (vw[0] * lift - fa) / (0.025 * RATE)
			fb += (vw[1] * lift - fb) / (0.025 * RATE)
			var g_t := g_on if into < d * 0.7 else g_on * 0.15
			g += (g_t - g) / (0.025 * RATE)
			if i % 32 == 0:
				c1 = _bq("bandpass", fa, 6.0)
				c2 = _bq("bandpass", fb, 9.0)
			ph += f / RATE
			var s := 2.0 * (ph - floorf(ph)) - 1.0
			var y1: float = c1[0] * s + c1[1] * s1[0] + c1[2] * s1[1] - c1[3] * s1[2] - c1[4] * s1[3]
			s1 = [s, s1[0], y1, s1[2]]
			var y2: float = c2[0] * s + c2[1] * s2[0] + c2[2] * s2[1] - c2[3] * s2[2] - c2[4] * s2[3]
			s2 = [s, s2[0], y2, s2[2]]
			b[i] += (y1 + y2) * g * 0.5
		t += d
