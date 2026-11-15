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
# Lab: tool crate. It blocks like a box, can be pushed or pulled, never counts toward the goals,
# and opens (disappears, +1 pull, never above DeadSolver.CHARGE_CAP) when it lands on the bench.
const NONE = Vector2i(-1, -1)
var tool_cell = NONE
var bench_cell = NONE
var charge_slots = 1          # how many pull slots the HUD shows (2 when the map has a tool crate)
var event_text = ""           # one-shot feedback (crate opened, pull returned), shown until the next move
var open_fx_time = 9.0
const OPEN_FX_SECONDS = 1.2
var open_fx_text = ""
var open_fx_wasted = false
var meter_flash = 9.0         # HUD pulse when a pull is spent, gained or returned
var meter_flash_gain = true
var meter_flash_label = ""
var charge_meter: Control
var dead_now = false          # the current state is proven unsolvable
var dead_unknown = false      # the solver hit its cap: no claim either way
var judge_label: Label        # "checking…" / "cannot tell", small, never a dead claim
# Lab 2: the work order's fixture (lamp, stove…) in a wall cell next to the goal.
const Fixture = preload("res://fixture_art.gd")
var fixture_kind = ""
var fixture_cell = NONE
var fixture_level = 0.0       # what is drawn; eases toward _fixture_target()
var fixture_done_before = false
var fixture_spark = 9.0       # seconds since the fixture came on (a short ring, then nothing)
var fixture_clock = 0.0
var animation_tool = false
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
var progress_save_error = OK      # Lab 3: why the last write failed, for the retry text
var progress_first_time = false   # the win that failed to save was the first one for this map
var progress_save_report: Dictionary = {}   # Lab 4: Progress.last_report of the last write
var retry_button: Button
var ability_label: Label
var audio_button: Button
var hint_button: Button
var hint_level = 0               # the hint shown now for the current stage (0 = the stage's guide)
## Lab 4: hints belong to a stage. hint_seen[stage] = highest hint the player has opened there
## (kept through undo, B and restart while the level is open). When the stage changes, the panel
## goes back to the new stage's guide; nothing is opened that the player did not ask for.
var hint_seen: Dictionary = {}
var hint_stage = "?"             # stage the shown hint belongs to; "?" until the first status update
# V7.9: the third hint is effectively the key step; ask once before showing it.
var hint_final_armed = false
# V7.7: exact dead-state check for built-in maps, Shift preview, work-order context.
const DeadSolver = preload("res://dead_state_solver.gd")
var dead_solver = null
var dead_rewind_steps = 0
var order_label: Label
var headline_label: Label
var finale_panel: PanelContainer
var finished_set_now = false
# V7.11: playtest attempt (empty unless the facilitator turned the log on).
const Playtest = preload("res://playtest_log.gd")
var attempt: Dictionary = {}
var rewinding = false   # V7.10: this win completed the whole set for the first time
var finale_label: Label
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
	if judge_pending:
		judge_slices += 1
		# about a third of a frame: 6 ms at 60 fps, more when frames are long anyway (slow GPUs, Web)
		judge_slice_usec = clampi(int(delta * 350000.0), JUDGE_SLICE_USEC, JUDGE_SLICE_MAX_USEC)
		_advance_judgement(false)
	if not fixture_kind.is_empty():
		fixture_clock += delta
		fixture_spark += delta
		var target = _fixture_target()
		if not is_equal_approx(fixture_level, target) or fixture_level > 0.0:
			fixture_level = move_toward(fixture_level, target, delta / 0.5)
			queue_redraw()
	if open_fx_time < OPEN_FX_SECONDS or meter_flash < 0.6:
		open_fx_time = minf(OPEN_FX_SECONDS, open_fx_time + delta)
		meter_flash = minf(0.6, meter_flash + delta)
		queue_redraw()
		if charge_meter: charge_meter.queue_redraw()
	if celebrate_time < CELEBRATE_SECONDS:
		celebrate_time = minf(CELEBRATE_SECONDS, celebrate_time + delta)
		queue_redraw()
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
	animation_tool = false
	effort_time = EFFORT_SECONDS

func _begin_animation(from: Vector2i, box_from: Vector2i = Vector2i(-1, -1), box_to: Vector2i = Vector2i(-1, -1), pulling: bool = false, is_tool: bool = false) -> void:
	animation_tool = is_tool
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
	var builtin = GameState.selected_builtin
	title_label.text = "试玩当前关卡" if is_preview else (Catalog.level_title(builtin) if builtin > 0 else "自定义存档 %d" % GameState.selected_slot)
	if not is_preview and builtin > 0:
		title_label.text += " · " + Catalog.chapter(builtin)
		order_label.text = Catalog.order_text(builtin)
		if Catalog.chapter(builtin) == "挑战篇":
			# Challenge chapter: the headline turns lamp-amber; the UI accent follows the situation.
			headline_label.text = "推箱工坊 · 夜班工单"
			headline_label.modulate = Board.GOLD
		elif Catalog.is_lab(builtin):
			headline_label.text = "推箱工坊 · 实验委托（不计入主线）"
			headline_label.modulate = Board.TOOL
	elif is_preview:
		headline_label.text = "推箱工坊 · 试玩台"
		order_label.text = "试玩你布置的工单 · Esc 回编辑器继续修改"
	else:
		headline_label.text = "推箱工坊 · 我的工单"
		order_label.text = "自定义工单 · 来自你的创作存档"
	if not is_preview and builtin > 0 and not Catalog.fixture(builtin).is_empty():
		var fx: Dictionary = Catalog.fixture(builtin)
		fixture_kind = String(fx["kind"])
		fixture_cell = Vector2i(int(fx["cell"][0]), int(fx["cell"][1]))
		fixture_done_before = Progress.best_moves(builtin) >= 0
		fixture_level = _fixture_target()
	restart_level()
	if Playtest.enabled() and not is_preview:
		attempt = Playtest.new_attempt(builtin, Catalog.position(builtin) if builtin > 0 else 0, GameState.selected_slot if builtin <= 0 else 0)

