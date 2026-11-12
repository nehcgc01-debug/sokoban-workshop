extends Node2D
const Catalog = preload("res://level_catalog.gd")

const Store = preload("res://level_store.gd")
const Board = preload("res://board_view.gd")
const Progress = preload("res://progress_store.gd")
const ORIGIN = Vector2(70, 140)
const CELL = 80.0

var initial_data: Dictionary = {}
var walls: Dictionary = {}
var goals: Dictionary = {}
var boxes: Array = []
var player_pos = Vector2i.ZERO
var level_complete = false
var moves = 0
var pushes = 0
var pull_charges = 0
var pulls = 0
var history: Array = []
var loaded = false
var is_preview = false
var status_label: Label
var count_label: Label
var progress_label: Label
var undo_button: Button
var title_label: Label
var next_button: Button
var editor_end_button: Button
var return_button: Button
var progress_save_failed = false
var ability_label: Label
var audio_button: Button
var hint_button: Button
var hint_level = 0
var preview_starts_blocked = false
# Logical state commits immediately; these fields are presentation only.
const MOVE_SECONDS = 0.18
const EFFORT_SECONDS = 0.4
var facing = Vector2i.DOWN
var animation_time = MOVE_SECONDS
var animation_from = Vector2.ZERO
var animation_box_from = Vector2i(-1, -1)
var animation_box_to = Vector2i(-1, -1)
var animation_effort = false
var animation_pulling = false
var effort_time = EFFORT_SECONDS

func _process(delta: float) -> void:
	if animation_time < MOVE_SECONDS or effort_time < EFFORT_SECONDS:
		animation_time = minf(MOVE_SECONDS, animation_time + delta)
		effort_time = minf(EFFORT_SECONDS, effort_time + delta)
		queue_redraw()

func _clear_animation() -> void:
	animation_time = MOVE_SECONDS
	animation_from = Vector2(player_pos)
	animation_box_from = Vector2i(-1, -1)
	animation_box_to = Vector2i(-1, -1)
	animation_effort = false
	animation_pulling = false
	effort_time = EFFORT_SECONDS

func _begin_animation(from: Vector2i, box_from: Vector2i = Vector2i(-1, -1), box_to: Vector2i = Vector2i(-1, -1), pulling: bool = false) -> void:
	animation_time = 0.0
	animation_from = Vector2(from)
	animation_box_from = box_from
	animation_box_to = box_to
	animation_effort = box_from != Vector2i(-1, -1)
	animation_pulling = pulling
	effort_time = 0.0 if animation_effort else EFFORT_SECONDS

func _ready() -> void:
	_build_ui()
	is_preview = not GameState.preview_data.is_empty()
	var result: Dictionary
	if is_preview:
		var error: String = Store.validate(GameState.preview_data, true)
		result = {"ok": error.is_empty(), "error": error, "data": GameState.preview_data.duplicate(true)}
	else:
		result = Store.load_path(GameState.selected_path(), true)
	if not result.get("ok", false):
		status_label.text = "无法开始关卡\n" + str(result.get("error", "未知错误"))
		status_label.modulate = Color("ffb4a6")
		return
	initial_data = result["data"].duplicate(true)
	title_label.text = "试玩当前关卡" if is_preview else ("示例关卡 %d" % GameState.selected_builtin if GameState.selected_builtin > 0 else "自定义存档 %d" % GameState.selected_slot)
	if not is_preview and GameState.selected_builtin > 0:
		title_label.text += " · " + ("挑战篇" if GameState.selected_builtin >= 6 else "入门篇")
	restart_level()

