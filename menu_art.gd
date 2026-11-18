extends Node2D
## Menu UI experiment: the main menu is one night-shift workshop.
## A fixed room (wall, floor, window, lamps, workbench with the board on a propped tray) plus a few
## small layers that follow progress already on disk. Nothing new is saved: every layer is read from
## the same best-move records as the map screen, so the room can never disagree with the records.
##   entry chapter   (01-03) -> crates go from the floor to a squared stack on the shelf
##   pull chapter    (04, 05, 08) -> rope lies loose on the shelf, then hangs coiled on the pegboard
##   challenge chapter (06, 07, 09-11) -> one tool per finished order on the pegboard
##   all eleven      -> a plant on the sill and a pinned drawing; the tray shows both crates home
##   lab requests T1-T4 -> the rest nook: lamp, stove fire, kettle on the stove, cat in its basket
## The lights that make the first night warm (wall sconce, hanging lamp) never depend on progress.

const Board = preload("res://board_view.gd")
const Catalog = preload("res://level_catalog.gd")
const Progress = preload("res://progress_store.gd")
const Fixture = preload("res://fixture_art.gd")

const INK = Color("2a1d13")
const WALL_TOP = 36.0
const FLOOR_Y = 602.0
const BOTTOM_Y = 704.0
## Interactive menu area on the left. Props never enter it, nor any label (checked by tests).
const MENU_ZONE = Rect2(60, 270, 380, 430)   # buttons, help text, sound/music rows, footer
const TRAY = Rect2(562, 318, 312, 262)
const BOARD_ORIGIN = Vector2(585, 337)
const BOARD_CELL = 38.0
const NOOK = Rect2(968, 192, 140, 410)
const NOTE_FOR = {"lamp": "等一盏灯", "stove": "炉子还冷着", "kettle": "炉上还空着", "cat": "缺块软垫"}

var phase = 0.0
var corner: Array = []        # [{id, kind, name, done}]
var fresh_id = 0              # the latest newly lit order (kept for tests)
var fresh_ids: Array = []     # lit for the first time since the menu was last shown: each pulses once
var fresh_time = 0.0
var corner_visible = true     # the level map covers the room; the nook text hides meanwhile
var chapters = {"入门篇": 0, "牵引篇": 0, "挑战篇": 0}
var chapter_sizes = {"入门篇": 0, "牵引篇": 0, "挑战篇": 0}
var main_done = 0
var _planks: Array = []       # [x, width, grain seeds] fixed once, so the wall never shimmers

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261115
	var x = 0.0
	while x < 1152.0:
		var w = [44.0, 48.0, 52.0][rng.randi_range(0, 2)]
		_planks.append([x, w, rng.randi_range(70, 540), rng.randi_range(40, 140), rng.randf() < 0.35, rng.randi_range(90, 520)])
		x += w
	refresh_corner()
	refresh_progress()
	fresh_id = GameState.fresh_fixture
	fresh_ids = GameState.fresh_fixtures.duplicate()
	GameState.fresh_fixture = 0
	GameState.fresh_fixtures.clear()

func refresh_corner() -> void:
	corner.clear()
	for id in Catalog.corner_ids():
		var fx: Dictionary = Catalog.fixture(id)
		corner.append({"id": id, "kind": String(fx["kind"]), "name": String(fx["name"]), "done": Progress.best_moves(id) >= 0})

func refresh_progress() -> void:
	main_done = 0
	for key in chapters.keys():
		chapters[key] = 0
		chapter_sizes[key] = 0
	for id in Catalog.ORDER:
		var ch = Catalog.chapter(id)
		if chapter_sizes.has(ch):
			chapter_sizes[ch] += 1
		if Progress.best_moves(id) >= 0:
			main_done += 1
			if chapters.has(ch):
				chapters[ch] += 1

func corner_done() -> int:
	var n = 0
	for item in corner:
		if item["done"]: n += 1
	return n

## Lab 3: named as lab requests, separate from the 11 main-line orders in the eyebrow line.
func corner_title() -> String:
	var done = corner_done()
	if done == 0:
		return "夜班休息角 · 完成委托会添上东西"
	if done == corner.size():
		return "夜班休息角 · %d 张委托都完成了" % corner.size()
	return "夜班休息角 · 委托 %d / %d" % [done, corner.size()]