func _build_ui() -> void:
	RenderingServer.set_default_clear_color(Board.BG)
	var ui = CanvasLayer.new()
	add_child(ui)
	var headline = _label(ui, "推箱工坊 · 今晚的工单", Vector2(52, 32), Vector2(600, 48), 30)
	headline.modulate = Board.TEAL
	headline_label = headline
	audio_button = _button(ui, AudioService.label_text(), Vector2(930, 38), Vector2(158, 38), AudioService.toggle_mute)
	audio_button.add_theme_font_size_override("font_size", 16)
	AudioService.muted_changed.connect(func(_muted: bool): audio_button.text = AudioService.label_text())
	title_label = _label(ui, "关卡加载中", Vector2(54, 80), Vector2(640, 30), 20)
	order_label = _label(ui, "", Vector2(54, 107), Vector2(640, 28), 17)
	order_label.modulate = Color("e6cf9f")
	var panel = PanelContainer.new()
	panel.position = Vector2(710, 145)
	panel.size = Vector2(378, 474)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("373329")
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	progress_label = _label(ui, "目标 0 / 0", Vector2(736, 170), Vector2(320, 35), 24)
	count_label = _label(ui, "步数 0 · 推动 0", Vector2(736, 211), Vector2(190, 26), 18)
	judge_label = _label(ui, "", Vector2(736, 235), Vector2(190, 22), 16)
	judge_label.modulate = Color("c9b78f")
	charge_meter = Control.new()
	charge_meter.position = Vector2(930, 172)
	charge_meter.size = Vector2(132, 70)
	charge_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_meter.draw.connect(_draw_meter)
	ui.add_child(charge_meter)
	status_label = _label(ui, "把每个箱子推到金色圆环上。\n箱子到位后会显示青绿色勾标。", Vector2(736, 259), Vector2(320, 90), 18)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	undo_button = _button(ui, "撤销一步  Z", Vector2(736, 365), Vector2(148, 44), undo_move)
	_button(ui, "重新开始  R", Vector2(898, 365), Vector2(156, 44), restart_level)
	return_button = _button(ui, "返回编辑器" if not GameState.preview_data.is_empty() else "返回主菜单", Vector2(736, 424), Vector2(318, 46), leave_game)
	next_button = _button(ui, "下一关  →", Vector2(736, 482), Vector2(318, 40), next_level)
	next_button.hide()
	editor_end_button = _button(ui, "打开关卡编辑器  E", Vector2(736, 482), Vector2(318, 40), open_editor_from_ending)
	editor_end_button.hide()
	hint_button = _button(ui, "需要一点提示？ H", Vector2(736, 482), Vector2(318, 40), request_hint)
	retry_button = _button(ui, "重试保存记录  Y", Vector2(736, 532), Vector2(318, 38), retry_save)
	retry_button.visible = false
	hint_button.hide()
	hint_button.tooltip_text = "重开保留已查看提示；返回菜单再进入重置。"
	ability_label = _label(ui, "", Vector2(736, 538), Vector2(320, 74), 18)
	ability_label.modulate = Board.TEAL
	ability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability_label.add_theme_font_size_override("font_size", 16)
	# V7.9: end-of-night summary, drawn over the board only; it never takes focus or input.
	finale_panel = PanelContainer.new()
	finale_panel.position = ORIGIN + Vector2(40, 130)
	finale_panel.size = Vector2(CELL * 7 - 80, 220)
	finale_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var finale_style = StyleBoxFlat.new()
	finale_style.bg_color = Color(0.13, 0.11, 0.08, 0.92)
	finale_style.border_color = Board.GOLD
	finale_style.set_border_width_all(2)
	finale_style.set_corner_radius_all(14)
	finale_style.content_margin_left = 24
	finale_style.content_margin_right = 24
	finale_style.content_margin_top = 18
	finale_style.content_margin_bottom = 18
	finale_panel.add_theme_stylebox_override("panel", finale_style)
	finale_label = Label.new()
	finale_label.add_theme_font_size_override("font_size", 20)
	finale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finale_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	finale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	finale_panel.add_child(finale_label)
	finale_panel.hide()
	ui.add_child(finale_panel)
	_label(ui, "方向键 / WASD 移动  ·  Z 撤销  ·  R 重开  ·  按住 Shift 预览牵引  ·  B 回到出错前  ·  Esc 返回", Vector2(54, 668), Vector2(1060, 36), 17)

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
		_draw_fixture()
		_draw_full_tag()
		_draw_pull_preview()
		_draw_open_fx()
		_draw_celebration()

## V7.7: while Shift is held, show where a pull would put the box and the player.
## It only shows the result; it never judges whether the pull is a good idea.
func _draw_pull_preview() -> void:
	if not Input.is_key_pressed(KEY_SHIFT) or pull_charges <= 0 or level_complete or animation_time < MOVE_SECONDS:
		return
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var box_cell = player_pos - d
		var dest = player_pos + d
		if not (boxes.has(box_cell) or box_cell == tool_cell) or _blocked(dest) or dest in boxes or dest == tool_cell:
			continue
		var player_rect = Rect2(ORIGIN + Vector2(player_pos) * CELL, Vector2.ONE * CELL).grow(-12)
		draw_rect(player_rect, Color(0.34, 0.88, 0.75, 0.22), true)
		draw_rect(player_rect, Board.TEAL, false, 3.0)
		var from_c = ORIGIN + (Vector2(box_cell) + Vector2(0.5, 0.5)) * CELL
		var to_c = ORIGIN + (Vector2(player_pos) + Vector2(0.5, 0.5)) * CELL
		var dest_c = ORIGIN + (Vector2(dest) + Vector2(0.5, 0.5)) * CELL
		draw_line(from_c, to_c, Board.TEAL, 4.0, true)
		draw_circle(to_c, 6.0, Board.TEAL)
		draw_arc(dest_c, CELL * 0.22, 0, TAU, 28, Board.TEXT, 3.0, true)
		draw_line(to_c, dest_c, Color(Board.TEXT, 0.7), 2.0, true)
		if box_cell == tool_cell and player_pos == bench_cell:
			_draw_tag(to_c + Vector2(0, -CELL * 0.48), "开箱" if pull_charges < DeadSolver.CHARGE_CAP else "开箱 · 已满", Board.TOOL)

## V7.9: short on-board win feedback: goal rings pulse outward, then fade (presentation only).
var celebrate_time = 9.0
const CELEBRATE_SECONDS = 0.9

func _celebrate() -> void:
	celebrate_time = 0.0
	queue_redraw()

func _draw_celebration() -> void:
	if celebrate_time >= CELEBRATE_SECONDS or not level_complete:
		return
	var t = celebrate_time / CELEBRATE_SECONDS
	for g in goals:
		var c = ORIGIN + (Vector2(g) + Vector2(0.5, 0.5)) * CELL
		draw_arc(c, CELL * (0.3 + 0.45 * t), 0, TAU, 40, Color(Board.GOLD, 1.0 - t), 4.0, true)
		draw_arc(c, CELL * (0.2 + 0.3 * t), 0, TAU, 40, Color(Board.TEAL, 0.8 * (1.0 - t)), 2.0, true)

func _notification(what: int) -> void:
	# Window closed or scene freed without a recorded ending (e.g. quitting the app).
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		Playtest.finish(attempt, "win_then_closed" if level_complete else "closed_unsolved")

