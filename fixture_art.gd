extends RefCounted
## Lab 2: small things in the workshop wall that react to finished work orders.
## One drawing routine serves the board (in a wall cell next to the goal) and the rest corner on
## the main menu, so what the player lit on the board is recognisably the same thing afterwards.
## level: 0 = never done, about 0.35 = done on an earlier visit (kept low), 1 = done right now.
## Everything is drawn with primitives; t (seconds) only drives small loops (flame, steam, breath).

static func _box(color: Color, radius: int) -> StyleBoxFlat:
	var st = StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(radius)
	return st

static func _oval(canvas: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, from: float = 0.0, to: float = TAU) -> void:
	var pts = PackedVector2Array()
	var n = 22
	for i in n + 1:
		var a = from + (to - from) * i / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if to - from < TAU - 0.01:
		pts.append(c)
	canvas.draw_colored_polygon(pts, color)

## Warm light spilling from a lit fixture onto its surroundings. Call before drawing the fixture.
static func draw_glow(canvas: CanvasItem, kind: String, rect: Rect2, level: float, t: float) -> void:
	if level <= 0.02 or kind == "cat":
		return
	var s = rect.size.x
	var c = rect.get_center()
	var tint = Color(1.0, 0.62, 0.25) if kind == "stove" else Color(1.0, 0.78, 0.42)
	var flick = 1.0 + 0.035 * sin(t * 6.3) + 0.02 * sin(t * 11.0)
	var reach = 1.55 if kind != "kettle" else 0.9
	for i in 12:
		canvas.draw_circle(c, s * reach * flick * (1.0 - i * 0.075), Color(tint, 0.026 * level))

static func draw(canvas: CanvasItem, kind: String, rect: Rect2, level: float, t: float) -> void:
	var s = rect.size.x
	var c = rect.get_center()
	# a niche cut into the masonry, so the fixture reads as part of the wall, never as a box
	canvas.draw_style_box(_box(Color("1f1b16"), int(s * 0.12)), rect.grow(-s * 0.09))
	canvas.draw_style_box(_box(Color("2e2820"), int(s * 0.10)), rect.grow(-s * 0.12))
	match kind:
		"lamp": _lamp(canvas, c, s, level, t)
		"stove": _stove(canvas, c, s, level, t)
		"kettle": _kettle(canvas, c, s, level, t)
		"cat": _cat(canvas, c, s, level, t)

static func _lamp(canvas: CanvasItem, c: Vector2, s: float, level: float, t: float) -> void:
	var glass = Color("4b4130").lerp(Color("ffd98a"), level)
	canvas.draw_line(c + Vector2(0, -s * 0.36), c + Vector2(0, -s * 0.22), Color("8a6c43"), maxf(2.0, s * 0.035), true)
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.17, -s * 0.16), c + Vector2(s * 0.17, -s * 0.16), c + Vector2(s * 0.09, -s * 0.25), c + Vector2(-s * 0.09, -s * 0.25)]), Color("6b5334"))
	canvas.draw_style_box(_box(Color("6b5334"), int(s * 0.04)), Rect2(c + Vector2(-s * 0.15, -s * 0.16), Vector2(s * 0.30, s * 0.40)))
	canvas.draw_style_box(_box(glass, int(s * 0.03)), Rect2(c + Vector2(-s * 0.11, -s * 0.12), Vector2(s * 0.22, s * 0.31)))
	canvas.draw_line(c + Vector2(0, -s * 0.12), c + Vector2(0, s * 0.19), Color("6b5334"), maxf(1.5, s * 0.025), true)
	canvas.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.24), Vector2(s * 0.36, s * 0.05)), Color("6b5334"))
	if level > 0.05:
		var f = 1.0 + 0.12 * sin(t * 7.0)
		canvas.draw_circle(c + Vector2(0, s * 0.06), s * 0.05 * f, Color(1.0, 0.95, 0.75, level))