## What the room shows right now; tests read this instead of pixels.
func workshop_state() -> Dictionary:
	var entry = chapters["入门篇"]
	var pull = chapters["牵引篇"]
	return {
		"main_done": main_done,
		"shelf_crates": 3 if entry >= chapter_sizes["入门篇"] else (2 if entry > 0 else 1),
		"floor_crates": 0 if entry >= chapter_sizes["入门篇"] else (1 if entry > 0 else 2),
		"rope": "hung" if pull >= chapter_sizes["牵引篇"] else ("loose" if pull > 0 else "none"),
		"tools": chapters["挑战篇"],
		"tray_home": 2 if main_done >= Catalog.COUNT else (1 if entry >= chapter_sizes["入门篇"] else 0),
		"finale": main_done >= Catalog.COUNT,
		"nook_lit": corner_done(),
	}

## Areas where things are drawn that are not wall or floor. Used by tests: none may touch the menu zone.
func prop_rects() -> Array:
	return [Rect2(442, 44, 120, 160), Rect2(474, 264, 36, 52), Rect2(596, 92, 268, 122), Rect2(866, 204, 98, 96),
		Rect2(692, 36, 50, 270), TRAY.grow(4), Rect2(540, 588, 360, 110), NOOK.grow_individual(4, 32, 4, 50), Rect2(493, 516, 51, 88)]

## The board's frame as drawn; the character must never cover it (checked by tests).
func board_rect() -> Rect2:
	return Rect2(BOARD_ORIGIN - Vector2(12, 12), Vector2(BOARD_CELL * 7 + 24, BOARD_CELL * 6 + 24))

func _process(delta: float) -> void:
	phase += delta
	fresh_time += delta
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _box(fill: Color, radius: int, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
	var st = StyleBoxFlat.new()
	st.bg_color = fill
	st.set_corner_radius_all(radius)
	if width > 0:
		st.border_color = border
		st.set_border_width_all(width)
	st.anti_aliasing = true
	return st

func _inked(r: Rect2, fill: Color, radius: int = 3, width: int = 2) -> void:
	draw_style_box(_box(fill, radius, INK, width), r)

func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

func _hgrad(r: Rect2, left: Color, right: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([left, right, right, left]))

## A soft pool of light: many faint discs, densest in the middle. Local only, never full screen.
func _glow(c: Vector2, radius: float, tint: Color, strength: float) -> void:
	var steps = 16
	for i in steps:
		draw_circle(c, radius * (1.0 - float(i) / steps), Color(tint, strength / steps * (0.55 + 0.45 * float(i) / steps)))

func _soft_shadow(c: Vector2, rx: float, ry: float, alpha: float) -> void:
	for i in 5:
		var k = 1.0 - i * 0.16
		_ellipse(c, rx * (1.15 - i * 0.05) , ry * (1.15 - i * 0.05), Color(0.03, 0.02, 0.01, alpha * 0.22 * k + 0.02))

func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts = PackedVector2Array()
	for i in 28:
		var a = TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)

func _ellipse_line(c: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var pts = PackedVector2Array()
	for i in 33:
		var a = TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, color, width, true)

