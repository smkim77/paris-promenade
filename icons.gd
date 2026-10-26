class_name Icons
extends Control
## The emoji the game uses (scoreboard avatars, shoes, trophy), drawn as small vector icons,
## because web and mobile builds have no emoji font to fall back on. The scoreboard keeps
## storing the emoji characters themselves (shared with the web version); only the look is ours.
## As a Control it shows one icon (`id`); Icons.paint() draws one onto any CanvasItem.

const IDS := ["🥖", "🗼", "🐕", "🐦", "👞", "🥐", "🧀", "🍷", "🎨", "🚲", "🐀", "🎩", "🏆", "🙂"]

var id := "🙂":
	set(v):
		id = v
		queue_redraw()


static func make(icon_id: String, px: float) -> Icons:
	var c := Icons.new()
	c.id = icon_id
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _draw() -> void:
	paint(self, id, size / 2, minf(size.x, size.y))


## draw icon `icon_id` centred at c, s pixels across
static func paint(ci: CanvasItem, icon_id: String, c: Vector2, s: float) -> void:
	match icon_id:
		"🥖":      # baguette
			_ell(ci, c, s, 0, 0, 0.48, 0.15, Color("d9a35a"), -0.6)
			for k in 3:
				var u := (k - 1) * 0.22
				_ln(ci, c, s, u * cos(-0.6) - 0.06, u * sin(-0.6) - 0.06, u * cos(-0.6) + 0.06, u * sin(-0.6) + 0.06, 0.04, Color("a8692c"))
		"🗼":      # Eiffel Tower
			var b := Color("8a6a52")
			_poly(ci, c, s, [[-0.32, 0.46], [-0.2, 0.46], [-0.05, -0.04], [-0.12, -0.04]], b)
			_poly(ci, c, s, [[0.32, 0.46], [0.2, 0.46], [0.05, -0.04], [0.12, -0.04]], b)
			_poly(ci, c, s, [[-0.17, -0.06], [0.17, -0.06], [0.17, 0.0], [-0.17, 0.0]], b)
			_poly(ci, c, s, [[-0.1, -0.04], [0.1, -0.04], [0.03, -0.36], [-0.03, -0.36]], b)
			_poly(ci, c, s, [[-0.03, -0.36], [0.03, -0.36], [0.0, -0.5]], b)
		"🐕":      # dog
			var d := Color("b98a4e")
			for x in [-0.2, -0.12, 0.12, 0.2]:
				_ln(ci, c, s, x, 0.05, x, 0.32, 0.07, d)
			_ln(ci, c, s, -0.26, 0.0, -0.4, -0.18, 0.05, d)
			_ell(ci, c, s, -0.02, 0.05, 0.28, 0.13, d)
			_ell(ci, c, s, 0.27, -0.12, 0.13, 0.11, d)
			_ell(ci, c, s, 0.38, -0.09, 0.07, 0.05, d)
			_ell(ci, c, s, 0.21, -0.17, 0.05, 0.1, Color("7a5530"), 0.4)
			_ell(ci, c, s, 0.43, -0.1, 0.025, 0.025, Color("1b1e24"))
		"🐦":      # pigeon
			_ell(ci, c, s, -0.04, 0.06, 0.3, 0.17, Color("8a95a3"))
			_poly(ci, c, s, [[-0.3, 0.02], [-0.48, -0.06], [-0.48, 0.12]], Color("5c6b74"))
			_ell(ci, c, s, -0.06, 0.02, 0.17, 0.08, Color("6f7a88"), -0.2)
			_ell(ci, c, s, 0.24, -0.12, 0.12, 0.12, Color("4f7a6a"))
			_poly(ci, c, s, [[0.34, -0.14], [0.46, -0.1], [0.34, -0.07]], Color("c88a5a"))
			_ell(ci, c, s, 0.26, -0.15, 0.025, 0.025, Color("1b1e24"))
			_ln(ci, c, s, 0.0, 0.22, -0.02, 0.36, 0.035, Color("c88a5a"))
			_ln(ci, c, s, 0.08, 0.22, 0.1, 0.36, 0.035, Color("c88a5a"))
		"👞":      # shoe
			_poly(ci, c, s, [[-0.46, -0.18], [-0.46, 0.2], [0.46, 0.2], [0.46, 0.08], [0.22, -0.04], [-0.02, -0.08], [-0.14, -0.2]], Color("6b4423"))
			_poly(ci, c, s, [[-0.46, 0.2], [0.46, 0.2], [0.46, 0.27], [-0.46, 0.27]], Color("3a2416"))
			for k in 3:
				_ln(ci, c, s, -0.06 + k * 0.08, -0.08 + k * 0.02, 0.0 + k * 0.08, 0.02 + k * 0.02, 0.025, Color("e8dcc6"))
		"🥐":      # croissant
			for k in 5:
				var a := PI * (1.1 + k * 0.2)
				var r := 0.11 if k == 0 or k == 4 else 0.16
				_ell(ci, c, s, cos(a) * 0.3, 0.12 + sin(a) * 0.3, r, r * 0.8, Color("d9a35a") if k % 2 == 0 else Color("c98d45"), a)
		"🧀":      # cheese wedge
			_poly(ci, c, s, [[-0.44, 0.06], [0.44, -0.24], [0.44, 0.26], [-0.44, 0.26]], Color("f2c94c"))
			_poly(ci, c, s, [[-0.44, 0.06], [0.44, -0.24], [0.44, -0.12], [-0.44, 0.12]], Color("f7dc7a"))
			for h in [[-0.1, 0.17, 0.06], [0.2, 0.08, 0.07], [0.26, 0.2, 0.04]]:
				_ell(ci, c, s, h[0], h[1], h[2], h[2], Color("d9a52c"))
		"🍷":      # glass of red wine
			_ell(ci, c, s, 0, -0.2, 0.24, 0.26, Color(0.85, 0.9, 0.95, 0.5), 0, 0, PI)
			_ell(ci, c, s, 0, -0.12, 0.21, 0.2, Color("8c1c2c"), 0, 0, PI)
			_ln(ci, c, s, 0, 0.06, 0, 0.34, 0.05, Color(0.85, 0.9, 0.95, 0.9))
			_ell(ci, c, s, 0, 0.36, 0.18, 0.05, Color(0.85, 0.9, 0.95, 0.9))
		"🎨":      # painter's palette
			_ell(ci, c, s, 0, 0, 0.46, 0.36, Color("e8c99b"))
			_ell(ci, c, s, 0.18, 0.14, 0.08, 0.07, Color("b98f5c"))
			for dot in [[-0.24, -0.06, "c8372d"], [-0.06, -0.2, "1d3b6e"], [0.16, -0.16, "f2c94c"], [-0.18, 0.16, "2f5d46"]]:
				_ell(ci, c, s, dot[0], dot[1], 0.08, 0.08, Color(dot[2]))
		"🚲":      # bicycle
			var f := Color("3f6fb0")
			for x in [-0.27, 0.27]:
				ci.draw_arc(_p(c, s, x, 0.12), 0.18 * s, 0, TAU, 24, Color("1b1e24"), maxf(1.0, 0.05 * s), true)
			_ln(ci, c, s, -0.27, 0.12, -0.02, 0.12, 0.05, f)
			_ln(ci, c, s, -0.02, 0.12, -0.12, -0.12, 0.05, f)
			_ln(ci, c, s, -0.12, -0.12, 0.17, -0.12, 0.05, f)
			_ln(ci, c, s, 0.17, -0.12, -0.02, 0.12, 0.05, f)
			_ln(ci, c, s, 0.17, -0.12, 0.27, 0.12, 0.05, f)
			_ln(ci, c, s, -0.27, 0.12, -0.12, -0.12, 0.05, f)
			_ln(ci, c, s, 0.14, -0.22, 0.24, -0.22, 0.05, Color("4a4f57"))
			_ln(ci, c, s, -0.17, -0.18, -0.06, -0.18, 0.06, Color("2a2c30"))
		"🐀":      # rat
			var g := Color("7a7a80")
			ci.draw_polyline(PackedVector2Array([_p(c, s, -0.24, 0.08), _p(c, s, -0.38, 0.14), _p(c, s, -0.46, 0.04), _p(c, s, -0.44, -0.08)]), Color("d9a0a0"), maxf(1.0, 0.035 * s), true)
			_ell(ci, c, s, -0.04, 0.06, 0.24, 0.14, g)
			_poly(ci, c, s, [[0.12, -0.04], [0.42, 0.06], [0.12, 0.16]], g)
			_ell(ci, c, s, 0.12, -0.08, 0.07, 0.07, Color("d9a0a0"))
			_ell(ci, c, s, 0.26, 0.02, 0.025, 0.025, Color("1b1e24"))
			_ell(ci, c, s, 0.42, 0.06, 0.025, 0.025, Color("d98080"))
		"🎩":      # top hat
			_ell(ci, c, s, 0, 0.3, 0.44, 0.1, Color("1b1e24"))
			_poly(ci, c, s, [[-0.24, 0.3], [-0.26, -0.36], [0.26, -0.36], [0.24, 0.3]], Color("2a2c30"))
			_ell(ci, c, s, 0, -0.36, 0.26, 0.06, Color("33363d"))
			_poly(ci, c, s, [[-0.245, 0.12], [0.245, 0.12], [0.24, 0.22], [-0.24, 0.22]], Color("c8372d"))
		"🏆":      # trophy
			var au := Color("e2b84a")
			for sd in [-1.0, 1.0]:
				ci.draw_arc(_p(c, s, sd * 0.24, -0.16), 0.11 * s, 0, TAU, 20, au, maxf(1.0, 0.05 * s), true)
			_ell(ci, c, s, 0, -0.3, 0.27, 0.36, au, 0, 0, PI)
			_poly(ci, c, s, [[-0.06, 0.06], [0.06, 0.06], [0.06, 0.26], [-0.06, 0.26]], au)
			_poly(ci, c, s, [[-0.2, 0.26], [0.2, 0.26], [0.22, 0.38], [-0.22, 0.38]], Color("b38a2e"))
			_ell(ci, c, s, -0.1, -0.2, 0.05, 0.12, Color(1, 1, 1, 0.35))
		_:         # 🙂 and anything unknown
			_ell(ci, c, s, 0, 0, 0.44, 0.44, Color("f2d27a"))
			_ell(ci, c, s, -0.14, -0.1, 0.05, 0.07, Color("1b1e24"))
			_ell(ci, c, s, 0.14, -0.1, 0.05, 0.07, Color("1b1e24"))
			ci.draw_arc(_p(c, s, 0, 0.02), 0.22 * s, 0.35, PI - 0.35, 16, Color("1b1e24"), maxf(1.0, 0.05 * s), true)


static func _p(c: Vector2, s: float, x: float, y: float) -> Vector2:
	return c + Vector2(x, y) * s


static func _ell(ci: CanvasItem, c: Vector2, s: float, x: float, y: float, rx: float, ry: float, col: Color,
		rot := 0.0, a0 := 0.0, a1 := TAU) -> void:
	var pts := PackedVector2Array()
	var n := 20
	for k in n + (0 if a1 - a0 >= TAU else 1):
		var t := a0 + (a1 - a0) * k / n
		pts.append(c + (Vector2(cos(t) * rx, sin(t) * ry).rotated(rot) + Vector2(x, y)) * s)
	ci.draw_colored_polygon(pts, col)


static func _poly(ci: CanvasItem, c: Vector2, s: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p[0], p[1]) * s)
	ci.draw_colored_polygon(out, col)


static func _ln(ci: CanvasItem, c: Vector2, s: float, x0: float, y0: float, x1: float, y1: float, w: float, col: Color) -> void:
	ci.draw_line(_p(c, s, x0, y0), _p(c, s, x1, y1), col, maxf(1.0, w * s), true)
