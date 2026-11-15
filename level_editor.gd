extends Node2D

# The editor keeps draft data separate from gameplay. Preview never writes a save.
const Store = preload("res://level_store.gd")
const Board = preload("res://board_view.gd")
const BOARD_ORIGIN = Vector2(48, 142)
const CELL_SIZE = 68.0
const TOOL_NAMES = {"wall": "墙", "floor": "擦除", "goal": "目标光圈", "box": "箱子", "player": "玩家起点", "tool": "工具箱", "bench": "工作台"}
const TOOL_KEYS = ["wall", "floor", "goal", "box", "player", "tool", "bench"]
const NONE = Vector2i(-1, -1)
const DeadSolver = preload("res://dead_state_solver.gd")
const CHECK_STATE_CAP = 300000

const DraftRecovery = preload("res://draft_recovery.gd")
var recovery_issue = ""
var recovery_fingerprint = ""
# V7.12: a kept draft from an earlier session that differs from the map we were asked to open.
# While held, nothing may overwrite or clear it until the player chooses.
var held_recovery: Dictionary = {}
# V7.13: slot the unsaved draft was based on, kept across restores (file_slot is 0 for a draft).
var draft_origin = 0
# V7.13: undo / redo of map edits. Each entry is a full map (7x6, tiny). clean_fingerprint is the
# map as last loaded or saved, so undoing back to it is not "unsaved" any more.
const UNDO_LIMIT = 100
var undo_stack: Array = []
var redo_stack: Array = []
var clean_fingerprint = ""
var conflict_dialog: AcceptDialog
var conflict_discard_button: Button
var leave_dialog: ConfirmationDialog

var walls: Dictionary = {}
var goals: Dictionary = {}
var boxes: Dictionary = {}
var player_cell = Vector2i(-1, -1)
var tool_cell = Vector2i(-1, -1)    # Lab: at most one tool crate and one bench per map
var bench_cell = Vector2i(-1, -1)
var pull_two: CheckButton
var check_label: Label
var selected_cell = Vector2i(-1, -1)
var selected_tool = "wall"
var save_slot = 0
var file_slot = 0          # V7.12: the slot the map on screen was last loaded from or saved to (0 = none)
var dirty = false
var pull_charges = 0
var pull_toggle: CheckButton
var popup_mode = "load"
var pending_slot = 0
var pending_data: Dictionary = {}
var pending_action = ""
var pending_is_original = false
var tool_buttons: Dictionary = {}
var status_label: Label
var dirty_label: Label
var tool_label: Label
var selection_label: Label
var slot_popup: PopupPanel
var slot_buttons: Array[Button] = []
var slot_confirm: Button
var overwrite_dialog: ConfirmationDialog
var discard_dialog: ConfirmationDialog
var error_dialog: AcceptDialog
# V7.9: background solvability check and share codes.
var check_fingerprint = ""
var check_button: Button
var pending_is_shared = false
# V7.11: share-code dialog with a text box (paste target on Web, manual copy fallback).
var share_dialog: ConfirmationDialog
var share_edit: LineEdit
var share_mode = ""          # "paste" or "copy"
var share_note: Label
var js_callbacks = []        # keep JavaScript callbacks alive while promises are pending

func _ready() -> void:
	_build_ui()
	_build_share_dialog()
	_build_draft_dialogs()
	var recovered = false
	var kept = DraftRecovery.load_draft()
	if GameState.editor_snapshot.is_empty():
		GameState.editor_snapshot = kept
		recovered = not kept.is_empty()
	if not GameState.editor_snapshot.is_empty():
		var snapshot: Dictionary = GameState.editor_snapshot.duplicate(true)
		if Store.validate(snapshot, false).is_empty():
			_apply_data(snapshot)
			dirty = bool(snapshot.get("_dirty", false))
			save_slot = int(snapshot.get("_slot", 0))
			file_slot = save_slot
			selected_tool = str(snapshot.get("_tool", "wall"))
			draft_origin = int(snapshot.get("_origin", 0))
	# undo history survives a test play (the editor scene is rebuilt), nothing else
	var history: Dictionary = GameState.editor_history
	if not recovered and not history.is_empty():
		undo_stack = history.get("undo", []).duplicate(true)
		redo_stack = history.get("redo", []).duplicate(true)
		clean_fingerprint = str(history.get("clean", ""))
	elif not dirty:
		clean_fingerprint = Store.fingerprint(_serialize())
	# V7.12: opening another map (e.g. an unfinished slot draft from the level list) must not
	# silently replace a draft the player chose to keep when closing the window.
	if not recovered and not kept.is_empty() and Store.fingerprint(kept) != Store.fingerprint(_serialize()):
		held_recovery = kept
		_ask_about_kept_draft.call_deferred()
	GameState.preview_data = {}
	_select_tool(selected_tool)
	_refresh_status()
	queue_redraw()
	if recovered:
		_announce_recovered(int(kept.get("_origin", 0)))

func _announce_recovered(origin: int) -> void:
	var base = "（基于存档 %d，存档本身未改动）" % origin if origin > 0 else ""
	status_label.text = "已恢复上次未保存的草稿%s。请保存到存档槽。" % base

func _build_draft_dialogs() -> void:
	conflict_dialog = AcceptDialog.new()
	conflict_dialog.title = "有一份未保存的草稿"
	conflict_dialog.ok_button_text = "恢复那份草稿"
	conflict_discard_button = conflict_dialog.add_button("放弃那份草稿", false, "discard")
	conflict_dialog.exclusive = true
	conflict_dialog.confirmed.connect(_restore_held)
	conflict_dialog.canceled.connect(_restore_held)   # closing the box is the safe choice
	conflict_dialog.custom_action.connect(_conflict_action)
	add_child(conflict_dialog)
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "返回主菜单"
	leave_dialog.dialog_text = "当前地图有未保存改动。\n保留后，下次打开编辑器会自动恢复（不会写入存档槽）。"
	leave_dialog.ok_button_text = "保留草稿并返回"
	leave_dialog.cancel_button_text = "取消"
	leave_dialog.add_button("放弃改动并返回", false, "discard")
	leave_dialog.exclusive = true
	leave_dialog.confirmed.connect(_keep_and_leave)
	leave_dialog.custom_action.connect(_leave_action)
	add_child(leave_dialog)

