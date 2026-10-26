extends Node
## Online scoreboard — the same Supabase project and RPCs as the web version (leaderboard,
## save_profile, submit_run), with the same anonymous player id + secret kept on this device.
## The server only accepts writes from the game's web address (it checks the Origin header),
## so a desktop build shows the board read-only; a web export served from that address can
## post records.

const LB_URL := "https://liiephbpoccyyahwkqrv.supabase.co"
const LB_KEY := "sb_publishable_erfuUfZP4osTTLx90rlksw_NZ_HPdV5"    # publishable (public) key, as in the web version
const SAVE_PATH := "user://paris_walk.cfg"
const AVATARS := ["🥖", "🗼", "🐕", "🐦", "👞", "🥐", "🧀", "🍷", "🎨", "🚲", "🐀", "🎩"]
const ERRORS := {
	"bad_nickname": "닉네임은 1~12자로 정해 주세요.",
	"bad_score": "기록을 확인할 수 없어 올리지 못했어요.",
	"too_fast": "잠시 뒤에 다시 올려 주세요.",
	"bad_origin": "이 주소에서는 기록을 올릴 수 없어요.",
	"bad_secret": "이 기기의 플레이어 정보가 맞지 않아요.",
}

var can_write := OS.has_feature("web")
var game: Node
var profile := {}            # id, secret, nickname, avatar
var pending_run := {}
var after_profile := Callable()
var picked_avatar := ""
var board_mode := "normal"
var board_period := "all"
var cache := {}              # "normal|all" etc. -> the leaderboard RPC's last answer

# UI
var hidden_panel: Control
var board: Control
var board_list: VBoxContainer
var board_me: Label
var tabs := {}
var prof: Control
var prof_hint: Label
var prof_status: Label
var nick: LineEdit
var avatar_btns: Array = []
var profile_btn: Button
var over_status: Label
var over_action: Button


func setup(g: Node, root: Control, start_box: VBoxContainer, over_box: VBoxContainer) -> void:
	game = g
	_load_profile()
	# start screen: 🏆 순위 보기 · 프로필
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon_btn("🏆", "순위 보기", open_board))
	if can_write:
		profile_btn = _icon_btn("🙂", "", func(): open_profile())
		row.add_child(profile_btn)
		_update_profile_button()
	start_box.add_child(row)
	# game over: status, an action (nickname / retry upload), and the board
	over_status = Label.new()
	over_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_status.add_theme_font_size_override("font_size", 14)
	over_status.add_theme_color_override("font_color", Color("f2d27a"))
	over_status.visible = false
	over_action = _btn("닉네임 정하고 기록 올리기", _on_over_action)
	over_action.visible = false
	var orow := HBoxContainer.new()
	orow.alignment = BoxContainer.ALIGNMENT_CENTER
	orow.add_theme_constant_override("separation", 8)
	orow.add_child(over_action)
	orow.add_child(_icon_btn("🏆", "순위 보기", open_board))
	over_box.add_child(over_status)
	over_box.move_child(over_status, 4)
	over_box.add_child(orow)
	_build_board(root)
	_build_profile(root)
	prefetch()


func is_open() -> bool:
	return board.visible or prof.visible


# ---------- server ----------

