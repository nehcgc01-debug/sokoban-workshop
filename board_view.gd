extends RefCounted

const BG = Color("29261f")
const FLOOR = Color("82745c")
const WALL = Color("746449")
const TEAL = Color("57e0c0")
const GOLD = Color("f3bc66")
const TEXT = Color("f2dfbd")
const MUTED = Color("9bafc2")

static var _textures: Dictionary = {}

static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var path = "res://art/%s.svg" % name
		if not ResourceLoader.exists(path):
			path = "res://art/%s.png" % name
		_textures[name] = load(path) if ResourceLoader.exists(path) else null
	return _textures[name] as Texture2D


static func _cells(points: Array) -> Dictionary:
	var result = {}
	for point in points:
		result[Vector2i(int(point[0]), int(point[1]))] = true
	return result

static func _rounded(canvas: Node2D, rect: Rect2, color: Color, radius: int = 8) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	canvas.draw_style_box(style, rect)

static func draw_board(canvas: Node2D, data: Dictionary, origin: Vector2, cell_size: float, selected: Vector2i = Vector2i(-1, -1)) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var walls = _cells(data.get("walls", []))
	var goals = _cells(data.get("goals", []))
	var boxes = _cells(data.get("boxes", []))
	var p = data.get("player", [-1, -1])
	var player = Vector2i(int(p[0]), int(p[1]))
	_rounded(canvas, Rect2(origin - Vector2(12, 12), Vector2(cell_size * 7 + 24, cell_size * 6 + 24)), Color("443829"), 14)
	for y in range(6):
		for x in range(7):
			var cell = Vector2i(x, y)
			var rect = Rect2(origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size)
			var center = rect.get_center()
			_rounded(canvas, rect.grow(-2), FLOOR if (x + y) % 2 == 0 else Color("82745c"), 5)
			if _texture("floor") != null:
				canvas.draw_texture_rect(_texture("floor"), rect.grow(-2), false)
			if walls.has(cell):
				_rounded(canvas, rect.grow(-3), Color("34493e"), 6)
				_rounded(canvas, Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 14)), WALL, 5)
				canvas.draw_line(rect.position + Vector2(10, 10), rect.position + Vector2(cell_size - 10, 10), Color("8c9a7d"), 2)
				if _texture("wall") != null:
					canvas.draw_texture_rect(_texture("wall"), rect.grow(-3), false)
			if goals.has(cell):
				canvas.draw_arc(center, cell_size * 0.38, 0, TAU, 32, Color("473a26"), 7, true)
				canvas.draw_arc(center, cell_size * 0.38, 0, TAU, 32, Color("ffe5a8"), 3, true)
				canvas.draw_circle(center, 4, GOLD)
				if _texture("goal") != null:
					canvas.draw_texture_rect(_texture("goal"), rect.grow(-3), false)
	# Draw moving objects after the whole floor so interpolation is never covered by a later tile.
	for cell in boxes:
		var visual_cell: Vector2 = data.get("visual_boxes", {}).get(cell, Vector2(cell))
		var rect = Rect2(origin + visual_cell * cell_size, Vector2.ONE * cell_size)
		var center = rect.get_center()
		if _texture("crate") != null:
			canvas.draw_texture_rect(_texture("crate"), rect.grow(-5), false)
		else:
			_rounded(canvas, rect.grow(-12), GOLD, 6)
		if goals.has(cell):
			var badge = rect.position + Vector2(cell_size - 12, 12)
			canvas.draw_circle(badge, 9, TEAL)
			canvas.draw_line(badge + Vector2(-4, 0), badge + Vector2(-1, 3), BG, 2, true)
			canvas.draw_line(badge + Vector2(-1, 3), badge + Vector2(5, -4), BG, 2, true)
	if player.x >= 0 and player.y >= 0:
		_draw_player(canvas, data, origin, cell_size, player)
	if selected.x >= 0 and selected.y >= 0:
		canvas.draw_rect(Rect2(origin + Vector2(selected) * cell_size, Vector2.ONE * cell_size).grow(-1), Color("edf6fc"), false, 2)

static func _direction_texture(facing: Vector2i) -> Texture2D:
	# Generated static directional poses; motion is procedural, not hand-drawn animation frames.
	if _texture("player_directions") == null or facing == Vector2i.DOWN:
		return _texture("player")
	var key = "direction_%d_%d" % [facing.x, facing.y]
	if not _textures.has(key):
		var sheet = _texture("player_directions")
		var regions = {Vector2i.RIGHT: Rect2(801, 30, 254, 542), Vector2i.UP: Rect2(179, 657, 279, 542), Vector2i.LEFT: Rect2(814, 657, 265, 542)}
		var atlas = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = regions[facing]
		_textures[key] = atlas
	return _textures[key]

static func _draw_player(canvas: Node2D, data: Dictionary, origin: Vector2, cell_size: float, player: Vector2i) -> void:
	var facing: Vector2i = data.get("facing", Vector2i.DOWN)
	var center = origin + (Vector2(data.get("visual_player", Vector2(player))) + Vector2.ONE * 0.5) * cell_size
	var phase: float = data.get("anim_phase", 1.0)
	var moving: bool = data.get("animating", false)
	var effort: bool = data.get("effort", false)
	var bob = sin(phase * PI) if moving else 0.0
	var texture = _direction_texture(facing)
	if texture == null:
		canvas.draw_circle(center, cell_size * 0.25, TEAL)
		return
	# Feet stay grounded; one light squash/bob communicates stepping, a lean communicates effort.
	var height = cell_size * 0.94
	var width = height * texture.get_width() / float(texture.get_height())
	center.y -= bob * cell_size * 0.045
	var lean = float(facing.x) * bob * (0.12 if effort else 0.035)
	canvas.draw_set_transform(center, lean, Vector2(1.0 + bob * 0.035, 1.0 - bob * 0.035))
	canvas.draw_texture_rect(texture, Rect2(Vector2(-width / 2.0, -height / 2.0), Vector2(width, height)), false)
	canvas.draw_set_transform(Vector2.ZERO)
	if effort:
		var progress: float = data.get("effort_progress", phase)
		var drop = center + Vector2(cell_size * 0.23, -cell_size * 0.27 + progress * cell_size * 0.10)
		var tint = Color("91e7ef")
		canvas.draw_colored_polygon(PackedVector2Array([drop + Vector2(0, -7), drop + Vector2(-3, 1), drop + Vector2(3, 1)]), tint)
		canvas.draw_circle(drop + Vector2(0, 1), 3, tint)
		# Small exertion marks behind the shoulders, distinct from sweat.
		canvas.draw_line(center + Vector2(-24, -4), center + Vector2(-29, -8), GOLD, 2, true)
