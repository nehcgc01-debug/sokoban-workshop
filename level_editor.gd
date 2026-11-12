extends Node2D

# The editor keeps draft data separate from gameplay. Preview never writes a save.
const Store = preload("res://level_store.gd")
const Board = preload("res://board_view.gd")
const BOARD_ORIGIN = Vector2(48, 142)
const CELL_SIZE = 68.0
const TOOL_NAMES = {"wall": "墙 / Wall", "floor": "擦除 / Erase", "goal": "目标 / Goal", "box": "箱子 / Box", "player": "玩家 / Player"}

var walls: Dictionary = {}
var goals: Dictionary = {}
var boxes: Dictionary = {}
var player_cell = Vector2i(-1, -1)
var selected_cell = Vector2i(-1, -1)
var selected_tool = "wall"
var save_slot = 0
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

func _ready() -> void:
	_build_ui()
	if not GameState.editor_snapshot.is_empty():
		var snapshot: Dictionary = GameState.editor_snapshot.duplicate(true)
		if Store.validate(snapshot, false).is_empty():
			_apply_data(snapshot)
			dirty = bool(snapshot.get("_dirty", false))
			save_slot = int(snapshot.get("_slot", 0))
			selected_tool = str(snapshot.get("_tool", "wall"))
	GameState.preview_data = {}
	_select_tool(selected_tool)
	_refresh_status()
	queue_redraw()

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
	_label(layer, "关卡编辑器  /  LEVEL WORKSHOP", Vector2(48, 28), 720, 30)
	_label(layer, "7 × 6 网格 · 左键放置 · 右键擦除", Vector2(48, 77), 700, 18)
	_label(layer, "工具 / TOOLS", Vector2(580, 142), 430, 21)
	var keys = ["wall", "floor", "goal", "box", "player"]
	for i in range(keys.size()):
		var key: String = keys[i]
		var at = Vector2(580 + (i % 2) * 220, 183 + (i / 2) * 52)
		tool_buttons[key] = _button(layer, "%d  %s" % [i + 1, TOOL_NAMES[key]], at, 206, _select_tool.bind(key))
	_button(layer, "导入原始关卡", Vector2(800, 287), 206, _open_slots.bind("original"))
	tool_label = _label(layer, "", Vector2(580, 345), 440, 19)
	dirty_label = _label(layer, "", Vector2(580, 378), 440, 18)
	_button(layer, "保存 / Save  [S]", Vector2(580, 424), 206, _open_slots.bind("save"))
	_button(layer, "读取 / Load  [L]", Vector2(800, 424), 206, _open_slots.bind("load"))
	_button(layer, "试玩 / Test  [T]", Vector2(580, 480), 206, _preview)
	_button(layer, "新建 / Clear", Vector2(800, 480), 206, _request_clear)
	_button(layer, "返回主菜单 / Back", Vector2(580, 536), 426, _request_back)
	pull_toggle = CheckButton.new()
	pull_toggle.text = "启用一次牵引  ·  Shift + 方向键"
	pull_toggle.position = Vector2(580, 584)
	pull_toggle.add_theme_font_size_override("font_size", 16)
	pull_toggle.toggled.connect(_set_pull_enabled)
	layer.add_child(pull_toggle)
	status_label = _label(layer, "草稿可保存；试玩需玩家、箱子和相同数量的目标。", Vector2(48, 638), 960, 17)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size = Vector2(960, 60)
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
	slot_confirm = _button(v, "确认 / Confirm", Vector2.ZERO, 340, _confirm_slot)
	_button(v, "取消 / Cancel", Vector2.ZERO, 340, slot_popup.hide)
	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "覆盖存档 / Overwrite save"
	overwrite_dialog.exclusive = true
	overwrite_dialog.confirmed.connect(_overwrite_confirmed)
	overwrite_dialog.canceled.connect(_return_to_picker)
	layer.add_child(overwrite_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "未保存的改动 / Unsaved changes"
	discard_dialog.exclusive = true
	discard_dialog.confirmed.connect(_discard_confirmed)
	discard_dialog.canceled.connect(_discard_canceled)
	layer.add_child(discard_dialog)
	error_dialog = AcceptDialog.new()
	error_dialog.title = "请检查关卡 / Check level"
	error_dialog.exclusive = true
	layer.add_child(error_dialog)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1152, 720)), Color("29261f"))
	Board.draw_board(self, _serialize(), BOARD_ORIGIN, CELL_SIZE, selected_cell)

