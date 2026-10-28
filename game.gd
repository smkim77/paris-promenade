extends Node2D
## 파리 산책하기 (Paris Walk) — Godot 4 port, first playable milestone.
##
## Same approach as the web version: an OutRun-style pseudo-3D sidewalk made of short
## segments, projected and painted far → near every frame. Everything is drawn with
## flat polygons, batched into one triangle array per frame (see fill/flush).
## World units: 250 units = 1 m; lateral positions are in "road units" where ±1 is the
## sidewalk edge.

const SEG_LEN := 200.0
const DRAW := 160            # segments generated / simulated ahead
const ROAD_W := 700.0
const CAM_H := 1000.0
const CAM_DEPTH := 0.84
const PLAYER_Z := CAM_H * CAM_DEPTH
const UNITS_PER_M := 250.0
const M_PER_SEG := SEG_LEN / UNITS_PER_M
const WALL_H := 2600.0
const ROOF_H := 3200.0
const SIDEWALK := 1.2          # sidewalk width relative to the obstacles
const BRIDGE_ROAD := 3.6       # the far parapet of a bridge, beyond the roadway
const PLACE_LEN := 220.0       # metres per landmark stretch
const PACE_MIN := 0.6
const PACE_MAX := 1.4
const SPEED0 := 1050.0         # forward speed at the start, at normal pace
const JUMP_TIME := 0.55
const FLY_REACH := 0.2
const TERRACE_HALF := 0.2
const STAIN_R := 0.1           # a landed bird dropping: hit radius in road units
const HUD_H := 46.0
const SPRAY_LEN := 650.0       # the cleaner's spray covers ±650 units around the truck…
const SPRAY_REACH := 0.42      # …up to 0.42 road units in from the curb
const WRECK_LANE := 1.38       # hard mode: burning cars in the parking lane along the curb

const PLACES := [
	{"name": "Tour Eiffel", "ko": "에펠탑", "street": "Avenue de Suffren", "arr": "7e"},
	{"name": "Arc de Triomphe", "ko": "개선문", "street": "Avenue Marceau", "arr": "8e"},
	{"name": "Musée du Louvre", "ko": "루브르", "street": "Rue de Rivoli", "arr": "1er"},
	{"name": "Notre-Dame", "ko": "노트르담", "street": "Quai de Montebello", "arr": "5e"},
	{"name": "Sacré-Cœur", "ko": "사크레쾨르", "street": "Rue Lepic", "arr": "18e"},
]

enum { IDLE, PLAY, PAUSED, OVER }

# ---------- colours ----------
var C_ASPHALT := Color("3d4148")
var C_STONES := [Color("e8dcc4"), Color("e2d3b8"), Color("ece2cf"), Color("dccdb2")]
var C_AWNING := [Color("1d3b6e"), Color("8c2a2a"), Color("2f5d46")]
var C_CORNER_AWNING := [Color("9b2f2b"), Color("1d3b6e"), Color("2f5d46")]
var C_CARS := [Color("c8372d"), Color("e8e4d8"), Color("2f5d46"), Color("1d3b6e"), Color("d9a441"), Color("6b6f78")]
var C_BIKES := [Color("8fc4a4"), Color("3f6fb0"), Color("c8372d"), Color("2a2c30"), Color("d9a441")]
var C_COATS := [Color("2f5d46"), Color("1d3b6e"), Color("8c2a2a"), Color("d9a441"), Color("4a4f57"), Color("e8e4d8"), Color("7a5a8c")]
var C_HEADS := ["3a2a1e", "1b1e24", "c9a066", "7a4a2a", "helmet", "beret"]
var C_SITTER_COATS := [Color("4a5568"), Color("8c2a2a"), Color("2f5d46"), Color("c9a227"), Color("6b3a4a"), Color("1d3b6e")]
var C_SITTER_HAIR := [Color("1b1e24"), Color("5b3a24"), Color("c9a26a"), Color("8a8a8a")]
var C_DOGS := [Color("8a5a2b"), Color("e8dcc6"), Color("2b2b2b"), Color("b98a4e"), Color("d8d2c4"), Color("5b3a24")]
var C_PEER_COATS := [Color("4a5568"), Color("5b4636"), Color("2f5d46"), Color("6b3a4a")]
var C_LOOTER_COATS := [Color("1b1e24"), Color("2a2c30"), Color("33363d"), Color("3a3330"), Color("2b3340"), Color("4a4f57")]
var ROOFS := []

# bundled Nanum Square Round (SIL Open Font License, see fonts/README.md), so Korean text
# also shows on web and mobile exports
var font: Font = preload("res://fonts/NanumSquareRoundR.ttf")
var font_bold: Font = preload("res://fonts/NanumSquareRoundB.ttf")
var mono: Font = font_bold

# ---------- screen ----------
var W := 640.0
var H := 900.0
var HORIZON := 0.0
var K := 0.0
var K2 := 0.0

# ---------- track ----------
var segs: Array = []
var crossings: Array = []
var g_w := 1.0
var g_next_cross := 70.0
var g_last_terrace := -999
var g_side := 1
var g_kind := "street"
var g_next_scene := 200.0
var g_cn := 5
var g_flip_x := false
var g_k := 0
var g_feature := ""
var g_tree_style := "round"

# ---------- state ----------
var state := IDLE
var hard := false
var best := 0
var score := 0.0
var slow_t := 0.0
var slow_warned := false
var position_z := 0.0
var speed := SPEED0
var dist := 0.0
var lives := 3
var invuln := 0.0
var player_x := 0.0
var step := 0.0
var gait := 0.0
var sky_offset := 0.0
var shake := 0.0
var flash := {}
var pace := 1.0
var jump_t := 0.0
var poops: Array = []
var dogs: Array = []
var peers: Array = []
var birds: Array = []
var drops: Array = []
var stains: Array = []
var texts: Array = []
var cyclists: Array = []      # bikes riding the street beside the sidewalk: scenery (and, in hard mode, throwers)
var cyc_t := 0.0
var trucks: Array = []         # street cleaners; in hard mode a gang of looters running up the street instead
var fires: Array = []          # hard mode: burning bins / rubbish heaps, and patches of fire left by Molotovs
var molotovs: Array = []
var wrecks: Array = []         # hard mode: cars burning by the curb (scenery only)
var fire_t := 0.0
var molot_t := 0.0
var wreck_t := 0.0
var clean_t := 0.0
var edge_t := 0.0
var edge_side := 0
var spawn_t := 0.0
var dog_t := 0.0
var bird_t := 0.0
var pee_t := 0.0
var shown_place := -1
var plate := {}
var drag := {}
var run_time := 0.0

# ---------- render scratch ----------
var rows: Array = []
var draw_n := DRAW             # segments actually drawn: shortened on a phone that can't keep up
var fps_low_t := 0.0
var cam_x := 0.0
var base_idx := 0
var player_screen := Vector2.ZERO
var player_h := 0.0
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()
var ga := 1.0                  # global alpha, like ctx.globalAlpha
var t_o := Vector2.ZERO        # local transform for the entity being drawn: p * t_s + t_o
var t_s := Vector2.ONE
var t_r := 0.0
# the segment being drawn (see P)
var _ax := 0.0
var _ay := 0.0
var _as := 0.0
var _aw := 0.0
var _bx := 0.0
var _by := 0.0
var _bs := 0.0
var _bw := 0.0
var _S := 1.0

# ---------- UI ----------
@onready var sfx = $Sfx
var start_panel: Control
var over_panel: Control
var over_score: Label
var over_dist: Label
var over_msg: Label
var hard_notes: Array = []
var diff_buttons: Array = []
var pause_btn: Button
var sound_btn: Button
var lb: Node                  # online scoreboard (leaderboard.gd)
# on-screen pad for phones: ◀ ▶ bottom-left, 점프 bottom-right. TouchScreenButtons follow each finger
# separately, so you can keep walking sideways while tapping 점프 (the drawing is ours, in draw_pad)
var pad_left: TouchScreenButton
var pad_right: TouchScreenButton
var pad_jump: TouchScreenButton
var touch_pad := false         # a touch screen (or `-- --touchpad` to try it with a mouse-less test)
const PAD_R := 32.0            # ◀ ▶ radius
const PAD_JR := 40.0           # 점프 radius


func _ready() -> void:
	randomize()
	# the Korean font has no accented Latin letters (é, è, à…): fall back to Godot's built-in font,
	# which every build carries (on the web there are no system fonts to fall back on)
	var fb: Array[Font] = [ThemeDB.fallback_font]
	font.fallbacks = fb
	font_bold.fallbacks = fb
	for i in 48:
		ROOFS.append({"w": 26 + ((i * 37) % 40), "h": 10 + ((i * 53) % 26), "chim": i % 3})
	_load_save()
	_build_ui()
	_build_pad()
	_set_mode(hard)
	_layout()
	reset()
	# `godot --path . -- --autoplay [--hard]` starts walking at once (used for smoke tests)
	if OS.get_cmdline_user_args().has("--hard"):
		_set_mode(true)
	if OS.get_cmdline_user_args().has("--autoplay"):
		start()


func _layout() -> void:
	var sz := get_viewport_rect().size
	W = sz.x
	H = sz.y
	HORIZON = H * 0.44
	K = H * 0.96 - HORIZON                # vertical: walker's feet near the bottom
	K2 = 0.33 * minf(W, H * 0.9) * CAM_H / ROAD_W   # horizontal: sidewalk spans ~80% of a portrait screen
	if pad_left:
		var by := H - 12 - PAD_R
		pad_left.position = V(12 + PAD_R, by)
		pad_right.position = V(12 + PAD_R * 3 + 10, by)
		pad_jump.position = V(W - 12 - PAD_JR, H - 12 - PAD_JR)
		var on := pad_on() and state == PLAY
		pad_left.visible = on
		pad_right.visible = on
		pad_jump.visible = on