func _input_shift_redraw(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		queue_redraw()

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
	var visual_tool = Vector2(tool_cell)
	if animation_tool and tool_cell != NONE and animation_box_to == tool_cell and phase < 1.0:
		visual_tool = Vector2(animation_box_from).lerp(Vector2(tool_cell), eased)
	var extra = {}
	if tool_cell != NONE: extra["tool"] = [tool_cell.x, tool_cell.y]
	if bench_cell != NONE:
		extra["bench"] = [bench_cell.x, bench_cell.y]
		extra["bench_used"] = tool_cell == NONE
	extra["visual_tool"] = visual_tool
	return extra.merged({"walls": wall_list, "goals": goal_list, "boxes": box_list, "player": [player_pos.x, player_pos.y], "pull_charges": pull_charges,
		"visual_player": animation_from.lerp(Vector2(player_pos), eased) if phase < 1.0 else Vector2(player_pos),
		"visual_boxes": visual_boxes, "facing": facing, "anim_phase": phase,
		"animating": phase < 1.0, "effort": animation_effort and effort_time < EFFORT_SECONDS, "effort_progress": clampf(effort_time / EFFORT_SECONDS, 0.0, 1.0), "pulling_visual": animation_pulling and effort_time < EFFORT_SECONDS})

func restart_level() -> void:
	if initial_data.is_empty():
		return
	if loaded and not attempt.is_empty():
		attempt.restarts += 1
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
	tool_cell = Store.cell_of(initial_data, "tool")
	bench_cell = Store.cell_of(initial_data, "bench")
	charge_slots = DeadSolver.CHARGE_CAP if (bench_cell != NONE or pull_charges > 1) else 1
	event_text = ""
	open_fx_time = OPEN_FX_SECONDS
	open_fx_wasted = false
	dead_now = false
	dead_unknown = false
	level_complete = false
	preview_starts_blocked = is_preview and has_permanent_corner()
	facing = Vector2i.DOWN
	_clear_animation()
	history.clear()
	# Lab 2: the solver (and everything it has proven about this map) survives a restart.
	_cancel_judgement()
	dead_rewind_steps = 0
	dead_logged = false
	loaded = true
	_update_status()
	queue_redraw()

func _input(event: InputEvent) -> void:
	_input_shift_redraw(event)
	# Gameplay directions keep moving the character even after Tab/click focuses a button.
	# Enter/Space are left to normal focused-button activation; on victory that is Continue.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_B, KEY_Y, KEY_E, KEY_H, KEY_R, KEY_Z, KEY_ESCAPE, KEY_N, KEY_RIGHT, KEY_D, KEY_LEFT, KEY_A, KEY_DOWN, KEY_S, KEY_UP, KEY_W]:
		get_viewport().set_input_as_handled()
		_unhandled_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_B: rewind_to_last_solvable()
		KEY_Y: retry_save()
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
	var pushing_tool = next_pos == tool_cell
	var beyond = next_pos + direction
	if (box_index >= 0 or pushing_tool) and (_blocked(beyond) or beyond in boxes or beyond == tool_cell):
		return false
	history.append(_history_entry(previous_facing))
	event_text = ""
	if box_index >= 0:
		boxes[box_index] = beyond
		pushes += 1
	elif pushing_tool:
		tool_cell = beyond
		pushes += 1
	var moved_something = box_index >= 0 or pushing_tool
	_begin_animation(player_pos, next_pos if moved_something else NONE, beyond if moved_something else NONE, false, pushing_tool)
	player_pos = next_pos
	moves += 1
	if not attempt.is_empty():
		attempt.moves_made += 1
	if pushing_tool and tool_cell == bench_cell:
		_open_tool()
	_update_status()
	if box_index >= 0: _play_box_sound(beyond)
	elif pushing_tool and tool_cell != NONE: AudioService.play_effect("push")
	queue_redraw()
	return true

func _history_entry(previous_facing: Vector2i) -> Dictionary:
	return {"player": player_pos, "boxes": boxes.duplicate(), "moves": moves, "pushes": pushes, "pull_charges": pull_charges, "pulls": pulls, "facing": previous_facing, "tool": tool_cell}

## Lab: the crate is on the bench. It disappears and gives one pull, never above the cap.
func _open_tool() -> void:
	var before = pull_charges
	pull_charges = mini(pull_charges + 1, DeadSolver.CHARGE_CAP)
	tool_cell = NONE
	open_fx_time = 0.0
	open_fx_wasted = pull_charges == before
	open_fx_text = "牵引已满" if open_fx_wasted else "+1 牵引"
	_flash_meter(not open_fx_wasted, "满" if open_fx_wasted else "+1")
	event_text = ("开箱时牵引已满（%d / %d）：\n工具箱打开了，次数没有增加。Z 可撤销。" % [pull_charges, DeadSolver.CHARGE_CAP]) if open_fx_wasted \
		else "工具箱打开了：牵引 +1（%d / %d）。" % [pull_charges, DeadSolver.CHARGE_CAP]
	if not attempt.is_empty():
		attempt["tool_opened"] = true
		if open_fx_wasted: attempt["tool_wasted"] = true
	AudioService.play_effect("goal")

func _flash_meter(gain: bool, text: String = "") -> void:
	meter_flash = 0.0
	meter_flash_gain = gain
	meter_flash_label = text if not text.is_empty() else ("+1" if gain else "−1")
	if charge_meter: charge_meter.queue_redraw()

## Shift + direction retreats one cell while pulling the box behind into our old cell.
## Invalid pulls never move, consume charge, count a move, or create undo history.
func try_pull(direction: Vector2i) -> bool:
	if not loaded or level_complete or direction not in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		return false
	var previous_facing = facing
	facing = -direction
	queue_redraw()
	var destination = player_pos + direction
	var behind = player_pos - direction
	var box_index = boxes.find(behind)
	var pulling_tool = behind == tool_cell
	if pull_charges <= 0 or (box_index < 0 and not pulling_tool) or _blocked(destination) or destination in boxes or destination == tool_cell:
		if ability_label:
			if pull_charges <= 0 and tool_cell != NONE:
				ability_label.text = "牵引用完了。工具箱推上工作台可再得 1 次。"
			elif pull_charges <= 0 and int(initial_data.get("pull_charges", 0)) == 0 and bench_cell == NONE:
				ability_label.text = "这一关不提供牵引，只能推。"
			else:
				ability_label.text = "牵引未发动：需要剩余次数、身后一个箱子、前方一个空格。"
		return false
	history.append(_history_entry(previous_facing))
	event_text = ""
	_begin_animation(player_pos, behind, player_pos, true, pulling_tool)
	if pulling_tool:
		tool_cell = player_pos
	else:
		boxes[box_index] = player_pos
	player_pos = destination
	pull_charges -= 1
	pulls += 1
	moves += 1
	_flash_meter(false)
	if not attempt.is_empty():
		attempt.moves_made += 1
		attempt.pulls_used += 1
	if pulling_tool and tool_cell == bench_cell:
		_open_tool()
	_update_status()
	if not pulling_tool: _play_box_sound(destination - direction)
	queue_redraw()
	return true

func undo_move() -> void:
	if history.is_empty():
		return
	var previous: Dictionary = history.pop_back()
	if not attempt.is_empty() and not rewinding:
		attempt.undos += 1
	player_pos = previous["player"]
	boxes = previous["boxes"].duplicate()
	moves = previous["moves"]
	pushes = previous["pushes"]
	var charges_before = pull_charges
	var crate_was_open = tool_cell == NONE and bench_cell != NONE
	pull_charges = previous["pull_charges"]
	pulls = previous["pulls"]
	facing = previous.get("facing", Vector2i.DOWN)
	tool_cell = previous.get("tool", NONE)
	if tool_cell != NONE:
		open_fx_wasted = false
	event_text = ""
	if not rewinding:
		if crate_was_open and tool_cell != NONE:
			event_text = "已撤销：工具箱合上，回到原处。"
		elif pull_charges > charges_before:
			event_text = "已撤销：牵引返还 1 次。"
	if pull_charges != charges_before:
		_flash_meter(pull_charges > charges_before)
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
	hint_final_armed = false
	var was_complete = level_complete
	level_complete = all_boxes_on_goals()
	if charge_meter:
		charge_meter.queue_redraw()
	if level_complete and not was_complete and not is_preview and GameState.selected_builtin > 0:
		var first_time = Progress.best_moves(GameState.selected_builtin) < 0
		# Lab 2: only the night's own maps can complete the night (a lab order used to trigger it).
		finished_set_now = first_time and not Catalog.is_lab(GameState.selected_builtin) and _all_others_done(GameState.selected_builtin)
		progress_first_time = first_time
		_save_progress()
	if level_complete and not was_complete:
		_celebrate()
		fixture_spark = 0.0
		if not attempt.is_empty() and not attempt.solved:
			attempt.solved = true
			attempt.solve_moves = moves
			attempt.solve_at = Playtest.seconds_since(attempt)
		if is_preview:
			# V7.9: finishing a test play proves the map solvable.
			Store.mark_verified(initial_data)
	_begin_judgement()
	_refresh_texts()
	if next_button and level_complete and not was_complete:
		(next_button if next_button.visible else return_button).grab_focus()

## Lab 3: one write of the record, used by the win and by the retry button. Progress.record never
## overwrites an unreadable file and leaves the old file alone when the write cannot start.
func _save_progress() -> void:
	progress_save_error = Progress.record(GameState.selected_builtin, moves)
	progress_save_failed = progress_save_error != OK
	progress_save_report = Progress.last_report.duplicate()
	if not progress_save_failed and not Catalog.fixture(GameState.selected_builtin).is_empty():
		if progress_first_time:
			GameState.fresh_fixture = GameState.selected_builtin
			if not GameState.fresh_fixtures.has(GameState.selected_builtin):
				GameState.fresh_fixtures.append(GameState.selected_builtin)
		fixture_done_before = true

func retry_save() -> void:
	if not level_complete or not progress_save_failed or is_preview or GameState.selected_builtin <= 0:
		return
	_save_progress()
	event_text = ""
	_refresh_texts()
	if not progress_save_failed:
		event_text = "记录已保存。"
		_refresh_texts()
		if next_button and next_button.visible:
			next_button.grab_focus()

## Lab 4: two lines under "关卡完成". The second one says only what was measured after the failure
## (Progress.last_report["old"]), never a promise.
func _save_failure_text() -> String:
	if progress_save_error == ERR_FILE_CORRUPT:
		return "记录文件读不了，这次成绩未保存。\n那个文件没有动，回主菜单会另存它。"
	if String(progress_save_report.get("stage", "")) == "recover":
		# Lab 5: an earlier interrupted write could not be put back yet; nothing new is written.
		return "这次成绩未保存。\n上次中断的保存还没恢复，先不写入。"
	var old_line = {
		"unchanged": "原有记录已核对，内容没有变。",
		"none": "这一关之前没有记录。",
		"backup": "原有记录在备份里，重开游戏会恢复。",
	}.get(String(progress_save_report.get("old", "")), "无法确认原有记录是否完好。")
	return "这次成绩未保存。\n" + old_line

## One line under the retry button: what will not change, and what to do.
func _save_failure_note() -> String:
	var what = "休息角这次不会点亮" if not Catalog.fixture(GameState.selected_builtin).is_empty() else "最佳步数这次不更新"
	if progress_save_error == ERR_FILE_CORRUPT:
		return what + "；回菜单后再通关。"
	return what + "；可按 Y 重试。"

## Everything the side panel says, derived from the current state. Safe to call again at any time
## (the dead-state judgement calls it when a sliced search finishes a few frames later).
func _refresh_texts() -> void:
	_sync_hint_stage()
	if ability_label:
		ability_label.text = _ability_text()
	var matched = 0
	for box in boxes:
		if goals.has(box):
			matched += 1
	if progress_label == null:
		return
	progress_label.text = "目标 %d / %d" % [matched, goals.size()]
	count_label.text = "步数 %d · 推动 %d" % [moves, pushes]
	undo_button.disabled = history.is_empty()
	status_label.text = _play_hint()
	if not level_complete and has_permanent_corner():
		status_label.text = "起点就有箱子卡在非目标角落。\n请返回编辑器修改。" if preview_starts_blocked else "非目标角落中的箱子已无法移出。\nZ 撤销，或 R 重开再试。"
	if dead_now:
		status_label.text = _dead_text()
	if judge_label:
		judge_label.text = "死局检查中…" if judge_pending else ("图太复杂，死局无法判断" if dead_unknown and not level_complete else "")
	if hint_button:
		hint_button.disabled = has_permanent_corner() or dead_now
		hint_button.text = ("先按 B 回到出错前，再看提示" if dead_rewind_steps > 0 else "先按 Z 撤销，再看提示") if hint_button.disabled else "需要一点提示？ H"
		hint_button.visible = not level_complete and not is_preview and not Catalog.hints(GameState.selected_builtin).is_empty()
	status_label.modulate = Board.TEAL if level_complete else Color.WHITE
	if level_complete:
		status_label.text = "关卡完成！共 %d 步，推动 %d 次。\nZ 可撤销复盘。" % [moves, pushes]
		if progress_save_failed and not is_preview and GameState.selected_builtin > 0:
			status_label.text = "关卡完成！共 %d 步。\n%s" % [moves, _save_failure_text()]
		elif progress_save_failed:
			status_label.text += "\n本次通关记录未能写入磁盘。"
		elif not is_preview and GameState.selected_builtin > 0:
			# V7.7: three short lines so the text never runs under the buttons.
			var best = Progress.best_moves(GameState.selected_builtin)
			var optimal = Catalog.optimal(GameState.selected_builtin)
			status_label.text = "关卡完成！共 %d 步。\n最佳 %d 步 · 最优 %d%s\n" % [moves, best, optimal, " ★" if best <= optimal else ""]
			var line = Catalog.insight(GameState.selected_builtin)
			status_label.text += line if not line.is_empty() else "Z 可撤销复盘，R 再挑战最优。"
	if level_complete and not is_preview and Catalog.is_last(GameState.selected_builtin):
		status_label.text = "最后一关完成！共 %d 步。\n木箱归位，灯火仍暖。\n" % moves
		if progress_save_failed:
			status_label.text = "最后一关完成！共 %d 步。\n%s" % [moves, _save_failure_text()]
		else:
			status_label.text += Catalog.insight(GameState.selected_builtin)
	if ability_label:
		# Lab 4: while the retry button is shown, the one-line note moves below it instead of being covered.
		var failing = level_complete and progress_save_failed and not is_preview and GameState.selected_builtin > 0
		# the retry button's real height comes from the theme (50 px), not from the size asked for
		ability_label.position.y = (retry_button.position.y + retry_button.size.y + 2.0) if failing and retry_button else 538.0
		ability_label.size.y = 30.0 if failing else 74.0
	if retry_button:
		retry_button.visible = level_complete and progress_save_failed and not is_preview and GameState.selected_builtin > 0
		retry_button.disabled = progress_save_error == ERR_FILE_CORRUPT
	if editor_end_button:
		editor_end_button.visible = level_complete and not is_preview and Catalog.is_last(GameState.selected_builtin)
	if finale_panel:
		_update_finale()
	if next_button:
		next_button.visible = level_complete and not is_preview and GameState.selected_builtin > 0
		var at_end = Catalog.next_id(GameState.selected_builtin) == 0
		next_button.position.y = 424 if at_end else 482
		next_button.text = "返回主菜单  Enter / N" if at_end else "下一关  Enter / N"
		# On the last built-in level show a single return action, not duplicate menu buttons.
		return_button.visible = not (next_button.visible and at_end)

## ---------------- dead-state judgement ----------------
## V7.7: exact check for built-in maps. Lab: every map, with a smaller state cap for maps nobody
## has measured. Lab 2: the search never blocks the game.
## - Built-in maps are small and measured (at most a few hundred states, under 20 ms for a whole
##   search), so they are judged at once, exactly as before.
## - Custom saves and editor test plays get a short head start (JUDGE_SYNC_STATES expansions, a
##   fixed count so results do not depend on machine speed; small maps finish inside it) and
##   then continue in JUDGE_SLICE_USEC slices per frame. Moving, undoing or restarting cancels the
##   running search. While it runs the panel says so; it never says "dead" without a proof.
## - Past the cap the answer is "unknown": no claim, and this map is not asked again.
## Results: dead_now, dead_unknown, dead_rewind_steps (undo steps back to the latest solvable
## state, 0 when unknown), dead_from_start (no solvable state in this attempt) and dead_reason.
const DEAD_CAP_BUILTIN = 20000
const DEAD_CAP_CUSTOM = 8000
const JUDGE_SYNC_STATES = 60
const JUDGE_SLICE_USEC = 6000
## A sliced judgement may use this much search time in total (about 100 frames of slices). Past it
## the answer is "unknown", like past the state cap. Built-in maps never get here.
const JUDGE_SLICE_MAX_USEC = 25000
var judge_slice_usec = JUDGE_SLICE_USEC
const JUDGE_TOTAL_USEC = 600000
var judge_spent_usec = 0
var dead_solver_gave_up = false
var dead_solver_map: Array = []
var dead_from_start = false
var dead_crate_lost = false   # the decisive move also left the unopened crate provably unable to reach the bench
## Why the decisive move killed the attempt. Only what the history proves:
## "push" / "pull" (a cargo box moved), "tool_stuck" (the crate moved and can provably never reach
## the bench), "tool_moved" (the crate moved), "open" (the crate was opened), "waste" (opened at the
## cap) and "waste_short" (opened at the cap, and one more pull would make this state solvable).
var dead_reason = ""
var judge_job = null
var judge_stage = ""          # "", "now", "back", "why"
var judge_back = -1
var judge_pending = false
var judge_sync_left = 0
var judge_why: Dictionary = {}
var judge_slices = 0          # frames spent on sliced searches (tests read it)
var judge_heavy = false       # a search on this map did not fit the head start
var dead_logged = false

func _judge_cap() -> int:
	return DEAD_CAP_BUILTIN if (not is_preview and GameState.selected_builtin > 0) else DEAD_CAP_CUSTOM

func _cancel_judgement() -> void:
	if judge_job != null:
		judge_job.cancel()
	judge_job = null
	judge_stage = ""
	judge_pending = false

func _begin_judgement() -> void:
	_cancel_judgement()
	dead_now = false
	dead_unknown = false
	dead_rewind_steps = 0
	dead_from_start = false
	dead_reason = ""
	dead_crate_lost = false
	if level_complete or not loaded:
		return
	var signature = [walls.hash(), goals.hash(), bench_cell]
	if dead_solver == null or signature != dead_solver_map:
		# the solver precomputes the map; a different map (tests swap walls in place) needs a new one
		dead_solver = DeadSolver.new(walls, goals, bench_cell)
		dead_solver_map = signature
		dead_solver_gave_up = false
		judge_heavy = false
	if dead_solver_gave_up:
		dead_unknown = true
		return
	judge_stage = "now"
	judge_spent_usec = 0
	# Once a search on this map has needed slices, later ones get no head start at all: moving
	# around a heavy map must not cost a few milliseconds of search inside every key press.
	judge_sync_left = -1 if (not is_preview and GameState.selected_builtin > 0) else (0 if judge_heavy else JUDGE_SYNC_STATES)
	_advance_judgement(true)

func _stage_job():
	var cap = _judge_cap()
	if judge_stage == "back":
		var h: Dictionary = history[judge_back]
		return dead_solver.start_job(h["player"], h["boxes"], h["pull_charges"], cap, h.get("tool", NONE))
	if judge_stage == "why":
		return dead_solver.start_job(judge_why["player"], judge_why["boxes"], int(judge_why["pull_charges"]) + 1, mini(cap, 4000), NONE)
	return dead_solver.start_job(player_pos, boxes, pull_charges, cap, tool_cell)

## Runs the pending stages. sync = the head start inside the move itself; otherwise one frame slice.
func _advance_judgement(sync: bool) -> void:
	var t0 = Time.get_ticks_usec()
	while not judge_stage.is_empty():
		if judge_job == null:
			judge_job = _stage_job()
		var finished = false
		if not sync:
			finished = judge_job.step(maxi(500, judge_slice_usec - (Time.get_ticks_usec() - t0)))
		elif judge_sync_left < 0:
			finished = judge_job.step(0)
		elif judge_sync_left == 0:
			finished = not judge_job.result.is_empty()
		else:
			var before = judge_job.expanded
			finished = judge_job.step(0, judge_sync_left)
			judge_sync_left -= judge_job.expanded - before
		if not finished and not sync and judge_spent_usec + (Time.get_ticks_usec() - t0) > JUDGE_TOTAL_USEC:
			# out of time: same meaning as the state cap. A proven "dead" for the current state stays;
			# only the search for the cause / the rewind target is dropped.
			judge_job.cancel()
			judge_job = null
			if judge_stage == "now":
				dead_unknown = true
				dead_solver_gave_up = true
			judge_stage = ""
			break
		if not finished:
			judge_pending = true
			judge_heavy = true
			judge_spent_usec += Time.get_ticks_usec() - t0
			return
		var result: String = judge_job.result
		judge_job = null
		_stage_done(result)
		if not sync and not judge_stage.is_empty() and Time.get_ticks_usec() - t0 >= judge_slice_usec:
			judge_pending = true
			judge_spent_usec += Time.get_ticks_usec() - t0
			return
	var was_pending = judge_pending
	judge_pending = false
	if dead_now and not dead_logged and not attempt.is_empty():
		attempt.dead_entries += 1
		if attempt.first_dead_at < 0:
			attempt.first_dead_at = Playtest.seconds_since(attempt)
	dead_logged = dead_now
	if was_pending:
		_refresh_texts()

func _stage_done(result: String) -> void:
	match judge_stage:
		"now":
			judge_stage = ""
			if result == "unknown":
				# a map this large would restart a capped search on every move: stop asking
				dead_unknown = true
				dead_solver_gave_up = true
			elif result == "dead":
				dead_now = true
				judge_back = history.size() - 1
				if judge_back >= 0:
					judge_stage = "back"
				else:
					dead_from_start = true
		"back":
			judge_stage = ""
			if result == "solvable":
				dead_rewind_steps = history.size() - judge_back
				_classify_decisive_move()
			elif result == "dead":
				judge_back -= 1
				if judge_back >= 0:
					judge_stage = "back"
				else:
					dead_from_start = true
			# "unknown": the last solvable state cannot be named; B stays off, Z and R still work
		"why":
			judge_stage = ""
			if result == "solvable":
				dead_reason = "waste_short"

## Compares the last solvable state with the state right after it. That single move is what B undoes.
func _classify_decisive_move() -> void:
	var before: Dictionary = history[judge_back]
	var after: Dictionary = history[judge_back + 1] if judge_back + 1 < history.size() else _history_entry(facing)
	var before_tool: Vector2i = before.get("tool", NONE)
	var after_tool: Vector2i = after.get("tool", NONE)
	var pulled = int(after["pulls"]) > int(before["pulls"])
	if before_tool != NONE and after_tool == NONE:
		if not pulled and int(after["pull_charges"]) == int(before["pull_charges"]):
			dead_reason = "waste"
			judge_why = after
			judge_stage = "why"   # would one more pull have been enough?
		else:
			dead_reason = "open"
	else:
		# Only a change counts: a crate that was already out of reach before this move is not its victim.
		dead_crate_lost = after_tool != NONE and _crate_cannot_reach_bench(after["player"], after_tool, int(after["pull_charges"])) \
			and not _crate_cannot_reach_bench(before["player"], before_tool, int(before["pull_charges"]))
		if before_tool != after_tool:
			dead_reason = "tool_stuck" if dead_crate_lost else "tool_moved"
		else:
			dead_reason = "pull" if pulled else "push"

## Proof by relaxation: with every cargo box taken away the crate still cannot reach the bench.
## (Removing boxes only ever adds moves, so "dead" here is a proof; anything else proves nothing.)
func _crate_cannot_reach_bench(player: Vector2i, crate: Vector2i, charges: int) -> bool:
	if crate == NONE or bench_cell == NONE:
		return false
	var probe = DeadSolver.new(walls, {bench_cell: true}, NONE)
	return probe.status(player, [crate], charges, 3000) == "dead"

## Tests and tools: finish a sliced judgement now.
func finish_judgement() -> void:
	if judge_pending:
		judge_sync_left = -1
		_advance_judgement(true)

const DEAD_HEADS = {
	"push": "这一步推箱之后，这一局已经无解。",
	"pull": "这次牵引之后，这一局已经无解。",
	"tool_stuck": "工具箱上不了工作台了，已经无解。",
	"tool_moved": "动了工具箱之后，这一局已经无解。",
	"open": "开箱之后，这一局已经无解。",
	"waste": "满额开箱没加次数，这一局已无解。",
	"waste_short": "满额开箱没加次数，这一局已无解。",
}

## Lab: the dead-state message names only the keys that actually help here.
## Lab 2: and only a cause the move history proves; otherwise the plain sentence.
func _dead_text() -> String:
	var tail = "R 重开 · Esc 回编辑器" if is_preview else "R 重开本关"
	if dead_from_start:
		# no solvable state anywhere in this attempt's history: the map was dead from its start
		if is_preview:
			return "这张地图从起点就无解。\n请返回编辑器修改（Esc）。"
		elif GameState.selected_builtin <= 0:
			return "这张存档从起点就无解。\n请在关卡编辑器里修改它。"
	var head = "非目标角落中的箱子已无法移出。" if has_permanent_corner() else String(DEAD_HEADS.get(dead_reason, "这一局已经无解。"))
	if dead_rewind_steps > 0:
		return "%s\nB 回到出错前（撤销 %d 步）\n%s" % [head, dead_rewind_steps, tail]
	return "%s\n%s%s" % [head, "Z 撤销 · " if not history.is_empty() else "", tail]

## One or two lines under the buttons for the causes that need a rule spelled out.
func _dead_detail() -> String:
	match dead_reason:
		"waste_short":
			return "上限 %d 次，满额开箱不加次数。\n计量器里还有 %d 次，但这一局正缺那一次。" % [DeadSolver.CHARGE_CAP, pull_charges]
		"waste":
			return "上限 %d 次，满额开箱不加次数。\n工具箱已经用掉，不会再有第二个。" % DeadSolver.CHARGE_CAP
		"tool_stuck":
			return "工具箱要上工作台才会打开；\n从它现在的位置，已经到不了工作台。"
	if dead_crate_lost:
		return "工具箱还没打开，\n而且现在也到不了工作台了。"
	return ""

## V7.7: B jumps back to the last solvable state in one action, undoing the decisive mistake.
func rewind_to_last_solvable() -> void:
	var steps = dead_rewind_steps
	if steps <= 0:
		return
	if not attempt.is_empty():
		attempt.rewinds += 1
	rewinding = true
	for i in steps:
		undo_move()
	rewinding = false
	event_text = "已回到出错前（再走那一步就会无解）。"
	_refresh_texts()

## V7.9: shown only when the last map is solved and every map has a record.
func _all_others_done(id: int) -> bool:
	for other in Catalog.ORDER:
		if other != id and Progress.best_moves(other) < 0:
			return false
	return true

## V7.10: shown on the last map whenever every map has a record, and on ANY map whose win
## completes the set for the first time (levels can be played in any order).
func _update_finale() -> void:
	var show = level_complete and not is_preview and GameState.selected_builtin > 0 and not progress_save_failed \
		and (Catalog.is_last(GameState.selected_builtin) or finished_set_now)
	var done = 0
	var stars = 0
	var total_best = 0
	if show:
		for id in Catalog.ORDER:
			var best = Progress.best_moves(id)
			if best >= 0:
				done += 1
				total_best += best
				if best <= Catalog.optimal(id):
					stars += 1
		show = done == Catalog.COUNT
	finale_panel.visible = show
	if show:
		finale_label.text = "今晚的 %d 张工单全部归位\n\n各关最佳合计 %d 步 · ★ %d / %d\n%s\n\n按 E 打开关卡编辑器，布置一张你自己的工单。" % [Catalog.COUNT, total_best, stars, Catalog.COUNT, "每一关都达到了最优步数！" if stars == Catalog.COUNT else "回到工坊地图，没有 ★ 的关卡还能更省几步。"]

func open_editor_from_ending() -> void:
	# V7.10: on a middle map the summary panel (not a button) offers E, so the Next button keeps its place.
	if not loaded or not level_complete or is_preview or not (editor_end_button.visible or finale_panel.visible):
		return
	# Preserve any unfinished editor snapshot; entering is not permission to discard it.
	GameState.preview_data.clear()
	Playtest.finish(attempt, "win_then_editor")
	get_tree().change_scene_to_file("res://level_editor.tscn")

func leave_game() -> void:
	Playtest.finish(attempt, "win_then_menu" if level_complete else "left_unsolved")
	GameState.preview_data.clear()
	get_tree().change_scene_to_file("res://level_editor.tscn" if is_preview else "res://main_menu.tscn")

func next_level() -> void:
	if not level_complete or is_preview or GameState.selected_builtin <= 0:
		return
	var following = Catalog.next_id(GameState.selected_builtin)
	if following == 0:
		leave_game()
		return
	Playtest.finish(attempt, "win_then_next")
	GameState.selected_builtin = following
	get_tree().reload_current_scene()

# Only fixed wall/boundary corners prove a deadlock. Movable boxes never count.
# Suppress whenever a pull remains; this is deliberately incomplete, not a solver.
func has_permanent_corner() -> bool:
	if pull_charges > 0 or tool_cell != NONE:
		return false
	for box in boxes:
		if goals.has(box):
			continue
		if (_blocked(box + Vector2i.LEFT) or _blocked(box + Vector2i.RIGHT)) and (_blocked(box + Vector2i.UP) or _blocked(box + Vector2i.DOWN)):
			return true
	return false

func _sync_hint_stage() -> void:
	var stage = _phase()
	if stage != hint_stage:
		hint_stage = stage
		hint_level = 0
		hint_final_armed = false

func request_hint() -> void:
	if not loaded or is_preview or level_complete or Catalog.hints(GameState.selected_builtin).is_empty():
		return
	# V7.8: also blocked while the exact check says the board is dead (B / Z first).
	if has_permanent_corner() or dead_now:
		return
	_sync_hint_stage()
	var seen = int(hint_seen.get(hint_stage, 0))
	# The step-revealing hint asks once per stage; a hint already opened here is shown again directly.
	if hint_level == 2 and seen < 3 and not hint_final_armed:
		hint_final_armed = true
		status_label.text = "最后一条提示会直接给出关键步骤。\n再按一次 H 查看；继续移动则取消。"
		return
	hint_final_armed = false
	hint_level = mini(hint_level + 1, 3)
	if hint_level > seen:
		hint_seen[hint_stage] = hint_level
		if not attempt.is_empty():
			attempt.max_hint = maxi(int(attempt.max_hint), hint_level)
			attempt.hint_at.append(Playtest.seconds_since(attempt))
	_update_status()

func _play_hint() -> String:
	var hints = [] if is_preview else Catalog.hints(GameState.selected_builtin, _phase())
	if not hints.is_empty() and hint_level > 0:
		return "提示 %d / 3 · H 查看\n%s" % [hint_level, hints[hint_level-1]]
	if not is_preview and GameState.selected_builtin == 4:
		if pull_charges > 0:
			if player_pos == Vector2i(2, 2):
				return "箱子贴着左墙，无法从左边推。\n按住 Shift，再按 →：向右后退，\n把左边箱子拉到你原来的位置。"
			return "牵引还剩 1 次，普通走路不会消耗。\n先回到箱子右边的目标圈上，\n再按 Shift + → 把箱子拉出来。"
		return "牵引已用过；Z 可撤销并返还次数。"
	if not is_preview and GameState.selected_builtin > 0 and not Catalog.guide(GameState.selected_builtin).is_empty():
		return Catalog.guide(GameState.selected_builtin, _phase())
	if not is_preview and GameState.selected_builtin > 0 and int(initial_data.get("pull_charges", 0)) > 0:
		return "牵引只有一次，先观察可移动空间。\n普通走路不会消耗牵引。\nZ 可撤销试错；R 重新挑战。"
	if tool_cell != NONE:
		return "把箱子推到金色圆环上。\n红绳工具箱推上工作台，会给你 1 次牵引。"
	return "把每个箱子推到金色圆环上。\n箱子到位后会显示青绿色勾标。"

func _play_box_sound(destination: Vector2i) -> void:
	AudioService.play_effect("win" if level_complete else ("goal" if goals.has(destination) else "push"))

## ---------------- Lab: pull meter, crate-opening feedback ----------------
## Lab 2: where the board is in the crate's life, so guides and hints never talk about the past.
## Lab 3: the stage is decided by facts about the current board (see Catalog.stage_for), not by
## what happened before, so undo, B and restart can never leave a stale text behind.
func _phase() -> String:
	if is_preview or GameState.selected_builtin <= 0:
		return ""
	return Catalog.stage_for(GameState.selected_builtin, _stage_facts())

func _stage_facts() -> Dictionary:
	var home = Store.cell_of(initial_data, "tool")
	return {"open": home != NONE and tool_cell == NONE, "tool_home": tool_cell == home, "tool": tool_cell,
		"boxes": boxes, "pulls": pulls}

func _fixture_target() -> float:
	if fixture_kind.is_empty():
		return 0.0
	return 1.0 if level_complete else (0.35 if fixture_done_before else 0.0)

func _draw_fixture() -> void:
	if fixture_kind.is_empty():
		return
	var rect = Rect2(ORIGIN + Vector2(fixture_cell) * CELL, Vector2.ONE * CELL)
	Fixture.draw_glow(self, fixture_kind, rect, fixture_level, fixture_clock)
	Fixture.draw(self, fixture_kind, rect, fixture_level, fixture_clock)
	if level_complete and fixture_spark < 0.9:
		var t = fixture_spark / 0.9
		draw_arc(rect.get_center(), CELL * (0.35 + 0.5 * t), 0, TAU, 40, Color(Board.GOLD, 1.0 - t), 3.0, true)

## A small "full" tag on the bench while opening would add nothing: the rule is visible before the
## mistake, without a dialog and without saying what to do instead.
func _draw_full_tag() -> void:
	if tool_cell == NONE or bench_cell == NONE or level_complete or pull_charges < DeadSolver.CHARGE_CAP:
		return
	_draw_tag(ORIGIN + (Vector2(bench_cell) + Vector2(0.5, 0.2)) * CELL, "已满", Board.TEXT, 0.95, 16)

func _thanks_text() -> String:
	var id = GameState.selected_builtin
	if is_preview or id <= 0 or Catalog.thanks(id).is_empty():
		return ""
	var fx: Dictionary = Catalog.fixture(id)
	if progress_save_failed:
		return Catalog.thanks(id) + "\n（记录没能保存，休息角暂时不会变。）"   # (not shown while the retry is offered)
	return "%s\n主菜单的休息角里，%s。" % [Catalog.thanks(id), String(fx.get("keeps", ""))]

func _ability_text() -> String:
	if level_complete and progress_save_failed and not is_preview and GameState.selected_builtin > 0:
		return _save_failure_note()   # shown under the retry button (see _refresh_texts)
	if level_complete and not _thanks_text().is_empty():
		return _thanks_text()
	if dead_now and not _dead_detail().is_empty():
		return _dead_detail()
	if not event_text.is_empty():
		return event_text
	var start = int(initial_data.get("pull_charges", 0))
	if start == 0 and bench_cell == NONE:
		return "经典推箱关卡 · 本关不提供牵引。"
	var text = "Shift + 方向键：后退并拉动身后的箱子。"
	if tool_cell != NONE:
		if pull_charges >= DeadSolver.CHARGE_CAP:
			return "牵引已满（%d / %d）。此时开箱：\n工具箱照样消失，次数不会增加。" % [pull_charges, DeadSolver.CHARGE_CAP]
		return text + "\n工具箱上工作台 → 牵引 +1（最多 %d）" % DeadSolver.CHARGE_CAP
	if bench_cell != NONE:
		return text + "\n工具箱已打开；Z 撤销会让它合上。"
	return text + "\n%s；Z 撤销会返还次数。" % ("每关仅一次" if start <= 1 else "本关开局 %d 次" % start)

func _draw_meter() -> void:
	if charge_meter == null or initial_data.is_empty():
		return
	var start = int(initial_data.get("pull_charges", 0))
	if start == 0 and bench_cell == NONE:
		return
	var font = Board.ui_font()
	charge_meter.draw_string(font, Vector2(0, 16), "牵引", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Board.TEXT, 0.8))
	var pulse = 1.0 - clampf(meter_flash / 0.6, 0.0, 1.0)
	for i in charge_slots:
		var c = Vector2(18 + i * 40, 44)
		var full = i < pull_charges
		var ring = Board.TEAL if full else Color("6c6250")
		if pulse > 0.0 and full == meter_flash_gain and meter_flash_label != "满":
			charge_meter.draw_circle(c, 16 + 7 * pulse, Color(Board.GOLD if meter_flash_gain else Board.TEXT, 0.35 * pulse))
		charge_meter.draw_circle(c, 15, Color("2b2720"))
		# a coiled rope: three nested arcs when available, a dashed outline when empty
		if full:
			for r in [12.0, 8.0, 4.0]:
				charge_meter.draw_arc(c, r, 0, TAU, 24, ring, 2.6, true)
		else:
			for k in 8:
				var a0 = k * TAU / 8.0
				charge_meter.draw_arc(c, 12, a0, a0 + TAU / 16.0, 4, ring, 2.0, true)
	if pulse > 0.0:
		charge_meter.draw_string(font, Vector2(charge_slots * 40 + 2, 50), meter_flash_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Board.GOLD if meter_flash_gain else Board.TEXT, pulse))