static func _stove(canvas: CanvasItem, c: Vector2, s: float, level: float, t: float) -> void:
	var iron = Color("4a443d")
	canvas.draw_rect(Rect2(c + Vector2(s * 0.08, -s * 0.38), Vector2(s * 0.12, s * 0.30)), Color("3a3530"))
	canvas.draw_style_box(_box(iron, int(s * 0.07)), Rect2(c + Vector2(-s * 0.28, -s * 0.12), Vector2(s * 0.56, s * 0.42)))
	canvas.draw_rect(Rect2(c + Vector2(-s * 0.31, -s * 0.15), Vector2(s * 0.62, s * 0.06)), Color("5a534a"))
	for x in [-0.22, 0.16]:
		canvas.draw_rect(Rect2(c + Vector2(s * x, s * 0.30), Vector2(s * 0.06, s * 0.07)), Color("3a3530"))
	var door = Rect2(c + Vector2(-s * 0.17, -s * 0.03), Vector2(s * 0.34, s * 0.25))
	canvas.draw_style_box(_box(Color("191613").lerp(Color("c9531c"), level), int(s * 0.04)), door)
	if level > 0.05:
		var base = door.position + Vector2(0, door.size.y)
		for i in 3:
			var h = door.size.y * (0.45 + 0.3 * level) * (0.8 + 0.2 * sin(t * 8.0 + i * 2.1))
			var x0 = door.size.x * (0.14 + i * 0.26)
			canvas.draw_colored_polygon(PackedVector2Array([base + Vector2(x0, 0), base + Vector2(x0 + door.size.x * 0.22, 0), base + Vector2(x0 + door.size.x * 0.11, -h)]), Color(1.0, 0.72 + 0.1 * (i % 2), 0.28, 0.55 + 0.45 * level))
	for i in 3:   # grate bars stay in front of the fire
		var gx = door.position.x + door.size.x * (0.25 + i * 0.25)
		canvas.draw_line(Vector2(gx, door.position.y + 2), Vector2(gx, door.position.y + door.size.y - 2), Color("2a2622"), maxf(1.5, s * 0.02))

static func _kettle(canvas: CanvasItem, c: Vector2, s: float, level: float, t: float) -> void:
	canvas.draw_rect(Rect2(c + Vector2(-s * 0.32, s * 0.22), Vector2(s * 0.64, s * 0.05)), Color("7a5c38"))   # shelf
	canvas.draw_rect(Rect2(c + Vector2(-s * 0.13, s * 0.14), Vector2(s * 0.26, s * 0.08)), Color("3a3530"))   # burner
	if level > 0.05:
		for i in 3:
			var h = s * 0.07 * (0.8 + 0.3 * sin(t * 9.0 + i))
			var x0 = -s * 0.10 + i * s * 0.07
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(x0, s * 0.14), c + Vector2(x0 + s * 0.06, s * 0.14), c + Vector2(x0 + s * 0.03, s * 0.14 - h)]), Color(1.0, 0.7, 0.3, level))
	var copper = Color("a9683a")
	_oval(canvas, c + Vector2(0, -s * 0.02), s * 0.19, s * 0.15, copper)
	_oval(canvas, c + Vector2(-s * 0.05, -s * 0.06), s * 0.07, s * 0.05, Color("c98b55"))
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.14, -s * 0.03), c + Vector2(s * 0.30, -s * 0.13), c + Vector2(s * 0.29, -s * 0.08), c + Vector2(s * 0.17, s * 0.04)]), copper)
	canvas.draw_arc(c + Vector2(0, -s * 0.15), s * 0.12, PI, TAU, 14, Color("5d4630"), maxf(2.0, s * 0.035), true)
	canvas.draw_circle(c + Vector2(0, -s * 0.17), s * 0.03, Color("5d4630"))
	if level > 0.05:
		for i in 3:
			var rise = fmod(t * 0.45 + i * 0.33, 1.0)
			var p = c + Vector2(s * 0.30 + sin(t * 2.0 + i * 2.0) * s * 0.03, -s * 0.14 - rise * s * 0.26)
			canvas.draw_circle(p, s * (0.035 + 0.035 * rise), Color(0.95, 0.93, 0.88, level * 0.55 * (1.0 - rise)))