func _build_pad() -> void:
	touch_pad = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touchpad")
	for a in ["pad_left", "pad_right"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var make := func(r: float, action: String) -> TouchScreenButton:
		var b := TouchScreenButton.new()
		var c := CircleShape2D.new()
		c.radius = r
		b.shape = c
		b.shape_centered = true
		b.action = action
		b.visible = false
		add_child(b)
		return b
	pad_left = make.call(PAD_R, "pad_left")
	pad_right = make.call(PAD_R, "pad_right")
	pad_jump = make.call(PAD_JR, "")
	pad_jump.pressed.connect(jump)


func pad_on() -> bool:
	return touch_pad and (state == PLAY or state == PAUSED)


## is a screen point on one of the pad buttons? (those touches must not also start a drag or a tap-jump)
func on_pad(pos: Vector2) -> bool:
	if not (pad_left and pad_left.visible):
		return false
	for b in [[pad_left, PAD_R], [pad_right, PAD_R], [pad_jump, PAD_JR]]:
		if pos.distance_to(b[0].position) <= b[1] + 6:
			return true
	return false


# ======================================================================
# track generation
# ======================================================================

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func reset_track() -> void:
	segs = []
	crossings = []
	g_w = 1.0
	g_next_cross = 70.0
	g_last_terrace = -999
	g_side = 1
	g_kind = "street"
	g_next_scene = 200.0
	g_cn = 5
	g_flip_x = false
	g_k = 0
	g_feature = ""
	g_tree_style = "round"


## street trees are one kind per block; the kind can only change across a crossing
func next_tree_style() -> void:
	if randf() < 0.3:
		return
	var others := ["round", "square", "rect"].filter(func(t): return t != g_tree_style)
	g_tree_style = others[randi() % others.size()]


func push_seg(curve: float, w: float, crossing: bool, k := -1, terrace := false) -> void:
	var i := segs.size()
	var bld := floori(i / 7.0)
	var kind := "crossing" if crossing else g_kind
	var street := kind == "street"
	segs.append({
		"i": i, "curve": curve, "w": w * SIDEWALK, "crossing": crossing, "ck": k, "cn": g_cn,
		"flip_x": crossing and g_flip_x, "side": g_side, "kind": kind, "k": g_k,
		"bld": bld, "shop": bld % 3 != 1, "terrace": terrace,
		"feature": g_feature if kind == "square" and g_k == 16 else "",
		"tree": (street or kind == "square") and i % 5 == 0, "tree_style": g_tree_style,
		"lamp": (street or kind == "square") and i % 9 == 4, "morris": street and i % 53 == 31,
	})
	g_k += 1


## n = 5: an ordinary side street (one lane each way); n = 9: a wide boulevard (two lanes each way).
## flip: the street we walk along ends here and the next one is laid out the other way round
func add_crossing(n := 5, flip := false) -> void:
	var start := segs.size()
	g_cn = n
	g_flip_x = flip
	for k in n:
		push_seg(0.0, g_w, true, k)
	g_cn = 5
	g_flip_x = false
	if flip:
		g_side = -g_side
	next_tree_style()
	var lanes := [1.6, 3.4] if n == 5 else [1.6, 3.2, 5.8, 7.4]
	var lane_z := []
	var spawn := []
	for j in lanes.size():
		lane_z.append((start + lanes[j]) * SEG_LEN)
		spawn.append(0.2 + j * 0.6)
	crossings.append({
		"z0": start * SEG_LEN, "z1": (start + n) * SEG_LEN, "lanes": lane_z,
		"dirs": [1, -1] if n == 5 else [1, 1, -1, -1], "cars": [], "spawn": spawn, "primed": false,
	})


## change of scene, then the flip: a Seine bridge, an open square, or straight onto a boulevard
func add_scene() -> void:
	var r := randf()
	var scene := "bridge" if r < 0.4 else ("square" if r < 0.75 else "boulevard")
	var w0 := g_w
	for i in 6:
		push_seg(0.0, w0 + (1.0 - w0) * smooth((i + 1) / 6.0), false)
	g_w = 1.0
	if scene != "boulevard":
		g_kind = scene
		g_k = 0
		g_feature = "fountain" if randf() < 0.5 else "obelisk"
		for i in (38 if scene == "bridge" else 34):
			push_seg(0.0, 1.0, false)
		g_kind = "street"
	add_crossing(9 if scene == "boulevard" else 5, true)


func gen_more(n: int) -> void:
	while segs.size() < n:
		var m := segs.size() * M_PER_SEG
		if m >= g_next_scene:
			var first := g_next_scene == 200.0
			g_next_scene += 220.0
			if first or randf() < 0.65:
				add_scene()
				g_next_cross = maxf(g_next_cross, segs.size() * M_PER_SEG + 70.0)
				continue
		if m >= g_next_cross:
			add_crossing()
			g_next_cross = m + 150.0 + randf() * 70.0
			continue
		var early := segs.size() < 40
		var length := 10 + randi() % 18
		var curve := 0.0
		if not early and randf() < 0.75:
			curve = (-1.0 if randf() < 0.5 else 1.0) * (1.5 + randf() * 2.5)
		var w_t := 1.0
		if not early and randf() < 0.3:
			w_t = 0.55 + randf() * 0.15
		var w0 := g_w
		var enter := maxi(2, length >> 2)
		var leave := maxi(2, length >> 2)
		var hold := length - enter - leave
		# now and then a short café terrace (2–3 tables) spills out from the wall
		var t_start := -1
		var t_len := 0
		if not early and randf() < 0.3 and segs.size() - g_last_terrace > 70:
			t_len = 3 if randf() < 0.5 else 5
			t_start = 1 + randi() % maxi(1, length - t_len - 2)
			if (segs.size() + t_start) % 2:
				t_start += 1
		for i in length:
			var c: float
			if i < enter:
				c = curve * smooth(float(i) / enter)
			elif i < enter + hold:
				c = curve
			else:
				c = curve * (1.0 - smooth(float(i - enter - hold) / leave))
			var terrace := t_start >= 0 and i >= t_start and i < t_start + t_len
			if terrace:
				g_last_terrace = segs.size()
			push_seg(c, w0 + (w_t - w0) * smooth((i + 1.0) / length), false, -1, terrace)
		g_w = w_t


func seg_at(z: float) -> Dictionary:
	var i := maxi(0, floori(z / SEG_LEN))
	gen_more(i + 1)
	return segs[i]


func near_crossing(z: float) -> bool:
	return seg_at(z).crossing or seg_at(z + SEG_LEN).crossing or seg_at(maxf(0.0, z - SEG_LEN)).crossing


func place_at(d: float) -> int:
	return maxi(0, floori(d / PLACE_LEN)) % PLACES.size()


# ======================================================================
# game state
# ======================================================================

func score_mult(p: float) -> float:
	return 0.5 + (p - PACE_MIN) / (1.0 - PACE_MIN) * 0.5 if p < 1.0 else 1.0 + (p - 1.0) / (PACE_MAX - 1.0)


## 4.5 km/h at the starting pace, gently compressed so the speed-up reads as a walk to a jog
func walk_kmh() -> float:
	return 4.5 * pow(speed / SPEED0, 0.5)


func cadence() -> float:
	return 0.2 + 0.36 * walk_kmh()


func airborne() -> bool:
	return jump_t > 0.0


func jump_height() -> float:
	return sin(PI * (1.0 - jump_t / JUMP_TIME)) if jump_t > 0.0 else 0.0


func pz() -> float:
	return position_z + PLAYER_Z


func reset() -> void:
	reset_track()
	position_z = 0.0
	speed = SPEED0
	pace = 1.0
	jump_t = 0.0
	dist = 0.0
	lives = 3
	invuln = 0.0
	player_x = 0.0
	step = 0.0
	gait = 0.0
	sky_offset = 0.0
	shake = 0.0
	flash = {}
	poops = []
	dogs = []
	peers = []
	birds = []
	drops = []
	stains = []
	texts = []
	trucks = []
	cyclists = []
	cyc_t = 0.0
	fires = []
	molotovs = []
	wrecks = []
	fire_t = 3.0
	molot_t = 3.0
	wreck_t = 2.0
	clean_t = 14.0
	edge_t = 0.0
	edge_side = 0
	score = 0.0
	slow_t = 0.0
	slow_warned = false
	run_time = 0.0
	spawn_t = 0.3
	dog_t = 2.5
	bird_t = 5.0
	pee_t = 3.0
	shown_place = -1
	plate = {}
	gen_more(DRAW + 2)        # so the street is there behind the start screen too
	update_place()


func update_place() -> void:
	var i := place_at(dist)
	if i == shown_place:
		return
	shown_place = i
	if state == PLAY:
		plate = {"text": PLACES[i].name, "ko": PLACES[i].ko, "life": 2.6}
		sfx.play("plate")


func start() -> void:
	reset()
	state = PLAY
	start_panel.visible = false
	over_panel.visible = false
	pause_btn.visible = true
	pause_btn.text = "II"
	plate = {"text": PLACES[0].name, "ko": PLACES[0].ko, "life": 2.6}
	sfx.play("start")
	sfx.music_play("riot" if hard else "waltz")      # hard mode: the riot piece; otherwise the Skaters' Waltz
	sfx.ambience_start()


func toggle_pause() -> void:
	if state == PLAY:
		state = PAUSED
		drag = {}
		sfx.quiet()
		pause_btn.text = "▶"
	elif state == PAUSED:
		state = PLAY
		pause_btn.text = "II"
		sfx.music_resume()


func game_over() -> void:
	state = OVER
	pause_btn.visible = false
	flash = {}
	shake = 0.0
	sfx.quiet()
	sfx.play("over")
	var d := floori(dist)
	var p: Dictionary = PLACES[place_at(dist)]
	var sc := floori(score)
	var msg: String = p.ko + " 근처에서 구두가 다 망가졌습니다. "
	if d < 100:
		msg += "파리지앵이 되려면 아직 멀었어요."
	elif d < 400:
		msg += "바게트 하나 사 들고 돌아가세요."
	elif d < 800:
		msg += "꽤 능숙한 산책가예요."
	else:
		msg += "당신은 진정한 똥 회피의 달인입니다."
	if sc > best:
		best = sc
		msg = ("어려움 최고 점수! " if hard else "최고 점수! ") + msg
		_save()
	over_score.text = _fmt(sc) + "점"
	over_dist.text = "%d m 걸음 · %s 근처" % [d, p.ko]
	over_msg.text = msg
	over_panel.visible = true
	lb.game_over({"score": sc, "dist": d, "place": place_at(dist), "duration": roundi(run_time * 1000.0), "mode": "hard" if hard else "normal"})


func take_hit(label: String, color: Color, sound: String) -> bool:
	lives -= 1
	invuln = 1.4
	shake = 0.35
	flash = {"color": color, "t": 0.35}
	pace = maxf(PACE_MIN, pace * 0.7)     # stumbling: down to 70% of the pace you were walking at
	if not drag.is_empty():
		drag.pace0 = pace
		drag.y0 = drag.cur_y
	texts.append({"text": label, "life": 1.1, "dy": 0.0})
	sfx.play(sound)
	if lives <= 0:
		game_over()
		return true
	return false


# ======================================================================
# spawning
# ======================================================================

func spawn_poop(z: float, x = null, fresh := false, kind := "dog") -> void:
	if near_crossing(z):
		return
	var seg := seg_at(z)
	var r := 0.17 + randf() * 0.05 if kind == "pee" else 0.08 + randf() * 0.04
	var px: float = x if x != null else (randf() * 2.0 - 1.0) * (seg.w - r - 0.05)
	var o := {"z": z, "x": px, "r": r, "fresh": fresh, "kind": kind, "steam": randf() * 6.0,
		"rot": randf() * PI, "age": 0.0, "flies": 0.0, "fly_at": INF, "fly_near": 0.0}
	# about 40% of dog poops get a fly swarm: some already buzzing, some arriving as you get close
	if kind == "dog" and randf() < 0.4:
		if randf() < 0.4:
			o.fly_at = 0.3 + randf() * 1.4
		else:
			o.fly_near = 2600.0 + randf() * 2400.0
	poops.append(o)


## dog temperaments: trot, zigzag, sniff (stops to do its business), dash, turnback, diagonal
func spawn_dog() -> void:
	var z := pz() + 3500.0 + randf() * 5000.0
	if near_crossing(z):
		return
	var seg := seg_at(z)
	if seg.kind == "bridge":
		return
	var dir := 1.0 if randf() < 0.5 else -1.0
	var kinds := ["trot", "zigzag", "sniff", "sniff", "dash", "turnback", "diagonal"]
	var kind: String = kinds[randi() % kinds.size()]
	var v := 0.6 + randf() * 0.35
	if kind == "dash":
		v = 1.8 + randf() * 0.6
	elif kind == "sniff":
		v = 0.45 + randf() * 0.2
	dogs.append({
		"z": z, "x": -dir * 2.4, "dir": dir, "kind": kind,
		"size": 0.75 if kind == "dash" else 0.85 + randf() * 0.4, "v": v,
		"zv": ((-1.0 if randf() < 0.5 else 1.0) * (250.0 + randf() * 250.0)) if kind == "diagonal" else 0.0,
		"t": randf() * 6.0, "state": "walk", "sniff_t": 0.0, "leg": 0.0,
		"drop_at": (randf() * 2.0 - 1.0) * (seg.w - 0.2), "dropped": false,
		"color": C_DOGS[randi() % C_DOGS.size()],
	})


## a passer-by stops at the wall (or the curb), pees, then walks off leaving a puddle.
## ambush_side: one that pops out right ahead on that side and is done almost at once
func spawn_peer(ambush_side := 0) -> bool:
	var z := pz() + speed * 1.25 if ambush_side else pz() + 9000.0 + randf() * 6000.0
	if near_crossing(z):
		return false
	var seg := seg_at(z)
	var side := ambush_side if ambush_side else (-1 if randf() < 0.5 else 1)
	if side == seg.side and seg.terrace:      # no room against a café terrace
		if ambush_side:
			return false
		side = -side
	peers.append({
		"z": z, "side": side, "x": side * (seg.w - 0.1), "t": 0.0,
		"T": 0.3 if ambush_side else 1.6 + randf() * 0.6, "done": false, "leave": 0.0,
		"bob": randf() * 6.0, "coat": C_PEER_COATS[randi() % C_PEER_COATS.size()],
	})
	return true


func spawn_bird() -> void:
	var from_left := randf() < 0.5
	birds.append({
		"x": -30.0 if from_left else W + 30.0, "y": HORIZON * (0.25 + randf() * 0.55),
		"vx": (1.0 if from_left else -1.0) * (150.0 + randf() * 80.0),
		"drop_at": W * (0.3 + randf() * 0.4), "dropped": false, "flap": randf() * 6.0,
	})


## the dropping is aimed near the walker: its ground target lies ahead by exactly the
## distance the walker covers before it lands
func drop_from_bird(b: Dictionary) -> void:
	var T := maxf(0.75, 1.25 - dist / 2000.0)
	var z := pz() + speed * T
	var seg := seg_at(z)
	var x := clampf(player_x + (randf() - 0.5) * 0.35, -seg.w + 0.12, seg.w - 0.12)
	drops.append({"sx": b.x, "sy": b.y, "z": z, "x": x, "t": 0.0, "T": T, "r": 0.2})
	sfx.play("drop", T)      # falling whistle: a heads-up that something is coming down


## irregular traffic: usually a long quiet gap, sometimes a car right behind another
func next_car_gap() -> float:
	var r := randf()
	if r < 0.2:
		return 0.7 + randf() * 0.5
	if r < 0.85:
		return 2.5 + randf() * 3.5
	return 6.0 + randf() * 4.0


## about a third of the crossing traffic is bikes: slower and narrower, but just as painful
func make_car(lane: int, dir: int, x = null) -> Dictionary:
	var x0: float = x if x != null else -dir * 6.0
	if randf() < 0.33:
		return {"lane": lane, "dir": dir, "bike": true, "x": x0,
			"v": 1.7 + randf() * 0.7 + minf(dist * 0.002, 0.8), "len": 0.65,
			"color": C_BIKES.pick_random(), "coat": C_COATS.pick_random(), "head": C_HEADS.pick_random(), "ph": randf() * 6.0}
	return {"lane": lane, "dir": dir, "bike": false, "x": x0,
		"v": 2.8 + randf() * 1.2 + minf(dist * 0.004, 1.5), "len": 1.9 + randf() * 0.4,
		"color": C_CARS.pick_random()}


## stable pseudo-random value in [0, 1) per seed, so the same looters keep the same look
func seat_rand(sd: float, side: float) -> float:
	var v := sin(sd * 12.9898 + side * 78.233) * 43758.5453
	return v - floorf(v)


## Paris street-cleaning truck driving slowly up the street, hosing the curb-side edge;
## in hard mode a gang of looters running up the street instead
func spawn_cleaner() -> void:
	var z := pz() + 9000.0 + randf() * 3000.0
	var side: int = seg_at(z).side
	var d := 0.0
	while d <= 16000.0:      # only where the street keeps the same side while the truck is in view
		var sg := seg_at(z + d)
		if sg.side != side or sg.flip_x:
			return
		d += 600.0
	trucks.append({"z": z, "v": 450.0 + randf() * 150.0, "t": 0.0, "march": hard, "seed": randf() * 100.0, "throw_t": 0.0, "throw_j": -1})


## how far the wet patch reaches in from the curb at world z: widest beside the truck, tapering
## to nothing at both ends, with a ragged edge that stays put on the pavement
func wet_reach(tr: Dictionary, z: float) -> float:
	var d: float = absf(z - tr.z) / SPRAY_LEN
	if d >= 1.0:
		return 0.0
	var taper := pow(1.0 - d * d, 0.6)
	var ragged := 0.74 + 0.14 * sin(z * 0.011) + 0.08 * sin(z * 0.0043 + 1.3) + 0.04 * sin(z * 0.031)
	return SPRAY_REACH * taper * ragged


## a cyclist on the street beside us: the near lane rides our way, the far lane comes toward us.
## Riders vary: leisurely (the walker overtakes them), everyday, and the odd one in a hurry.
func spawn_cyclist() -> void:
	var toward := randf() < 0.4
	var far := position_z + (DRAW - 6) * SEG_LEN
	var r := randf()
	var base := 900.0 + randf() * 1300.0
	if r >= 0.8:
		base = 3000.0 + randf() * 800.0
	elif r >= 0.35:
		base = 2000.0 + randf() * 1200.0
	var v := -base * 0.75 if toward else base * 0.65
	# faster than us: comes up from behind; slower: starts ahead, about 7 s of catching up away
	var z := far
	if not toward:
		z = position_z - 300.0 if v > speed else position_z + maxf(6000.0, minf(far - position_z, (speed - v) * 7.0))
	var seg := seg_at(z)
	if seg.flip_x:
		return
	cyclists.append({"z": z, "v": v, "side": seg.side, "toward": toward, "throw_t": 0.0,
		"lane": (2.15 if hard else 1.95) if toward else (1.75 if hard else 1.45),
		"ph": randf() * 6.0, "color": C_BIKES.pick_random(), "coat": C_COATS.pick_random(),
		"head": C_HEADS.pick_random(), "basket": randf() < 0.35})


## a car set alight in the parking lane, far up the street
func spawn_wreck() -> void:
	var z := position_z + DRAW * SEG_LEN * 0.85
	if near_crossing(z) or seg_at(z).flip_x:
		return
	wrecks.append({"z": z, "t": randf() * 5.0, "seed": randf() * 10.0, "color": C_CARS.pick_random()})


## a street bin set alight (or, half the time, a heap of rubbish bags and boxes)
func spawn_fire() -> void:
	var z := position_z + DRAW * SEG_LEN * 0.8
	if near_crossing(z):
		return
	var seg := seg_at(z)
	fires.append({"z": z, "x": (randf() * 2.0 - 1.0) * (seg.w - 0.25), "kind": "bin", "pile": randf() < 0.5,
		"t": randf() * 5.0, "seed": randf() * 10.0, "r": 0.16, "life": 1.0})


## a Molotov lobbed in from the street side, aimed just ahead of the walker (its ring on the
## ground shows where it will land). Usually a looter in view throws it.
func throw_molotov() -> void:
	var T := maxf(0.95, 1.35 - dist / 2500.0)
	var z := pz() + speed * T
	var seg := seg_at(z)
	var x := clampf(player_x + (randf() - 0.5) * 0.5, -seg.w + 0.15, seg.w - 0.15)
	var side: int = seg_at(pz()).side
	var sx := -20.0 if side > 0 else W + 20.0
	var sy := H * (0.5 + randf() * 0.2)
	var throwers := []
	for c in cyclists:
		if c.side == side and c.z - position_z > 900.0 and c.z - position_z < 7000.0:
			throwers.append(c)
	var pi_ := floori(position_z / SEG_LEN)
	for i in range(pi_ + 4, mini(pi_ + 36, segs.size())):
		var sg: Dictionary = segs[i]
		var dz := terrace_z(sg) - position_z
		if sg.terrace and i % 2 == 0 and dz > 900.0 and dz < 7000.0:
			throwers.append(sg)
	for tr in trucks:
		if tr.march and tr.z - position_z > 900.0 and tr.z - position_z < 7000.0:
			throwers.append(tr)
	if throwers.size() and randf() < 0.8:
		var th: Dictionary = throwers.pick_random()
		var hand := {}
		if th.has("toward"):      # a cyclist
			var sg := seg_at(th.z)
			th.throw_t = 0.5
			hand = to_screen(th.z, -th.side * sg.w * th.lane, 430)
		elif th.has("march"):
			var j := randi() % 11
			var zj: float = th.z + (j - 5) * SPRAY_LEN * 0.17
			var sg := seg_at(zj)
			th.throw_j = j
			th.throw_t = 0.5
			hand = to_screen(zj, sg.side * (-sg.w + 0.1), 950)
		else:
			th["throw_at"] = run_time
			hand = to_screen(terrace_z(th), terrace_x(th), 950)
		if not hand.is_empty():
			sx = hand.x
			sy = hand.y
	molotovs.append({"sx": sx, "sy": sy, "z": z, "x": x, "t": 0.0, "T": T, "spin": randf() * 6.0})
	sfx.play("throw")


## a patch of fire grows in a flash, burns, then dies down in its last second
func fire_scale(f: Dictionary) -> float:
	if f.kind == "bin":
		return 1.0
	return minf(1.0, f.t / 0.25) * clampf(f.life, 0.0, 1.0)


func terrace_z(s: Dictionary) -> float:
	return (s.i + 0.5) * SEG_LEN


func terrace_x(s: Dictionary) -> float:
	return s.side * (s.w - 0.22)


func hit_radius(p: Dictionary) -> float:
	return p.r + p.flies * FLY_REACH


# ======================================================================
# update
# ======================================================================

func _process(delta: float) -> void:
	_layout()
	if state == PLAY:
		update(minf(delta, 0.05))
		_adapt_quality(delta)
	queue_redraw()


## a slow phone: after 2 s below 45 fps, draw 15 fewer segments of the street (down to 85);
## the far end just appears a little later
func _adapt_quality(delta: float) -> void:
	if draw_n <= 85:
		return
	if Engine.get_frames_per_second() < 45:
		fps_low_t += delta
		if fps_low_t > 2.0:
			draw_n -= 15
			fps_low_t = 0.0
	else:
		fps_low_t = 0.0


func update(dt: float) -> void:
	var up := Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)
	var down := Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("pad_left")
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("pad_right")
	if up or down or left or right:
		drag = {}
	pace += (int(up) - int(down)) * 0.8 * dt
	if not drag.is_empty() and drag.moved:
		pace = drag.pace0 - (drag.cur_y - drag.y0) / (H * 0.4) * (PACE_MAX - PACE_MIN)
	pace = clampf(pace, PACE_MIN, PACE_MAX)
	speed = (SPEED0 + minf(dist * 4.5, 3700.0 - SPEED0)) * pace
	score += speed * dt / UNITS_PER_M * score_mult(pace)
	position_z += speed * dt
	dist = position_z / UNITS_PER_M
	step += dt * speed / 330.0
	gait += dt * PI * cadence()
	run_time += dt
	var p_z := pz()
	var pseg := seg_at(p_z)

	# steering; bends pull the walker toward the outside, like a car in OutRun
	player_x += (int(right) - int(left)) * 1.9 * dt
	if not drag.is_empty():
		var target: float = drag.px + (drag.cur - drag.x0) / (W * 0.36)
		var diff := target - player_x
		player_x += signf(diff) * minf(absf(diff), 3.0 * dt)
	player_x -= dt * pseg.curve * (speed / 4000.0) * 0.38
	var lim: float = pseg.w - 0.1
	player_x = clampf(player_x, -lim, lim)
	sky_offset -= pseg.curve * (speed / 4000.0) * dt * 70.0
	sky_offset *= 1.0 - dt * 0.25

	update_place()
	if not plate.is_empty():
		plate.life -= dt
		if plate.life <= 0.0:
			plate = {}

	# spawning
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_poop(position_z + DRAW * SEG_LEN * 0.8)
		if dist > 150.0 and randf() < 0.3:
			spawn_poop(position_z + DRAW * SEG_LEN * 0.8 + 300.0)
		spawn_t = maxf(0.28, 0.9 - dist / 900.0) * (0.6 + randf() * 0.8)
	dog_t -= dt
	if dog_t <= 0.0:
		spawn_dog()
		dog_t = maxf(2.2, 6.0 - dist / 250.0) * (0.7 + randf() * 0.6)
	if dist > 50.0:
		pee_t -= dt
		if pee_t <= 0.0:
			spawn_peer()
			pee_t = maxf(4.5, 9.0 - dist / 150.0) * (0.7 + randf() * 0.6)
	# hugging one edge for too long brings a passer-by right there, just ahead
	var at_edge := int(signf(player_x)) if absf(player_x) > lim - 0.15 else 0
	if at_edge and at_edge == edge_side:
		edge_t += dt
	else:
		edge_side = at_edge
		edge_t = 0.0
	if dist > 30.0 and edge_side and edge_t > 2.5 and spawn_peer(edge_side):
		edge_t = -1.5
	# dawdling below 80% pace for a while makes the pigeons gather: up to 3× as many
	if pace < 0.8:
		slow_t += dt
	else:
		slow_t = maxf(0.0, slow_t - dt * 2.0)
	var flock := 1.0 + minf((slow_t - 2.0) / 3.0, 1.0) * 2.0 if slow_t > 2.0 else 1.0
	if flock > 1.0 and not slow_warned:
		slow_warned = true
		texts.append({"text": "비둘기들이 노려봅니다…", "life": 1.6, "dy": 0.0, "small": true})
	if slow_t == 0.0:
		slow_warned = false
	if dist > 40.0 or flock > 1.0:
		bird_t -= dt * flock
		if bird_t <= 0.0:
			spawn_bird()
			bird_t = maxf(1.8, 5.5 - dist / 300.0) * (0.7 + randf() * 0.6)

	# crossings: cars keep coming in every lane while the crossing is in view
	for c in crossings:
		if c.z1 < position_z or c.z0 - position_z > DRAW * SEG_LEN:
			continue
		if not c.primed:
			c.primed = true
			for lane in c.lanes.size():
				if randf() < 0.5:
					c.cars.append(make_car(lane, c.dirs[lane], (randf() * 2.0 - 1.0) * 5.0))
				c.spawn[lane] = randf() * 3.0
		for lane in c.lanes.size():
			c.spawn[lane] -= dt
			if c.spawn[lane] <= 0.0:
				c.cars.append(make_car(lane, c.dirs[lane]))
				c.spawn[lane] = next_car_gap() * (1.3 if c.lanes.size() > 2 else 1.0)
		for car in c.cars:
			car.x += car.dir * car.v * dt
			if car.bike:
				car.ph += car.v * dt * 4.0
		c.cars = c.cars.filter(func(car): return absf(car.x) < 7.0)
	crossings = crossings.filter(func(c): return c.z1 > position_z)

	cyc_t -= dt
	if cyc_t <= 0.0:
		spawn_cyclist()
		cyc_t = 1.2 + randf() * 3.5
	for c in cyclists:
		c.z += c.v * dt
		c.ph += absf(c.v) * dt / 380.0
		c.throw_t = maxf(0.0, c.throw_t - dt)
	if dist > 80.0:
		clean_t -= dt
		if clean_t <= 0.0:
			spawn_cleaner()
			clean_t = 16.0 + randf() * 12.0
	for tr in trucks:
		tr.z += tr.v * dt
		tr.t += dt
		tr.throw_t = maxf(0.0, tr.throw_t - dt)
	if hard:
		fire_t -= dt
		if fire_t <= 0.0:
			spawn_fire()
			fire_t = maxf(2.4, 6.0 - dist / 250.0) * (0.7 + randf() * 0.6)
		wreck_t -= dt
		if wreck_t <= 0.0:
			spawn_wreck()
			wreck_t = 6.0 + randf() * 9.0
		if dist > 20.0:
			molot_t -= dt
			if molot_t <= 0.0:
				throw_molotov()
				molot_t = maxf(1.3, 4.0 - dist / 250.0) * (0.7 + randf() * 0.6)
	for f in fires:
		f.t += dt
		if f.kind == "patch":
			f.life -= dt
	for w in wrecks:
		w.t += dt
	# a Molotov smashes where it lands and leaves a patch of fire; the bottle itself doesn't hurt,
	# only fire you walk into later does (see the fire collisions below). Aimed at the walker, it
	# often lands right underfoot: that patch is behind you a moment later and never hurts (under).
	for i in range(molotovs.size() - 1, -1, -1):
		var m: Dictionary = molotovs[i]
		m.t += dt
		if m.t < m.T:
			continue
		molotovs.remove_at(i)
		sfx.play("shatter")
		var under: bool = absf(m.z - p_z) < 150.0 and absf(m.x - player_x) < 0.28 + 0.07
		fires.append({"z": m.z, "x": m.x, "r": 0.28, "kind": "patch", "pile": false, "t": 0.0, "life": 4.5,
			"seed": randf() * 10.0, "under": under})

	if jump_t > 0.0:
		jump_t = maxf(0.0, jump_t - dt)
	for p in poops:
		p.steam += dt * 3.0
		p.age += dt
		if p.fly_near and p.z - p_z < p.fly_near:
			p.fly_at = minf(p.fly_at, p.age)
		if p.age > p.fly_at:
			p.flies = minf(1.0, p.flies + dt / 0.7)
	for d in dogs:
		d.t += dt
		if d.state == "sniff":
			d.sniff_t -= dt
			if d.sniff_t <= 0.0:
				d.state = "walk"
		else:
			d.x += d.dir * d.v * dt
			if d.kind == "zigzag":
				d.z += sin(d.t * 3.4) * 500.0 * dt
			if d.kind == "diagonal":
				d.z += d.zv * dt
			d.leg += dt * (6.0 + d.v * 8.0)
		if not d.dropped and ((d.dir > 0 and d.x >= d.drop_at) or (d.dir < 0 and d.x <= d.drop_at)):
			d.dropped = true
			spawn_poop(d.z, d.x - d.dir * 0.12 * d.size, true)
			if d.kind == "sniff":
				d.state = "sniff"
				d.sniff_t = 1.0 + randf() * 1.2
			if d.kind == "turnback":
				d.dir = -d.dir
	for s in peers:
		s.t += dt
		if not s.done and s.t >= s.T:
			s.done = true
			var sg := seg_at(s.z)
			poops.append({"z": s.z, "x": s.side * (sg.w - 0.15), "r": 0.2, "kind": "pee", "rot": s.bob,
				"age": 0.0, "flies": 0.0, "fly_at": INF, "fly_near": 0.0, "steam": 0.0, "fresh": false})
			texts.append({"text": "Pardon~", "life": 1.0, "dy": 0.0, "at": s, "small": true})
		if s.done:
			s.leave += dt
			s.z += 350.0 * dt
	for b in birds:
		b.x += b.vx * dt
		b.flap += dt * 16.0
		if not b.dropped and ((b.vx > 0 and b.x >= b.drop_at) or (b.vx < 0 and b.x <= b.drop_at)):
			b.dropped = true
			drop_from_bird(b)
	for t in texts:
		t.life -= dt
		t.dy -= 30.0 * dt
	if not flash.is_empty():
		flash.t -= dt
		if flash.t <= 0.0:
			flash = {}
	if invuln > 0.0:
		invuln -= dt
	if shake > 0.0:
		shake -= dt

	# bird droppings land when their timer runs out and stay on the pavement; the falling dropping
	# itself doesn't hurt, stepping in one later does (see the collisions below). One that lands
	# right underfoot is behind you a moment later and never counts (under).
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.t += dt
		if d.t < d.T:
			continue
		drops.remove_at(i)
		var under: bool = absf(d.z - p_z) < 150.0 and absf(d.x - player_x) < STAIN_R + 0.07
		stains.append({"z": d.z, "x": d.x, "seed": randf() * 10.0, "under": under})

	# collisions with things on the pavement (a jump clears poop, fly swarms and puddles)
	var reach := 60.0 + speed * dt
	if invuln <= 0.0 and not airborne():
		for p in poops:
			if absf(p.z - p_z) > reach:
				continue
			if absf(p.x - player_x) < hit_radius(p) + 0.07:
				poops.erase(p)
				var label := "첨벙! 오줌이잖아!" if p.kind == "pee" else ("윙윙~ 파리 떼!" if p.flies > 0.5 else "으악, 밟았다!")
				var sound := "pee" if p.kind == "pee" else ("flies" if p.flies > 0.5 else "splat")
				var col := Color(0.91, 0.78, 0.29, 0.45) if p.kind == "pee" else Color(0.42, 0.27, 0.14, 0.45)
				if take_hit(label, col, sound):
					return
				break
	# bird droppings on the pavement: stepped in like poop, cleared by a jump
	if invuln <= 0.0 and not airborne():
		for st in stains:
			if st.get("under", false) or absf(st.z - p_z) > reach:
				continue
			if absf(st.x - player_x) < STAIN_R + 0.07:
				stains.erase(st)
				if take_hit("으악, 새똥 밟았다!", Color(0.96, 0.95, 0.92, 0.6), "birdHit"):
					return
				break
	# café terrace tables against the wall
	if invuln <= 0.0:
		var pi_ := floori(p_z / SEG_LEN)
		for i in range(pi_ - 1, pi_ + 2):
			if i < 0 or i >= segs.size():
				continue
			var s: Dictionary = segs[i]
			if not s.terrace or i % 2:
				continue
			if absf(terrace_z(s) - p_z) > reach + 60.0:
				continue
			if absf(player_x - terrace_x(s)) < TERRACE_HALF + 0.06:
				var over_t := take_hit("약탈자와 부딪혔다!", Color(0.78, 0.24, 0.16, 0.4), "grumble") if hard \
					else take_hit("Attention! 테라스!", Color(0.55, 0.16, 0.16, 0.35), "crash")
				if over_t:
					return
				break
	# fire: a burning bin, a burning heap of rubbish and a patch of fire on the ground can all be jumped
	if invuln <= 0.0:
		for f in fires:
			if f.get("under", false) or absf(f.z - p_z) > reach + 40.0:
				continue
			if airborne():
				continue
			var r: float = 0.16 if f.kind == "bin" else f.r * fire_scale(f)
			if r > 0.04 and absf(f.x - player_x) < r + 0.07:
				var label := "앗 뜨거! 불길이다!"
				if f.kind == "bin":
					label = "앗 뜨거! 쓰레기 더미가 불타요!" if f.pile else "앗 뜨거! 쓰레기통이 불타요!"
				if take_hit(label, Color(0.94, 0.47, 0.12, 0.45), "burn"):
					return
				break
	# the street cleaner's spray along the curb (or the looters' gang, in the same stretch)
	if invuln <= 0.0:
		for tr in trucks:
			if pseg.side * player_x < -pseg.w + wet_reach(tr, p_z):
				var over_s := take_hit("약탈자 무리에 휩쓸렸다!", Color(0.78, 0.24, 0.16, 0.4), "grumble") if tr.march \
					else take_hit("살수차 물벼락!", Color(0.44, 0.63, 0.78, 0.45), "spray")
				if over_s:
					return
				break
	# cars and bikes on the crossings
	if invuln <= 0.0:
		var hit := false
		for c in crossings:
			for car in c.cars:
				if absf(c.lanes[car.lane] - p_z) > 260.0:
					continue
				if absf(car.x - player_x) < car.len / 2.0 + 0.06:
					var over := take_hit("Oh là là! 자전거 조심!", Color(0.78, 0.47, 0.18, 0.4), "grumble") if car.bike \
						else take_hit("빵빵! 차 조심!", Color(0.78, 0.22, 0.18, 0.4), "honk")
					if over:
						return
					hit = true
					break
			if hit:
				break

	# cleanup: anything behind the camera is gone
	poops = poops.filter(func(p): return p.z > position_z + 100.0)
	stains = stains.filter(func(s): return s.z > position_z + 100.0)
	dogs = dogs.filter(func(d): return d.z > position_z + 100.0 and absf(d.x) < 2.6)
	peers = peers.filter(func(s): return s.z > position_z + 100.0 and s.leave < 2.5)
	birds = birds.filter(func(b): return b.x > -60.0 and b.x < W + 60.0)
	cyclists = cyclists.filter(func(c): return c.z > position_z - 400.0 and c.z < position_z + DRAW * SEG_LEN and seg_at(c.z).side == c.side)
	trucks = trucks.filter(func(tr): return tr.z > position_z - SPRAY_LEN and tr.z < position_z + DRAW * SEG_LEN)
	fires = fires.filter(func(f): return f.z > position_z + 100.0 and (f.kind == "bin" or f.life > 0.0))
	wrecks = wrecks.filter(func(w): return w.z > position_z + 100.0)
	texts = texts.filter(func(t): return t.life > 0.0)
	update_ambience(p_z)