func _draw_open_fx() -> void:
	if open_fx_time >= OPEN_FX_SECONDS or bench_cell == NONE:
		return
	var t = open_fx_time / OPEN_FX_SECONDS
	var c = ORIGIN + (Vector2(bench_cell) + Vector2(0.5, 0.5)) * CELL
	var color = Board.TEXT if open_fx_wasted else Board.GOLD
	# lid pops, ribbons fly, a tag rises: about one second, never covering other cells for long
	for k in 6:
		var a = k * TAU / 6.0 + 0.4
		var r = CELL * (0.2 + 0.5 * t)
		draw_line(c + Vector2.from_angle(a) * r * 0.6, c + Vector2.from_angle(a) * r, Color(Board.TOOL, 1.0 - t), 3.0, true)
	draw_arc(c, CELL * (0.25 + 0.4 * t), 0, TAU, 32, Color(color, 1.0 - t), 3.0, true)
	_draw_tag(c + Vector2(0, -CELL * (0.55 + 0.35 * t)), open_fx_text, color, 1.0 - t * t)

func _draw_tag(center: Vector2, text: String, color: Color, alpha: float = 1.0, font_size: int = 18) -> void:
	var font = Board.ui_font()
	var size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var rect = Rect2(center - Vector2(size.x / 2.0 + 10, font_size * 0.9), Vector2(size.x + 20, font_size * 1.65))
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.08, 0.88 * alpha)
	style.border_color = Color(color, alpha)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	draw_style_box(style, rect)
	draw_string(font, Vector2(rect.position.x + 10, rect.position.y + font_size * 1.17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, alpha))
