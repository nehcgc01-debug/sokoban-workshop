extends Node

var selected_slot = 1
var selected_builtin = 1
var preview_data: Dictionary = {}
var editor_snapshot: Dictionary = {}
var editor_history: Dictionary = {}   # V7.13: editor undo/redo, kept across a test play only
var fresh_fixture = 0   # Lab 2: the latest order whose fixture was lit for the first time
var fresh_fixtures: Array = []   # every such order since the menu was last shown (the menu pulses them once; not saved)

# V7.8: fonts/NotoSansCJK-Regular.ttc holds 10 faces; Godot uses face 0 (Noto Sans CJK JP) by
# default, which draws Japanese glyph forms for some Simplified Chinese characters (e.g. 关, 骨, 直).
# Wrap the shared project theme font in a FontVariation that selects face 2 (Noto Sans CJK SC).
# The font file itself is unchanged.
const SC_FACE_INDEX = 2
var ui_font_face = ""

func _init() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or theme.default_font == null:
		return
	var base: Font = theme.default_font
	if base is FontVariation:
		base = (base as FontVariation).base_font
	if base == null or base.get_face_count() <= SC_FACE_INDEX:
		return
	var sc := FontVariation.new()
	sc.base_font = base
	sc.variation_face_index = SC_FACE_INDEX
	theme.default_font = sc
	ui_font_face = sc.get_font_name()

func selected_path() -> String:
	if selected_builtin > 0:
		return "res://levels/demo_%d.json" % selected_builtin
	return "user://custom_level.json" if selected_slot == 1 else "user://custom_level_%d.json" % selected_slot

# V7.11.1: OS close requests must not silently destroy an editor draft.
const DraftRecovery = preload("res://draft_recovery.gd")
var close_dialog: ConfirmationDialog
var close_error: AcceptDialog
var quit_requested = false
var suppress_quit_for_test = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	if _real_desktop_window():
		fit_window_to_screen.call_deferred()
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "关闭工坊"
	close_dialog.dialog_text = "当前有未保存的编辑草稿。\n保留后，下次打开编辑器将自动恢复；不会覆盖存档槽。"
	close_dialog.ok_button_text = "保留草稿并退出"
	close_dialog.cancel_button_text = "取消"
	close_dialog.add_button("放弃草稿并退出", false, "discard")
	close_dialog.confirmed.connect(_keep_and_quit)
	close_dialog.custom_action.connect(_close_action)
	add_child(close_dialog)
	close_error = AcceptDialog.new()
	close_error.ok_button_text = "返回编辑"
	add_child(close_error)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func _active_draft() -> Dictionary:
	var scene = get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("_serialize"):
		scene._snapshot()
	return editor_snapshot

func request_quit() -> void:
	var data = _active_draft()
	if bool(data.get("_dirty", false)):
		if not close_dialog.visible:
			close_dialog.popup_centered(Vector2i(570, 180))
		return
	_finish_quit()

func _keep_and_quit() -> void:
	close_dialog.hide()
	var data = _active_draft()
	var issue = DraftRecovery.save_draft(data) if bool(data.get("_dirty", false)) else ""
	if not issue.is_empty():
		close_error.dialog_text = issue + "\n未退出，草稿仍在。"
		close_error.popup_centered()
		return
	_finish_quit()

func _close_action(action: String) -> void:
	if action != "discard": return
	close_dialog.hide()
	var issue = DraftRecovery.clear()
	if not issue.is_empty():
		close_error.dialog_text = issue + "\n未退出，草稿仍在。"
		close_error.popup_centered()
		return
	editor_snapshot = {}
	_finish_quit()

# V7.12: the 1152x720 design is scaled to the screen it opens on (bigger on large or high-DPI
# screens, smaller on 1366x768 laptops so the bottom row is not under the taskbar). F11 = fullscreen.
const BASE_SIZE = Vector2(1152, 720)
var saved_window_rect = Rect2i()
var saved_window_mode = DisplayServer.WINDOW_MODE_WINDOWED

func _real_desktop_window() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor()

static func window_scale_for(usable: Vector2i) -> float:
	# 92% of the width and 88% of the height leave room for the title bar and screen edges.
	var fit = minf(usable.x * 0.92 / BASE_SIZE.x, usable.y * 0.88 / BASE_SIZE.y)
	if fit < 1.0:
		return maxf(fit, 0.5)
	return floorf(fit * 4.0) / 4.0   # quarter steps keep the pixel art even

const MIN_SIZE = Vector2i(960, 600)

static func min_window_size(fitted: Vector2i) -> Vector2i:
	# never larger than what the screen allowed (small laptops), otherwise 960x600 (= 5/6 scale)
	return Vector2i(mini(MIN_SIZE.x, fitted.x), mini(MIN_SIZE.y, fitted.y))

func fit_window_to_screen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var usable = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var k = window_scale_for(usable.size)
	var size = Vector2i(roundi(BASE_SIZE.x * k), roundi(BASE_SIZE.y * k))
	# V7.13: dragging the window smaller than this made the 16-17 px text hard to read.
	DisplayServer.window_set_min_size(min_window_size(size))
	if size == DisplayServer.window_get_size():
		return
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)

func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_restore_window.call_deferred()
	else:
		saved_window_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		saved_window_mode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _restore_window() -> void:
	if saved_window_rect.size.x > 0 and saved_window_rect.size.y > 0:
		DisplayServer.window_set_size(saved_window_rect.size)
		DisplayServer.window_set_position(saved_window_rect.position)
		if saved_window_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
			DisplayServer.window_set_mode(saved_window_mode)
	else:
		fit_window_to_screen()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11 and _real_desktop_window():
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func _finish_quit() -> void:
	quit_requested = true
	if not suppress_quit_for_test: get_tree().quit()