func _text(pos: Vector2, s: String, size: int, color: Color, width: float = -1, align = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(Board.ui_font(), pos, s, align, width, size, color)

func _crate(r: Rect2, angle: float = 0.0) -> void:
	var tex = Board._texture("crate")
	if tex == null:
		_inked(r, Color("c08a52"), 4)
		return
	if angle == 0.0:
		draw_texture_rect(tex, r, false)
	else:
		draw_set_transform(r.get_center(), angle, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-r.size / 2.0, r.size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- the room (fixed)
func _draw_room() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("221d16"))
	for p in _planks:
		var r = Rect2(p[0], WALL_TOP, p[1], FLOOR_Y - WALL_TOP)
		_vgrad(r, Color("2b241c"), Color("33291f"))
		draw_rect(Rect2(p[0], WALL_TOP, 1.6, r.size.y), Color("1a1510"))
		var gx = p[0] + 10 + fmod(p[2], maxf(p[1] - 20, 1))
		draw_polyline(PackedVector2Array([Vector2(gx, p[2]), Vector2(gx + 3, p[2] + p[3] * 0.5), Vector2(gx, p[2] + p[3])]), Color("3a3025"), 1.0, true)
		if p[4]:
			_ellipse_line(Vector2(p[0] + p[1] / 2.0, p[5]), 3, 5, Color("3a3026"), 1.2)
	# ceiling beam and the original copper strip
	draw_rect(Rect2(0, 0, 1152, 12), Color("80603b"))
	draw_rect(Rect2(0, 12, 1152, 24), Color("47362a"))
	draw_rect(Rect2(0, 34, 1152, 2.5), Color("1a1510"))
	# skirting board and floor
	draw_rect(Rect2(0, FLOOR_Y - 16, 1152, 16), Color("392b1f"))
	draw_rect(Rect2(0, FLOOR_Y - 16, 1152, 2), Color("4d3a29"))
	_vgrad(Rect2(0, FLOOR_Y, 1152, BOTTOM_Y - FLOOR_Y), Color("281f17"), Color("3b2e22"))
	for y in [618.0, 640.0, 668.0]:
		draw_rect(Rect2(0, y, 1152, 1.4), Color("1d1611"))
	for seam in [[90, 602, 618], [300, 618, 640], [520, 602, 618], [700, 640, 668], [980, 618, 640], [180, 668, 704], [420, 640, 668], [860, 668, 704], [1080, 602, 618]]:
		draw_rect(Rect2(seam[0], seam[1], 1.4, seam[2] - seam[1]), Color("1d1611"))
	_vgrad(Rect2(0, FLOOR_Y - 4, 1152, 18), Color(0.02, 0.015, 0.01, 0.35), Color(0.02, 0.015, 0.01, 0.0))
	draw_rect(Rect2(0, BOTTOM_Y, 1152, 16), Color("191612"))
	# the menu keeps a calm, darker strip of the same wall so the text stays readable
	_hgrad(Rect2(0, WALL_TOP, 560, BOTTOM_Y - WALL_TOP), Color(0.07, 0.055, 0.04, 0.55), Color(0.07, 0.055, 0.04, 0.0))

func _draw_window(finale: bool) -> void:
	var r = Rect2(460, 54, 92, 132)
	_soft_shadow(Vector2(506, r.end.y + 20), 62, 6, 0.4)
	_inked(r.grow(9), Color("5e452f"), 5)
	_vgrad(r, Color("141b29"), Color("29344e"))
	for s in [[474, 74, 1.2], [502, 66, 0.9], [538, 92, 1.3], [480, 118, 0.9], [528, 134, 1.0]]:
		draw_circle(Vector2(s[0], s[1]), s[2], Color(0.96, 0.92, 0.82, 0.8))
	draw_circle(Vector2(534, 80), 10, Color("ece3c8"))
	draw_circle(Vector2(539, 77), 9, Color("19212f"))
	draw_rect(Rect2(r.position.x + r.size.x / 2 - 2, r.position.y, 4, r.size.y), Color("6b4f34"))
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y / 2 - 2, r.size.x, 4), Color("6b4f34"))
	_inked(Rect2(r.position.x - 16, r.end.y + 7, r.size.x + 32, 9), Color("86643f"), 2, 1)
	# a curtain on a rod, tied back
	_inked(Rect2(r.position.x - 18, r.position.y - 15, r.size.x + 36, 4), Color("6b4f34"), 2, 1)
	var cx = r.position.x
	var cy = r.position.y
	var curtain = PackedVector2Array([Vector2(cx - 12, cy - 10), Vector2(cx + 18, cy - 10), Vector2(cx + 14, cy + 30), Vector2(cx + 2, cy + 60),
		Vector2(cx + 8, cy + 100), Vector2(cx + 6, cy + 136), Vector2(cx - 18, cy + 136), Vector2(cx - 14, cy + 90), Vector2(cx - 8, cy + 60), Vector2(cx - 14, cy + 20)])
	draw_colored_polygon(curtain, Color("85392f"))
	curtain.append(curtain[0])
	draw_polyline(curtain, INK, 1.5, true)
	draw_line(Vector2(cx - 2, cy - 6), Vector2(cx + 2, cy + 56), Color("6a2c24"), 1.3, true)
	draw_line(Vector2(cx - 8, cy + 66), Vector2(cx - 6, cy + 132), Color("6a2c24"), 1.3, true)
	draw_line(Vector2(cx - 10, cy + 60), Vector2(cx + 12, cy + 60), Color("d1a35d"), 3.5, true)
	if finale:   # somebody brought a plant
		_inked(Rect2(r.position.x + 58, r.end.y - 9, 22, 16), Color("b0643a"), 3, 1)
		var leaf = Color("6f9a52")
		draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 69, r.end.y - 9), Vector2(r.position.x + 56, r.end.y - 30), Vector2(r.position.x + 66, r.end.y - 22)]), leaf)
		draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 69, r.end.y - 9), Vector2(r.position.x + 82, r.end.y - 34), Vector2(r.position.x + 74, r.end.y - 18)]), leaf)
		draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 69, r.end.y - 9), Vector2(r.position.x + 70, r.end.y - 38), Vector2(r.position.x + 64, r.end.y - 20)]), Color("82ad62"))

