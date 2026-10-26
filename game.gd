extends Node2D
## 파리 산책하기 (Paris Walk) — Godot 4 port, first playable milestone.
##
## Same approach as the web version: an OutRun-style pseudo-3D sidewalk made of short
## segments, projected and painted far → near every frame. Everything is drawn with
## flat polygons, batched into one triangle array per frame (see fill/flush).
## World units: 250 units = 1 m; lateral positions are in "road units" where ±1 is the
## sidewalk edge.

const SEG_LEN := 200.0
const DRAW := 160
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
const HUD_H := 46.0

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
var C_DOGS := [Color("8a5a2b"), Color("e8dcc6"), Color("2b2b2b"), Color("b98a4e"), Color("d8d2c4"), Color("5b3a24")]
var C_PEER_COATS := [Color("4a5568"), Color("5b4636"), Color("2f5d46"), Color("6b3a4a")]
var ROOFS := []

var font: Font = preload("res://fonts/korean.tres")
var font_bold: SystemFont
var mono: SystemFont

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


func _ready() -> void:
	randomize()
	for i in 48:
		ROOFS.append({"w": 26 + ((i * 37) % 40), "h": 10 + ((i * 53) % 26), "chim": i % 3})
	font_bold = SystemFont.new()
	font_bold.font_names = (font as SystemFont).font_names
	font_bold.font_weight = 800
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 600
	_load_save()
	_build_ui()
	_set_mode(hard)
	_layout()
	reset()
	# `godot --path . -- --autoplay` starts walking at once (used for headless smoke tests)
	if OS.get_cmdline_user_args().has("--autoplay"):
		start()


func _layout() -> void:
	var sz := get_viewport_rect().size
	W = sz.x
	H = sz.y
	HORIZON = H * 0.44
	K = H * 0.96 - HORIZON                # vertical: walker's feet near the bottom
	K2 = 0.33 * minf(W, H * 0.9) * CAM_H / ROAD_W   # horizontal: sidewalk spans ~80% of a portrait screen


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


func toggle_pause() -> void:
	if state == PLAY:
		state = PAUSED
		drag = {}
		pause_btn.text = "▶"
	elif state == PAUSED:
		state = PLAY
		pause_btn.text = "II"


func game_over() -> void:
	state = OVER
	pause_btn.visible = false
	flash = {}
	shake = 0.0
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
	sfx.play("drop")


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
	queue_redraw()


func update(dt: float) -> void:
	var up := Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)
	var down := Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
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

	# bird droppings land when their timer runs out
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.t += dt
		if d.t < d.T:
			continue
		drops.remove_at(i)
		if invuln <= 0.0 and absf(d.x - player_x) < d.r + 0.05 and absf(d.z - p_z) < 600.0:
			if take_hit("새똥 명중!", Color(0.96, 0.95, 0.92, 0.6), "birdHit"):
				return
		else:
			stains.append({"z": d.z, "x": d.x, "seed": randf() * 10.0})

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
				if take_hit("Attention! 테라스!", Color(0.55, 0.16, 0.16, 0.35), "crash"):
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
	texts = texts.filter(func(t): return t.life > 0.0)


# ======================================================================
# input
# ======================================================================

func jump() -> void:
	if state != PLAY or jump_t > 0.0:
		return
	jump_t = JUMP_TIME
	sfx.play("jump")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
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


func xf(origin: Vector2, scale := Vector2.ONE) -> void:
	t_o = origin
	t_s = scale