func _build_ui() -> void:
	RenderingServer.set_default_clear_color(Board.BG)
	var ui = CanvasLayer.new()
	add_child(ui)
	var headline = _label(ui, "推箱工坊 / PLAY", Vector2(52, 32), Vector2(600, 48), 30)
	headline.modulate = Board.TEAL
	audio_button = _button(ui, AudioService.label_text(), Vector2(930, 38), Vector2(158, 38), AudioService.toggle_mute)
	audio_button.add_theme_font_size_override("font_size", 16)
	AudioService.muted_changed.connect(func(_muted: bool): audio_button.text = AudioService.label_text())
	title_label = _label(ui, "关卡加载中", Vector2(54, 87), Vector2(700, 36), 21)
	var panel = PanelContainer.new()
	panel.position = Vector2(710, 145)
	panel.size = Vector2(378, 474)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("373329")
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	progress_label = _label(ui, "目标 0 / 0", Vector2(736, 170), Vector2(320, 35), 24)
	count_label = _label(ui, "步数 0 · 推动 0", Vector2(736, 213), Vector2(320, 32), 18)
	status_label = _label(ui, "把每个箱子推到金色圆环上。\n箱子到位后会显示青绿色勾标。", Vector2(736, 259), Vector2(320, 90), 18)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	undo_button = _button(ui, "撤销一步  Z", Vector2(736, 365), Vector2(148, 44), undo_move)
	_button(ui, "重新开始  R", Vector2(898, 365), Vector2(156, 44), restart_level)
	return_button = _button(ui, "返回编辑器" if not GameState.preview_data.is_empty() else "返回主菜单", Vector2(736, 424), Vector2(318, 46), leave_game)
	next_button = _button(ui, "下一关  →", Vector2(736, 482), Vector2(318, 40), next_level)
	next_button.hide()
	editor_end_button = _button(ui, "设计自己的关卡  E", Vector2(736, 482), Vector2(318, 40), open_editor_from_ending)
	editor_end_button.hide()
	hint_button = _button(ui, "需要一点提示？ H", Vector2(736, 482), Vector2(318, 40), request_hint)
	hint_button.hide()
	hint_button.tooltip_text = "重开保留已查看提示；返回菜单再进入重置。"
	ability_label = _label(ui, "", Vector2(736, 538), Vector2(320, 74), 18)
	ability_label.modulate = Board.TEAL
	ability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability_label.add_theme_font_size_override("font_size", 16)
	_label(ui, "方向键 / WASD 移动   ·   Z 撤销   ·   R 重开   ·   Esc 返回", Vector2(54, 668), Vector2(880, 36), 18)

func _label(parent: Node, text: String, position_: Vector2, size_: Vector2, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.position = position_
	label.size = size_
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Board.TEXT)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, position_: Vector2, size_: Vector2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.position = position_
	button.size = size_
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _draw() -> void:
	if loaded:
		Board.draw_board(self, current_data(), ORIGIN, CELL)

func current_data() -> Dictionary:
	var wall_list = []
	var goal_list = []
	var box_list = []
	for p in walls:
		wall_list.append([p.x, p.y])
	for p in goals:
		goal_list.append([p.x, p.y])
	for p in boxes:
		box_list.append([p.x, p.y])
	var phase = clampf(animation_time / MOVE_SECONDS, 0.0, 1.0)
	var eased = phase * phase * (3.0 - 2.0 * phase)
	var visual_boxes = {}
	for box in boxes:
		visual_boxes[box] = Vector2(animation_box_from).lerp(Vector2(box), eased) if box == animation_box_to and phase < 1.0 else Vector2(box)
	return {"walls": wall_list, "goals": goal_list, "boxes": box_list, "player": [player_pos.x, player_pos.y], "pull_charges": pull_charges,
		"visual_player": animation_from.lerp(Vector2(player_pos), eased) if phase < 1.0 else Vector2(player_pos),
		"visual_boxes": visual_boxes, "facing": facing, "anim_phase": phase,
		"animating": phase < 1.0, "effort": animation_effort and effort_time < EFFORT_SECONDS, "effort_progress": clampf(effort_time / EFFORT_SECONDS, 0.0, 1.0), "pulling_visual": animation_pulling and effort_time < EFFORT_SECONDS}

func restart_level() -> void:
	if initial_data.is_empty():
		return
	walls.clear()
	goals.clear()
	boxes.clear()
	for point in initial_data["walls"]:
		walls[Vector2i(int(point[0]), int(point[1]))] = true
	for point in initial_data["goals"]:
		goals[Vector2i(int(point[0]), int(point[1]))] = true
	for point in initial_data["boxes"]:
		boxes.append(Vector2i(int(point[0]), int(point[1])))
	player_pos = Vector2i(int(initial_data["player"][0]), int(initial_data["player"][1]))
	moves = 0
	pushes = 0
	pulls = 0
	pull_charges = int(initial_data.get("pull_charges", 0))
	level_complete = false
	preview_starts_blocked = is_preview and has_permanent_corner()
	facing = Vector2i.DOWN
	_clear_animation()
	history.clear()
	loaded = true
	_update_status()
	queue_redraw()

func _input(event: InputEvent) -> void:
	# Gameplay directions keep moving the character even after Tab/click focuses a button.
	# Enter/Space are left to normal focused-button activation; on victory that is Continue.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_E, KEY_H, KEY_R, KEY_Z, KEY_ESCAPE, KEY_N, KEY_RIGHT, KEY_D, KEY_LEFT, KEY_A, KEY_DOWN, KEY_S, KEY_UP, KEY_W]:
		get_viewport().set_input_as_handled()
		_unhandled_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E: open_editor_from_ending()
		KEY_H: request_hint()
		KEY_R: restart_level()
		KEY_Z: undo_move()
		KEY_ESCAPE: leave_game()
		KEY_N, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: next_level()
		KEY_RIGHT, KEY_D: try_move(Vector2i.RIGHT, event.shift_pressed)
		KEY_LEFT, KEY_A: try_move(Vector2i.LEFT, event.shift_pressed)
		KEY_DOWN, KEY_S: try_move(Vector2i.DOWN, event.shift_pressed)
		KEY_UP, KEY_W: try_move(Vector2i.UP, event.shift_pressed)

