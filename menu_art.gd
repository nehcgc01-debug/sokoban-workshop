extends Node2D

const Board = preload("res://board_view.gd")
var phase = 0.0

func _process(delta: float) -> void:
	phase += delta
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
	var board = {"walls": [[0,0],[1,0],[2,0],[3,0],[4,0],[5,0],[6,0],[0,1],[6,1],[0,2],[6,2],[0,3],[6,3],[0,4],[6,4],[0,5],[1,5],[2,5],[3,5],[4,5],[5,5],[6,5]], "goals": [[4,2],[4,3]], "boxes": [[3,2],[4,3]], "player": [2,2]}
	Board.draw_board(self, board, Vector2(576, 229), 64.0 * 0.97)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
