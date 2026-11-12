extends SceneTree
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func run() -> void:
	var editor = load("res://level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._paint_cell(Vector2i(1,1), "player")
	editor._paint_cell(Vector2i(2,1), "box")
	editor._paint_cell(Vector2i(3,1), "goal")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	var before = FileAccess.get_file_as_string("user://custom_level.json")
	editor._paint_cell(Vector2i(0,0), "wall")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	check(editor.overwrite_dialog.visible and not editor.slot_popup.visible, "overwrite exclusively owns modal")
	editor.overwrite_dialog.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	check(not editor.overwrite_dialog.visible and editor.slot_popup.visible, "real overwrite Cancel button defers then restores picker")
	check(FileAccess.get_file_as_string("user://custom_level.json") == before, "cancel never overwrites saved bytes")
	check(editor.dirty and editor.walls.has(Vector2i(0,0)), "cancel preserves dirty draft")
	editor.slot_popup.hide()
	editor._open_slots("load")
	editor._choose_slot(1)
	editor._confirm_slot()
	check(editor.discard_dialog.visible and not editor.slot_popup.visible, "dirty load opens exclusive discard confirmation")
	editor.discard_dialog.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	check(not editor.discard_dialog.visible and editor.slot_popup.visible, "real discard Cancel button restores picker after old modal hides")
	check(editor.dirty and editor.walls.has(Vector2i(0,0)), "discard cancellation retains unsaved wall")
	editor.slot_popup.hide()
	editor._open_slots("save")
	check(editor.slot_popup.visible and editor.save_slot == 0 and editor.slot_confirm.disabled, "picker remains usable and requires fresh selection")
	editor.queue_free()
	await process_frame
	print("MODAL CANCEL TESTS: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