func _modal_open() -> bool:
	return slot_popup.visible or overwrite_dialog.visible or discard_dialog.visible or error_dialog.visible

func _unhandled_input(event: InputEvent) -> void:
	if _modal_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select_tool("wall")
			KEY_2: _select_tool("floor")
			KEY_3: _select_tool("goal")
			KEY_4: _select_tool("box")
			KEY_5: _select_tool("player")
			KEY_S: _open_slots("save")
			KEY_L: _open_slots("load")
			KEY_T: _preview()
			KEY_ESCAPE: _request_back()
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
		"floor":
			walls.erase(cell)
			goals.erase(cell)
			boxes.erase(cell)
			if player_cell == cell: player_cell = Vector2i(-1, -1)
		"goal":
			walls.erase(cell)
			goals[cell] = true
		"box":
			walls.erase(cell)
			boxes[cell] = true
			if player_cell == cell: player_cell = Vector2i(-1, -1)
		"player":
			walls.erase(cell)
			boxes.erase(cell)
			player_cell = cell
	if before != _serialize(): dirty = true
	_refresh_status()
	queue_redraw()

func _serialize() -> Dictionary:
	var data = {"walls": [], "goals": [], "boxes": [], "player": [player_cell.x, player_cell.y], "pull_charges": pull_charges}
	for cell in walls: data["walls"].append([cell.x, cell.y])
	for cell in goals: data["goals"].append([cell.x, cell.y])
	for cell in boxes: data["boxes"].append([cell.x, cell.y])
	return data

func _apply_data(data: Dictionary) -> void:
	pull_charges = int(data.get("pull_charges", 0))
	if pull_toggle: pull_toggle.set_pressed_no_signal(pull_charges > 0)
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
	dirty_label.text = ("● 未保存改动" if dirty else "○ 无未保存改动") + "  |  箱子 %d / 目标 %d" % [boxes.size(), goals.size()]

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
	slot_popup.hide()
	status_label.text = "已保存到存档 %d。可以返回主菜单游玩，也可以继续编辑。" % save_slot
	_snapshot()
	_refresh_status()

func _load_pending() -> void:
	_apply_data(pending_data)
	save_slot = 0 if pending_is_original else pending_slot
	dirty = pending_is_original
	pending_action = ""
	slot_popup.hide()
	status_label.text = "原始草稿已导入，原文件不变。原图按标准推箱规则未找到解；建议先修改，再试玩。" if pending_is_original else "已读取存档 %d。" % save_slot
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
		pending_action = "back"
		discard_dialog.dialog_text = "当前地图有未保存改动。返回主菜单将放弃这些改动。\n先保存请点取消；确定返回请点确定。"
		discard_dialog.popup_centered(Vector2i(490, 150))
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
			_apply_data({"walls": [], "goals": [], "boxes": [], "player": [-1, -1]})
			dirty = true
			status_label.text = "已清空编辑区。请放置玩家、箱子和目标。"
			_refresh_status()
	pending_action = ""

func _discard_canceled() -> void:
	if pending_action == "load": _return_to_picker()
	pending_action = ""

func _go_back() -> void:
	GameState.editor_snapshot = {}
	GameState.preview_data = {}
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _snapshot() -> void:
	var data = _serialize()
	data["_dirty"] = dirty
	data["_slot"] = save_slot
	data["_tool"] = selected_tool
	GameState.editor_snapshot = data

func _preview() -> void:
	if _modal_open(): return
	var data = _serialize()
	var issue = Store.validate(data, true)
	if not issue.is_empty():
		_show_error(issue)
		return
	_snapshot()
	GameState.preview_data = data.duplicate(true)
	get_tree().change_scene_to_file("res://game.tscn")

func _show_error(message: String) -> void:
	error_dialog.dialog_text = message
	error_dialog.popup_centered(Vector2i(500, 170))

func _set_pull_enabled(enabled: bool) -> void:
	pull_charges = 1 if enabled else 0
	dirty = true
	_refresh_status()