func _blocked(cell: Vector2i) -> bool:
	return cell.x < 0 or cell.x >= 7 or cell.y < 0 or cell.y >= 6 or walls.has(cell)

func try_move(direction: Vector2i, pulling: bool = false) -> bool:
	if not loaded or level_complete or direction not in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		return false
	if pulling:
		return try_pull(direction)
	var previous_facing = facing
	facing = direction
	queue_redraw()
	var next_pos = player_pos + direction
	if _blocked(next_pos):
		return false
	var box_index = boxes.find(next_pos)
	if box_index >= 0 and (_blocked(next_pos + direction) or next_pos + direction in boxes):
		return false
	history.append({"player": player_pos, "boxes": boxes.duplicate(), "moves": moves, "pushes": pushes, "pull_charges": pull_charges, "pulls": pulls, "facing": previous_facing})
	if box_index >= 0:
		boxes[box_index] = next_pos + direction
		pushes += 1
	_begin_animation(player_pos, next_pos if box_index >= 0 else Vector2i(-1, -1), next_pos + direction if box_index >= 0 else Vector2i(-1, -1))
	player_pos = next_pos
	moves += 1
	_update_status()
	if box_index >= 0: _play_box_sound(next_pos + direction)
	queue_redraw()
	return true

## Shift + direction retreats one cell while pulling the box behind into our old cell.
## Invalid pulls never move, consume charge, count a move, or create undo history.
func try_pull(direction: Vector2i) -> bool:
	if not loaded or level_complete or direction not in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		return false
	var previous_facing = facing
	facing = -direction
	queue_redraw()
	var destination = player_pos + direction
	var box_index = boxes.find(player_pos - direction)
	if pull_charges <= 0 or box_index < 0 or _blocked(destination) or destination in boxes:
		if ability_label:
			ability_label.text = "牵引未发动：需要剩余次数、身后一个箱子、前方一个空格。"
		return false
	history.append({"player": player_pos, "boxes": boxes.duplicate(), "moves": moves, "pushes": pushes, "pull_charges": pull_charges, "pulls": pulls, "facing": previous_facing})
	_begin_animation(player_pos, player_pos - direction, player_pos, true)
	boxes[box_index] = player_pos
	player_pos = destination
	pull_charges -= 1
	pulls += 1
	moves += 1
	_update_status()
	_play_box_sound(destination - direction)
	queue_redraw()
	return true

func undo_move() -> void:
	if history.is_empty():
		return
	var previous: Dictionary = history.pop_back()
	player_pos = previous["player"]
	boxes = previous["boxes"].duplicate()
	moves = previous["moves"]
	pushes = previous["pushes"]
	pull_charges = previous["pull_charges"]
	pulls = previous["pulls"]
	facing = previous.get("facing", Vector2i.DOWN)
	_clear_animation()
	_update_status()
	queue_redraw()

func all_boxes_on_goals() -> bool:
	if boxes.is_empty():
		return false
	for box in boxes:
		if not goals.has(box):
			return false
	return true

