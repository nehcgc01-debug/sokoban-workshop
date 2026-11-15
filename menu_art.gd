extends Node2D

const Board = preload("res://board_view.gd")
const Catalog = preload("res://level_catalog.gd")
const Progress = preload("res://progress_store.gd")
const Fixture = preload("res://fixture_art.gd")
var phase = 0.0
## Lab 2: the night-shift rest corner. Each finished lab order leaves its fixture on here.
## Nothing new is saved: the corner is read from the same best-move records as the map screen,
## so it survives restarts and can never disagree with the records.
const CORNER_ORIGIN = Vector2(580, 106)
const CORNER_CELL = 58.0
const CORNER_GAP = 104.0
var corner: Array = []        # [{id, kind, name, done}]
var fresh_id = 0              # the latest newly lit order (kept for tests)
var fresh_ids: Array = []     # lit for the first time since the menu was last shown: each pulses once
var fresh_time = 0.0

func _ready() -> void:
	refresh_corner()
	fresh_id = GameState.fresh_fixture
	fresh_ids = GameState.fresh_fixtures.duplicate()
	GameState.fresh_fixture = 0
	GameState.fresh_fixtures.clear()

func refresh_corner() -> void:
	corner.clear()
	for id in Catalog.corner_ids():
		var fx: Dictionary = Catalog.fixture(id)
		corner.append({"id": id, "kind": String(fx["kind"]), "name": String(fx["name"]), "done": Progress.best_moves(id) >= 0})

func corner_done() -> int:
	var n = 0
	for item in corner:
		if item["done"]: n += 1
	return n

var corner_visible = true     # the level map covers this strip; the menu hides it meanwhile

## Lab 3: named as lab requests, separate from the 11 main-line orders in the eyebrow line.
func corner_title() -> String:
	var done = corner_done()
	if done == 0:
		return "夜班休息角 · 完成实验委托会添上东西"
	if done == corner.size():
		return "夜班休息角 · %d 张实验委托都完成了" % corner.size()
	return "夜班休息角 · 实验委托 %d / %d" % [done, corner.size()]

func _draw_corner() -> void:
	if corner.is_empty() or not corner_visible:
		return
	var font = Board.ui_font()
	var done = corner_done()
	var title = corner_title()
	draw_string(font, CORNER_ORIGIN + Vector2(0, -8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e6cf9f") if done > 0 else Color("a8997c"))
	for i in corner.size():
		var item: Dictionary = corner[i]
		var rect = Rect2(CORNER_ORIGIN + Vector2(i * CORNER_GAP, 0), Vector2.ONE * CORNER_CELL)
		var level = 1.0 if item["done"] else 0.0
		if fresh_ids.has(item["id"]) and fresh_time < 1.2:
			level = clampf(fresh_time / 1.2, 0.0, 1.0)   # comes on in front of the player, once
		Fixture.draw_glow(self, item["kind"], rect, level * 0.7, phase)
		Fixture.draw(self, item["kind"], rect, level, phase)
		if fresh_ids.has(item["id"]) and fresh_time < 2.4:
			var t = fresh_time / 2.4
			draw_arc(rect.get_center(), CORNER_CELL * (0.55 + 0.35 * t), 0, TAU, 36, Color(Board.GOLD, 1.0 - t), 3.0, true)
		var caption = String(item["name"]) if item["done"] else "%s 的委托" % Catalog.code(item["id"])
		draw_string(font, Vector2(rect.position.x - (CORNER_GAP - CORNER_CELL) / 2.0, rect.position.y + CORNER_CELL + 17), caption, HORIZONTAL_ALIGNMENT_CENTER, CORNER_GAP, 16, Color("f3bc66") if item["done"] else Color("8f846e"))

func _process(delta: float) -> void:
	phase += delta
	fresh_time += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("29261f"))
	# A quiet workshop at dusk: timber grain, lamp halo and slow dust motes.
	for y in range(0, 720, 80):
		draw_line(Vector2(0, y), Vector2(1152, y), Color("322d24"), 1)
	for i in range(9):
		var radius = 270.0 - i * 22.0
		draw_circle(Vector2(850, 208), radius, Color(0.98, 0.64, 0.25, 0.008 + i * 0.001))
	draw_rect(Rect2(0, 0, 1152, 12), Color("80603b"))
	draw_rect(Rect2(0, 704, 1152, 16), Color("211e18"))
	for x in [26, 1126]:
		draw_line(Vector2(x, 20), Vector2(x, 694), Color("5b5140"), 2)
	for i in range(16):
		var x = 520.0 + fmod(i * 97.0 + sin(phase * 0.19 + i) * 11.0, 580.0)
		var y = 130.0 + fmod(i * 71.0 + phase * 3.0, 480.0)
		draw_circle(Vector2(x, y), 1.2, Color(0.96, 0.79, 0.47, 0.25 + 0.12 * sin(phase + i)))
	# Hanging lantern and a tangible miniature board instead of a software info card.
	draw_line(Vector2(1018, 12), Vector2(1018, 106), Color("b29465"), 2)
	draw_circle(Vector2(1018, 130), 36, Color(1, 0.7, 0.25, 0.06))
	draw_style_box(_box(Color("705438"), 6), Rect2(999, 107, 38, 48))
	draw_style_box(_box(Color("f0bd6c"), 4), Rect2(1005, 112, 26, 36))
	draw_line(Vector2(1018, 112), Vector2(1018, 148), Color("9b713a"), 2)
	draw_style_box(_box(Color("654d36"), 18), Rect2(550, 207, 510, 387))
	draw_style_box(_box(Color("a17c4e"), 15), Rect2(550, 201, 510, 378))
	var board = {"walls": [[0,0],[1,0],[2,0],[3,0],[4,0],[5,0],[6,0],[0,1],[6,1],[0,2],[6,2],[0,3],[6,3],[0,4],[6,4],[0,5],[1,5],[2,5],[3,5],[4,5],[5,5],[6,5]], "goals": [[4,2],[4,3]], "boxes": [[3,2],[4,3]], "player": [2,2], "tool": [2,4], "bench": [1,3]}
	Board.draw_board(self, board, Vector2(576, 229), 64.0 * 0.97)
	_draw_corner()

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
