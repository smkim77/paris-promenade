extends Node
## Placeholder sound effects. The web version synthesises everything live with Web Audio;
## here each effect is rendered once at start-up into a short PCM clip and played from a
## small pool of players. Music and ambience are not ported yet.

const RATE := 22050

var clips := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var muted := false


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()


func play(sound: String) -> void:
	if muted or not clips.has(sound):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = clips[sound]
	p.play()


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		for p in players:
			p.stop()
	return muted


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