func _update_status() -> void:
	if ability_label:
		ability_label.text = "牵引 %d / 1  ·  按住 Shift + 方向键，后退并拉动身后的箱子。\n每关仅一次；Z 撤销会返还次数。" % pull_charges if int(initial_data.get("pull_charges", 0)) > 0 else "经典推箱关卡 · 本关不提供牵引。"
	var was_complete = level_complete
	level_complete = all_boxes_on_goals()
	if level_complete and not was_complete and not is_preview and GameState.selected_builtin > 0:
		progress_save_failed = Progress.record(GameState.selected_builtin, moves) != OK
	var matched = 0
	for box in boxes:
		if goals.has(box):
			matched += 1
	if progress_label:
		progress_label.text = "目标 %d / %d" % [matched, goals.size()]
		count_label.text = "步数 %d · 推动 %d" % [moves, pushes]
		undo_button.disabled = history.is_empty()
		status_label.text = "关卡完成！\n可以撤销复盘、重开或返回。" if level_complete else _play_hint()
		if not level_complete and has_permanent_corner():
			status_label.text = "起点就有箱子卡在非目标角落。\n请返回编辑器修改。" if preview_starts_blocked else "非目标角落中的箱子已无法移出。\nZ 撤销，或 R 重开再试。"
		if hint_button:
			hint_button.disabled = has_permanent_corner()
			hint_button.text = "先撤销死角，再查看提示 H" if hint_button.disabled else "需要一点提示？ H"
			hint_button.visible = not level_complete and not is_preview and GameState.selected_builtin in [6,7]
		status_label.modulate = Board.TEAL if level_complete else Color.WHITE
		if level_complete:
			status_label.text = "关卡完成！共 %d 步，推动 %d 次。\nZ 可撤销复盘。" % [moves, pushes]
			if progress_save_failed:
				status_label.text += "\n本次通关记录未能写入磁盘。"
			elif not is_preview and GameState.selected_builtin > 0:
				status_label.text += " 最佳：%d 步" % Progress.best_moves(GameState.selected_builtin)
		if level_complete and not is_preview and GameState.selected_builtin == Catalog.COUNT:
			status_label.text = "最后一关完成！共 %d 步。\n木箱归位，灯火仍暖。\n" % moves
			status_label.text += "记录未保存；Z 可撤销复盘。" if progress_save_failed else "来布置你自己的关卡吧。"
		if editor_end_button:
			editor_end_button.visible = level_complete and not is_preview and GameState.selected_builtin == Catalog.COUNT
		if next_button:
			next_button.visible = level_complete and not is_preview and GameState.selected_builtin > 0
			next_button.position.y = 424 if GameState.selected_builtin >= Catalog.COUNT else 482
			next_button.text = "下一关  Enter / N" if GameState.selected_builtin < Catalog.COUNT else "返回主菜单  Enter / N"
			# On the last built-in level show a single return action, not duplicate menu buttons.
			return_button.visible = not (next_button.visible and GameState.selected_builtin >= Catalog.COUNT)
			if level_complete and not was_complete:
				(next_button if next_button.visible else return_button).grab_focus()

func open_editor_from_ending() -> void:
	if not loaded or not level_complete or is_preview or GameState.selected_builtin != Catalog.COUNT:
		return
	# Preserve any unfinished editor snapshot; entering is not permission to discard it.
	GameState.preview_data.clear()
	get_tree().change_scene_to_file("res://level_editor.tscn")

func leave_game() -> void:
	GameState.preview_data.clear()
	get_tree().change_scene_to_file("res://level_editor.tscn" if is_preview else "res://main_menu.tscn")

func next_level() -> void:
	if not level_complete or is_preview or GameState.selected_builtin <= 0:
		return
	if GameState.selected_builtin >= Catalog.COUNT:
		leave_game()
		return
	GameState.selected_builtin += 1
	get_tree().reload_current_scene()

# Only fixed wall/boundary corners prove a deadlock. Movable boxes never count.
# Suppress whenever a pull remains; this is deliberately incomplete, not a solver.
func has_permanent_corner() -> bool:
	if pull_charges > 0:
		return false
	for box in boxes:
		if goals.has(box):
			continue
		if (_blocked(box + Vector2i.LEFT) or _blocked(box + Vector2i.RIGHT)) and (_blocked(box + Vector2i.UP) or _blocked(box + Vector2i.DOWN)):
			return true
	return false

func request_hint() -> void:
	if not loaded or is_preview or level_complete or GameState.selected_builtin not in [6,7]:
		return
	if has_permanent_corner():
		return
	hint_level = mini(hint_level + 1, 3)
	_update_status()

func _play_hint() -> String:
	if not is_preview and GameState.selected_builtin in [6,7] and hint_level > 0:
		var hints = ["先别急着牵引，观察两个箱子的去路。", "有些暂时推不动的位置，牵引能救回。", "先安置下箱，再用牵引救上箱。"] if GameState.selected_builtin == 6 else ["先给另一个箱子留出通道。", "先安排下方箱子，再考虑上方目标。", "上箱到顶行后，从左边试着拉。"]
		return "提示 %d / 3 · H 查看\n%s" % [hint_level, hints[hint_level-1]]
	if not is_preview and GameState.selected_builtin == 4:
		if pull_charges > 0:
			if player_pos == Vector2i(2, 2):
				return "箱子贴着左墙，无法从左边推。\n按住 Shift，再按 →：向右后退，\n把左边箱子拉到你原来的位置。"
			return "牵引还剩 1 次，普通走路不会消耗。\n先回到箱子右边的目标圈上，\n再按 Shift + → 把箱子拉出来。"
		return "牵引已用过；Z 可撤销并返还次数。"
	if not is_preview and GameState.selected_builtin >= 5:
		return "牵引只有一次，先观察可移动空间。\n普通走路不会消耗牵引。\nZ 可撤销试错；R 重新挑战。"
	return "把每个箱子推到金色圆环上。\n箱子到位后会显示青绿色勾标。"

func _play_box_sound(destination: Vector2i) -> void:
	AudioService.play_effect("win" if level_complete else ("goal" if goals.has(destination) else "push"))