func xf_reset() -> void:
	t_o = Vector2.ZERO
	t_s = Vector2.ONE


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
	for n in DRAW:
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
		if n < 0 or n >= DRAW:
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
			add.call(terrace_z(s), draw_terrace.bind(to_screen(terrace_z(s), terrace_x(s)), s.i, s.side))
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

	for n in range(DRAW - 1, -1, -1):
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
func draw_terrace(p: Dictionary, _seat_seed: int, side: int) -> void:
	if p.is_empty():
		return
	var k: float = p.k
	var x: float = p.x
	var y: float = p.y
	ell(x, y, 260 * k, 260 * k * p.flat, Color(0, 0, 0, 0.15))
	for sd in [-1.0, 1.0]:
		var cx: float = x + sd * 190 * k
		rect(cx - 70 * k, y - 430 * k, 140 * k, 40 * k, Color("9a7448"))            # seat
		rect(cx + sd * 50 * k, y - 800 * k, 25 * k * sd, 410 * k, Color("7a5a35"))   # back
		rect(cx - 60 * k, y - 390 * k, 14 * k, 390 * k, Color("4a3a28"))
		rect(cx + 46 * k, y - 390 * k, 14 * k, 390 * k, Color("4a3a28"))
	rect(x - 12 * k, y - 680 * k, 24 * k, 680 * k, Color("2a2c30"))
	rect(x - 90 * k, y - 20 * k, 180 * k, 20 * k, Color("2a2c30"))
	ell(x, y - 690 * k, 170 * k, 40 * k, Color("b8b2a6"))
	rect(x - 24 * k + side * 40 * k, y - 760 * k, 48 * k, 60 * k, Color("f4f2ea"))


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


func draw_rider_head(x: float, y: float, r: float, head: String) -> void:
	circ(x, y, r, Color("e8b98f"))
	if head == "helmet":
		ell(x, y - r * 0.3, r * 1.15, r * 0.85, Color("e8e4d8"), 0, PI, TAU)
	elif head == "beret":
		ell(x + r * 0.2, y - r * 0.75, r * 1.1, r * 0.45, Color("1b1e24"), -0.15)
	else:
		ell(x, y, r * 1.02, r * 1.02, Color(head), 0, PI * 1.05, PI * 1.95)


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
	var y := H - 22
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
	var cols := [["점수", _fmt(floori(score))], ["거리", "%d m" % floori(dist)], ["구두", "👞".repeat(maxi(0, lives)) if lives > 0 else "—"], ["최고 점수", _fmt(best)]]
	var cw := W / cols.size()
	for j in cols.size():
		var cx := cw * (j + 0.5)
		text(cols[j][0], V(cx, 16), 11, Color("b9b3a8"), HORIZONTAL_ALIGNMENT_CENTER, font)
		text(cols[j][1], V(cx, 37), 18, Color("f2d27a") if j == 0 else Color.WHITE)
	var p: Dictionary = PLACES[place_at(dist)]
	text("%s · PARIS %s Arr." % [p.street, p.arr], V(W / 2, HUD_H + 18), 13, Color("1b1e24"), HORIZONTAL_ALIGNMENT_CENTER, font, 4, Color(1, 1, 1, 0.75))


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
	tab.content_margin_top = 6
	tab.content_margin_bottom = 6
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
	_pin_top_right(sound_btn, HUD_H + 80)
	sound_btn.theme_type_variation = "TabBtn"
	sound_btn.pressed.connect(_toggle_sound)
	root.add_child(sound_btn)


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
	# 일반 / 어려움 — hard mode only changes the look and keeps its own best score for now
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
	var note := _para("폭동이 번진 날의 파리. (프로토타입: 불길·화염병·약탈자는 아직 없어요 — 지금은 하늘빛과 최고 점수만 따로예요.)")
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
	b.offset_left = -56
	b.offset_right = -12
	b.offset_top = top
	b.offset_bottom = top + 40


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
	sound_btn.text = "×" if m else "♪"
	if not m:
		sfx.play("plate")


const SAVE_PATH := "user://paris_walk.cfg"


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		hard = cf.get_value("game", "mode", "normal") == "hard"
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
	var key := "hard" if hard else "normal"
	cf.set_value("best", key, maxi(best, cf.get_value("best", key, 0)))
	cf.save(SAVE_PATH)