func _ask_about_kept_draft() -> void:
	if held_recovery.is_empty() or not is_inside_tree():
		return
	var what = "存档 %d" % file_slot if file_slot > 0 else "这张地图"
	var origin = int(held_recovery.get("_origin", 0))
	conflict_dialog.dialog_text = "之前保留了一份未保存的草稿（%s墙 %d · 箱子 %d · 目标 %d）。\n恢复草稿只能有一份：改用%s，那份草稿会被放弃。" % [
		"基于存档 %d · " % origin if origin > 0 else "", held_recovery.walls.size(), held_recovery.boxes.size(), held_recovery.goals.size(), what]
	conflict_discard_button.text = "放弃那份，打开%s" % what
	conflict_dialog.popup_centered(Vector2i(600, 170))

func _restore_held() -> void:
	if held_recovery.is_empty():
		return
	var data = held_recovery
	held_recovery = {}
	_cancel_check()
	_push_undo(_serialize())
	_apply_data(data)
	dirty = true
	save_slot = 0
	file_slot = 0
	draft_origin = int(data.get("_origin", 0))
	check_fingerprint = ""
	recovery_fingerprint = ""
	_refresh_status()
	queue_redraw()
	_announce_recovered(int(data.get("_origin", 0)))

func _conflict_action(action: String) -> void:
	if action != "discard":
		return
	var data = held_recovery
	held_recovery = {}   # cleared first, so a canceled signal from hide() cannot restore it
	conflict_dialog.hide()
	var issue = DraftRecovery.clear()
	if not issue.is_empty():
		held_recovery = data
		# V7.13: the question must come back; otherwise the editor is usable while auto-protection
		# is paused for the held draft (found in review).
		_show_error(issue + "\n那份草稿仍保留着，请再选择一次。")
		error_dialog.visibility_changed.connect(_reask_after_error, CONNECT_ONE_SHOT)
		return
	recovery_fingerprint = ""
	_refresh_status()
	status_label.text = "已放弃上次保留的草稿。"

func _reask_after_error() -> void:
	if not held_recovery.is_empty() and not error_dialog.visible:
		_ask_about_kept_draft.call_deferred()

func _keep_and_leave() -> void:
	leave_dialog.hide() # Do not stack exclusive error and confirmation windows.
	_cancel_check()
	_snapshot()
	var issue = DraftRecovery.save_draft(_serialize(), _origin_for_draft())
	if not issue.is_empty():
		_show_error(issue + "\n未返回主菜单，地图仍在。")
		return
	# Deferred: the key/click that pressed the dialog button is still being delivered to it.
	_leave_to_menu.call_deferred()

func _leave_action(action: String) -> void:
	if action != "discard":
		return
	leave_dialog.hide()
	# Deferred: changing scene now would free the dialog while its key event is still in flight
	# (engine error "!is_inside_tree()" when Enter pressed the custom button).
	_go_back.call_deferred()

func _style(color: Color, border: Color = Color("6b5a42")) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s