## ambience volumes from what is near the walker (closer = louder, 0 when out of earshot)
func near_v(d: float, reach_: float) -> float:
	var v := 1.0 - absf(d) / reach_
	return v * v if v > 0.0 else 0.0


func update_ambience(p_z: float) -> void:
	var spray := 0.0
	var flies := 0.0
	var car := 0.0
	var car_pan := 0.0
	var chatter := 0.0
	for tr in trucks:
		if tr.march:
			chatter = maxf(chatter, near_v(tr.z - p_z, 5000.0))      # a gang is a crowd, not a hose
		else:
			spray = maxf(spray, near_v(tr.z - p_z, 4500.0))
	# buzz only while a swarm is flying in, not for poop that already has its flies
	for p in poops:
		if p.flies <= 0.0 or p.flies >= 1.0 or p.z - p_z > 7000.0:
			continue
		flies = maxf(flies, sin(PI * p.flies) * near_v(Vector2(p.z - p_z, (p.x - player_x) * ROAD_W).length(), 7500.0))
	for c in crossings:
		for cr in c.cars:
			if cr.bike:
				continue
			var dx: float = (cr.x - player_x) * ROAD_W
			var v := near_v(Vector2(c.lanes[cr.lane] - p_z, dx).length(), 5000.0)
			if v > car:
				car = v
				car_pan = clampf(dx / 2500.0, -1.0, 1.0)
	var pi_ := floori(p_z / SEG_LEN)
	for i in range(maxi(0, pi_ - 6), mini(segs.size(), pi_ + 31)):
		var s: Dictionary = segs[i]
		# only tables where somebody is actually sitting (same rule as draw_terrace)
		if not s.terrace or i % 2:
			continue
		var people := 2 if hard else int(seat_rand(i, -1.0) < 0.6) + int(seat_rand(i, 1.0) < 0.6)
		if people:
			chatter = maxf(chatter, near_v(terrace_z(s) - p_z, 4000.0) * (1.0 if people == 2 else 0.7))
	var fire := 0.0
	var fire_pan := 0.0
	for w in wrecks:
		var sg := seg_at(w.z)
		var dx: float = (-sg.side * sg.w * WRECK_LANE - player_x) * ROAD_W
		var v := near_v(Vector2(w.z - p_z, dx).length(), 7000.0) * 1.2
		if v > fire:
			fire = minf(1.0, v)
			fire_pan = clampf(dx / 2500.0, -1.0, 1.0)
	for f in fires:
		var dx: float = (f.x - player_x) * ROAD_W
		var v := near_v(Vector2(f.z - p_z, dx).length(), 5500.0) * (1.0 if f.kind == "bin" else 0.7 * fire_scale(f))
		if v > fire:
			fire = v
			fire_pan = clampf(dx / 2500.0, -1.0, 1.0)
	sfx.ambient({"spray": spray * 0.15, "flies": flies * 0.09, "car": car * 0.5, "car_pan": car_pan,
		"chatter": chatter * 0.45, "fire": fire * 0.14, "fire_pan": fire_pan})


# ======================================================================
# input
# ======================================================================

func _notification(what: int) -> void:
	# switching apps or tabs (or the phone locking) pauses the walk, like the web version
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and state == PLAY \
			and not OS.get_cmdline_user_args().has("--autoplay"):
		toggle_pause()


func jump() -> void:
	if state != PLAY or jump_t > 0.0:
		return
	jump_t = JUMP_TIME
	sfx.play("jump")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if lb.is_open():      # the scoreboard or profile panel is up: Esc closes it, nothing else
		if key and key.pressed and key.physical_keycode == KEY_ESCAPE:
			lb.close_panels()
		return
	if key:
		if key.pressed and not key.echo:
			match key.physical_keycode:
				KEY_P, KEY_ESCAPE:
					toggle_pause()
				KEY_M:
					_toggle_sound()
				KEY_SPACE:
					jump()       # Space never (re)starts a walk, so a late jump can't skip the game-over screen
				KEY_ENTER, KEY_KP_ENTER:
					if state == IDLE or state == OVER:
						start()
		return
	if state != PLAY:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if on_pad(mb.position):
				return
			drag = {"x0": mb.position.x, "cur": mb.position.x, "px": player_x, "y0": mb.position.y,
				"cur_y": mb.position.y, "pace0": pace, "moved": false, "t0": Time.get_ticks_msec()}
		else:
			# a quick tap without dragging is a jump (for phones)
			if not drag.is_empty() and not drag.moved and absf(mb.position.x - drag.x0) < 10.0 					and Time.get_ticks_msec() - drag.t0 < 250:
				jump()
			drag = {}
		return
	var mm := event as InputEventMouseMotion
	if mm and not drag.is_empty():
		drag.cur = mm.position.x
		drag.cur_y = mm.position.y
		if absf(drag.cur_y - drag.y0) > 12.0:
			drag.moved = true      # vertical drag sets the pace


# ======================================================================
# drawing primitives: everything goes into one triangle batch, in paint order
# ======================================================================

func fill(pts: PackedVector2Array, col: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	var c := col
	c.a *= ga
	if c.a <= 0.003:
		return
	var base := _v.size()
	if t_r != 0.0:
		for p in pts:
			_v.append((p * t_s).rotated(t_r) + t_o)
			_c.append(c)
	else:
		for p in pts:
			_v.append(p * t_s + t_o)
			_c.append(c)
	for k in range(1, n - 1):
		_i.append(base)
		_i.append(base + k)
		_i.append(base + k + 1)


func flush() -> void:
	if _i.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _i, _v, _c)
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()


func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	fill(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), col)


func ell(cx: float, cy: float, rx: float, ry: float, col: Color, rot := 0.0, a0 := 0.0, a1 := TAU) -> void:
	if absf(rx) < 0.15 or absf(ry) < 0.05:
		return
	var n := clampi(int(maxf(absf(rx), absf(ry)) * 0.5) + 8, 8, 40)
	var full := a1 - a0 >= TAU - 0.001
	var cnt := n if full else n + 1
	var cr := cos(rot)
	var sr := sin(rot)
	var pts := PackedVector2Array()
	pts.resize(cnt)
	for k in cnt:
		var t := a0 + (a1 - a0) * k / n
		var px := cos(t) * rx
		var py := sin(t) * ry
		pts[k] = Vector2(cx + px * cr - py * sr, cy + px * sr + py * cr)
	fill(pts, col)


func circ(cx: float, cy: float, r: float, col: Color) -> void:
	ell(cx, cy, r, r, col)


func line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var nrm := Vector2(-d.y, d.x) / l * (w * 0.5)
	fill(PackedVector2Array([a + nrm, b + nrm, b - nrm, a - nrm]), col)


func polyline(pts: Array, w: float, col: Color) -> void:
	for k in range(pts.size() - 1):
		line(pts[k], pts[k + 1], w, col)


func ring(cx: float, cy: float, rx: float, ry: float, w: float, col: Color, dashed := false) -> void:
	var n := 36
	for k in n:
		if dashed and k % 2:
			continue
		var t0 := TAU * k / n
		var t1 := TAU * (k + 1) / n
		line(Vector2(cx + cos(t0) * rx, cy + sin(t0) * ry), Vector2(cx + cos(t1) * rx, cy + sin(t1) * ry), w, col)