func _draw_sconce() -> void:
	# always lit: the very first night already has a warm lamp beside the menu
	_inked(Rect2(482, 304, 20, 8), Color("5a4029"), 2, 1)
	draw_polyline(PackedVector2Array([Vector2(492, 304), Vector2(492, 292), Vector2(500, 282)]), Color("5a4029"), 3, true)
	draw_colored_polygon(PackedVector2Array([Vector2(478, 278), Vector2(506, 278), Vector2(502, 268), Vector2(482, 268)]), Color("6b5334"))
	_inked(Rect2(481, 278, 22, 26), Color("ffd690"), 3, 2)
	draw_rect(Rect2(491, 279, 2, 24), Color("6b5334"))

func _draw_shelf(state: Dictionary) -> void:
	_soft_shadow(Vector2(730, 198), 128, 6, 0.45)
	_inked(Rect2(600, 180, 260, 11), Color("a57a4b"), 2)
	draw_rect(Rect2(602, 181, 256, 2), Color("d2a873"))
	for bx in [618.0, 836.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(bx, 191), Vector2(bx, 209), Vector2(bx + 14, 191)]), Color("6b4f34"))
	match int(state["shelf_crates"]):
		3:
			for p in [Vector2(616, 140), Vector2(656, 140), Vector2(636, 101)]:
				_crate(Rect2(p, Vector2(42, 42)))
			draw_rect(Rect2(626, 166, 16, 7), Color("efe2c4"))
			draw_rect(Rect2(666, 166, 16, 7), Color("efe2c4"))
		2:
			_crate(Rect2(616, 140, 42, 42))
			_crate(Rect2(662, 142, 40, 40), 0.1)
		_:
			_crate(Rect2(620, 144, 38, 38), -0.12)
	# a jar of screws and two notebooks never move: they belong to whoever works here
	_inked(Rect2(708, 150, 22, 30), Color("8fae9e"), 5, 1)
	_inked(Rect2(708, 146, 22, 7), Color("6b5334"), 2, 1)
	_inked(Rect2(744, 168, 46, 10), Color("6d7e9a"), 2, 1)
	_inked(Rect2(748, 158, 40, 10), Color("a8554a"), 2, 1)
	if state["rope"] == "loose":   # wound halfway, left lying on the shelf
		var rope = Color("c9a46a")
		_ellipse_line(Vector2(822, 172), 18, 6, Color("8a6a3e"), 6.5)
		_ellipse_line(Vector2(822, 172), 18, 6, rope, 4.0)
		draw_polyline(PackedVector2Array([Vector2(838, 176), Vector2(850, 186), Vector2(848, 200), Vector2(856, 212)]), Color("8a6a3e"), 6.0, true)
		draw_polyline(PackedVector2Array([Vector2(838, 176), Vector2(850, 186), Vector2(848, 200), Vector2(856, 212)]), rope, 3.6, true)
	if state["finale"]:   # a drawing pinned above the shelf
		draw_set_transform(Vector2(806, 128), -0.07, Vector2.ONE)
		_inked(Rect2(-17, -20, 34, 38), Color("ece0c4"), 2, 1)
		draw_colored_polygon(PackedVector2Array([Vector2(-11, 12), Vector2(-3, 0), Vector2(3, 6), Vector2(8, 1), Vector2(12, 12)]), Color("b8754a"))
		draw_circle(Vector2(5, -10), 3, Color("e2b36a"))
		draw_circle(Vector2(0, -18), 2.5, Color("c94f3f"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_pegboard(state: Dictionary) -> void:
	var r = Rect2(870, 208, 90, 88)
	_inked(r, Color("3c3125"), 3)
	for gx in range(880, 958, 12):
		for gy in range(218, 294, 12):
			draw_circle(Vector2(gx, gy), 1.5, Color("231d16"))
	if state["rope"] == "hung":
		var rope = Color("c9a46a")
		draw_rect(Rect2(884, 220, 4, 9), Color("9b8a6a"))
		_ellipse_line(Vector2(886, 252), 12, 20, Color("8a6a3e"), 6.0)
		_ellipse_line(Vector2(886, 252), 12, 20, rope, 3.8)
		_ellipse_line(Vector2(886, 254), 7, 14, rope, 3.0)
	var tools = int(state["tools"])
	var slots = [906.0, 920.0, 934.0, 948.0, 913.0]
	for i in range(mini(tools, 5)):
		var x = slots[i]
		var y = 226.0 if i < 4 else 268.0
		draw_rect(Rect2(x - 1, y - 6, 2, 6), Color("9b8a6a"))
		match i:
			0:   # hammer
				draw_rect(Rect2(x - 2, y, 4, 34), Color("8c6a44"))
				_inked(Rect2(x - 8, y, 16, 7), Color("7b858c"), 1, 1)
			1:   # wrench
				draw_line(Vector2(x, y), Vector2(x, y + 36), Color("8d9196"), 4, true)
				draw_arc(Vector2(x, y + 38), 5, 0.5, TAU - 0.5, 10, Color("8d9196"), 3, true)
			2:   # chisel
				draw_rect(Rect2(x - 2.5, y, 5, 18), Color("b0643a"))
				draw_rect(Rect2(x - 1.5, y + 18, 3, 18), Color("a4a8ac"))
			3:   # tape measure on its hook
				_inked(Rect2(x - 7, y + 2, 14, 14), Color("d4a03a"), 7, 1)
				draw_circle(Vector2(x, y + 9), 3, Color("3c3125"))
			4:   # a small hand saw, hung sideways along the bottom
				draw_colored_polygon(PackedVector2Array([Vector2(x - 26, y + 6), Vector2(x + 10, y + 2), Vector2(x + 10, y + 12), Vector2(x - 26, y + 12)]), Color("a4a8ac"))
				_inked(Rect2(x + 8, y, 12, 14), Color("8c6a44"), 3, 1)

func _draw_hanging_lamp() -> void:
	draw_rect(Rect2(716, WALL_TOP, 2, 246), Color("a68c63"))
	var shade = PackedVector2Array([Vector2(692, 300), Vector2(742, 300), Vector2(732, 280), Vector2(702, 280)])
	draw_colored_polygon(shade, Color("6b5334"))
	shade.append(shade[0])
	draw_polyline(shade, INK, 1.6, true)
	_ellipse(Vector2(717, 302), 16, 4, Color("ffe2a2"))

func _tray_board(state: Dictionary) -> Dictionary:
	var walls = []
	for x in 7:
		walls.append([x, 0])
		walls.append([x, 5])
	for y in range(1, 5):
		walls.append([0, y])
		walls.append([6, y])
	var boxes = [[3, 2], [3, 3]]
	var player = [2, 2]
	match int(state["tray_home"]):
		1: boxes = [[3, 2], [4, 3]]
		2:
			boxes = [[4, 2], [4, 3]]
			player = [3, 3]
	return {"walls": walls, "goals": [[4, 2], [4, 3]], "boxes": boxes, "player": player, "tool": [2, 4], "bench": [1, 3]}

func _draw_workbench(state: Dictionary) -> void:
	for lx in [576.0, 864.0]:
		_soft_shadow(Vector2(lx, 694), 24, 5, 0.6)
	_soft_shadow(Vector2(720, 693), 186, 9, 0.35)
	_inked(Rect2(562, 610, 22, 82), Color("6b4c31"), 2)
	_inked(Rect2(854, 610, 22, 82), Color("6b4c31"), 2)
	_inked(Rect2(578, 612, 280, 30), Color("6f5034"), 2)
	_inked(Rect2(656, 618, 124, 18), Color("7c5a3a"), 2, 1)
	draw_circle(Vector2(718, 627), 3, Color("d9b67a"))
	_inked(Rect2(544, 592, 352, 20), Color("a57a4b"), 3)
	draw_rect(Rect2(548, 593, 344, 3), Color("d8b07a"))
	# the board stands in a wooden tray, propped on two blocks and casting a shadow on the bench
	_soft_shadow(Vector2(718, 590), 158, 6, 0.55)
	_inked(Rect2(580, 576, 22, 18), Color("6b4f34"), 2, 1)
	_inked(Rect2(834, 576, 22, 18), Color("6b4f34"), 2, 1)
	_inked(TRAY, Color("ad8150"), 14, 2)
	draw_rect(Rect2(TRAY.position.x + 8, TRAY.position.y + 4, TRAY.size.x - 16, 3), Color("e2bb83"))
	draw_style_box(_box(Color("3d3225"), 9, INK, 1), Rect2(575, 331, 286, 240))
	_inked(Rect2(566, 572, 304, 10), Color("6b4f34"), 5, 1)
	Board.draw_board(self, _tray_board(state), BOARD_ORIGIN, BOARD_CELL)
	# a pencil left on the bench
	draw_line(Vector2(878, 590), Vector2(852, 585), Color("d9a441"), 3.5, true)

func _draw_floor_crates(state: Dictionary) -> void:
	var n = int(state["floor_crates"])
	if n >= 1:
		_soft_shadow(Vector2(518, 602), 24, 4, 0.55)
		_crate(Rect2(496, 558, 44, 44), 0.05)
	if n >= 2:
		_crate(Rect2(500, 522, 36, 36), -0.18)

# ---------------------------------------------------------------- the rest nook
func _note(pos: Vector2, s: String, angle: float) -> void:
	if not corner_visible:
		return
	var w = 16.0 * s.length() + 14.0
	draw_set_transform(pos, angle, Vector2.ONE)
	_inked(Rect2(0, 0, w, 24), Color("ece2c9"), 2, 1)
	_text(Vector2(0, 18), s, 15, Color("4f3c27"), w, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _level_of(item: Dictionary) -> float:
	var level = 1.0 if item["done"] else 0.0
	if fresh_ids.has(item["id"]) and fresh_time < 1.2:
		level = clampf(fresh_time / 1.2, 0.0, 1.0)   # comes on in front of the player, once
	return level

func _pulse(item: Dictionary, c: Vector2, size: float) -> void:
	if fresh_ids.has(item["id"]) and fresh_time < 2.4:
		var t = fresh_time / 2.4
		draw_arc(c, size * (0.55 + 0.35 * t), 0, TAU, 36, Color(Board.GOLD, 1.0 - t), 3.0, true)

func _item(kind: String) -> Dictionary:
	for item in corner:
		if item["kind"] == kind:
			return item
	return {}

func _draw_nook() -> void:
	var arch = PackedVector2Array([Vector2(968, FLOOR_Y)])
	arch.append(Vector2(968, 236))
	for i in 13:
		var a = PI + PI * i / 12.0
		arch.append(Vector2(1038, 236) + Vector2(cos(a) * 70, sin(a) * 44))
	arch.append(Vector2(1108, FLOOR_Y))
	draw_colored_polygon(arch, Color("2a2119"))
	arch.append(arch[0])
	draw_polyline(arch, Color("3b3024"), 2, true)
	_vgrad(Rect2(970, 200, 136, 70), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0))
	_inked(Rect2(982, 160, 112, 28), Color("4a3a28"), 4, 1)
	_text(Vector2(982, 181), "夜班休息角", 16, Color("e3cda0"), 112, HORIZONTAL_ALIGNMENT_CENTER)
	if corner_visible:
		# Menu tidy (post-exam): the count is quieter than the room it describes.
		_text(Vector2(968, 227), "委托 %d / %d" % [corner_done(), corner.size()], 15, Color(0.77, 0.68, 0.53, 0.95) if corner_done() > 0 else Color(0.77, 0.68, 0.53, 0.90), 140, HORIZONTAL_ALIGNMENT_CENTER)
	var stove = _item("stove")
	var kettle = _item("kettle")
	var lamp = _item("lamp")
	var cat = _item("cat")
	var stove_level = _level_of(stove) if not stove.is_empty() else 0.0
	var lamp_level = _level_of(lamp) if not lamp.is_empty() else 0.0
	# light first, so everything in the nook sits inside it
	if stove_level > 0.02:
		_glow(Vector2(1040, 560), 170, Color(1.0, 0.55, 0.22), 0.55 * stove_level)
		_ellipse(Vector2(1036, 624), 92, 20, Color(1.0, 0.6, 0.3, 0.10 * stove_level))
	if lamp_level > 0.02:
		_glow(Vector2(1086, 372), 86, Color(1.0, 0.82, 0.5), 0.5 * lamp_level)
	# stove pipe runs up the back of the recess
	_vgrad(Rect2(1052, 250, 18, 240), Color("3d3833"), Color("4a443d"))
	draw_rect(Rect2(1052, 250, 1.5, 240), INK)
	draw_rect(Rect2(1068.5, 250, 1.5, 240), INK)
	_soft_shadow(Vector2(1040, 600), 48, 6, 0.6)
	# rug in front of the stove
	_ellipse(Vector2(1036, 626), 70, 13, Color("7a3a31"))
	_ellipse_line(Vector2(1036, 626), 70, 13, INK, 1.5)
	_ellipse_line(Vector2(1036, 626), 54, 8, Color("c98a5a"), 1.6)
	if not stove.is_empty():
		Fixture.draw_object(self, "stove", Rect2(Vector2(965, 465), Vector2(150, 150)), stove_level, phase)
		_pulse(stove, Vector2(1040, 540), 150)
		if stove_level < 0.05:
			_note(Vector2(990, 548), NOTE_FOR["stove"], -0.05)
	if not kettle.is_empty():
		if kettle["done"] or fresh_ids.has(kettle["id"]):
			Fixture.draw_object(self, "kettle", Rect2(Vector2(984, 454), Vector2(80, 80)), _level_of(kettle), phase)
			_pulse(kettle, Vector2(1024, 494), 80)
		else:
			_note(Vector2(984, 480), NOTE_FOR["kettle"], -0.04)
	# a little wall shelf beside the pipe: the lamp lives here
	_soft_shadow(Vector2(1086, 400), 22, 4, 0.5)
	_inked(Rect2(1066, 388, 40, 7), Color("a57a4b"), 2, 1)
	draw_colored_polygon(PackedVector2Array([Vector2(1072, 395), Vector2(1072, 403), Vector2(1080, 395)]), Color("6b4f34"))
	if not lamp.is_empty():
		if lamp["done"] or fresh_ids.has(lamp["id"]):
			Fixture.draw_object(self, "lamp", Rect2(Vector2(1058, 344), Vector2(56, 56)), lamp_level, phase)
			_pulse(lamp, Vector2(1086, 372), 56)
		else:
			_note(Vector2(1032, 356), NOTE_FOR["lamp"], 0.05)
	# cat basket on the rug, beside the warm stove
	if not cat.is_empty():
		Fixture.draw_object(self, "cat", Rect2(Vector2(1042, 576), Vector2(76, 76)), _level_of(cat), phase)
		_pulse(cat, Vector2(1080, 614), 76)
		if not cat["done"] and not fresh_ids.has(cat["id"]):
			_note(Vector2(1022, 644), NOTE_FOR["cat"], 0.04)

# ---------------------------------------------------------------- lights that are always on
func _draw_lights() -> void:
	_glow(Vector2(492, 292), 250, Color(1.0, 0.7, 0.36), 0.30)
	_glow(Vector2(506, 120), 110, Color(0.62, 0.71, 0.88), 0.06)
	# the hanging lamp throws a cone down onto the tray: directional, not a wash over the room
	draw_polygon(PackedVector2Array([Vector2(694, 304), Vector2(740, 304), Vector2(838, 590), Vector2(596, 590)]),
		PackedColorArray([Color(1.0, 0.85, 0.55, 0.16), Color(1.0, 0.85, 0.55, 0.16), Color(1.0, 0.85, 0.55, 0.0), Color(1.0, 0.85, 0.55, 0.0)]))
	_glow(Vector2(717, 330), 300, Color(1.0, 0.74, 0.42), 0.26)
	_glow(Vector2(717, 303), 46, Color(1.0, 0.9, 0.65), 0.55)
	for i in 10:
		var x = 628.0 + fmod(i * 97.0 + sin(phase * 0.19 + i) * 9.0, 200.0)
		var y = 320.0 + fmod(i * 61.0 + phase * 2.5, 250.0)
		draw_circle(Vector2(x, y), 1.1, Color(0.97, 0.83, 0.55, 0.3 + 0.12 * sin(phase + i)))

func _draw_character_shadow() -> void:
	# the portrait is a TextureRect drawn above this node; its feet land here
	_soft_shadow(Vector2(940, 688), 42, 7, 0.75)

func _draw() -> void:
	var state = workshop_state()
	_draw_room()
	_draw_window(state["finale"])
	_draw_sconce()
	_draw_shelf(state)
	_draw_pegboard(state)
	_draw_hanging_lamp()
	_draw_lights()
	_draw_nook()
	_draw_floor_crates(state)
	_draw_workbench(state)
	_draw_character_shadow()