func _label(parent: Node, text: String, at: Vector2, width: float, font_size: int = 20) -> Label:
	var l = Label.new()
	l.text = text
	l.position = at
	l.size.x = width
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color("f2dfbd"))
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, at: Vector2, width: float, action: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.position = at
	b.custom_minimum_size = Vector2(width, 44)
	b.size = Vector2(width, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", _style(Color("413b2e")))
	b.add_theme_stylebox_override("hover", _style(Color("5b5038"), Color("dcc38d")))
	b.add_theme_stylebox_override("pressed", _style(Color("536045"), Color("dcc38d")))
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _build_ui() -> void:
	var layer = CanvasLayer.new()
	layer.name = "CanvasLayer"
	add_child(layer)
	_label(layer, "关卡编辑器 · 布置工单", Vector2(48, 28), 720, 30)
	_label(layer, "左键放置 · 右键擦除 · 数字键 1–7 切换工具 · Z 撤销 / Shift+Z 重做", Vector2(48, 77), 760, 17)
	_button(layer, "返回主菜单  Esc", Vector2(880, 30), 226, _request_back)
	# Lab: a workbench panel on the right; status card under the board.
	var panel = Panel.new()
	panel.position = Vector2(548, 126)
	panel.size = Vector2(566, 566)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle = _style(Color("332d24"), Color("5c4c36"))
	pstyle.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", pstyle)
	layer.add_child(panel)
	var card = Panel.new()
	card.position = Vector2(40, 562)
	card.size = Vector2(492, 130)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cstyle = _style(Color("ece0c4"), Color("b39a6c"))
	cstyle.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", cstyle)
	layer.add_child(card)
	_label(layer, "工具", Vector2(568, 136), 120, 21)
	tool_label = _label(layer, "", Vector2(700, 140), 400, 17)
	for i in range(TOOL_KEYS.size()):
		var key: String = TOOL_KEYS[i]
		var at = Vector2(568 + (i % 2) * 268, 172 + (i / 2) * 50)
		var b = _button(layer, "%d  %s" % [i + 1, TOOL_NAMES[key]], at, 256, _select_tool.bind(key))
		b.icon = _tool_icon(key)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tool_buttons[key] = b
	pull_toggle = CheckButton.new()
	pull_toggle.text = "开局有牵引"
	pull_toggle.position = Vector2(836, 322)
	pull_toggle.add_theme_font_size_override("font_size", 16)
	pull_toggle.focus_mode = Control.FOCUS_NONE
	pull_toggle.toggled.connect(_set_pull_enabled)
	layer.add_child(pull_toggle)
	pull_two = CheckButton.new()
	pull_two.text = "开局 2 次"
	pull_two.position = Vector2(836, 352)
	pull_two.add_theme_font_size_override("font_size", 16)
	pull_two.focus_mode = Control.FOCUS_NONE
	pull_two.toggled.connect(_set_pull_two)
	layer.add_child(pull_two)
	for toggle in [pull_toggle, pull_two]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			toggle.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		toggle.add_theme_color_override("font_color", Color("e6cf9f"))
		toggle.add_theme_color_override("font_hover_color", Color("fff1cf"))
		toggle.add_theme_color_override("font_pressed_color", Color("8fe0c8"))
		toggle.add_theme_color_override("font_hover_pressed_color", Color("b5f0de"))
	dirty_label = _label(layer, "", Vector2(568, 386), 540, 17)
	_button(layer, "保存  S", Vector2(568, 420), 256, _open_slots.bind("save"))
	_button(layer, "读取  L", Vector2(836, 420), 256, _open_slots.bind("load"))
	_button(layer, "试玩  T", Vector2(568, 470), 256, _preview)
	check_button = _button(layer, "检查可解  V", Vector2(836, 470), 256, _start_check)
	_button(layer, "复制分享码  C", Vector2(568, 520), 256, _copy_share_code)
	_button(layer, "粘贴分享码  P", Vector2(836, 520), 256, _paste_share_code)
	_button(layer, "导入原始草稿", Vector2(568, 570), 256, _open_slots.bind("original"))
	_button(layer, "清空", Vector2(836, 570), 256, _request_clear)
	check_label = _label(layer, "", Vector2(568, 626), 530, 16)
	check_label.add_theme_color_override("font_color", Color("cdbb94"))
	check_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check_label.size = Vector2(530, 56)
	status_label = _label(layer, "草稿可保存；试玩需玩家、箱子和相同数量的目标。", Vector2(56, 572), 460, 17)
	status_label.add_theme_color_override("font_color", Color("3a2f22"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size = Vector2(460, 112)
	slot_popup = PopupPanel.new()
	slot_popup.name = "SlotPopup"
	slot_popup.exclusive = true
	layer.add_child(slot_popup)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(350, 310)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	slot_popup.add_child(margin)
	margin.add_child(v)
	selection_label = Label.new()
	selection_label.add_theme_font_size_override("font_size", 20)
	v.add_child(selection_label)
	for i in range(1, 4):
		var b = _button(v, "存档 %d" % i, Vector2.ZERO, 340, _choose_slot.bind(i))
		slot_buttons.append(b)
	slot_confirm = _button(v, "确认", Vector2.ZERO, 340, _confirm_slot)
	_button(v, "取消", Vector2.ZERO, 340, slot_popup.hide)
	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "覆盖存档"
	overwrite_dialog.ok_button_text = "覆盖"
	overwrite_dialog.cancel_button_text = "取消"
	overwrite_dialog.exclusive = true
	overwrite_dialog.confirmed.connect(_overwrite_confirmed)
	overwrite_dialog.canceled.connect(_return_to_picker)
	layer.add_child(overwrite_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "放弃当前改动？"
	discard_dialog.ok_button_text = "放弃改动"
	discard_dialog.cancel_button_text = "取消"
	discard_dialog.exclusive = true
	discard_dialog.confirmed.connect(_discard_confirmed)
	discard_dialog.canceled.connect(_discard_canceled)
	layer.add_child(discard_dialog)
	error_dialog = AcceptDialog.new()
	error_dialog.title = "请检查关卡"
	error_dialog.ok_button_text = "知道了"
	error_dialog.exclusive = true
	error_dialog.dialog_autowrap = true
	# Lab 4: with autowrap the label's own minimum width is tiny, and the dialog then sizes itself
	# to that (measured: 140×611 headless). A fixed text width makes the layout the same everywhere.
	error_dialog.get_label().custom_minimum_size = Vector2(520, 0)
	error_dialog.min_size = Vector2i(560, 150)
	layer.add_child(error_dialog)

## Lab: tool buttons show the piece they place, drawn with the same art as the board.
func _tool_icon(key: String) -> Texture2D:
	var names = {"wall": "wall", "box": "crate", "tool": "toolbox", "bench": "bench", "floor": "floor"}
	if key == "player":
		return load("res://art/player.png") if ResourceLoader.exists("res://art/player.png") else null
	if key == "goal":
		var img = Image.create(30, 30, false, Image.FORMAT_RGBA8)
		for y in 30:
			for x in 30:
				var d = Vector2(x, y).distance_to(Vector2(14.5, 14.5))
				if d >= 9.5 and d <= 12.5: img.set_pixel(x, y, Color("ffe5a8"))
				elif d <= 2.5: img.set_pixel(x, y, Color("f3bc66"))
		return ImageTexture.create_from_image(img)
	var path = "res://art/%s.svg" % names.get(key, key)
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var image = tex.get_image()
	if image == null:
		return tex
	image.resize(30, 30, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1152, 720)), Color("29261f"))
	# Lab: plank wall behind the work surface, so the editor reads as the same workshop.
	for y in range(0, 720, 64):
		draw_line(Vector2(0, y), Vector2(1152, y), Color("322d24"), 1)
	draw_rect(Rect2(0, 0, 1152, 10), Color("80603b"))
	Board.draw_board(self, _serialize(), BOARD_ORIGIN, CELL_SIZE, selected_cell)

func _modal_open() -> bool:
	return slot_popup.visible or overwrite_dialog.visible or discard_dialog.visible or error_dialog.visible \
		or (share_dialog != null and share_dialog.visible) or (conflict_dialog != null and conflict_dialog.visible) \
		or (leave_dialog != null and leave_dialog.visible) or GameState.close_dialog.visible or GameState.close_error.visible

func _unhandled_input(event: InputEvent) -> void:
	if _modal_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# V7.11: Ctrl/Cmd combos are not the single-letter shortcuts (Ctrl+V used to start a check).
		if event.ctrl_pressed or event.meta_pressed:
			match event.keycode:
				KEY_C: _copy_share_code()
				KEY_V: _paste_share_code()
				KEY_Z: _redo() if event.shift_pressed else _undo()
				KEY_Y: _redo()
			return
		if event.alt_pressed:
			return
		match event.keycode:
			KEY_1: _select_tool("wall")
			KEY_2: _select_tool("floor")
			KEY_3: _select_tool("goal")
			KEY_4: _select_tool("box")
			KEY_5: _select_tool("player")
			KEY_6: _select_tool("tool")
			KEY_7: _select_tool("bench")
			KEY_S: _open_slots("save")
			KEY_L: _open_slots("load")
			KEY_T: _preview()
			KEY_V: _start_check()
			KEY_C: _copy_share_code()
			KEY_P: _paste_share_code()
			KEY_ESCAPE: _request_back()
			KEY_Z: _redo() if event.shift_pressed else _undo()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		var p = (event.position - BOARD_ORIGIN) / CELL_SIZE
		var cell = Vector2i(floori(p.x), floori(p.y))
		if cell.x >= 0 and cell.x < 7 and cell.y >= 0 and cell.y < 6:
			_paint_cell(cell, "floor" if event.button_index == MOUSE_BUTTON_RIGHT else selected_tool)

func _select_tool(tool: String) -> void:
	selected_tool = tool if TOOL_NAMES.has(tool) else "wall"
	for key in tool_buttons:
		tool_buttons[key].add_theme_stylebox_override("normal", _style(Color("536045") if key == selected_tool else Color("413b2e"), Color("dcc38d") if key == selected_tool else Color("6b5a42")))
	tool_label.text = "当前工具：" + TOOL_NAMES[selected_tool]

func _paint_cell(cell: Vector2i, tool: String) -> void:
	var before = _serialize()
	selected_cell = cell
	match tool:
		"wall":
			walls[cell] = true
			goals.erase(cell)
			boxes.erase(cell)
			if player_cell == cell: player_cell = Vector2i(-1, -1)
			_clear_special(cell)
		"floor":
			walls.erase(cell)
			goals.erase(cell)
			boxes.erase(cell)
			if player_cell == cell: player_cell = Vector2i(-1, -1)
			_clear_special(cell)
		"goal":
			walls.erase(cell)
			goals[cell] = true
			_clear_special(cell)
		"box":
			walls.erase(cell)
			boxes[cell] = true
			if player_cell == cell: player_cell = Vector2i(-1, -1)
			_clear_special(cell)
		"player":
			walls.erase(cell)
			boxes.erase(cell)
			player_cell = cell
			if tool_cell == cell: tool_cell = NONE
		"tool":
			# one crate per map: placing it again moves it
			walls.erase(cell)
			goals.erase(cell)
			boxes.erase(cell)
			if player_cell == cell: player_cell = Vector2i(-1, -1)
			if bench_cell == cell: bench_cell = NONE
			tool_cell = cell
		"bench":
			walls.erase(cell)
			goals.erase(cell)
			boxes.erase(cell)
			if tool_cell == cell: tool_cell = NONE
			bench_cell = cell
	if before != _serialize():
		_push_undo(before)
		dirty = true
		check_fingerprint = ""
		if check_job != null:
			_cancel_check("地图已改动，检查已取消。")
	_refresh_status()
	queue_redraw()

func _clear_special(cell: Vector2i) -> void:
	if tool_cell == cell: tool_cell = NONE
	if bench_cell == cell: bench_cell = NONE

func _serialize() -> Dictionary:
	var data = {"walls": [], "goals": [], "boxes": [], "player": [player_cell.x, player_cell.y], "pull_charges": pull_charges}
	for cell in walls: data["walls"].append([cell.x, cell.y])
	for cell in goals: data["goals"].append([cell.x, cell.y])
	for cell in boxes: data["boxes"].append([cell.x, cell.y])
	if tool_cell != NONE: data["tool"] = [tool_cell.x, tool_cell.y]
	if bench_cell != NONE: data["bench"] = [bench_cell.x, bench_cell.y]
	return data

func _apply_data(data: Dictionary) -> void:
	if check_job != null:
		_cancel_check()
	pull_charges = int(data.get("pull_charges", 0))
	_sync_pull_buttons()
	tool_cell = Store.cell_of(data, "tool")
	bench_cell = Store.cell_of(data, "bench")
	walls.clear()
	goals.clear()
	boxes.clear()
	for p in data["walls"]: walls[Vector2i(int(p[0]), int(p[1]))] = true
	for p in data["goals"]: goals[Vector2i(int(p[0]), int(p[1]))] = true
	for p in data["boxes"]: boxes[Vector2i(int(p[0]), int(p[1]))] = true
	player_cell = Vector2i(int(data["player"][0]), int(data["player"][1]))
	selected_cell = Vector2i(-1, -1)
	queue_redraw()

func _refresh_status() -> void:
	_sync_recovery()
	dirty_label.text = ("● 未保存改动" + ("（自动保护失败）" if not recovery_issue.is_empty() else "") if dirty else "○ 存档 %d 已保存" % file_slot if file_slot > 0 else "○ 新建未保存") + "  |  箱子 %d / 目标 %d" % [boxes.size(), goals.size()]
	_refresh_check_label()

func _open_slots(mode: String) -> void:
	if _modal_open(): return
	popup_mode = mode
	save_slot = 0
	pending_slot = 0
	selection_label.text = "选择保存位置" if mode == "save" else ("原始草稿 · 待修正" if mode == "original" else "选择要读取的存档")
	slot_confirm.disabled = true
	for i in range(3):
		var exists = FileAccess.file_exists(Store.slot_path(i + 1))
		slot_buttons[i].text = "存档 %d · %s" % [i + 1, "已有内容" if exists else "空"]
		slot_buttons[i].disabled = mode == "load" and not exists
		if mode == "original":
			slot_buttons[i].text = "原始草稿 %d · 未找到解" % [i + 1]
			slot_buttons[i].disabled = i == 2
			if i == 2: slot_buttons[i].text = "无第三个原始关卡"
	slot_popup.popup_centered(Vector2i(380, 350))

func _choose_slot(slot: int) -> void:
	save_slot = slot
	selection_label.text = "导入原始草稿 %d（副本）" % slot if popup_mode == "original" else (("保存至：" if popup_mode == "save" else "读取：") + "存档 %d" % slot)
	slot_confirm.disabled = false

func _confirm_slot() -> void:
	if save_slot < 1 or save_slot > 3: return
	pending_slot = save_slot
	if popup_mode == "save":
		pending_data = _serialize().duplicate(true)
		var issue = Store.validate(pending_data, false)
		if not issue.is_empty():
			selection_label.text = issue
			return
		if FileAccess.file_exists(Store.slot_path(pending_slot)):
			slot_popup.hide()
			overwrite_dialog.dialog_text = "存档 %d 已有内容。确定用当前地图覆盖吗？\n取消会保留原存档。" % pending_slot
			overwrite_dialog.popup_centered(Vector2i(440, 150))
		else:
			_save_pending()
	else:
		pending_is_original = popup_mode == "original"
		var load_path = Store.slot_path(pending_slot)
		if pending_is_original:
			load_path = "res://levels/user_custom_level.json" if pending_slot == 1 else "res://levels/user_custom_level_2.json"
		var result: Dictionary = Store.load_path(load_path, false)
		if not result["ok"]:
			selection_label.text = result["error"]
			return
		pending_data = result["data"].duplicate(true)
		if dirty:
			slot_popup.hide()
			pending_action = "load"
			var target_name = "原始草稿 %d（副本）" % pending_slot if pending_is_original else "存档 %d" % pending_slot
			var operation = "导入" if pending_is_original else "读取"
			discard_dialog.dialog_text = "当前地图有未保存改动。%s%s会替换这些改动。\n确定继续？" % [operation, target_name]
			if pending_is_original:
				discard_dialog.dialog_text += "\n原图按标准推箱规则未找到解，建议先修改。"
			discard_dialog.popup_centered(Vector2i(470, 150))
		else:
			_load_pending()

func _overwrite_confirmed() -> void:
	_save_pending()

func _save_pending() -> void:
	var issue = Store.save_path(Store.slot_path(pending_slot), pending_data)
	if not issue.is_empty():
		slot_popup.hide()
		_show_error(issue)
		return
	dirty = false
	save_slot = pending_slot
	file_slot = pending_slot
	draft_origin = 0
	clean_fingerprint = Store.fingerprint(pending_data)
	slot_popup.hide()
	status_label.text = "已保存到存档 %d。可以返回主菜单游玩，也可以继续编辑。" % save_slot
	_snapshot()
	_refresh_status()

func _load_pending() -> void:
	var before = _serialize()
	_apply_data(pending_data)
	if before != _serialize():
		_push_undo(before)
	save_slot = 0 if pending_is_original or pending_is_shared else pending_slot
	file_slot = save_slot
	draft_origin = 0
	dirty = pending_is_original or pending_is_shared
	clean_fingerprint = "" if dirty else Store.fingerprint(_serialize())
	check_fingerprint = ""
	pending_action = ""
	slot_popup.hide()
	status_label.text = "原始草稿已导入，原文件不变。原图按标准推箱规则未找到解；建议先修改，再试玩。" if pending_is_original else "已读取存档 %d。" % save_slot
	if pending_is_shared:
		var missing = Store.validate(pending_data, true)
		if missing.is_empty():
			status_label.text = "已从分享码导入关卡（尚未保存）。可以先试玩或检查可解，再保存到存档。"
		else:
			status_label.text = "已导入一份未完成的草稿（尚未保存）：" + missing + " 补全后才能试玩。"
	pending_is_shared = false
	_snapshot()
	_refresh_status()

func _return_to_picker() -> void:
	# ConfirmationDialog emits canceled before auto-hide. Reopen next idle turn.
	_reopen_slot_picker.call_deferred()

func _reopen_slot_picker() -> void:
	if is_inside_tree():
		slot_popup.popup_centered(Vector2i(380, 350))

func _request_back() -> void:
	if _modal_open(): return
	if dirty:
		# V7.12: same choices as closing the window; Enter keeps the work.
		leave_dialog.popup_centered(Vector2i(560, 170))
		leave_dialog.get_ok_button().call_deferred("grab_focus")
	else:
		_go_back()

func _request_clear() -> void:
	if _modal_open(): return
	pending_action = "clear"
	discard_dialog.dialog_text = "确定清空当前编辑区？已有存档文件不会被删除。"
	discard_dialog.popup_centered(Vector2i(440, 150))

func _discard_confirmed() -> void:
	match pending_action:
		"load": _load_pending()
		"back": _go_back()
		"clear":
			_push_undo(_serialize())
			_apply_data({"walls": [], "goals": [], "boxes": [], "player": [-1, -1]})
			dirty = true
			status_label.text = "已清空编辑区。请放置玩家、箱子和目标。"
			_refresh_status()
	pending_action = ""

func _discard_canceled() -> void:
	if pending_action == "load" and not pending_is_shared: _return_to_picker()
	pending_is_shared = false
	pending_action = ""

func _go_back() -> void:
	var issue = DraftRecovery.clear()
	if not issue.is_empty():
		_show_error(issue)
		return
	_leave_to_menu()

func _leave_to_menu() -> void:
	_cancel_check()
	GameState.editor_history = {}
	GameState.editor_snapshot = {}
	GameState.preview_data = {}
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _snapshot() -> void:
	var data = _serialize()
	data["_dirty"] = dirty
	data["_slot"] = file_slot
	data["_tool"] = selected_tool
	data["_origin"] = draft_origin
	GameState.editor_snapshot = data
	GameState.editor_history = {"undo": undo_stack, "redo": redo_stack, "clean": clean_fingerprint}

func _preview() -> void:
	if _modal_open(): return
	_cancel_check()
	var data = _serialize()
	var issue = Store.validate(data, true)
	if not issue.is_empty():
		_show_error(issue)
		return
	_snapshot()
	GameState.preview_data = data.duplicate(true)
	get_tree().change_scene_to_file("res://game.tscn")

## ---------------- V7.10: solvability check, time-sliced on the main thread ----------------
## No threads: identical on desktop and single-threaded Web builds, cancellable at any moment.
const CHECK_SLICE_USEC = 6000
var check_job = null          # current SearchJob (with-pull or classic phase)
var check_phase = ""          # "main" then optional "classic"
var check_data: Dictionary = {}
var check_main_result = ""

func _start_check() -> void:
	if _modal_open():
		return
	if check_job != null:
		_cancel_check("已取消检查。")
		return
	var data = _serialize()
	var issue = Store.validate(data, true)
	if not issue.is_empty():
		_show_error(issue)
		return
	check_fingerprint = Store.fingerprint(data)
	check_data = data
	check_phase = "main"
	check_job = _make_job(data, int(data.get("pull_charges", 0)))
	check_button.text = "取消检查  V"
	status_label.text = "正在检查这张地图是否有解……（再按 V 可取消）"
	_refresh_check_label()

## open_ok = false: the crate never opens (it is only an obstacle), to see whether it is needed.
func _make_job(data: Dictionary, charges: int, open_ok: bool = true):
	var walls_ = {}
	var goals_ = {}
	var boxes_ = []
	for p in data.walls: walls_[Vector2i(int(p[0]), int(p[1]))] = true
	for p in data.goals: goals_[Vector2i(int(p[0]), int(p[1]))] = true
	for p in data.boxes: boxes_.append(Vector2i(int(p[0]), int(p[1])))
	var bench_ = Store.cell_of(data, "bench") if open_ok else NONE
	return DeadSolver.new(walls_, goals_, bench_).start_job(Vector2i(int(data.player[0]), int(data.player[1])), boxes_, charges, CHECK_STATE_CAP, Store.cell_of(data, "tool"))

func _process(_delta: float) -> void:
	if check_job == null:
		return
	if not check_job.step(CHECK_SLICE_USEC):
		return
	var has_tool = Store.cell_of(check_data, "tool") != NONE
	if check_phase == "main" and check_job.result == "solvable" and has_tool:
		check_main_result = "solvable"
		check_phase = "noopen"
		check_job = _make_job(check_data, int(check_data.get("pull_charges", 0)), false)
		return
	if check_phase == "main" and check_job.result == "solvable" and int(check_data.get("pull_charges", 0)) > 0:
		check_main_result = "solvable"
		check_phase = "classic"
		check_job = _make_job(check_data, 0)
		return
	var main_result = check_main_result if check_phase in ["classic", "noopen"] else check_job.result
	var without_pull = check_job.result if check_phase == "classic" else ""
	var without_tool = check_job.result if check_phase == "noopen" else ""
	check_job = null
	check_main_result = ""
	_finish_check({"result": main_result, "without_pull": without_pull, "without_tool": without_tool, "data": check_data})

func _cancel_check(message: String = "") -> void:
	if check_job != null:
		check_job.cancel()
	check_job = null
	check_main_result = ""
	check_button.text = "检查可解  V"
	if not message.is_empty():
		status_label.text = message
	if check_label:
		_refresh_check_label()

func _finish_check(outcome: Dictionary) -> void:
	check_button.text = "检查可解  V"
	var still_current = Store.fingerprint(_serialize()) == check_fingerprint
	var short = ""
	match outcome.result:
		"solvable":
			Store.mark_verified(outcome.data)
			var note = ""
			if outcome.without_pull == "solvable":
				note = "不用牵引也能解，牵引在这关只是可选项。"
			elif outcome.without_pull == "dead":
				note = "必须用到牵引才能解。"
			elif outcome.without_pull == "unknown":
				note = "（是否必须用牵引：超出检查上限，未能确认。）"
			var tool_note = str(outcome.get("without_tool", ""))
			if tool_note == "solvable":
				note = "不打开工具箱也能解，工具箱在这关只是可选项。"
			elif tool_note == "dead":
				note = "必须把工具箱推上工作台才能解。"
			elif tool_note == "unknown":
				note = "（是否必须开箱：超出检查上限，未能确认。）"
			status_label.text = "✓ 有解。" + note
			short = "✓ 有解" + {"不用牵引也能解，牵引在这关只是可选项。": " · 牵引可选", "必须用到牵引才能解。": " · 必须牵引", "不打开工具箱也能解，工具箱在这关只是可选项。": " · 工具箱可选", "必须把工具箱推上工作台才能解。": " · 必须开箱"}.get(note, "")
		"dead":
			status_label.text = "✗ 这张地图无解：无论怎么推拉，都不能让所有箱子归位。"
			short = "✗ 无解"
		_:
			status_label.text = "这张地图太复杂，检查在上限内没有得出结论。可以试玩确认。"
			short = "？太复杂，未得出结论"
	if not still_current:
		status_label.text += "（检查期间地图已改动，结果针对改动前的版本。）"
	# Lab 2: the sentence above is said once, in the message card. Next to the button stays only a
	# short verdict for exactly the checked version; any edit replaces it with "not checked yet".
	check_verdict = short
	check_verdict_ok = outcome.result
	check_verdict_fp = check_fingerprint if still_current else ""
	_refresh_status()

var check_verdict = ""
var check_verdict_ok = ""
var check_verdict_fp = ""

func _refresh_check_label() -> void:
	if check_label == null:
		return
	var data = _serialize()
	var color = Color("b3a685")
	if check_job != null:
		check_label.text = "检查中……"
	elif not check_verdict.is_empty() and Store.fingerprint(data) == check_verdict_fp:
		check_label.text = check_verdict
		color = Color("8fe0c8") if check_verdict_ok == "solvable" else (Color("f0a58c") if check_verdict_ok == "dead" else Color("e6cf9f"))
	elif Store.is_verified(data):
		check_label.text = "✓ 已验证可解"
		color = Color("8fe0c8")
	else:
		check_label.text = "尚未检查 · V 检查，或试玩通关来验证"
	check_label.add_theme_color_override("font_color", color)

func _exit_tree() -> void:
	_cancel_check()

## ---------------- V7.9: share codes ----------------
## Lab 3: both formats are named wherever a code is asked for. The digit is the starting pulls.
const SHARE_EXAMPLE = "例：KURO1-…（普通地图）或 KUROT2-…（含工具箱）"
## Lab 4: shorter, one format per line, so the dialogs stay readable in a 960×600 window.
const SHARE_FORMATS = "普通地图：KURO0- / KURO1- 开头\n含工具箱：KUROT0- / KUROT1- / KUROT2- 开头（数字是开局牵引次数）"

func _build_share_dialog() -> void:
	share_dialog = ConfirmationDialog.new()
	share_dialog.min_size = Vector2i(600, 230)
	share_dialog.cancel_button_text = "取消"
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	share_note = Label.new()
	share_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	share_note.custom_minimum_size = Vector2(560, 0)
	share_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(share_note)
	share_edit = LineEdit.new()
	share_edit.custom_minimum_size = Vector2(560, 40)
	share_edit.placeholder_text = SHARE_EXAMPLE
	box.add_child(share_edit)
	share_dialog.add_child(box)
	share_dialog.register_text_enter(share_edit)
	share_dialog.confirmed.connect(_share_dialog_confirmed)
	share_edit.gui_input.connect(_share_edit_input)
	add_child(share_dialog)

## V7.11: on Web, Ctrl+V in a text box pastes Godot's own last copy, not the browser clipboard
## (measured in Chromium). Read the browser clipboard directly instead.
func _share_edit_input(event: InputEvent) -> void:
	if not OS.has_feature("web") or share_mode != "paste":
		return
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V:
		share_edit.accept_event()
		_read_browser_clipboard(true)

func _read_browser_clipboard(replace: bool) -> void:
	var got_cb = JavaScriptBridge.create_callback(func(args):
		var value = String(args[0]).strip_edges() if args.size() > 0 else ""
		if share_dialog.visible and (replace or share_edit.text.is_empty()):
			share_edit.text = value
			share_edit.caret_column = value.length())
	var fail_cb = JavaScriptBridge.create_callback(func(_args):
		if share_dialog.visible:
			share_note.text = "浏览器没有允许读取剪贴板。请在浏览器的权限提示中选择允许，或直接输入分享码。")
	js_callbacks = [got_cb, fail_cb]
	var clipboard = JavaScriptBridge.get_interface("navigator").clipboard
	if clipboard == null:
		share_note.text = "这个浏览器不支持读取剪贴板，请直接输入分享码。"
	else:
		clipboard.readText().then(got_cb, fail_cb)

func _copy_share_code() -> void:
	if _modal_open():
		return
	var data = _serialize()
	var issue = Store.validate(data, true)
	if not issue.is_empty():
		_show_error("分享前请先让关卡可以试玩：\n" + issue)
		return
	var code = Store.share_code(data)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) and not OS.has_feature("web"):
		_open_share_dialog("copy", code)  # no system clipboard: let the player copy by hand
		return
	DisplayServer.clipboard_set(code)
	if not OS.has_feature("web") and DisplayServer.clipboard_get().strip_edges() != code:
		_open_share_dialog("copy", code)
		return
	var tail = "" if Store.is_verified(data) else "\n提示：这张地图还没验证可解，建议先按 V 检查或试玩通关。"
	status_label.text = "分享码已复制：" + code + tail
	if OS.has_feature("web"):
		# The browser may refuse clipboard access; then show the code to copy by hand.
		var ok_cb = JavaScriptBridge.create_callback(func(_args): status_label.text = "分享码已复制：" + code + tail)
		var fail_cb = JavaScriptBridge.create_callback(func(_args): _open_share_dialog("copy", code))
		js_callbacks = [ok_cb, fail_cb]
		var clipboard = JavaScriptBridge.get_interface("navigator").clipboard
		if clipboard == null:
			_open_share_dialog("copy", code)
		else:
			clipboard.writeText(code).then(ok_cb, fail_cb)

func _paste_share_code() -> void:
	if _modal_open():
		return
	var has_clipboard = DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	var text = "" if OS.has_feature("web") or not has_clipboard else DisplayServer.clipboard_get().strip_edges()
	var found = text.to_upper().begins_with("KURO")
	_open_share_dialog("paste", text if found else "")
	if not OS.has_feature("web"):
		# Lab 3: say what happened to the clipboard, so a failed read is not mistaken for a broken code.
		share_note.text = ("已从剪贴板读到分享码，按回车导入。" if found else "剪贴板里没有分享码：在框里按 Ctrl+V，或直接输入。") + "\n" + SHARE_FORMATS
	if OS.has_feature("web"):
		_read_browser_clipboard(false)  # pre-fill when the browser allows it

func _open_share_dialog(mode: String, text: String) -> void:
	share_mode = mode
	share_edit.text = text
	share_edit.editable = mode == "paste"
	if mode == "paste":
		share_dialog.title = "粘贴分享码"
		share_dialog.ok_button_text = "导入"
		share_note.text = "粘贴（Ctrl+V）或直接输入分享码，按回车导入。\n" + SHARE_FORMATS
	else:
		share_dialog.title = "复制分享码"
		share_dialog.ok_button_text = "完成"
		share_note.text = "未能确认已复制到剪贴板（可能被系统或其他程序占用）。\n下面的分享码已全选：按 Ctrl+C 再试，或直接抄录。"
	share_dialog.popup_centered()
	_fit_to_text(share_dialog, share_note)
	share_edit.call_deferred("grab_focus")
	if mode == "copy":
		share_edit.call_deferred("select_all")

func _share_dialog_confirmed() -> void:
	if share_mode == "paste":
		var text = share_edit.text
		share_dialog.hide()
		_import_share_code(text)

func _import_share_code(text: String) -> void:
	var parsed = Store.parse_share_code(text)
	if not parsed.ok:
		_show_error("无法导入：" + parsed.error + "\n" + SHARE_FORMATS)
		return
	pending_data = parsed.data
	pending_is_original = false
	pending_is_shared = true
	pending_slot = 0
	if dirty:
		pending_action = "load"
		discard_dialog.dialog_text = "当前地图有未保存改动。导入分享码会替换这些改动。\n确定继续？"
		discard_dialog.popup_centered(Vector2i(470, 150))
	else:
		_load_pending()

## Messages here are a few lines; anything far longer (it would only come from a bug) is cut so
## the dialog can never outgrow the window.
const ERROR_TEXT_LIMIT = 300
var dialog_text_shortened = false
func _show_error(message: String) -> void:
	dialog_text_shortened = message.length() > ERROR_TEXT_LIMIT
	error_dialog.dialog_text = message.left(ERROR_TEXT_LIMIT) + "…" if dialog_text_shortened else message
	error_dialog.reset_size()
	error_dialog.popup_centered(Vector2i(560, 150))
	_fit_to_text(error_dialog, error_dialog.get_label())

## Lab 4: a dialog grows until its text shows every line, measured after the real layout (font,
## wrapping and window scale differ between machines, so a fixed height can clip on one of them).
## It never grows past the visible window; dialog_fit_clipped tells tests if that ever happens.
var dialog_fit_clipped = false
func _fit_to_text(dialog: Window, text_label: Label) -> void:
	dialog_fit_clipped = false
	var room = get_viewport().get_visible_rect().size
	var limit = int(room.y) - 24
	for i in 16:
		await get_tree().process_frame
		if not is_instance_valid(dialog) or not dialog.visible:
			return
		if text_label.get_visible_line_count() >= text_label.get_line_count() and dialog.size.y <= limit:
			break
		if dialog.size.y >= limit:
			dialog_fit_clipped = true
			break
		dialog.size.y = mini(limit, dialog.size.y + int(ceil(text_label.get_line_height())) + 4)
		dialog.position = Vector2i((room - Vector2(dialog.size)) / 2.0)

func _sync_pull_buttons() -> void:
	if pull_toggle: pull_toggle.set_pressed_no_signal(pull_charges > 0)
	if pull_two: pull_two.set_pressed_no_signal(pull_charges > 1)

## Lab: "开局 2 次" implies the first switch; turning the first switch off clears both.
func _set_pull_two(on: bool) -> void:
	var before = _serialize()
	pull_charges = 2 if on else (1 if pull_toggle.button_pressed else 0)
	_sync_pull_buttons()
	if before != _serialize():
		_push_undo(before)
		dirty = true
		check_fingerprint = ""
	_refresh_status()

func _set_pull_enabled(enabled: bool) -> void:
	var before = _serialize()
	pull_charges = (2 if pull_two and pull_two.button_pressed else 1) if enabled else 0
	_sync_pull_buttons()
	if before != _serialize():
		_push_undo(before)
	dirty = true
	_refresh_status()

func _sync_recovery() -> void:
	_snapshot()
	if not held_recovery.is_empty():
		return  # V7.12: an earlier kept draft is waiting for the player's decision
	var data = _serialize()
	var key = Store.fingerprint(data) if dirty else "clean"
	if key == recovery_fingerprint and recovery_issue.is_empty(): return
	var previous_issue = recovery_issue
	recovery_issue = DraftRecovery.save_draft(data, _origin_for_draft()) if dirty else DraftRecovery.clear()
	if recovery_issue.is_empty():
		recovery_fingerprint = key
		if not previous_issue.is_empty() and status_label.text == previous_issue:
			status_label.text = "自动保护已恢复。"
	else:
		status_label.text = recovery_issue

func _origin_for_draft() -> int:
	return file_slot if file_slot > 0 else draft_origin

## ---- V7.13: undo / redo ----
func _push_undo(before: Dictionary) -> void:
	undo_stack.append(before.duplicate(true))
	if undo_stack.size() > UNDO_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	_step_history(undo_stack, redo_stack, "已撤销")

func _redo() -> void:
	_step_history(redo_stack, undo_stack, "已重做")

func _step_history(from: Array, to: Array, verb: String) -> void:
	if _modal_open():
		return
	if from.is_empty():
		status_label.text = "没有可以%s的操作。" % ("撤销" if verb == "已撤销" else "重做")
		return
	_cancel_check()
	to.append(_serialize())
	var data: Dictionary = from.pop_back()
	_apply_data(data)
	pull_charges = int(data.get("pull_charges", 0))
	_sync_pull_buttons()
	dirty = Store.fingerprint(_serialize()) != clean_fingerprint
	check_fingerprint = ""
	_refresh_status()
	queue_redraw()
	status_label.text = "%s（还可撤销 %d 步，重做 %d 步）。" % [verb, undo_stack.size(), redo_stack.size()]