func qcurve(p0: Vector2, c: Vector2, p1: Vector2, n := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		out.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
	return out


func xf(origin: Vector2, scale := Vector2.ONE, rot := 0.0) -> void:
	t_o = origin
	t_s = scale
	t_r = rot


func xf_reset() -> void:
	t_o = Vector2.ZERO
	t_s = Vector2.ONE
	t_r = 0.0


func text(s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, f: Font = null, outline := 0, outline_col := Color.BLACK) -> void:
	flush()
	var fnt: Font = f if f else font_bold
	var x := pos.x
	var width := -1.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= 400.0
		width = 800.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= 400.0
		width = 400.0
	var c := col
	c.a *= ga
	if outline > 0:
		var oc := outline_col
		oc.a *= ga
		draw_string_outline(fnt, Vector2(x, pos.y), s, align, width, size, outline, oc)
	draw_string(fnt, Vector2(x, pos.y), s, align, width, size, c)


# ======================================================================
# projection
# ======================================================================

func proj(xacc: float, z: float) -> Dictionary:
	var s := CAM_DEPTH / z
	return {"s": s, "x": W / 2.0 + s * (xacc - cam_x) * K2, "y": HORIZON + s * CAM_H * K}


## world (z, lateral road units) → screen; k = pixels per world unit. Empty when off screen.
func to_screen(z: float, xr: float, h := 0.0) -> Dictionary:
	var zr := z - position_z
	if zr < PLAYER_Z * 0.6:
		return {}
	var n := floori(z / SEG_LEN) - base_idx
	if n < 0 or n >= rows.size():
		return {}
	var row: Dictionary = rows[n]
	var f: float = (z - row.zs) / SEG_LEN
	var xacc: float = row.x1 + (row.x2 - row.x1) * f
	var s := CAM_DEPTH / zr
	return {"x": W / 2.0 + s * (xacc + xr * ROAD_W - cam_x) * K2, "y": HORIZON + s * (CAM_H - h) * K,
		"k": s * K2, "flat": minf(0.55, CAM_H / zr * 0.5)}


# ======================================================================
# render
# ======================================================================

func _draw() -> void:
	if segs.is_empty():
		return
	ga = 1.0
	xf_reset()
	var sh := Vector2.ZERO
	if shake > 0.0:
		sh = Vector2(randf() - 0.5, randf() - 0.5) * 8.0
	draw_set_transform(sh)
	draw_sky()
	rect(-10, HORIZON, W + 20, H - HORIZON + 10, C_ASPHALT)

	base_idx = floori(position_z / SEG_LEN)
	gen_more(base_idx + DRAW + 2)
	cam_x = player_x * ROAD_W * 0.7
	var base_pct := fmod(position_z, SEG_LEN) / SEG_LEN
	var x := 0.0
	var dx: float = -(segs[base_idx].curve * base_pct)
	rows = []
	for n in draw_n:
		var i := base_idx + n
		var seg: Dictionary = segs[i]
		var zs := i * SEG_LEN
		var a := proj(x, maxf(zs - position_z, 40.0))
		var b := proj(x + dx, zs + SEG_LEN - position_z)
		a["w"] = a.s * ROAD_W * seg.w * K2
		b["w"] = b.s * ROAD_W * seg.w * K2
		rows.append({"seg": seg, "a": a, "b": b, "zs": zs, "x1": x, "x2": x + dx})
		x += dx
		dx += seg.curve

	# bucket everything drawn on the street by segment, then paint far → near
	var buckets := {}
	var add := func(z: float, fn: Callable) -> void:
		var n := floori(z / SEG_LEN) - base_idx
		if n < 0 or n >= draw_n:
			return
		if not buckets.has(n):
			buckets[n] = []
		buckets[n].append([z, fn])
	for row in rows:
		var s: Dictionary = row.seg
		var zc: float = row.zs + SEG_LEN * 0.5
		var S: float = s.side
		if s.tree:
			add.call(zc, draw_tree.bind(to_screen(zc, -S * s.w * 1.13), s.tree_style))
		if s.lamp:
			add.call(zc + 1, draw_lamp.bind(to_screen(zc + 1, -S * s.w * 1.06)))
		if s.morris:
			add.call(zc + 2, draw_morris.bind(to_screen(zc + 2, -S * s.w * 1.2)))
		if s.kind == "bridge" and s.k % 8 == 4:
			for u in [1.08, -BRIDGE_ROAD]:
				add.call(zc + 3, draw_lamp.bind(to_screen(zc + 3, S * s.w * u)))
		if s.feature == "fountain":
			add.call(zc, draw_fountain.bind(to_screen(zc, S * s.w * 3.2)))
		elif s.feature == "obelisk":
			add.call(zc, draw_obelisk.bind(to_screen(zc, S * s.w * 3.2)))
		if s.terrace and s.i % 2 == 0:
			add.call(terrace_z(s), (draw_looter_group if hard else draw_terrace).bind(to_screen(terrace_z(s), terrace_x(s)), s.i, s.side))
	for tr in trucks:
		if not tr.march:
			add.call(tr.z, draw_cleaner.bind(tr))
			continue
		# the looters: a loose pack running along the curb, spilling into the road, filling the
		# same stretch the cleaner's spray would (so it is dodged the same way)
		for j in 11:
			var zj: float = tr.z + (j - 5) * SPRAY_LEN * 0.17
			var sg := seg_at(zj)
			var xj: float = sg.side * (-sg.w + maxf(0.05, wet_reach(tr, zj)) * (0.25 + 0.6 * seat_rand(tr.seed, j)) - (0.35 if j % 3 == 0 else 0.0))
			var o := {"throwing": 1.0 - tr.throw_t / 0.5} if tr.throw_t > 0.0 and tr.throw_j == j else {}
			add.call(zj, draw_looter.bind(to_screen(zj, xj), tr.seed + j * 7.1, tr.t, false, o))
	for c in cyclists:
		add.call(c.z, draw_cyclist.bind(c))
	for f in fires:
		add.call(f.z, draw_fire.bind(to_screen(f.z, f.x), f))
	for w in wrecks:
		var sg := seg_at(w.z)
		add.call(w.z, draw_wreck.bind(to_screen(w.z, -sg.side * sg.w * WRECK_LANE), w))
	for m in molotovs:
		add.call(m.z, draw_target.bind(to_screen(m.z, m.x), {"t": m.t, "T": m.T, "r": 0.3}))
	for st in stains:
		add.call(st.z, draw_stain.bind(to_screen(st.z, st.x), st.seed))
	for p in poops:
		add.call(p.z, draw_poop.bind(to_screen(p.z, p.x), p))
	for d in drops:
		add.call(d.z, draw_target.bind(to_screen(d.z, d.x), d))
	for d in dogs:
		add.call(d.z, draw_dog.bind(to_screen(d.z, d.x), d))
	for s in peers:
		add.call(s.z, draw_peer.bind(s))
	for c in crossings:
		for car in c.cars:
			var lz: float = c.lanes[car.lane]
			add.call(lz, (draw_bike if car.bike else draw_car).bind(to_screen(lz, car.x), car))

	for n in range(draw_n - 1, -1, -1):
		draw_segment(rows[n])
		if buckets.has(n):
			var list: Array = buckets[n]
			list.sort_custom(func(p, q): return p[0] > q[0])
			for it in list:
				it[1].call()

	draw_player()

	# falling droppings, from the pigeon down to their ground target
	for d in drops:
		var tgt := to_screen(d.z, d.x)
		if tgt.is_empty():
			continue
		var k := minf(d.t / d.T, 1.0)
		var fx: float = d.sx + (tgt.x - d.sx) * k
		var fy: float = d.sy + (tgt.y - d.sy) * k * k
		ell(fx, fy, 4 + k * 3 + 1, 5.5 + k * 4 + 1, Color(0.24, 0.24, 0.24, 0.5))
		ell(fx, fy, 3 + k * 3, 4.5 + k * 4, Color("f4f2ea"))
	for b in birds:
		draw_bird(b)
	for m in molotovs:
		draw_molotov(m)

	for t in texts:
		var tx := player_screen.x
		var ty: float = player_screen.y - player_h * 1.1 - 22 + t.dy
		if t.has("at"):
			var p := to_screen(t.at.z, t.at.x, 700)
			if p.is_empty():
				continue
			tx = p.x
			ty = p.y + t.dy
		ga = clampf(t.life, 0.0, 1.0)
		var small: bool = t.get("small", false)
		text(t.text, Vector2(tx, ty), 14 if small else 22, Color.WHITE if small else Color("f2d27a"),
			HORIZONTAL_ALIGNMENT_CENTER, font_bold, 6, Color("1b1e24"))
		ga = 1.0
	if not plate.is_empty():
		draw_plate()
	if state == PLAY or state == PAUSED:
		draw_pace_gauge()
	if not flash.is_empty():
		rect(-10, -10, W + 20, H + 20, Color(flash.color, flash.color.a * flash.t / 0.35))
	flush()
	draw_set_transform(Vector2.ZERO)
	draw_hud()
	if state == PAUSED:
		rect(-10, -10, W + 20, H + 20, Color(0.106, 0.118, 0.141, 0.55))
		text("일시 정지", Vector2(W / 2, H * 0.45), 34, Color.WHITE)
		text("P 또는 ▶ 버튼으로 계속 걷기", Vector2(W / 2, H * 0.45 + 30), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font)
	flush()


# point on the current segment: f = 0 near … 1 far, u = lateral (±1 sidewalk edge; negative =
# street side, positive = building side, mirrored where the layout is flipped), h = height
func P(f: float, u: float, h := 0.0) -> Vector2:
	var s := _as + (_bs - _as) * f
	var w := _aw + (_bw - _aw) * f
	return Vector2(_ax + (_bx - _ax) * f + w * u * _S, _ay + (_by - _ay) * f - s * h * K)


func quad(col: Color, f0: float, f1: float, u0: float, u1: float, h := 0.0) -> void:
	fill(PackedVector2Array([P(f0, u0, h), P(f1, u0, h), P(f1, u1, h), P(f0, u1, h)]), col)


func wallq(col: Color, f0: float, f1: float, u: float, h0: float, h1: float) -> void:
	fill(PackedVector2Array([P(f0, u, h0), P(f1, u, h0), P(f1, u, h1), P(f0, u, h1)]), col)


func draw_segment(row: Dictionary) -> void:
	var seg: Dictionary = row.seg
	var a: Dictionary = row.a
	var b: Dictionary = row.b
	if b.y >= a.y or a.y < HORIZON:
		return
	_ax = a.x; _ay = a.y; _as = a.s; _aw = a.w
	_bx = b.x; _by = b.y; _bs = b.s; _bw = b.w
	_S = seg.side
	var i: int = seg.i
	var detail: bool = a.y - b.y > 0.6      # far away a segment is under a pixel tall: skip the small stuff

	if seg.kind == "bridge":
		var ripple := Color("5b8297") if i % 3 else Color("668ea2")
		quad(ripple, 0, 1, 1.08, 30)
		quad(ripple, 0, 1, -BRIDGE_ROAD, -30)
	# lane dashes on the street give a sense of speed
	if i % 4 < 2 and not seg.flip_x:
		quad(Color(0.92, 0.91, 0.86, 0.55), 0, 1, -2.35, -2.25)

	if seg.crossing:
		# zebra stripes; curb lips at both ends; a boulevard gets lane markings
		var last: int = seg.cn - 1
		var mid := last >> 1
		if seg.ck >= 1 and seg.ck < last:
			for j in 7:
				var u0 := -0.93 + j * 0.27
				quad(Color("ecebe4"), 0, 1, u0, u0 + 0.15)
		if seg.ck == mid and seg.cn == 5:
			for sd in [-1.0, 1.0]:
				var u := 1.3
				while u < 7.0:
					quad(Color(0.92, 0.91, 0.86, 0.6), 0.42, 0.58, sd * u, sd * (u + 0.45))
					u += 0.9
		if seg.cn > 5 and seg.ck == mid:
			for sd in [-1.0, 1.0]:
				quad(Color(0.92, 0.91, 0.86, 0.7), 0.4, 0.6, sd * 1.2, sd * 9)
		if seg.ck == 0:
			quad(Color("9d968b"), 0.8, 1, -1, 1)
		if seg.ck == last:
			quad(Color("9d968b"), 0, 0.2, -1, 1)
		return
	quad(Color("6f8aa3"), 0, 1, -1.1, -1.06)                                 # gutter water
	quad(Color("9d968b"), 0, 1, -1.06, -1)                                   # curb
	quad(Color("cfc6b8") if floori(i / 2.0) % 2 else Color("c5bbac"), 0, 1, -1, 1)   # sidewalk slabs
	# wet patch along the curb where a street cleaner is spraying: a ragged, tapering inner edge
	# (sampled 6× per segment) with a lighter sheen inside
	for tr in trucks:
		if tr.march or row.zs + SEG_LEN < tr.z - SPRAY_LEN or row.zs > tr.z + SPRAY_LEN:
			continue
		for j in 6:
			var f0 := j / 6.0
			var f1 := (j + 1) / 6.0
			var e0: float = wet_reach(tr, row.zs + f0 * SEG_LEN) / seg.w
			var e1: float = wet_reach(tr, row.zs + f1 * SEG_LEN) / seg.w
			fill(PackedVector2Array([P(f0, -1.1), P(f1, -1.1), P(f1, -1.1 + maxf(0, e1 + 0.1)), P(f0, -1.1 + maxf(0, e0 + 0.1))]), Color(0.24, 0.35, 0.45, 0.36))
			fill(PackedVector2Array([P(f0, -1.1), P(f1, -1.1), P(f1, -1 + e1 * 0.45), P(f0, -1 + e0 * 0.45)]), Color(0.8, 0.87, 0.93, 0.16))
	if detail:
		quad(Color(0.47, 0.42, 0.36, 0.35), 0, 1, -0.34, -0.33)
		quad(Color(0.47, 0.42, 0.36, 0.35), 0, 1, 0.33, 0.34)
	if seg.kind == "bridge":
		quad(Color("b9ae9c"), 0, 1, 1, 1.08)
		wallq(Color("d6ccba"), 0, 1, 1.08, 0, 330)
		wallq(Color("c4b8a4"), 0, 1, 1.08, 330, 380)
		wallq(Color("d6ccba"), 0, 1, -BRIDGE_ROAD, 0, 330)
		wallq(Color("c4b8a4"), 0, 1, -BRIDGE_ROAD, 330, 380)
		if seg.k % 6 == 0:
			for u in [1.08, -BRIDGE_ROAD]:
				wallq(Color("b3a68f"), 0, 0.25, u, 0, 520)
		if seg.k == 0 or seg.k == 37:
			for u in [1.08, -BRIDGE_ROAD]:
				wallq(Color("a89a82"), 0, 1, u, 0, 760)
		return
	if seg.kind == "square":
		quad(Color("d9d0c0"), 0, 1, 1, 40)
		if seg.k % 4 == 0:
			quad(Color(0.55, 0.5, 0.43, 0.3), 0, 0.06, 1, 40)
		for u in [3.0, 8.0]:
			quad(Color(0.55, 0.5, 0.43, 0.3), 0, 1, u, u + 0.04)
		return
	quad(Color("a59b8c"), 0, 1, 1, 1.04)                                    # foot of the wall

	# Haussmann facade: stone wall, shopfront, iron balconies, windows, zinc mansard roof
	var stone: Color = C_STONES[seg.bld % 4]
	wallq(stone, 0, 1, 1.04, 0, WALL_H)
	if detail:
		if seg.shop:
			wallq(Color("3d4752"), 0.12, 0.88, 1.04, 60, 640)
			wallq(C_AWNING[seg.bld % 3], 0, 1, 1.04, 680, 860)
		else:
			wallq(Color("5d4a3a"), 0.3, 0.7, 1.04, 0, 700)
		for fh in [1150.0, 1650.0, 2150.0]:
			wallq(Color("5f6f80"), 0.3, 0.7, 1.04, fh, fh + 360)
		wallq(Color("2a2c30"), 0, 1, 1.04, 1100, 1140)
		wallq(Color("2a2c30"), 0, 1, 1.04, 2100, 2140)
		if i % 7 == 0:
			wallq(Color(0.31, 0.27, 0.24, 0.35), 0, 0.06, 1.04, 0, WALL_H)
	fill(PackedVector2Array([P(0, 1.04, WALL_H), P(1, 1.04, WALL_H), P(1, 1.13, ROOF_H), P(0, 1.13, ROOF_H)]), Color("6f7d8c"))
	# café awning reaching out over the terrace, red and cream stripes
	if seg.terrace:
		fill(PackedVector2Array([P(0, 1.04, 1050), P(1, 1.04, 1050), P(1, 0.66, 860), P(0, 0.66, 860)]),
			Color("e9dfc9") if i % 2 else Color("9b2f2b"))
	if i % 7 == 3:
		fill(PackedVector2Array([P(0.3, 1.1, ROOF_H - 50), P(0.7, 1.1, ROOF_H - 50), P(0.7, 1.1, ROOF_H + 260), P(0.3, 1.1, ROOF_H + 260)]), Color("8a6a55"))
	if hard and detail:
		draw_damage(seg)
	# first building of a block: its corner face looks back at us, so give it a proper front
	if i > 0:
		var prev: Dictionary = segs[i - 1]
		if prev.kind != "street" or prev.side != seg.side:
			draw_corner_face(stone, seg.bld)


func draw_corner_face(stone: Color, bld: int) -> void:
	var face := func(u0: float, u1: float, h0: float, h1: float, col: Color) -> void:
		fill(PackedVector2Array([P(0, u0, h0), P(0, u1, h0), P(0, u1, h1), P(0, u0, h1)]), col)
	var DEEP := 14.0                                                      # reaches well past the edge of the screen
	face.call(1.04, DEEP, 0, WALL_H, stone)
	fill(PackedVector2Array([P(0, 1.04, WALL_H), P(0, DEEP, WALL_H), P(0, DEEP, ROOF_H), P(0, 1.13, ROOF_H)]), Color("6f7d8c"))
	face.call(1.04, DEEP, 1100, 1140, Color("2a2c30"))
	face.call(1.04, DEEP, 2100, 2140, Color("2a2c30"))
	var u := 1.35
	while u < DEEP - 0.5:
		for fh in [1150.0, 1650.0, 2150.0]:
			face.call(u, u + 0.32, fh, fh + 360, Color("5f6f80"))
		face.call(u + 0.05, u + 0.27, ROOF_H - 50, ROOF_H + 260, Color("8a6a55"))
		u += 0.75
	face.call(1.12, 3.2, 60, 640, Color("3d4752"))
	face.call(1.08, 3.3, 680, 860, C_CORNER_AWNING[bld % 3])
	face.call(3.7, 4.3, 0, 760, Color("5d4a3a"))
	face.call(1.04, 1.1, 0, WALL_H, Color(0.31, 0.27, 0.24, 0.3))


# ---------- sky and landmarks ----------

func draw_sky() -> void:
	var top := Color("59555e") if hard else Color("8fb0cf")
	var bot := Color("d99c72") if hard else Color("e4e6e1")
	var base := _v.size()
	for p in [Vector2(-10, -10), Vector2(W + 10, -10), Vector2(W + 10, HORIZON), Vector2(-10, HORIZON)]:
		_v.append(p)
	_c.append_array(PackedColorArray([top, top, bot, bot]))
	_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	# soft clouds drift with the bends
	var cloud := Color(0.43, 0.39, 0.39, 0.5) if hard else Color(1, 1, 1, 0.7)
	for i in 5:
		var cx := fposmod(i * 211 + sky_offset * 0.3, W + 200) - 100
		var cy := HORIZON * (0.15 + (i % 3) * 0.12)
		ell(cx, cy, 46, 12, cloud)
		ell(cx + 26, cy - 7, 28, 11, cloud)
	# the landmark for this stretch grows as you approach and cross-fades to the next
	var i := place_at(dist)
	var prog := fmod(dist, PLACE_LEN) / PLACE_LEN
	var cx := W * 0.5 + clampf(sky_offset, -W * 0.4, W * 0.4)
	var h := H * 0.3 * (0.75 + 0.45 * prog)
	var fade := (prog - 0.88) / 0.12 if prog > 0.88 else 0.0
	ga = 1.0 - fade
	draw_landmark(i, cx, HORIZON + 4, h)
	if fade > 0:
		ga = fade
		draw_landmark((i + 1) % PLACES.size(), cx, HORIZON + 4, H * 0.3 * 0.75)
	ga = 1.0
	xf_reset()
	# distant zinc rooftops with chimney pots, parallax with the bends
	var x := fposmod(sky_offset * 0.6, 1600.0) - 1600.0
	var j := 0
	while x < W + 40:
		var r: Dictionary = ROOFS[j % ROOFS.size()]
		rect(x, HORIZON - r.h, r.w, r.h + 2, Color("9aa6b3"))
		rect(x, HORIZON - r.h, r.w, 4, Color("8693a1"))
		if r.chim:
			rect(x + r.w * 0.3, HORIZON - r.h - 6, 4, 6, Color("a07f6c"))
			rect(x + r.w * 0.65, HORIZON - r.h - 5, 4, 5, Color("a07f6c"))
		x += r.w
		j += 1


func draw_landmark(i: int, cx: float, by: float, h: float) -> void:
	xf(Vector2(cx, by))
	match i:
		0: lm_eiffel(h)
		1: lm_arc(h)
		2: lm_louvre(h)
		3: lm_notre_dame(h)
		4: lm_sacre_coeur(h)
	xf_reset()


func V(x: float, y: float) -> Vector2:
	return Vector2(x, y)


func lm_eiffel(h: float) -> void:
	var c := Color("6e5b4d")
	for sd in [-1.0, 1.0]:      # the legs, curving in to the first platform
		var pts := PackedVector2Array([V(sd * 0.3 * h, 0), V(sd * 0.19 * h, 0)])
		pts.append_array(qcurve(V(sd * 0.19 * h, 0), V(sd * 0.12 * h, -0.17 * h), V(sd * 0.03 * h, -0.3 * h), 6))
		pts.append_array(qcurve(V(sd * 0.11 * h, -0.3 * h), V(sd * 0.16 * h, -0.14 * h), V(sd * 0.3 * h, 0), 6))
		fill(pts, c)
	fill(PackedVector2Array([V(-0.11 * h, -0.3 * h), V(0.11 * h, -0.3 * h), V(0.05 * h, -0.55 * h), V(-0.05 * h, -0.55 * h)]), c)
	fill(PackedVector2Array([V(-0.05 * h, -0.55 * h), V(0.05 * h, -0.55 * h), V(0.018 * h, -0.9 * h), V(0.006 * h, -h), V(-0.006 * h, -h), V(-0.018 * h, -0.9 * h)]), c)
	rect(-0.15 * h, -0.31 * h, 0.3 * h, 0.03 * h, c)
	rect(-0.075 * h, -0.56 * h, 0.15 * h, 0.022 * h, c)
	rect(-0.03 * h, -0.91 * h, 0.06 * h, 0.018 * h, c)
	for k in 6:
		var y0 := -0.32 * h - k * 0.04 * h
		var y1 := y0 - 0.04 * h
		var w0 := 0.1 * h - k * 0.009 * h
		var w1 := w0 - 0.009 * h
		line(V(-w0, y0), V(w1, y1), 1, Color(0.9, 0.86, 0.78, 0.35))
		line(V(w0, y0), V(-w1, y1), 1, Color(0.9, 0.86, 0.78, 0.35))


func lm_arc(h: float) -> void:
	var w := 0.9 * h
	var c := Color("c9bea6")
	rect(-w / 2, -h, w / 2 - 0.17 * h, h, c)
	rect(0.17 * h, -h, w / 2 - 0.17 * h, h, c)
	rect(-0.17 * h, -h, 0.34 * h, 0.35 * h, c)
	for sd in [-1.0, 1.0]:      # the spandrels above the arch
		var pts := PackedVector2Array([V(sd * 0.17 * h, -0.65 * h), V(sd * 0.17 * h, -0.48 * h)])
		for k in 9:
			var t: float = (PI if sd < 0 else 0.0) + (k / 8.0) * PI / 2 * (1.0 if sd < 0 else -1.0)
			pts.append(V(cos(t) * 0.17 * h, -0.48 * h + sin(t) * 0.17 * h))
		fill(pts, c)
	var d := Color("b3a78e")
	rect(-w / 2, -h, w, 0.05 * h, d)
	rect(-w / 2, -0.8 * h, w, 0.03 * h, d)
	rect(-w / 2 - 0.02 * h, -0.86 * h, w + 0.04 * h, 0.03 * h, d)
	rect(-w / 2 + 0.05 * h, -0.55 * h, 0.12 * h, 0.2 * h, d)
	rect(w / 2 - 0.17 * h, -0.55 * h, 0.12 * h, 0.2 * h, d)
	var fw := 0.1 * h / 1.5
	for k in 3:      # tricolour hanging in the arch
		rect((k - 1.5) * fw, -0.6 * h, fw, 0.16 * h, [Color("1d3b6e"), Color("f4f2ea"), Color("c8372d")][k])


func lm_louvre(h: float) -> void:
	var pw := 1.7 * h * 0.55
	rect(-2.2 * h, -0.42 * h, 4.4 * h, 0.42 * h, Color("d8ccb3"))
	rect(-2.2 * h, -0.5 * h, 4.4 * h, 0.08 * h, Color("7f8b99"))
	for px in [-1.9, -0.9, 0.9, 1.9]:
		rect((px - 0.18) * h, -0.62 * h, 0.36 * h, 0.2 * h, Color("7f8b99"))
	var x := -2.1
	while x < 2.2:
		rect(x * h, -0.34 * h, 0.06 * h, 0.1 * h, Color("9c917c"))
		rect(x * h, -0.18 * h, 0.06 * h, 0.1 * h, Color("9c917c"))
		x += 0.16
	fill(PackedVector2Array([V(-pw, 0), V(0, -0.6 * h), V(pw, 0)]), Color(0.66, 0.76, 0.84, 0.95))
	for k in range(1, 7):
		var t := k / 7.0
		line(V(-pw * (1 - t), -0.6 * h * t), V(pw * (1 - t), -0.6 * h * t), 1, Color(0.31, 0.39, 0.47, 0.6))
		line(V(-pw + 2 * pw * t, 0), V(0, -0.6 * h), 1, Color(0.31, 0.39, 0.47, 0.6))


func lm_notre_dame(h: float) -> void:
	var w := 0.8 * h
	var c := Color("c4b89f")
	var d := Color("7d715d")
	rect(-0.012 * h, -1.25 * h, 0.024 * h, 0.6 * h, Color("a99c84"))
	rect(-w / 2, -0.7 * h, w, 0.7 * h, c)
	rect(-w / 2, -h, 0.3 * w, 0.32 * h, c)
	rect(w / 2 - 0.3 * w, -h, 0.3 * w, 0.32 * h, c)
	circ(0, -0.5 * h, 0.11 * h, d)
	circ(0, -0.5 * h, 0.075 * h, Color("a7b8c9"))
	for px in [-0.28, 0.0, 0.28]:
		rect((px - 0.08) * h, -0.16 * h, 0.16 * h, 0.16 * h, d)
		ell(px * h, -0.16 * h, 0.08 * h, 0.08 * h, d, 0, PI, TAU)
	rect(-w / 2, -0.7 * h, w, 0.025 * h, d)
	var x := -w / 2 + 0.04 * h
	while x < w / 2 - 0.03 * h:
		rect(x, -0.66 * h, 0.025 * h, 0.06 * h, d)
		x += 0.06 * h
	for sd in [-1.0, 1.0]:
		for k in 2:
			rect(sd * w * 0.35 - 0.02 * h + k * 0.06 * h * sd, -0.95 * h, 0.03 * h, 0.17 * h, d)


func lm_sacre_coeur(h: float) -> void:
	fill(qcurve(V(-1.4 * h, 0), V(0, -0.62 * h), V(1.4 * h, 0), 16), Color("7f9a6e"))
	var o := t_o
	t_o = o + V(0, -0.3 * h)
	var c := Color("f2efe6")
	rect(-0.42 * h, -0.28 * h, 0.84 * h, 0.3 * h, c)
	ell(0, -0.28 * h, 0.2 * h, 0.3 * h, c, 0, PI, TAU)
	rect(-0.2 * h, -0.36 * h, 0.4 * h, 0.08 * h, c)
	rect(-0.025 * h, -0.66 * h, 0.05 * h, 0.1 * h, c)
	ell(0, -0.66 * h, 0.04 * h, 0.06 * h, c, 0, PI, TAU)
	for sd in [-1.0, 1.0]:
		rect(sd * 0.31 * h - 0.06 * h, -0.4 * h, 0.12 * h, 0.12 * h, c)
		ell(sd * 0.31 * h, -0.4 * h, 0.06 * h, 0.1 * h, c, 0, PI, TAU)
	rect(0.5 * h, -0.62 * h, 0.1 * h, 0.64 * h, c)
	fill(PackedVector2Array([V(0.5 * h, -0.62 * h), V(0.55 * h, -0.74 * h), V(0.6 * h, -0.62 * h)]), c)
	for px in [-0.3, -0.1, 0.1, 0.3]:
		rect(px * h - 0.02 * h, -0.22 * h, 0.04 * h, 0.1 * h, Color(0.59, 0.63, 0.67, 0.5))
	t_o = o


# ---------- street furniture ----------

func draw_tree(p: Dictionary, style: String) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	rect(x - 160 * k, y - 14 * k, 320 * k, 28 * k, Color("5b5e63"))
	rect(x - 30 * k, y - 1300 * k, 60 * k, 1300 * k, Color("7a6a58"))
	if style != "round":
		# clipped crown: a square, or a tall upright rectangle
		var hw := 460.0 if style == "square" else 340.0
		var top := 2150.0 if style == "square" else 2600.0
		var x0 := x - hw * k
		var w := 2 * hw * k
		var y0 := y - top * k
		var hh := (top - 1250.0) * k
		rect(x0, y0, w, hh, Color("5f7f4e"))
		rect(x0, y0 + hh * 0.84, w, hh * 0.16, Color("4f6d41"))
		rect(x0, y0, w, hh * 0.1, Color("7a9a62"))
		return
	circ(x, y - 1650 * k, 520 * k, Color("5f7f4e"))
	circ(x - 200 * k, y - 1800 * k, 320 * k, Color("6f9159"))
	circ(x + 220 * k, y - 1550 * k, 300 * k, Color("6f9159"))


func draw_lamp(p: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	var c := Color("25382f")
	rect(x - 18 * k, y - 1500 * k, 36 * k, 1500 * k, c)
	rect(x - 45 * k, y - 120 * k, 90 * k, 120 * k, c)
	fill(PackedVector2Array([V(x - 70 * k, y - 1500 * k), V(x + 70 * k, y - 1500 * k), V(x + 45 * k, y - 1720 * k), V(x - 45 * k, y - 1720 * k)]), c)
	rect(x - 40 * k, y - 1690 * k, 80 * k, 160 * k, Color("f2e3a6"))


func draw_morris(p: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	rect(x - 170 * k, y - 1200 * k, 340 * k, 1200 * k, Color("2f5d46"))
	rect(x - 150 * k, y - 1050 * k, 300 * k, 750 * k, Color("e8d9b8"))
	rect(x - 120 * k, y - 1000 * k, 110 * k, 300 * k, Color("c8372d"))
	rect(x + 10 * k, y - 800 * k, 110 * k, 380 * k, Color("1d3b6e"))
	ell(x, y - 1200 * k, 200 * k, 160 * k, Color("2f5d46"), 0, PI, TAU)


func draw_fountain(p: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	ell(x, y, 900 * k, 900 * k * p.flat, Color(0, 0, 0, 0.18))
	rect(x - 850 * k, y - 260 * k, 1700 * k, 260 * k, Color("bfb39f"))
	ell(x, y - 260 * k, 850 * k, 120 * k, Color("6f9ab3"))
	rect(x - 70 * k, y - 1100 * k, 140 * k, 850 * k, Color("a99c86"))
	for tier in [[700.0, 420.0], [1100.0, 230.0]]:
		ell(x, y - tier[0] * k, tier[1] * k, tier[1] * 0.28 * k, Color("c9bea9"))
		for sd in [-1.0, 1.0]:
			polyline(Array(qcurve(V(x + sd * tier[1] * k, y - tier[0] * k), V(x + sd * tier[1] * 1.25 * k, y - (tier[0] - 150) * k),
				V(x + sd * tier[1] * 1.3 * k, y - (tier[0] - 380) * k), 6)), maxf(1, 18 * k), Color(0.84, 0.91, 0.96, 0.75))
	line(V(x, y - 1100 * k), V(x, y - (1500 + sin(step * 0.7) * 40) * k), maxf(1, 26 * k), Color(0.9, 0.95, 0.98, 0.85))


func draw_obelisk(p: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	ell(x, y, 600 * k, 600 * k * p.flat, Color(0, 0, 0, 0.18))
	rect(x - 420 * k, y - 300 * k, 840 * k, 300 * k, Color("9a8e7c"))
	rect(x - 300 * k, y - 1100 * k, 600 * k, 800 * k, Color("b3a690"))
	fill(PackedVector2Array([V(x - 190 * k, y - 1100 * k), V(x + 190 * k, y - 1100 * k), V(x + 120 * k, y - 5200 * k), V(x, y - 5550 * k), V(x - 120 * k, y - 5200 * k)]), Color("c99a86"))
	fill(PackedVector2Array([V(x - 120 * k, y - 5200 * k), V(x + 120 * k, y - 5200 * k), V(x, y - 5550 * k)]), Color("e2b84a"))
	for j in 6:
		rect(x - 40 * k, y - (1500 + j * 600) * k, 80 * k, 300 * k, Color(0.43, 0.31, 0.27, 0.35))


## bistro table with a coffee cup and two rattan chairs (the sitters come later)
## café guest seen from the side, facing the table (f = +1 right, -1 left), sipping now and then
func draw_sitter(cx: float, y: float, k: float, f: float, r: float, sd: float) -> void:
	var coat: Color = C_SITTER_COATS[int(r * 97) % C_SITTER_COATS.size()]
	var hair: Color = C_SITTER_HAIR[int(r * 53) % C_SITTER_HAIR.size()]
	var beret := int(r * 31) % 3 == 0
	var sip := sin(step * 0.18 + sd * 1.7 + f) > 0.55      # raises the cup every few seconds
	# legs: thigh along the seat, shin down to the floor
	rect(minf(cx, cx + f * 190 * k), y - 520 * k, 190 * k, 60 * k, Color("2d3138"))
	rect(cx + f * 160 * k - 28 * k, y - 480 * k, 56 * k, 470 * k, Color("2d3138"))
	rect(cx + f * 160 * k - 30 * k + (0.0 if f > 0 else -30 * k), y - 30 * k, 90 * k, 30 * k, Color("3a2416"))
	# torso and head
	rect(cx - f * 15 * k - 65 * k, y - 920 * k, 130 * k, 420 * k, coat)
	circ(cx + f * 5 * k, y - 1000 * k, 72 * k, Color("e8b98f"))
	ell(cx - f * 8 * k, y - 1015 * k, 70 * k, 70 * k, hair, 0, PI, TAU)
	if beret:
		ell(cx, y - 1068 * k, 85 * k, 30 * k, Color("1b1e24"), -f * 0.2)
	# arm with the cup: at the lips when sipping, otherwise resting by the table
	var sx := cx + f * 20 * k
	var sy := y - 860 * k
	var hx := cx + f * 95 * k if sip else cx + f * 230 * k
	var hy := y - 975 * k if sip else y - 730 * k
	var ex := cx + f * 140 * k if sip else cx + f * 150 * k
	var ey := y - 820 * k if sip else y - 720 * k
	polyline([V(sx, sy), V(ex, ey), V(hx, hy)], maxf(1.5, 42 * k), coat)
	rect(hx - 24 * k, hy - 50 * k, 48 * k, 55 * k, Color.WHITE)
	rect(hx - 20 * k, hy - 50 * k, 40 * k, 10 * k, Color("5b3a24"))
	if not sip and k > 0.05:      # a wisp of steam
		var pts := []
		for j in 6:
			pts.append(V(hx + sin(step * 0.3 + j) * 12 * k, hy - 60 * k - j * 22 * k))
		polyline(pts, maxf(1, 10 * k), Color(1, 1, 1, 0.6))


## bistro table with a coffee cup and two rattan chairs; about 6 in 10 chairs have someone
## having a coffee (the same people stay at the same tables)
func draw_terrace(p: Dictionary, seat_seed: int, _side: int) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	var cw := 0.13 * ROAD_W * k
	ell(x, y, TERRACE_HALF * ROAD_W * k, TERRACE_HALF * ROAD_W * k * p.flat, Color(0, 0, 0, 0.18))
	for sd in [-1.0, 1.0]:
		var cx: float = x + sd * cw
		rect(cx - 40 * k, y - 450 * k, 80 * k, 450 * k, Color("7a5532"))
		rect(cx - 70 * k, y - 470 * k, 140 * k, 40 * k, Color("a77b4f"))
		# chair back on the far side from the table, so a sitter faces the table
		rect(cx + sd * 60 * k - 10 * k, y - 860 * k, 20 * k, 400 * k, Color("2f5d46") if seat_seed % 4 == 0 else Color("9b2f2b"))
		circ(cx + sd * 60 * k, y - 880 * k, 25 * k, Color("c99d6a"))
		var r := seat_rand(seat_seed, sd)
		if r < 0.6:
			draw_sitter(cx, y, k, -sd, r, seat_seed)
	rect(x - 18 * k, y - 680 * k, 36 * k, 680 * k, Color("3a3a3a"))
	rect(x - 90 * k, y - 20 * k, 180 * k, 20 * k, Color("3a3a3a"))
	ell(x, y - 690 * k, 170 * k, 45 * k, Color("efece4"))
	rect(x + 30 * k, y - 760 * k, 45 * k, 60 * k, Color.WHITE)
	rect(x + 33 * k, y - 760 * k, 39 * k, 10 * k, Color("5b3a24"))


# ---------- hazards ----------

func draw_stain(p: Dictionary, stain_seed: float) -> void:
	if p.is_empty():
		return
	var r: float = 55 * p.k
	var c := Color("f4f2ea")
	ell(p.x, p.y, r, r * p.flat, c)
	for i in 4:
		var a := stain_seed + i * 1.7
		ell(p.x + cos(a) * r * 1.4, p.y + sin(a) * r * p.flat * 1.4, r * 0.3, r * 0.3 * p.flat, c)


func draw_puddle(p: Dictionary, rr: float) -> void:
	if p.is_empty():
		return
	var r: float = rr * ROAD_W * p.k
	var f: float = p.flat
	var lobes := [[0.0, 0.0, 1.0, 1.0], [0.5, 0.25, 0.6, 0.7], [-0.55, 0.15, 0.55, 0.65], [0.15, -0.35, 0.5, 0.55]]
	for l in lobes:
		ell(p.x + l[0] * r, p.y + l[1] * r * f, l[2] * r + 1.5, l[3] * r * f + 1.5, Color(0.69, 0.54, 0.12, 0.35))
	for l in lobes:
		ell(p.x + l[0] * r, p.y + l[1] * r * f, l[2] * r, l[3] * r * f, Color(0.91, 0.78, 0.29, 0.62))
	ell(p.x - r * 0.3, p.y - r * f * 0.2, r * 0.3, r * f * 0.12, Color(1, 1, 0.94, 0.5))


func draw_poop(p: Dictionary, o: Dictionary) -> void:
	if p.is_empty():
		return
	if o.kind == "pee":
		draw_puddle(p, o.r)
		return
	var x: float = p.x
	var y: float = p.y
	var R: float = o.r * ROAD_W * p.k
	var HR: float = hit_radius(o) * ROAD_W * p.k
	if o.flies > 0:
		ell(x, y, HR, HR * p.flat, Color(0.16, 0.16, 0.12, 0.12 * o.flies))
		ring(x, y, HR, HR * p.flat, 1, Color(0.16, 0.16, 0.12, 0.4 * o.flies), true)
	ell(x, y, R * 1.15, R * 1.15 * p.flat, Color(0, 0, 0, 0.2))
	var base := Color("5a361a") if o.fresh else Color("6b4423")
	for t in [[0.0, 1.0, 0.5], [-0.42, 0.75, 0.42], [-0.78, 0.45, 0.36]]:
		ell(x, y - R * 0.3 + t[0] * R, t[1] * R, t[2] * R, base)
		ell(x - t[1] * R * 0.3, y - R * 0.3 + t[0] * R - t[2] * R * 0.3, t[1] * R * 0.35, t[2] * R * 0.3, Color(1, 0.86, 0.7, 0.2))
	if o.fresh and R > 3:      # steam
		for i in range(-1, 2):
			var pts := []
			for k in 10:
				pts.append(V(x + i * R * 0.4 + sin(o.steam + k * 0.6 + i) * R * 0.2, y - R * 1.3 - k * R * 0.18))
			polyline(pts, maxf(1, R * 0.08), Color(1, 1, 1, 0.6))
	if o.flies > 0:
		var arrive: float = 1.0 - o.flies
		var fs := maxf(1.2, R * 0.16)
		for i in 6:
			var a: float = o.steam * (1.4 + (i % 3) * 0.5) + i * PI / 3
			var rr: float = HR * (0.5 + 0.45 * absf(sin(a * 1.7 + i))) + arrive * 80
			var fx: float = x + cos(a) * rr
			var fy: float = y - R * (0.8 + (i % 3) * 0.5) + sin(a) * rr * p.flat
			ell(fx - fs * 0.8, fy - fs * 0.8, fs * 1.1, fs * 0.55, Color(0.86, 0.9, 0.94, 0.8), 0.6)
			ell(fx + fs * 0.8, fy - fs * 0.8, fs * 1.1, fs * 0.55, Color(0.86, 0.9, 0.94, 0.8), -0.6)
			circ(fx, fy, fs, Color("1b1e24"))


func draw_target(p: Dictionary, d: Dictionary) -> void:
	if p.is_empty():
		return
	var k := minf(d.t / d.T, 1.0)
	var R: float = d.r * ROAD_W * p.k
	ell(p.x, p.y, R * (0.35 + k * 0.6), R * (0.35 + k * 0.6) * p.flat, Color(0, 0, 0, 0.08 + k * 0.22))
	ring(p.x, p.y, R, R * p.flat, 2, Color(0.78, 0.22, 0.18, 0.4 + k * 0.5), true)


## dog seen from the side, trotting across the sidewalk
func draw_dog(p: Dictionary, d: Dictionary) -> void:
	if p.is_empty():
		return
	var L: float = 300 * d.size * p.k
	xf(V(p.x, p.y), V(d.dir, 1))
	ell(0, 0, L * 0.6, L * 0.6 * p.flat, Color(0, 0, 0, 0.18))
	var sniff: bool = d.state == "sniff"
	var sw: float = 0.0 if sniff else sin(d.leg) * L * 0.1
	var c: Color = d.color
	for lg in [[-0.3, sw], [-0.22, -sw], [0.28, -sw], [0.36, sw]]:
		line(V(lg[0] * L, -0.38 * L), V(lg[0] * L + lg[1], 0), maxf(1.5, L * 0.08), c)
	ell(0, -0.48 * L, 0.45 * L, 0.17 * L, c)
	var hy := -0.3 * L if sniff else -0.68 * L
	ell(0.5 * L, hy, 0.16 * L, 0.13 * L, c, 0.6 if sniff else -0.2)
	ell(0.64 * L, hy + 0.04 * L, 0.09 * L, 0.06 * L, c)
	ell(0.44 * L, hy - 0.06 * L, 0.06 * L, 0.11 * L, Color(0, 0, 0, 0.35), 0.4)
	circ(0.72 * L, hy + 0.03 * L, maxf(1, 0.03 * L), Color("1b1e24"))
	var wag: float = sin(d.t * 25) * 0.12 * L if sniff else sin(d.leg * 1.5) * 0.06 * L
	line(V(-0.42 * L, -0.55 * L), V(-0.6 * L, -0.75 * L + wag), maxf(1.2, L * 0.05), c)
	xf_reset()


func draw_peer(s: Dictionary) -> void:
	var p := to_screen(s.z, s.x)
	if p.is_empty():
		return
	if not s.done:
		draw_puddle(to_screen(s.z, s.side * (seg_at(s.z).w - 0.15)), 0.2 * (0.25 + 0.75 * minf(s.t / s.T, 1.0)))
	var Hh: float = 560 * p.k
	var face: float = s.side
	xf(V(p.x, p.y))
	if s.done:
		ga = maxf(0.0, 1.0 - s.leave / 2.5)
	ell(0, 0, Hh * 0.22, Hh * 0.22 * p.flat, Color(0, 0, 0, 0.2))
	var walk: float = sin(s.leave * 10) * Hh * 0.04 if s.done else 0.0
	rect(-Hh * 0.08 + walk, -Hh * 0.42, Hh * 0.07, Hh * 0.42, Color("2d3748"))
	rect(Hh * 0.01 - walk, -Hh * 0.42, Hh * 0.07, Hh * 0.42, Color("2d3748"))
	fill(PackedVector2Array([V(-Hh * 0.13, -Hh * 0.82), V(Hh * 0.13, -Hh * 0.82), V(Hh * 0.16, -Hh * 0.38), V(-Hh * 0.16, -Hh * 0.38)]), s.coat)
	if not s.done:
		rect(Hh * 0.08 if face > 0 else -Hh * 0.2, -Hh * 0.62, Hh * 0.12, Hh * 0.06, s.coat)
	circ(face * Hh * 0.02, -Hh * 0.9, Hh * 0.08, Color("e8b98f"))
	ell(face * Hh * 0.01, -Hh * 0.96, Hh * 0.09, Hh * 0.04, Color("8c2a2a"))
	if not s.done:
		var wob: float = sin(s.t * 25 + s.bob) * Hh * 0.01
		polyline(Array(qcurve(V(face * Hh * 0.12, -Hh * 0.45), V(face * Hh * 0.3, -Hh * 0.4 + wob), V(face * Hh * 0.32, -Hh * 0.02), 8)),
			maxf(1, Hh * 0.012), Color(0.91, 0.78, 0.29, 0.9))
	ga = 1.0
	xf_reset()


## car crossing the zebra crossing, seen from the side
func draw_car(p: Dictionary, car: Dictionary) -> void:
	if p.is_empty():
		return
	var L: float = car.len * ROAD_W * p.k
	xf(V(p.x, p.y), V(car.dir, 1))
	ell(0, 0, L * 0.55, L * 0.55 * p.flat * 0.5, Color(0, 0, 0, 0.25))
	rect(-L / 2, -0.3 * L, L, 0.2 * L, car.color)
	fill(PackedVector2Array([V(-0.3 * L, -0.3 * L), V(-0.2 * L, -0.47 * L), V(0.18 * L, -0.47 * L), V(0.3 * L, -0.3 * L)]), car.color)
	var glass := Color(0.63, 0.75, 0.82, 0.9)
	fill(PackedVector2Array([V(-0.26 * L, -0.31 * L), V(-0.18 * L, -0.44 * L), V(-0.02 * L, -0.44 * L), V(-0.02 * L, -0.31 * L)]), glass)
	fill(PackedVector2Array([V(0.02 * L, -0.31 * L), V(0.02 * L, -0.44 * L), V(0.16 * L, -0.44 * L), V(0.26 * L, -0.31 * L)]), glass)
	for wx in [-0.3, 0.3]:
		circ(wx * L, -0.1 * L, 0.09 * L, Color("1b1e24"))
		circ(wx * L, -0.1 * L, 0.04 * L, Color("9a9ea6"))
	rect(0.47 * L, -0.26 * L, 0.03 * L, 0.05 * L, Color("f7e7a0"))
	xf_reset()


func draw_rider_head(x: float, y: float, r: float, head: String, face := true) -> void:
	circ(x, y, r, Color("e8b98f"))
	if head == "helmet":
		ell(x, y - r * 0.3, r * 1.15, r * 0.85, Color("e8e4d8"), 0, PI, TAU)
	elif head == "beret":
		ell(x + r * 0.2, y - r * 0.75, r * 1.1, r * 0.45, Color("1b1e24"), -0.15)
	else:
		if face:
			ell(x, y, r * 1.02, r * 1.02, Color(head), 0, PI * 1.05, PI * 1.95)
		else:      # from behind there is no face, only hair
			circ(x, y, r * 1.02, Color(head))


## cyclist on the street beside the sidewalk, seen from the front (oncoming) or from behind
func draw_cyclist(c: Dictionary) -> void:
	var seg := seg_at(c.z)
	var p := to_screen(c.z, -c.side * seg.w * c.lane)
	if p.is_empty():
		return
	var Hh: float = 470 * p.k
	var lw := maxf(1, Hh * 0.05)
	var pedal: float = sin(c.ph)
	xf(V(p.x, p.y))
	if seg.flip_x:
		ga = maxf(0.0, 1.0 - (seg.ck + 1.0) / seg.cn)      # turning off where the street ends
	ell(0, 0, Hh * 0.14, Hh * 0.14 * p.flat, Color(0, 0, 0, 0.2))
	rect(-Hh * 0.025, -Hh * 0.4, Hh * 0.05, Hh * 0.4, Color("1b1e24"))      # tyre, end-on
	rect(-Hh * 0.04, -Hh * 0.44, Hh * 0.08, Hh * 0.08, c.color)             # mudguard and frame
	for sd in [-1.0, 1.0]:                                                   # legs pumping
		var foot: float = -Hh * (0.2 + 0.09 * pedal * sd)
		polyline([V(sd * Hh * 0.06, -Hh * 0.56), V(sd * Hh * 0.11, (foot - Hh * 0.56) / 2 - Hh * 0.04), V(sd * Hh * 0.05, foot)], lw * 1.4, Color("2d3748"))
	fill(PackedVector2Array([V(-Hh * 0.1, -Hh * 0.55), V(Hh * 0.1, -Hh * 0.55), V(Hh * 0.13, -Hh * 0.86), V(-Hh * 0.13, -Hh * 0.86)]), c.coat)
	for sd in [-1.0, 1.0]:                                                   # arms down to the handlebar
		line(V(sd * Hh * 0.12, -Hh * 0.83), V(sd * Hh * 0.17, -Hh * 0.68), lw, c.coat)
	line(V(-Hh * 0.18, -Hh * 0.67), V(Hh * 0.18, -Hh * 0.67), lw * 0.6, Color("4a4f57"))
	if c.toward and c.basket:
		rect(-Hh * 0.09, -Hh * 0.64, Hh * 0.18, Hh * 0.1, Color("9a7448"))
	if c.throw_t > 0.0:                                                      # follow-through of a throw toward the pavement
		var u: float = 1.0 - c.throw_t / 0.5
		line(V(c.side * Hh * 0.12, -Hh * 0.83), V(c.side * Hh * (0.22 + 0.12 * u), -Hh * (1.12 - 0.2 * u)), lw * 1.1, c.coat)
	draw_rider_head(0, -Hh * 0.95, Hh * 0.08, c.head, c.toward)
	ga = 1.0
	xf_reset()


## bike crossing the zebra crossing, seen from the side, pedals going round
func draw_bike(p: Dictionary, b: Dictionary) -> void:
	if p.is_empty():
		return
	var L: float = b.len * ROAD_W * p.k
	var lw := maxf(1, L * 0.028)
	var R := 0.17 * L
	xf(V(p.x, p.y), V(b.dir, 1))
	ell(0, 0, L * 0.5, L * 0.5 * p.flat * 0.4, Color(0, 0, 0, 0.22))
	for wx in [-0.32, 0.32]:
		ring(wx * L, -R, R, R, lw, Color("1b1e24"))
	var Q := func(x: float, y: float) -> Vector2: return V(x * L, y * L)
	var rear: Vector2 = Q.call(-0.32, -0.17)
	var bb: Vector2 = Q.call(0, -0.17)
	var seat: Vector2 = Q.call(-0.1, -0.45)
	var head: Vector2 = Q.call(0.22, -0.47)
	var front: Vector2 = Q.call(0.32, -0.17)
	var bar: Vector2 = Q.call(0.24, -0.56)
	polyline([rear, bb, seat, rear], lw * 1.3, b.color)
	polyline([seat, head, bb], lw * 1.3, b.color)
	polyline([head, front], lw * 1.3, b.color)
	polyline([head, bar, Q.call(0.19, -0.57)], lw, Color("4a4f57"))
	var hip: Vector2 = Q.call(-0.1, -0.5)
	var shoulder: Vector2 = Q.call(0.07, -0.85)
	var crank := 0.08 * L
	for ph in [b.ph, b.ph + PI]:
		var foot := V(cos(ph) * crank, -0.17 * L + sin(ph) * crank)
		var knee := V((hip.x + foot.x) / 2 + 0.1 * L, (hip.y + foot.y) / 2 - 0.04 * L)
		polyline([hip, knee, foot], lw * 2.2, Color("2d3748"))
	fill(PackedVector2Array([V(hip.x - 0.06 * L, hip.y), V(hip.x + 0.06 * L, hip.y + 0.02 * L), V(shoulder.x + 0.06 * L, shoulder.y), V(shoulder.x - 0.07 * L, shoulder.y - 0.02 * L)]), b.coat)
	polyline([shoulder, Q.call(0.17, -0.7), bar], lw * 1.6, b.coat)
	draw_rider_head(shoulder.x + 0.04 * L, shoulder.y - 0.11 * L, 0.075 * L, b.head)
	xf_reset()


func draw_bird(b: Dictionary) -> void:
	var s := maxf(0.8, H / 600.0)
	xf(V(b.x, b.y), V(signf(b.vx) * s, s))
	var w: float = sin(b.flap) * 10
	fill(PackedVector2Array([V(-4, -2), V(4, -2), V(-2, -12 - w)]), Color("7f8794"))
	ell(0, 0, 11, 5, Color("9aa2ad"))
	circ(10, -2, 4, Color("4f7a6a"))
	fill(PackedVector2Array([V(13, -2.5), V(17, -1.5), V(13, -0.5)]), Color("c88a5a"))
	fill(PackedVector2Array([V(-10, 0), V(-17, -3), V(-17, 3)]), Color("5c6b74"))
	fill(PackedVector2Array([V(-4, 1), V(4, 1), V(-1, 10 + w * 0.6)]), Color("7f8794"))
	xf_reset()


# ---------- hard mode: fire, Molotovs, burning cars, damaged buildings, looters ----------

## one licking flame: a teardrop that sways, orange outside and yellow inside
func flame(x: float, y: float, w: float, h: float, ph: float) -> void:
	var sway := sin(ph) * w * 0.35
	var hh := h * (0.85 + 0.15 * sin(ph * 1.7))
	var outer := qcurve(V(x - w / 2, y), V(x - w * 0.55, y - hh * 0.55), V(x + sway, y - hh), 6)
	outer.append_array(qcurve(V(x + sway, y - hh), V(x + w * 0.55, y - hh * 0.55), V(x + w / 2, y), 6))
	fill(outer, Color(0.93, 0.41, 0.13, 0.9))
	var inner := qcurve(V(x - w * 0.25, y), V(x - w * 0.28, y - hh * 0.35), V(x + sway * 0.6, y - hh * 0.6), 5)
	inner.append_array(qcurve(V(x + sway * 0.6, y - hh * 0.6), V(x + w * 0.28, y - hh * 0.35), V(x + w * 0.25, y), 5))
	fill(inner, Color(1.0, 0.84, 0.35, 0.95))


## burning car parked by the curb, seen from behind: scorched paint, blown-out rear window,
## flames pouring out of the cabin and a thick column of black smoke
func draw_wreck(p: Dictionary, w: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	var t: float = w.t
	var sd: float = w.seed
	var hw := 230 * k
	var H0 := 170 * k
	var H1 := 380 * k
	ell(x, y, 700 * k, 700 * k * p.flat, Color(1, 0.51, 0.16, 0.22))
	for j in 6:      # black smoke billowing up and leaning away
		var u := fposmod(t * 0.25 + j / 6.0, 1.0)
		circ(x + sin(u * 2.5 + sd) * 160 * k + u * 380 * k, y - (450 + u * 2600) * k, (200 + u * 520) * k, Color(0.14, 0.13, 0.13, 0.55 * (1 - u)))
	ell(x, y, hw * 1.1, hw * 1.1 * p.flat * 0.6, Color(0, 0, 0, 0.3))
	rect(x - hw * 0.95, y - 90 * k, hw * 0.32, 90 * k, Color("141414"))      # tyres
	rect(x + hw * 0.63, y - 90 * k, hw * 0.32, 90 * k, Color("141414"))
	rect(x - hw, y - H0 - 40 * k, hw * 2, H0 - 30 * k, w.color)             # what's left of the paint
	rect(x - hw, y - H0 - 40 * k, hw * 2, (H0 - 30 * k) * 0.6, Color(0.12, 0.1, 0.09, 0.75))
	fill(PackedVector2Array([V(x - hw * 0.92, y - H0 - 40 * k), V(x - hw * 0.7, y - H1), V(x + hw * 0.7, y - H1), V(x + hw * 0.92, y - H0 - 40 * k)]), Color("2a2523"))
	fill(PackedVector2Array([V(x - hw * 0.78, y - H0 - 55 * k), V(x - hw * 0.62, y - H1 + 20 * k), V(x + hw * 0.62, y - H1 + 20 * k), V(x + hw * 0.78, y - H0 - 55 * k)]), Color(1, 0.59, 0.2, 0.85))
	rect(x - hw * 0.95, y - H0 - 20 * k, hw * 0.2, 30 * k, Color("7a1a14"))  # dead tail lights
	rect(x + hw * 0.75, y - H0 - 20 * k, hw * 0.2, 30 * k, Color("7a1a14"))
	for j in 6:
		flame(x + (j - 2.5) * hw * 0.3, y - H1 + 30 * k, 130 * k, (420 + 160 * sin(j * 1.7 + sd)) * k, t * 8 + j * 1.4 + sd)
	flame(x + hw * 0.55, y - H0, 110 * k, 260 * k, t * 11 + sd)


## burning bin (the green Paris litter bin) or heap of rubbish, or a patch of fire left by a Molotov
func draw_fire(p: Dictionary, f: Dictionary) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	var t: float = f.t
	var sd: float = f.seed
	if f.kind == "bin":
		ell(x, y, 420 * k, 420 * k * p.flat, Color(1, 0.55, 0.16, 0.22))   # glow on the pavement
		for j in 4:      # smoke rising and drifting
			var u := fposmod(t * 0.35 + j / 4.0, 1.0)
			circ(x + sin(u * 3 + sd) * 120 * k + u * 160 * k, y - (700 + u * 1500) * k, (130 + u * 260) * k, Color(0.27, 0.26, 0.26, 0.45 * (1 - u)))
		if f.pile:       # a heap of bags and boxes
			var blob := func(dx: float, dy: float, rx: float, ry: float, c: Color) -> void:
				ell(x + dx * k, y + dy * k, rx * k, ry * k, c)
			blob.call(-120, -80, 140, 95, Color("1e2522"))
			blob.call(115, -75, 130, 90, Color("2f5d46"))
			blob.call(0, -60, 150, 80, Color("2a2c30"))
			xf(V(x - 40 * k, y - 190 * k), Vector2.ONE, -0.35 + 0.2 * sin(sd))
			rect(-90 * k, -70 * k, 180 * k, 140 * k, Color("b48a5a"))
			rect(-90 * k, -10 * k, 180 * k, 14 * k, Color("8a6a48"))
			xf_reset()
			blob.call(80, -200, 110, 85, Color("3a4440"))
			blob.call(-10, -280, 90, 70, Color("1e2522"))
			rect(x + 130 * k, y - 40 * k, 70 * k, 30 * k, Color("d9d0c0"))      # spilled litter
			rect(x - 230 * k, y - 25 * k, 50 * k, 20 * k, Color("d9d0c0"))
			for j in 5:
				flame(x + (j - 2) * 75 * k, y - (200 + 90 * cos(j)) * k, 140 * k, (330 + 120 * sin(j * 2.1 + sd)) * k, t * 9 + j * 1.3 + sd)
			return
		rect(x - 130 * k, y - 430 * k, 260 * k, 430 * k, Color("2f5d46"))   # the bin
		rect(x - 140 * k, y - 450 * k, 280 * k, 40 * k, Color("1f3f30"))
		rect(x - 20 * k, y - 430 * k, 40 * k, 430 * k, Color("4a4a4a"))
		for j in 5:
			flame(x + (j - 2) * 60 * k, y - 440 * k, 150 * k, (380 + 120 * sin(j * 2.1 + sd)) * k, t * 9 + j * 1.3 + sd)
		return
	var sc := fire_scale(f)
	if sc <= 0.0:
		return
	var R: float = f.r * ROAD_W * k * sc
	ell(x, y, R * 1.05, R * 1.05 * p.flat, Color(0.16, 0.12, 0.1, 0.5))    # scorched pavement
	ell(x, y, R * 1.3, R * 1.3 * p.flat, Color(1, 0.55, 0.16, 0.3))
	for j in 7:      # flames standing on the patch, back row first
		var a := PI * (j / 6.0)
		flame(x + cos(a + sd) * R * 0.75, y - absf(sin(a)) * R * p.flat * 0.6, 110 * k * sc, (220 + 90 * sin(j * 1.9 + sd)) * k * sc, t * 10 + j * 1.7)
	flame(x, y + R * p.flat * 0.3, 140 * k * sc, 300 * k * sc, t * 8 + sd)


## the bottle in flight: arcs over from the street side, tumbling, its rag alight
func draw_molotov(m: Dictionary) -> void:
	var tgt := to_screen(m.z, m.x)
	if tgt.is_empty():
		return
	var k := minf(m.t / m.T, 1.0)
	var x: float = m.sx + (tgt.x - m.sx) * k
	var y: float = m.sy + (tgt.y - m.sy) * k - sin(PI * k) * H * 0.32
	var s := maxf(0.8, H / 600.0) * (0.8 + k * 0.6)
	xf(V(x, y), V(s, s), m.spin + m.t * 9)
	rect(-4, -6, 8, 14, Color(0.47, 0.59, 0.35, 0.9))
	rect(-2, -11, 4, 6, Color(0.35, 0.47, 0.27, 0.95))
	rect(-1.5, -15, 3, 5, Color("e8dcc6"))
	xf_reset()
	flame(x, y - 12 * s, 10 * s, (16 + sin(m.t * 30) * 4) * s, m.t * 20)


## now and then a building has been set on fire (soot, gutted windows glowing, flames out of
## the shop) or looted (smashed shopfront, boards, glass on the pavement, graffiti). Decided per
## building, so the whole frontage of one building shares its fate.
func building_damage(bld: int) -> String:
	var v := sin(bld * 91.7 + 7.3) * 43758.5453
	var f := v - floorf(v)
	return "burnt" if f < 0.09 else ("looted" if f < 0.22 else "")


func draw_damage(seg: Dictionary) -> void:
	var dmg := building_damage(seg.bld)
	if dmg == "":
		return
	var t := run_time
	var i: int = seg.i
	var kk := _as * K2
	if dmg == "burnt":
		wallq(Color(0.12, 0.09, 0.08, 0.45), 0, 1, 1.04, 0, WALL_H)            # soot all over
		for fh in [1150.0, 1650.0, 2150.0]:
			wallq(Color("16110e"), 0.3, 0.7, 1.04, fh, fh + 360)              # gutted windows
			if fposmod(i + fh / 500.0, 2.0) < 1.0:
				wallq(Color(1, (120 + floorf(40 * sin(t * 6 + i))) / 255.0, 0.16, 0.75), 0.36, 0.64, 1.04, fh + 60, fh + 300)
			wallq(Color(0.04, 0.03, 0.03, 0.55), 0.25, 0.75, 1.04, fh + 360, fh + 520)   # black tongues above them
		if kk > 0.01:
			for fh in [1150.0, 1650.0, 2150.0]:      # fire licking out of the windows, all the way up
				if fposmod(i * 7 + fh / 250.0, 3.0) >= 2.0:
					continue
				var wp := P(0.5, 1.04, fh + 330)
				for j in 2:
					flame(wp.x + (j - 0.5) * 90 * kk, wp.y, 170 * kk, (380 + 120 * sin(t * 3 + i + fh + j)) * kk, t * 9 + j * 2.3 + i + fh * 0.01)
			if i % 2 == 0:                           # and through the roof
				var rp := P(0.5, 1.1, ROOF_H)
				for j in 3:
					flame(rp.x + (j - 1) * 120 * kk, rp.y, 200 * kk, (520 + 160 * sin(j * 1.7 + i)) * kk, t * 7 + j * 1.6 + i)
		wallq(Color("16110e"), 0.12, 0.88, 1.04, 60, 640)
		if kk > 0.01:
			var fp := P(0.5, 1.04, 60)
			for j in 3:
				flame(fp.x + (j - 1) * 130 * kk, fp.y, 220 * kk, (520 + 140 * sin(j * 2 + i)) * kk, t * 8 + j * 1.9 + i)
			var sp := P(0.5, 1.13, ROOF_H)
			for j in 3:                              # smoke pouring off the roof
				var u := fposmod(t * 0.2 + j / 3.0 + i * 0.13, 1.0)
				circ(sp.x + u * 500 * kk, sp.y - u * 1600 * kk, (250 + u * 500) * kk, Color(0.16, 0.14, 0.14, 0.5 * (1 - u)))
		return
	# looted
	if seg.shop:
		wallq(Color("1c1f24"), 0.12, 0.88, 1.04, 60, 640)                      # dark, emptied shop
		for pts in [[[0.12, 640.0], [0.3, 420.0], [0.22, 200.0], [0.12, 60.0]], [[0.88, 640.0], [0.7, 480.0], [0.8, 260.0], [0.66, 60.0]]]:
			var line_pts := []
			for q in pts:
				line_pts.append(P(q[0], 1.04, q[1]))
			polyline(line_pts, maxf(1, 12 * kk), Color(0.92, 0.94, 0.96, 0.75))   # what's left of the glass
		if i % 2:      # boarded up
			wallq(Color("b08a5a"), 0.14, 0.5, 1.04, 80, 620)
			wallq(Color(0.31, 0.24, 0.16, 0.4), 0.14, 0.5, 1.04, 330, 350)
		wallq(Color(0.78, 0.78, 0.78, 0.35), 0, 1, 1.04, 680, 860)               # shop sign smashed
	# graffiti scrawled along the stone, and broken glass on the pavement below
	var graff := [[[Color("c8372d"), Color("1d3b6e"), Color("1b1e24")][seg.bld % 3], 740.0, 0.0]]
	if i % 3 == 0:
		graff.append([Color("2f5d46"), 930.0, 2.1])
	for g in graff:
		var gp := []
		for j in 11:
			gp.append(P(j / 10.0, 1.04, g[1] + 70 * sin(i * 1.7 + j * 1.3 + g[2]) + 40 * sin(j * 3.1)))
		polyline(gp, maxf(1, 15 * kk), g[0])
	for j in 4:
		var gl := P((j + 0.3) / 4.0, 0.86 + 0.1 * absf(sin(i * 3 + j)))
		rect(gl.x, gl.y - 30 * kk, maxf(1, 40 * kk), maxf(1, 14 * kk), Color(0.88, 0.92, 0.94, 0.8))


## a looter: dark hoodie with the hood up, face covered, making off with something: a boxed TV,
## bulging shopping bags, a stack of shoe boxes, or a crowbar. Seen from behind (running up the
## street with the gang) or from the front (carrying the goods out of a shop by the wall).
## o.walk: walking; o.carry == false: empty-handed; o.smash: swinging a crowbar at the window;
## o.throwing: 0…1 through a throw; o.flip: mirrored; o.alpha: fading in or out
func draw_looter(p: Dictionary, sd: float, t: float, front: bool, o := {}) -> void:
	if p.is_empty():
		return
	var Hh: float = 560 * p.k * (0.9 + 0.2 * seat_rand(sd, 1))
	var coat: Color = C_LOOTER_COATS[int(seat_rand(sd, 2) * C_LOOTER_COATS.size())]
	var walk: bool = o.get("walk", false)
	var prop := seat_rand(sd, 4)                    # someone hauling loot holds loot
	if o.get("smash", false) or o.has("throwing"):
		prop = 1.0
	elif o.get("carry", true) == false:
		prop = -1.0
	elif walk:
		prop *= 0.8
	var run: float
	var bob: float
	if walk:
		run = sin(t * 9 + sd) * Hh * 0.045
		bob = absf(sin(t * 9 + sd)) * Hh * 0.015
	elif front:
		run = sin(t * 3 + sd) * Hh * 0.015
		bob = 0.0
	else:
		run = sin(t * 11 + sd) * Hh * 0.06
		bob = absf(sin(t * 11 + sd)) * Hh * 0.03
	xf(V(p.x, p.y), V(-1 if o.get("flip", false) else 1, 1))
	if o.has("alpha"):
		ga = clampf(o.alpha, 0.0, 1.0)
	ell(0, 0, Hh * 0.2, Hh * 0.2 * p.flat, Color(0, 0, 0, 0.2))
	t_o.y -= bob
	rect(-Hh * 0.08, -Hh * 0.42 + run, Hh * 0.07, Hh * 0.42 - run, Color("202328"))   # legs
	rect(Hh * 0.01, -Hh * 0.42 - run, Hh * 0.07, Hh * 0.42 + run, Color("202328"))
	rect(-Hh * 0.09, -Hh * 0.03 + minf(0, run), Hh * 0.09, Hh * 0.03, Color("e8e4d8"))   # white trainers
	rect(0, -Hh * 0.03 + minf(0, -run), Hh * 0.09, Hh * 0.03, Color("e8e4d8"))
	fill(PackedVector2Array([V(-Hh * 0.15, -Hh * 0.8), V(Hh * 0.15, -Hh * 0.8), V(Hh * 0.16, -Hh * 0.38), V(-Hh * 0.16, -Hh * 0.38)]), coat)   # hoodie
	circ(0, -Hh * 0.9, Hh * 0.085, Color("c99a74") if front else coat)       # hood up; from the front, a masked face
	ell(0, -Hh * 0.92, Hh * 0.095, Hh * 0.095, coat, 0, PI * 0.95, PI * 2.05)
	if front:
		rect(-Hh * 0.07, -Hh * 0.9, Hh * 0.14, Hh * 0.07, Color("111111"))        # mask over nose and mouth
		rect(-Hh * 0.045, -Hh * 0.935, Hh * 0.025, Hh * 0.012, Color("e8e4d8"))
		rect(Hh * 0.02, -Hh * 0.935, Hh * 0.025, Hh * 0.012, Color("e8e4d8"))
	var aw := Hh * 0.06
	if prop < 0:                                       # empty-handed, arms swinging
		for s in [-1.0, 1.0]:
			line(V(s * Hh * 0.16, -Hh * 0.76), V(s * Hh * 0.19, -Hh * 0.48 + s * run * 0.8), aw, coat)
	elif o.has("throwing"):                            # arm flung up and out, toward the walker
		var u: float = o.throwing
		line(V(Hh * 0.15, -Hh * 0.76), V(Hh * 0.2, -Hh * 0.48), aw, coat)
		line(V(-Hh * 0.13, -Hh * 0.76), V(-Hh * (0.2 + 0.12 * u), -Hh * (1.15 - 0.25 * u)), aw, coat)
	elif o.get("smash", false):                        # wind up slowly, strike hard, rest
		var s := fposmod(t * 1.4 + sd, 1.0)
		var a := 0.5
		if s < 0.65:
			a = -0.5 - 1.9 * (s / 0.65)
		elif s < 0.75:
			a = -2.4 + 2.9 * ((s - 0.65) / 0.1)
		var sh := V(Hh * 0.13, -Hh * 0.76)
		var hand := sh + V(cos(a), sin(a)) * Hh * 0.24
		line(V(-Hh * 0.15, -Hh * 0.76), V(-Hh * 0.2, -Hh * 0.48), aw, coat)
		line(sh, hand, aw, coat)
		var tip := hand + V(cos(a), sin(a)) * Hh * 0.3
		line(hand, tip, maxf(1, Hh * 0.025), Color("8c2a2a"))
		if s > 0.73 and s < 0.85:                      # glass flying off the window
			for j in 6:
				var ang := j * 1.1 + sd
				var d := (s - 0.73) * Hh * 2.2
				rect(tip.x + cos(ang) * d, tip.y + sin(ang) * d * 0.6 - d * 0.3, Hh * 0.03, Hh * 0.02, Color(0.92, 0.96, 0.98, 0.9))
	elif prop < 0.35:                                  # a boxed flat-screen TV, hugged in both arms
		var bw := Hh * 0.46
		var bh := Hh * 0.3
		var by := -Hh * 0.74
		rect(-bw / 2, by, bw, bh, Color("c8a170"))
		rect(-bw * 0.36, by + bh * 0.2, bw * 0.72, bh * 0.55, Color("b08a5a"))
		rect(-bw * 0.3, by + bh * 0.08, bw * 0.24, bh * 0.1, Color("1d3b6e"))
		for s in [-1.0, 1.0]:
			line(V(s * Hh * 0.15, -Hh * 0.76), V(s * bw * 0.5, by + bh * 0.6), aw, coat)
	elif prop < 0.6:                                   # bulging shopping bags, one in each hand
		for s in [-1.0, 1.0]:
			line(V(s * Hh * 0.16, -Hh * 0.76), V(s * Hh * 0.22, -Hh * 0.5 + s * run * 0.5), aw, coat)
			rect(s * Hh * 0.22 - Hh * 0.08, -Hh * 0.5 + s * run * 0.5, Hh * 0.16, Hh * 0.2, Color("e8e4d8") if s < 0 else Color("c8372d"))
	elif prop < 0.8:                                   # a stack of shoe boxes
		for j in 3:
			rect(-Hh * 0.16 + j * Hh * 0.01, -Hh * (0.62 + j * 0.09), Hh * 0.3, Hh * 0.085, [Color("e8742b"), Color("f2f2f2"), Color("1b1e24")][j])
		for s in [-1.0, 1.0]:
			line(V(s * Hh * 0.15, -Hh * 0.76), V(s * Hh * 0.17, -Hh * 0.58), aw, coat)
	else:                                              # a crowbar, brandished
		line(V(-Hh * 0.15, -Hh * 0.76), V(-Hh * 0.2, -Hh * 0.48), aw, coat)
		line(V(Hh * 0.13, -Hh * 0.76), V(Hh * 0.2, -Hh * 0.98), aw, coat)
		polyline([V(Hh * 0.2, -Hh * 0.98), V(Hh * 0.32, -Hh * 1.26), V(Hh * 0.27, -Hh * 1.3)], maxf(1, Hh * 0.025), Color("8c2a2a"))
	ga = 1.0
	xf_reset()


## hard mode: where the café tables would be, a gang looting the shop by the wall. One keeps
## smashing at the window with a crowbar; the other two go in empty-handed (fading into the shop)
## and come back out towards the street carrying a TV, bags or shoe boxes.
func draw_looter_group(p: Dictionary, seg_i: int, S: int) -> void:
	if p.is_empty():
		return
	var cw: float = 0.12 * ROAD_W * p.k
	var t := run_time
	var thrown: float = t - segs[seg_i].get("throw_at", -99.0)      # just threw a Molotov at the walker?
	var q := p.duplicate()
	q.x = p.x + S * cw * 1.1
	q.y = p.y - 6 * p.k
	if thrown < 0.6:
		draw_looter(q, seg_i * 3.7, t, true, {"throwing": thrown / 0.6, "flip": S < 0})
	else:
		draw_looter(q, seg_i * 3.7, t, false, {"smash": true, "flip": S < 0})
	for j in [1, 2]:
		var ph := fposmod(t / 3.4 + j * 0.5 + seg_i * 0.13, 1.0)
		var sd: float = seg_i * 3.7 + j
		var r := p.duplicate()
		if ph < 0.42:
			var u := ph / 0.42
			r.x = p.x + S * cw * (-1 + 2.3 * u)
			draw_looter(r, sd, t, false, {"walk": true, "carry": false, "alpha": 1 - maxf(0, (u - 0.75) / 0.25)})
		elif ph >= 0.58:
			var u := (ph - 0.58) / 0.42
			r.x = p.x + S * cw * (1.3 - 2.3 * u)
			draw_looter(r, sd, t, true, {"walk": true, "alpha": u / 0.2})


## green Paris street-cleaning truck seen from behind, hosing the sidewalk edge
func draw_cleaner(tr: Dictionary) -> void:
	var seg := seg_at(tr.z)
	var S: float = seg.side
	var p := to_screen(tr.z, -1.75 * S)
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	var w := 0.85 * ROAD_W * k
	var h := 1050 * k
	ell(x, y, w * 0.6, w * 0.6 * p.flat, Color(0, 0, 0, 0.25))
	rect(x - w * 0.45, y - 160 * k, w * 0.18, 160 * k, Color("1b1e24"))
	rect(x + w * 0.27, y - 160 * k, w * 0.18, 160 * k, Color("1b1e24"))
	rect(x - w / 2, y - h, w, h - 130 * k, Color("2e7d4f"))
	ell(x, y - h * 0.62, w * 0.36, h * 0.3, Color("3c9a63"))
	rect(x - w * 0.42, y - h * 0.25, w * 0.84, h * 0.08, Color("e9eef5"))
	rect(x - w * 0.46, y - h * 0.22, w * 0.08, h * 0.06, Color("c8372d"))
	rect(x + w * 0.38, y - h * 0.22, w * 0.08, h * 0.06, Color("c8372d"))
	ell(x, y - h - 20 * k, 40 * k, 40 * k, Color("f2a33a"), 0, PI, TAU)
	if w > 40:
		text("PROPRETÉ DE PARIS", V(x, y - h * 0.185), int(maxf(6, w * 0.09)), Color("1d3b6e"), HORIZONTAL_ALIGNMENT_CENTER, mono)
	# water fans out from a side nozzle as streams of droplets, with a misty splash where they land
	var sx := x + S * w * 0.5
	var sy := y - 330 * k
	rect(sx - 10 * k - (50 * k if S < 0 else 0.0), sy - 25 * k, 70 * k, 50 * k, Color(0.63, 0.73, 0.8, 0.9))
	for j in 5:
		var zj: float = tr.z + (j - 2) * SPRAY_LEN * 0.35
		var g := to_screen(zj, S * (-seg.w + wet_reach(tr, zj) * 0.7 + sin(tr.t * 9 + j) * 0.04))
		if g.is_empty():
			continue
		var c := V((sx + g.x) / 2, minf(sy, g.y) - 90 * k)
		var a := V(sx, sy)
		var e := V(g.x, g.y)
		var core := []
		for n in 7:
			var u := 0.05 * n
			core.append(a.lerp(c, u).lerp(c.lerp(e, u), u))
		polyline(core, maxf(1, 14 * k), Color(0.84, 0.91, 0.96, 0.7))
		for n in 12:
			var u := fposmod(n / 12.0 + tr.t * 1.6, 1.0)
			if u < 0.25:
				continue
			var pt := a.lerp(c, u).lerp(c.lerp(e, u), u)
			var spread := u * 40 * k
			circ(pt.x + sin(n * 12.9 + j * 3.1) * spread, pt.y + cos(n * 7.3 + j) * spread * 0.6, maxf(0.8, (10 + u * 12) * k), Color(0.86, 0.93, 0.97, 0.85 - u * 0.4))
		var r := maxf(2, 90 * g.k)
		ell(g.x, g.y - r * 0.3, r, r * 0.55, Color(0.88, 0.93, 0.97, 0.35))


# ---------- the walker, seen from behind ----------

func draw_player() -> void:
	var k0 := K2 / CAM_H
	var x := W / 2 + (player_x * ROAD_W - cam_x) * k0
	var gy := HORIZON + K
	var Hh := 520 * k0
	var air := jump_height()                       # 0 on the ground … 1 at the top of a jump
	var y0 := gy - air * Hh * 0.38
	player_screen = V(x, y0)
	player_h = Hh
	if invuln > 0 and floori(invuln * 10) % 2 == 0:
		return
	# legs and arms swing at the walking cadence; from about 5.4 km/h the walk blends into a run
	var kmh := walk_kmh()
	var amp := Hh * (0.012 + 0.009 * kmh)
	var run := 0.0 if air > 0 else clampf((kmh - 5.4) / 1.6, 0, 1)
	var bob := 0.0 if air > 0 else absf(sin(gait)) * Hh * (maxf(0, kmh - 3) * 0.006 + run * 0.03)
	var y := y0 - bob
	var lean := run * Hh * 0.03
	player_screen = V(x, y)
	ell(x, gy, Hh * 0.2 * (1 - air * 0.35), Hh * 0.05 * (1 - air * 0.35), Color(0, 0, 0, 0.22 - air * 0.1))
	for side in [-1.0, 1.0]:
		var ph := gait + (0.0 if side < 0 else PI)
		var shift := 0.0 if air > 0 else -(1 - run) * sin(ph) * amp
		var kick := run * maxf(0, sin(ph))
		var top := y - Hh * 0.38 - shift
		var len := Hh * 0.36 * (1 - 0.5 * kick)
		rect(x + (-0.1 if side < 0 else 0.02) * Hh, top, Hh * 0.08, len, Color("2d3138"))
		ell(x + side * Hh * 0.06, top + len - Hh * 0.02, Hh * 0.055, Hh * (0.03 + 0.03 * kick), Color("5a4232") if kick > 0.3 else Color("3a2416"))
	for i in 3 - lives:      # muddy shoes
		circ(x + (1 if i % 2 else -1) * Hh * 0.06, y - Hh * 0.03, Hh * 0.025, Color("6b4423"))
	# trench coat with belt, then the arms
	var yt := y + lean
	var coat := Color("b8955f")
	fill(PackedVector2Array([V(x - Hh * 0.15, yt - Hh * 0.8), V(x + Hh * 0.15, yt - Hh * 0.8), V(x + Hh * 0.18, y - Hh * 0.34), V(x - Hh * 0.18, y - Hh * 0.34)]), coat)
	for side in [-1.0, 1.0]:
		var arm_sw := (1.0 if side < 0 else -1.0) * (0.0 if air > 0 else sin(gait)) * amp * (1 - run * 0.35)
		var ax: float = x + side * Hh * 0.185
		var sy := yt - Hh * 0.76 + arm_sw * (1 - run)
		var ey := sy + Hh * 0.14 + arm_sw * run * 0.5
		var hx: float = ax - side * Hh * 0.09 * run
		var hy := ey + Hh * 0.14 * (1 - run) - Hh * 0.02 * run + arm_sw * run
		polyline([V(ax, sy), V(ax, ey), V(hx, hy)], Hh * 0.07, coat)
		circ(hx, hy + Hh * 0.03 * (1 - run), Hh * 0.028, Color("e8b98f"))
	rect(x - Hh * 0.16, y - Hh * 0.56 + lean * 0.5, Hh * 0.32, Hh * 0.03, Color("9c7c4b"))
	rect(x - Hh * 0.005, y - Hh * 0.53 + lean * 0.5, Hh * 0.01, Hh * 0.19, Color("9c7c4b"))
	# scarf (its tail flaps when running), head, beret
	var flap := run * sin(gait * 2) * Hh * 0.035
	rect(x - Hh * 0.09, yt - Hh * 0.83, Hh * 0.18, Hh * 0.05, Color("c8372d"))
	rect(x + Hh * 0.03 + flap, yt - Hh * 0.8, Hh * 0.05, Hh * (0.14 - run * 0.03), Color("c8372d"))
	circ(x, yt - Hh * 0.9, Hh * 0.085, Color("3b2a20"))
	ell(x, yt - Hh * 0.97, Hh * 0.1, Hh * 0.045, Color("1b1e24"), -0.15)
	rect(x - Hh * 0.008, yt - Hh * 1.03, Hh * 0.016, Hh * 0.03, Color("1b1e24"))


# ---------- HUD ----------

## blue street plate announcing the landmark of this stretch
func draw_plate() -> void:
	ga = clampf(minf(plate.life / 0.4, (2.6 - plate.life) / 0.3), 0, 1)
	var tw := maxf(font_bold.get_string_size(plate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 60) + 36
	var x := W / 2 - tw / 2
	var y := HUD_H + 34
	rect(x - 3, y - 3, tw + 6, 60, Color("e9eef5"))
	rect(x, y, tw, 54, Color("1d3b6e"))
	text(plate.text, V(W / 2, y + 26), 20, Color.WHITE)
	text(plate.ko, V(W / 2, y + 45), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font)
	ga = 1.0


## pace gauge in the bottom-left corner, like OutRun's speedometer
func draw_pace_gauge() -> void:
	var x := 12.0
	var y := H - 22 - (96.0 if pad_on() else 0.0)      # above the ◀ ▶ buttons on phones
	var w := minf(160, maxf(140, W * 0.36))
	var h := 10.0
	var t := (pace - PACE_MIN) / (PACE_MAX - PACE_MIN)
	var kmh := "%.1f" % walk_kmh()
	rect(x - 6, y - 46, w + 12, h + 54, Color(0.106, 0.118, 0.141, 0.72))
	text(kmh, V(x, y - 22), 22, Color("f2d27a"), HORIZONTAL_ALIGNMENT_LEFT, mono)
	var num_w := mono.get_string_size(kmh, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	text("km/h", V(x + num_w + 5, y - 22), 12, Color("e9e4da"), HORIZONTAL_ALIGNMENT_LEFT, mono)
	text("느긋하게" if t < 0.3 else ("서둘러서" if t > 0.7 else "보통 걸음"), V(x, y - 6), 12, Color("e9e4da"), HORIZONTAL_ALIGNMENT_LEFT, font)
	text(str(roundi(pace * 100)) + "%", V(x + w, y - 6), 12, Color("e9e4da"), HORIZONTAL_ALIGNMENT_RIGHT, mono)
	var m := score_mult(pace)
	text("×%.1f" % m, V(x + w, y - 22), 16, Color("e07a5f") if m >= 1.5 else (Color("f2d27a") if m >= 1 else Color("9fb0a0")), HORIZONTAL_ALIGNMENT_RIGHT, mono)
	for i in 10:
		var on := (i + 0.5) / 10.0 <= t
		var c := Color(0.91, 0.89, 0.85, 0.18)
		if on:
			c = Color("7fb069") if i < 3 else (Color("f2d27a") if i < 7 else Color("e07a5f"))
		rect(x + i * (w / 10), y + 2, w / 10 - 2, h, c)


## top bar: score, distance, shoes, best; with the street name under it
func draw_hud() -> void:
	rect(0, 0, W, HUD_H, Color(0.106, 0.118, 0.141, 0.82))
	var cols := [["점수", _fmt(floori(score))], ["거리", "%d m" % floori(dist)], ["구두", "" if lives > 0 else "—"], ["최고 점수", _fmt(best)]]
	var cw := W / cols.size()
	for j in cols.size():
		var cx := cw * (j + 0.5)
		text(cols[j][0], V(cx, 16), 11, Color("b9b3a8"), HORIZONTAL_ALIGNMENT_CENTER, font)
		text(cols[j][1], V(cx, 37), 18, Color("f2d27a") if j == 0 else Color.WHITE)
	flush()
	for k in maxi(0, lives):      # one drawn shoe per pair left (emoji don't render on web / mobile)
		Icons.paint(self, "👞", V(cw * 2.5 + (k - (lives - 1) / 2.0) * 24, 31), 22)
	var p: Dictionary = PLACES[place_at(dist)]
	text("%s · PARIS %s Arr." % [p.street, p.arr], V(W / 2, HUD_H + 18), 13, Color("1b1e24"), HORIZONTAL_ALIGNMENT_CENTER, font, 4, Color(1, 1, 1, 0.75))
	draw_pad()


## the on-screen pad: translucent discs with a light rim, lit while held
func draw_pad() -> void:
	if not (pad_left and pad_left.visible):
		return
	for b in [[pad_left, PAD_R, -1.0], [pad_right, PAD_R, 1.0], [pad_jump, PAD_JR, 0.0]]:
		var c: Vector2 = b[0].position
		var r: float = b[1]
		var held: bool = b[0].is_pressed()
		circ(c.x, c.y, r, Color(0.91, 0.93, 0.96, 0.7))
		circ(c.x, c.y, r - 2, Color(0.95, 0.82, 0.48, 0.6) if held else Color(0.106, 0.118, 0.141, 0.45))
		var ink := Color("1b1e24") if held else Color.WHITE
		if b[2] != 0.0:      # ◀ / ▶
			var d: float = b[2]
			fill(PackedVector2Array([V(c.x + d * 11, c.y), V(c.x - d * 7, c.y - 11), V(c.x - d * 7, c.y + 11)]), ink)
		else:
			text("점프", V(c.x, c.y + 7), 19, ink)
	flush()


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ======================================================================
# UI overlays (start / game over), mode switch, save data
# ======================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 16
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("c8372d")
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 22
	btn.content_margin_right = 22
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var btn_hover: StyleBoxFlat = btn.duplicate()
	btn_hover.bg_color = Color("dc4a3f")
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_hover)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var tab: StyleBoxFlat = btn.duplicate()
	tab.bg_color = Color(1, 1, 1, 0.12)
	tab.content_margin_left = 14
	tab.content_margin_right = 14
	tab.content_margin_top = 9
	tab.content_margin_bottom = 9
	var tab_on: StyleBoxFlat = tab.duplicate()
	tab_on.bg_color = Color("c8372d")
	var tab_hover: StyleBoxFlat = tab.duplicate()
	tab_hover.bg_color = Color(1, 1, 1, 0.22)
	th.set_stylebox("normal", "TabBtn", tab)
	th.set_stylebox("hover", "TabBtn", tab_hover)
	th.set_stylebox("pressed", "TabBtn", tab_on)
	th.set_stylebox("hover_pressed", "TabBtn", tab_on)
	th.set_type_variation("TabBtn", "Button")
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	root.theme = th

	start_panel = _overlay(root, "Bonne promenade!", [
		"그저 파리를 산책하고 싶었을 뿐인데, 이 도시는 그냥 걷게 두질 않네요. 개똥, 오줌 웅덩이, 비둘기, 차와 자전거를 피해 구두 세 켤레가 망가지기 전에 최대한 멀리 가 보세요.",
		"서두를수록 점수가 커지지만, 구석으로만 걸으면 오히려 위험해요.",
	], "산책 시작")
	var keys := Label.new()
	if DisplayServer.is_touchscreen_available():
		keys.text = "◀ ▶ 버튼이나 좌우 드래그로 이동 · 위아래 드래그로 속도\n점프 버튼이나 짧은 탭으로 점프 · II 버튼으로 일시 정지"
	else:
		keys.text = "← → 이동 · ↑ ↓ 속도 · Space 점프 · P 정지 · M 소리\n(터치: 드래그로 이동·속도, 탭으로 점프)"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 13)
	keys.modulate = Color(1, 1, 1, 0.75)
	var sbox: VBoxContainer = start_panel.get_meta("box")
	sbox.add_child(keys)
	sbox.move_child(keys, 3)

	over_panel = _overlay(root, "Merde alors!", [], "다시 걷기")
	var obox: VBoxContainer = over_panel.get_meta("box")
	over_score = Label.new()
	over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_score.add_theme_font_override("font", font_bold)
	over_score.add_theme_font_size_override("font_size", 40)
	over_score.add_theme_color_override("font_color", Color("f2d27a"))
	over_dist = Label.new()
	over_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_dist.add_theme_font_size_override("font_size", 14)
	over_msg = _para("")
	for n in [over_score, over_dist, over_msg]:
		obox.add_child(n)
		obox.move_child(n, 1 + [over_score, over_dist, over_msg].find(n))
	over_panel.visible = false

	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_NONE
	_pin_top_right(pause_btn, HUD_H + 34)
	pause_btn.theme_type_variation = "TabBtn"
	pause_btn.pressed.connect(toggle_pause)
	pause_btn.visible = false
	root.add_child(pause_btn)
	sound_btn = Button.new()
	sound_btn.text = "♪"
	sound_btn.focus_mode = Control.FOCUS_NONE
	_pin_top_right(sound_btn, HUD_H + 88)
	sound_btn.theme_type_variation = "TabBtn"
	sound_btn.pressed.connect(_toggle_sound)
	sound_btn.text = "×" if sfx.muted else "♪"
	root.add_child(sound_btn)
	lb = preload("res://leaderboard.gd").new()
	add_child(lb)
	lb.setup(self, root, sbox, obox)


## a centred dark card with a title, paragraphs, the difficulty switch and a main button
func _overlay(root: Control, title: String, paras: Array, button: String) -> Control:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.118, 0.141, 0.9)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(minf(440, W - 48), 0)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", font_bold)
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color("f2d27a"))
	box.add_child(t)
	for s in paras:
		box.add_child(_para(s))
	# 일반 / 어려움 — hard mode is a riot: fire, Molotovs and looters, with its own best score
	var diff := HBoxContainer.new()
	diff.alignment = BoxContainer.ALIGNMENT_CENTER
	diff.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.text = "난이도"
	diff.add_child(lab)
	for mode in [false, true]:
		var b := Button.new()
		b.text = "어려움" if mode else "일반"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "TabBtn"
		b.pressed.connect(_set_mode.bind(mode))
		b.set_meta("hard", mode)
		diff_buttons.append(b)
		diff.add_child(b)
	box.add_child(diff)
	var note := _para("폭동이 번진 날의 파리. 불길과 화염병, 약탈자까지 피해야 해요. 최고 점수도 따로예요.")
	note.add_theme_font_size_override("font_size", 13)
	note.modulate = Color(1, 0.75, 0.65)
	hard_notes.append(note)
	box.add_child(note)
	var go := Button.new()
	go.text = button
	go.focus_mode = Control.FOCUS_NONE    # Space must not press it: only Enter or a click starts a walk
	go.add_theme_font_override("font", font_bold)
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(start)
	box.add_child(go)
	cc.set_meta("box", box)
	return cc


func _pin_top_right(b: Control, top: float) -> void:
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -64
	b.offset_right = -12
	b.offset_top = top
	b.offset_bottom = top + 46


func _para(s: String) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(minf(440, W - 48), 0)
	return l


func _set_mode(h: bool) -> void:
	hard = h
	for b in diff_buttons:
		b.button_pressed = b.get_meta("hard") == hard
	for n in hard_notes:
		n.visible = hard
	_load_best()
	_save()


func _toggle_sound() -> void:
	var m: bool = sfx.toggle_mute()
	_save()
	sound_btn.text = "×" if m else "♪"
	if not m:
		sfx.play("plate")


const SAVE_PATH := "user://paris_walk.cfg"


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		hard = cf.get_value("game", "mode", "normal") == "hard"
		sfx.set_muted(cf.get_value("game", "muted", false))
	_load_best()


func _load_best() -> void:
	var cf := ConfigFile.new()
	best = 0
	if cf.load(SAVE_PATH) == OK:
		best = cf.get_value("best", "hard" if hard else "normal", 0)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("game", "mode", "hard" if hard else "normal")
	cf.set_value("game", "muted", sfx.muted)
	var key := "hard" if hard else "normal"
	cf.set_value("best", key, maxi(best, cf.get_value("best", key, 0)))
	cf.save(SAVE_PATH)