static func _cat(canvas: CanvasItem, c: Vector2, s: float, level: float, t: float) -> void:
	var fur = Color("e29a4b")
	var dark = Color("b06f2c")
	# basket with a cushion; the cat only shows up once somebody brought the padding
	_oval(canvas, c + Vector2(0, s * 0.16), s * 0.31, s * 0.17, Color("6e4a25"))
	_oval(canvas, c + Vector2(0, s * 0.13), s * 0.26, s * 0.11, Color("c9b79a") if level > 0.05 else Color("3a3127"))
	if level > 0.7:
		var breath = 1.0 + 0.03 * sin(t * 1.6)
		_oval(canvas, c + Vector2(s * 0.02, s * 0.06), s * 0.21, s * 0.13 * breath, fur)          # curled body
		canvas.draw_arc(c + Vector2(s * 0.02, s * 0.07), s * 0.19, 0.2, 2.6, 14, dark, maxf(2.0, s * 0.045), true)  # tail
		var head = c + Vector2(-s * 0.13, s * 0.02)
		canvas.draw_circle(head, s * 0.095, fur)
		canvas.draw_colored_polygon(PackedVector2Array([head + Vector2(-s * 0.09, -s * 0.04), head + Vector2(-s * 0.07, -s * 0.14), head + Vector2(-s * 0.01, -s * 0.08)]), fur)
		canvas.draw_colored_polygon(PackedVector2Array([head + Vector2(s * 0.01, -s * 0.09), head + Vector2(s * 0.06, -s * 0.14), head + Vector2(s * 0.08, -s * 0.04)]), fur)
		canvas.draw_arc(head + Vector2(-s * 0.035, s * 0.0), s * 0.022, 0.2, PI - 0.2, 6, Color("4a2e12"), maxf(1.2, s * 0.018), true)
		canvas.draw_arc(head + Vector2(s * 0.035, s * 0.0), s * 0.022, 0.2, PI - 0.2, 6, Color("4a2e12"), maxf(1.2, s * 0.018), true)
		var font = load("res://board_view.gd").ui_font()
		for i in 2:
			var rise = fmod(t * 0.35 + i * 0.5, 1.0)
			canvas.draw_string(font, c + Vector2(s * 0.12 + i * s * 0.07, -s * 0.12 - rise * s * 0.16), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * (0.13 + 0.05 * i)), Color(0.95, 0.9, 0.78, 0.8 * (1.0 - rise)))
	elif level > 0.05:
		# an earlier visit left the cushion: the cat sits up and waits
		var body = c + Vector2(0, s * 0.04)
		_oval(canvas, body, s * 0.12, s * 0.15, fur)
		var head = c + Vector2(0, -s * 0.14)
		canvas.draw_circle(head, s * 0.095, fur)
		canvas.draw_colored_polygon(PackedVector2Array([head + Vector2(-s * 0.09, -s * 0.03), head + Vector2(-s * 0.07, -s * 0.14), head + Vector2(-s * 0.01, -s * 0.08)]), fur)
		canvas.draw_colored_polygon(PackedVector2Array([head + Vector2(s * 0.01, -s * 0.08), head + Vector2(s * 0.07, -s * 0.14), head + Vector2(s * 0.09, -s * 0.03)]), fur)
		canvas.draw_circle(head + Vector2(-s * 0.035, -s * 0.005), s * 0.016, Color("3a2410"))
		canvas.draw_circle(head + Vector2(s * 0.035, -s * 0.005), s * 0.016, Color("3a2410"))
		canvas.draw_arc(body + Vector2(s * 0.10, s * 0.08), s * 0.08, -0.6, 1.8, 10, dark, maxf(2.0, s * 0.04), true)