## POST /rest/v1/rpc/<fn>; returns {"ok": true, "data": …} or {"ok": false, "error": "…"}
func call_api(fn: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	# in a browser the response arrives already unzipped; letting Godot gunzip it again fails
	http.accept_gzip = false
	add_child(http)
	var headers := ["apikey: " + LB_KEY, "Authorization: Bearer " + LB_KEY, "Content-Type: application/json"]
	var err := http.request(LB_URL + "/rest/v1/rpc/" + fn, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTP request failed (%d)" % err}
	var res: Array = await http.request_completed
	http.queue_free()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] < 200 or res[1] >= 300:
		var msg := "HTTP %d" % res[1]
		if data is Dictionary:
			msg = str(data.get("message", data.get("hint", msg)))
		return {"ok": false, "error": msg}
	return {"ok": true, "data": data}


## a whole number from JSON (which only has floats), or "-"
func _n(v) -> String:
	return str(int(v)) if v != null else "-"


func err_text(e: String) -> String:
	for k in ERRORS:
		if e.contains(k):
			return ERRORS[k]
	return "서버에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."


# ---------- profile (anonymous id + secret, kept on this device) ----------

func _load_profile() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		profile = cf.get_value("profile", "data", {})


func _store_profile() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("profile", "data", profile)
	cf.save(SAVE_PATH)


func _ensure_identity() -> void:
	if profile.has("id") and profile.has("secret"):
		return
	var crypto := Crypto.new()
	var u := crypto.generate_random_bytes(16)
	u[6] = (u[6] & 0x0f) | 0x40      # UUID version 4
	u[8] = (u[8] & 0x3f) | 0x80
	var hex := u.hex_encode()
	profile = {
		"id": "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)],
		"secret": crypto.generate_random_bytes(32).hex_encode(),
		"nickname": "", "avatar": "",
	}


func has_nickname() -> bool:
	return profile.get("nickname", "") != ""


func _update_profile_button() -> void:
	if profile_btn:
		_set_icon_btn(profile_btn, profile.avatar if has_nickname() and profile.get("avatar", "") != "" else "🙂",
			profile.nickname if has_nickname() else "닉네임 정하기")


# ---------- after each game: post the run (asking for a nickname the first time) ----------

func game_over(run: Dictionary) -> void:
	pending_run = run
	over_action.visible = false
	over_status.visible = true
	if not can_write:
		pending_run = {}
		over_status.text = "온라인 순위 등록은 웹 버전에서만 돼요. 순위는 볼 수 있어요."
		return
	if not has_nickname():
		over_status.text = "닉네임을 정하면 이 기록이 순위에 올라가요."
		over_action.text = "닉네임 정하고 기록 올리기"
		over_action.visible = true
		return
	submit_pending()


func _on_over_action() -> void:
	if not has_nickname():
		open_profile("닉네임을 정하면 방금 기록이 순위에 올라가요.", submit_pending)
	else:
		submit_pending()


func submit_pending() -> void:
	if pending_run.is_empty():
		return
	var run := pending_run
	over_status.visible = true
	over_action.visible = false
	over_status.text = "기록 올리는 중…"
	var body := {"p_player": profile.id, "p_secret": profile.secret, "p_nickname": profile.nickname, "p_avatar": profile.avatar,
		"p_score": run.score, "p_dist": run.dist, "p_place": run.place, "p_duration_ms": run.duration}
	if run.mode == "hard":
		body["p_mode"] = "hard"
	var r := await call_api("submit_run", body)
	if not r.ok:
		over_status.text = err_text(r.error)
		over_action.text = "다시 올리기"
		over_action.visible = true
		return
	pending_run = {}
	prefetch([run.mode])      # the boards this run changed, ready for 순위 보기
	var a = r.data.get("all", {}).get("me")
	var w = r.data.get("week", {}).get("me")
	over_status.text = ("어려움 · " if run.mode == "hard" else "") + "전체 %s위 · 이번 주 %s위" % [
		_n(a.rank) if a else "-", _n(w.rank) if w else "-"] + (" (내 최고 기록!)" if a and int(a.score) == int(run.score) else "")


# ---------- the board ----------

func open_board() -> void:
	board_mode = "hard" if game.hard else "normal"
	board_period = "all"
	_show(board)
	load_board()


## Boards are cached per difficulty × period: all four are fetched once at start-up, and the
## played difficulty again right after a run is posted. Opening a board shows the cached copy
## at once and refreshes it in the background.
func prefetch(modes := ["normal", "hard"]) -> void:
	for m in modes:
		for p in ["all", "week"]:
			fetch_board(m, p)


func fetch_board(m: String, p: String) -> Dictionary:
	var body := {"p_period": p, "p_player": profile.get("id", null)}
	if m == "hard":
		body["p_mode"] = "hard"
	var r := await call_api("leaderboard", body)
	if r.ok:
		cache[m + "|" + p] = r.data
	if board.visible and m == board_mode and p == board_period:      # still the board on screen
		if r.ok:
			_render_board(r.data)
		elif not cache.has(m + "|" + p):
			board_me.text = err_text(r.error)
	return r


func load_board() -> void:
	for k in tabs:
		tabs[k].button_pressed = k == board_mode or k == board_period
	var key := board_mode + "|" + board_period
	if cache.has(key):
		_render_board(cache[key])
	else:
		for c in board_list.get_children():
			c.queue_free()
		board_me.text = "불러오는 중…"
	fetch_board(board_mode, board_period)


func _render_board(data: Dictionary) -> void:
	for c in board_list.get_children():
		c.queue_free()
	var top: Array = data.get("top", [])
	if top.is_empty():
		board_list.add_child(_label("이번 주 기록이 아직 없어요. 첫 주인공이 되어 보세요!" if board_period == "week" else "아직 기록이 없어요.", 14))
	for row in top:
		board_list.add_child(_board_row(row))
	var me = data.get("me")
	board_me.text = "내 순위 %s위 / %s명 · %s점" % [_n(me.rank), _n(data.get("total")), game._fmt(int(me.score))] if me \
		else "참가자 %s명" % _n(data.get("total"))


## one row: rank, emoji, nickname with distance / landmark, score
func _board_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var place: int = int(r.get("place", 0))
	var place_ko: String = game.PLACES[place].ko if place >= 0 and place < game.PLACES.size() else ""
	var mine: bool = r.get("mine") == true      # missing values arrive as null
	var rk := _label(_n(r.get("rank")), 16)
	rk.custom_minimum_size.x = 30
	row.add_child(rk)
	row.add_child(Icons.make(str(r.avatar) if r.get("avatar") else "🙂", 26))
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 0)
	var nm := _label(str(r.get("nickname", "")), 16)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_box.add_child(nm)
	var sub := _label("%s m · %s" % [game._fmt(int(r.get("dist", 0))), place_ko], 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.modulate = Color(1, 1, 1, 0.65)
	name_box.add_child(sub)
	row.add_child(name_box)
	row.add_child(_label(game._fmt(int(r.get("score", 0))), 16))
	if mine:
		row.modulate = Color("f2d27a")
	return row


func _build_board(root: Control) -> void:
	var box := _panel(root, "순위")
	board = box.get_meta("cc")
	var t1 := HBoxContainer.new()
	t1.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in [["normal", "일반"], ["hard", "어려움"]]:
		tabs[k[0]] = _tab(k[1], _pick_mode.bind(k[0]))
		t1.add_child(tabs[k[0]])
	var t2 := HBoxContainer.new()
	t2.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in [["all", "전체"], ["week", "이번 주"]]:
		tabs[k[0]] = _tab(k[1], _pick_period.bind(k[0]))
		t2.add_child(tabs[k[0]])
	box.add_child(t1)
	box.add_child(t2)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board_list = VBoxContainer.new()
	board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_list.add_theme_constant_override("separation", 6)
	scroll.add_child(board_list)
	box.add_child(scroll)
	board_me = _label("", 14)
	board_me.modulate = Color(1, 1, 1, 0.8)
	box.add_child(board_me)
	box.add_child(_btn("닫기", close_panels))


# ---------- profile panel ----------

func open_profile(hint := "", after := Callable()) -> void:
	after_profile = after
	_ensure_identity()
	picked_avatar = profile.avatar if profile.get("avatar", "") != "" else AVATARS.pick_random()
	prof_hint.text = hint if hint != "" else "순위표에 보일 이모지와 닉네임을 정하세요."
	nick.text = profile.nickname if has_nickname() else "산책자%d" % (1000 + randi() % 9000)
	prof_status.text = ""
	_render_avatars()
	_show(prof)
	nick.grab_focus()
	nick.select_all()


func _pick_mode(m: String) -> void:
	board_mode = m
	load_board()


func _pick_period(p: String) -> void:
	board_period = p
	load_board()


func _pick_avatar(a: String) -> void:
	picked_avatar = a
	_render_avatars()


func _render_avatars() -> void:
	for b in avatar_btns:
		b.button_pressed = b.get_meta("id") == picked_avatar


func save_profile(_t := "") -> void:
	var nn := nick.text.strip_edges()
	if nn.length() < 1 or nn.length() > 12:
		prof_status.text = ERRORS.bad_nickname
		return
	profile.nickname = nn
	profile.avatar = picked_avatar
	_store_profile()
	_update_profile_button()
	prof_status.text = "저장하는 중…"
	if pending_run.is_empty():      # with a pending run, the submit saves the profile too
		var r := await call_api("save_profile", {"p_player": profile.id, "p_secret": profile.secret, "p_nickname": nn, "p_avatar": picked_avatar})
		if not r.ok:
			prof_status.text = err_text(r.error)
			return
		prefetch()      # the new nickname / emoji shows on the cached boards too
	var next := after_profile
	after_profile = Callable()
	close_panels()
	if next.is_valid():
		next.call()


func _build_profile(root: Control) -> void:
	var box := _panel(root, "프로필")
	prof = box.get_meta("cc")
	prof_hint = _label("", 15)
	prof_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(prof_hint)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for a in AVATARS:
		var b := _tab("", _pick_avatar.bind(a))
		b.set_meta("id", a)
		var ic := CenterContainer.new()
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.add_child(Icons.make(a, 30))
		b.add_child(ic)
		b.custom_minimum_size = Vector2(52, 44)
		b.add_theme_font_size_override("font_size", 22)
		avatar_btns.append(b)
		grid.add_child(b)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	box.add_child(gc)
	box.add_child(_label("닉네임 (1~12자)", 13))
	nick = LineEdit.new()
	nick.max_length = 12
	nick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nick.add_theme_font_size_override("font_size", 18)
	nick.text_submitted.connect(save_profile)
	box.add_child(nick)
	prof_status = _label("", 14)
	prof_status.add_theme_color_override("font_color", Color("f2d27a"))
	box.add_child(prof_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(_btn("저장", save_profile))
	row.add_child(_btn("취소", close_panels))
	box.add_child(row)


# ---------- panel plumbing ----------

## show a panel on its own: the start / game-over card steps aside until it closes
func _show(p: Control) -> void:
	board.visible = false
	prof.visible = false
	if not hidden_panel:
		for c in [game.start_panel, game.over_panel]:
			if c.visible:
				hidden_panel = c
				c.visible = false
	p.visible = true


func close_panels() -> void:
	board.visible = false
	prof.visible = false
	after_profile = Callable()
	if hidden_panel:
		hidden_panel.visible = true
		hidden_panel = null


func _panel(root: Control, title: String) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.visible = false
	root.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.118, 0.141, 0.94)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(minf(420, game.W - 40), 0)
	panel.add_child(box)
	var t := _label(title, 28)
	t.add_theme_font_override("font", game.font_bold)
	t.add_theme_color_override("font_color", Color("f2d27a"))
	box.add_child(t)
	box.set_meta("cc", cc)
	return box


func _label(s: String, size: int) -> Label:
	var l := Label.new()
	l.text = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	return l


func _btn(s: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = s
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "TabBtn"
	b.pressed.connect(on)
	return b


## a button with a drawn icon before its text (emoji don't render on web / mobile builds)
func _icon_btn(icon_id: String, s: String, on: Callable) -> Button:
	var b := _btn("", on)
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var ic := Icons.make(icon_id, 20)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	box.add_child(l)
	b.add_child(box)
	b.set_meta("icon", ic)
	b.set_meta("label", l)
	_set_icon_btn(b, icon_id, s)
	return b


func _set_icon_btn(b: Button, icon_id: String, s: String) -> void:
	b.get_meta("icon").id = icon_id
	b.get_meta("label").text = s
	b.custom_minimum_size = Vector2(game.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 64, 40)


func _tab(s: String, on: Callable) -> Button:
	var b := _btn(s, on)
	b.toggle_mode = true
	return b
