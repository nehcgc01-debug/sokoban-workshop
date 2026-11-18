extends SceneTree
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, note):
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func run():
	var editor = load("res://level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._open_slots("save")
	await process_frame
	await process_frame
	check(editor.slot_buttons[0].has_focus(), "save opens with visible first-slot focus")
	check(editor.slot_confirm.disabled and editor.save_slot == 0, "focus is not a selected slot; confirmation still required")
	check(editor._configure_slot_focus().size() == 4, "fresh picker skips disabled confirm")
	check(editor.slot_buttons[2].get_node(editor.slot_buttons[2].focus_next) == editor.slot_cancel, "Tab skips disabled confirm")
	editor.slot_buttons[1].pressed.emit()
	check(editor.save_slot == 2 and editor.slot_confirm.has_focus(), "activating a slot selects it then focuses confirmation")
	check(editor._configure_slot_focus().size() == 5, "confirm enters navigation when enabled")
	check(editor.slot_confirm.get_node(editor.slot_confirm.focus_neighbor_bottom) == editor.slot_cancel, "arrow navigation reaches cancel")
	editor.slot_popup.hide()
	await process_frame
	await process_frame
	editor._open_slots("load")
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	check(editor.slot_cancel.has_focus(), "empty load focuses cancel, not disabled slots")
	check(editor._configure_slot_focus().size() == 1, "empty load only has cancel")
	editor.slot_popup.hide()
	await process_frame
	await process_frame
	editor._open_slots("original")
	await process_frame
	await process_frame
	check(editor.slot_buttons[0].has_focus(), "original import focuses first choice")
	check(editor.slot_buttons[2].disabled and editor._configure_slot_focus().size() == 3, "missing original slot stays excluded")
	editor.slot_popup.hide()
	await process_frame
	await process_frame
	editor._paint_cell(Vector2i(1,1), "player")
	editor._paint_cell(Vector2i(2,1), "box")
	editor._paint_cell(Vector2i(3,1), "goal")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	check(FileAccess.file_exists("user://custom_level.json"), "keyboard-accessible actions still save map")
	editor._paint_cell(Vector2i(0,0), "wall")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	check(editor.overwrite_dialog.visible, "overwrite confirmation remains required")
	editor.overwrite_dialog.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	check(editor.slot_popup.visible and editor.slot_buttons[0].has_focus(), "cancel overwrite restores selected-slot focus")
	check(editor.dirty, "cancel retains unsaved edit")
	editor.slot_popup.hide()
	await process_frame
	await process_frame
	editor.queue_free()
	await process_frame
	var game = load("res://game.gd").new()
	for id in [1,2,3,4,5,9,12,13,14,15,16]:
		var result = game.Store.load_path("res://levels/demo_%d.json" % id, true)
		game.initial_data = result.data
		var expected = int(result.data.get("pull_charges",0)) > 0 or result.data.has("tool")
		check(game._shortcut_text().contains("Shift") == expected, "map %d capability help" % id)
	game.initial_data = {"pull_charges":0}
	check(not game._shortcut_text().contains("Shift"), "custom zero-pull map hides pull help")
	game.initial_data = {"pull_charges":0,"tool":[2,2],"bench":[3,2]}
	check(game._shortcut_text().contains("Shift"), "zero-charge toolbox retains learnable action")
	game.initial_data = {"pull_charges":1}
	game.pull_charges = 0
	check(game._shortcut_text().contains("Shift"), "spent charges do not erase undo-recoverable ability help")
	var hints = game.Catalog.LEVELS[9].hints
	check(hints.size() == 3 and hints[0] == "观察窄槽里的箱子：你能站到它的左右两侧吗？", "L9 first hint points to concrete observation")
	check(not hints[0].contains("Shift") and not hints[0].contains("先拉") and not hints[0].contains("先推"), "L9 first hint does not provide move sequence")
	game.free()
	print("MENUWARM V3.1 TESTS: ", checks - failures, "/", checks)
	quit(1 if failures else 0)