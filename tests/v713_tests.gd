extends SceneTree
## V7.13: review fixes (draft origin kept across restores, re-ask after a failed discard,
## visible auto-protection failure) and editor undo / redo.
const Recovery = preload("res://draft_recovery.gd")
const Store = preload("res://level_store.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)
func frames(n := 3) -> void:
	for i in n:
		await process_frame
func to_editor():
	change_scene_to_file("res://level_editor.tscn")
	await frames()
	return current_scene
func key(code: int, shift := false, ctrl := false) -> InputEventKey:
	var k = InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	k.ctrl_pressed = ctrl
	return k
func file_origin() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(Recovery.PATH)).get("origin_slot", 0)
func block_writes() -> void:
	var tmp = Recovery.PATH + ".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(tmp))
	var b = FileAccess.open(tmp + "/x", FileAccess.WRITE)
	b.store_string("x")
	b.close()
func unblock_writes() -> void:
	var tmp = Recovery.PATH + ".tmp"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp + "/x"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
const SLOT_DRAFT = {"walls": [[0, 0]], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": 0}

func run():
	var state = root.get_node("GameState")
	state.suppress_quit_for_test = true

	# ---- 1. origin survives every restore
	Recovery.save_draft({"walls": [[1, 1]], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": 0}, 2)
	var e = await to_editor()
	check(e.status_label.text.contains("基于存档 2"), "first restore names slot 2")
	e._paint_cell(Vector2i(2, 2), "wall")
	check(int(file_origin()) == 2, "an edit after restoring keeps origin 2 in the file")
	state.editor_snapshot = {}
	state.editor_history = {}
	e = await to_editor()
	check(e.status_label.text.contains("基于存档 2"), "second restore still names slot 2")
	e._snapshot()                       # test play and back
	e = await to_editor()
	e._paint_cell(Vector2i(3, 2), "wall")
	check(int(file_origin()) == 2, "origin survives a test play")
	e._request_back()
	await frames()
	e.leave_dialog.get_ok_button().pressed.emit()
	await frames(4)
	check(int(file_origin()) == 2, "keep-and-return keeps the origin")

	# ---- 2. failed discard of a held draft asks again
	var f = FileAccess.open(Store.slot_path(2), FileAccess.WRITE)
	f.store_string(JSON.stringify(SLOT_DRAFT))
	f.close()
	var kept_text = FileAccess.get_file_as_string(Recovery.PATH)
	change_scene_to_file("res://main_menu.tscn")
	await frames()
	current_scene._play_slot(2)
	current_scene._open_draft()
	await frames()
	e = current_scene
	check(e.conflict_dialog.visible, "conflict question shown")
	block_writes()
	e._conflict_action("discard")
	await frames()
	check(e.error_dialog.visible and e.error_dialog.dialog_text.contains("再选择一次"), "failed discard explains and keeps the draft")
	e.error_dialog.hide()
	await frames()
	check(e.conflict_dialog.visible and e._modal_open() and not e.held_recovery.is_empty(), "the question comes back; the editor is not left unprotected")
	check(FileAccess.get_file_as_string(Recovery.PATH) == kept_text, "kept draft untouched by the failed discard")
	unblock_writes()
	e._conflict_action("discard")
	await frames()
	check(Recovery.load_draft().is_empty() and not e._modal_open(), "a second try succeeds once the disk works")

	# ---- 3. auto-protection failure stays visible
	block_writes()
	e._paint_cell(Vector2i(4, 4), "wall")
	check(e.dirty_label.text.contains("自动保护失败"), "status bar shows that the draft is not protected")
	unblock_writes()
	e._paint_cell(Vector2i(5, 4), "wall")
	check(not e.dirty_label.text.contains("自动保护失败") and Recovery.load_draft().walls.size() == 3, "next edit retries and clears the warning")

	# ---- 4. undo / redo
	state.editor_snapshot = {}
	state.editor_history = {}
	Recovery.clear()
	e = await to_editor()
	check(not e.dirty and e.walls.is_empty(), "blank editor")
	e._unhandled_input(key(KEY_Z))
	check(e.status_label.text.contains("没有可以撤销"), "Z with nothing to undo says so")
	e._paint_cell(Vector2i(1, 1), "wall")
	e._paint_cell(Vector2i(2, 1), "wall")
	e._paint_cell(Vector2i(2, 1), "wall")   # no change -> no history entry
	check(e.undo_stack.size() == 2, "only real changes are recorded")
	e._unhandled_input(key(KEY_Z))
	check(e.walls.size() == 1 and e.walls.has(Vector2i(1, 1)), "Z undoes the last placement")
	e._unhandled_input(key(KEY_Z, true))
	check(e.walls.size() == 2, "Shift+Z redoes it")
	e._unhandled_input(key(KEY_Z, false, true))
	e._unhandled_input(key(KEY_Y, false, true))
	check(e.walls.size() == 2 and e.check_job == null, "Ctrl+Z / Ctrl+Y work and do not start a check")
	e._unhandled_input(key(KEY_Z))
	e._unhandled_input(key(KEY_Z))
	check(e.walls.is_empty() and not e.dirty and Recovery.load_draft().is_empty(), "undoing back to the starting map is no longer unsaved and drops the draft")
	e._unhandled_input(key(KEY_Z, true))
	check(e.dirty and Recovery.load_draft().walls.size() == 1, "redo makes it unsaved and protected again")
	e._paint_cell(Vector2i(3, 3), "box")
	check(e.redo_stack.is_empty(), "a new edit clears redo")
	# erase by right click, pull toggle and clear are undoable
	e._paint_cell(Vector2i(1, 1), "floor")
	e._unhandled_input(key(KEY_Z))
	check(e.walls.has(Vector2i(1, 1)), "erasing is undoable")
	e._set_pull_enabled(true)
	e._unhandled_input(key(KEY_Z))
	check(e.pull_charges == 0 and not e.pull_toggle.button_pressed, "pull toggle is undoable and the switch follows")
	var before_clear = Store.canonical(e._serialize())
	e.pending_action = "clear"
	e._discard_confirmed()
	check(e.walls.is_empty() and e.boxes.is_empty(), "cleared")
	e._unhandled_input(key(KEY_Z))
	check(Store.canonical(e._serialize()) == before_clear, "clear can be undone")
	# importing a share code over work can be undone
	var code_map = Store.load_path("res://levels/demo_9.json").data
	e.pending_data = code_map
	e.pending_is_shared = true
	e._load_pending()
	check(Store.canonical(e._serialize()) == Store.canonical(code_map), "share code imported")
	e._unhandled_input(key(KEY_Z))
	check(Store.canonical(e._serialize()) == before_clear, "importing a share code can be undone")
	# history survives a test play, not leaving to the menu
	e._unhandled_input(key(KEY_Z, true))
	var undo_n = e.undo_stack.size()
	e._snapshot()
	e = await to_editor()
	check(e.undo_stack.size() == undo_n and e.redo_stack.is_empty(), "history survives a test play")
	e._unhandled_input(key(KEY_Z))
	check(Store.canonical(e._serialize()) == before_clear, "undo after a test play works")
	# saving sets the clean point
	e.pending_slot = 3
	e.pending_data = e._serialize()
	e._save_pending()
	e._paint_cell(Vector2i(6, 0), "wall")
	e._unhandled_input(key(KEY_Z))
	check(not e.dirty and e.dirty_label.text.contains("存档 3 已保存"), "undo back to the saved map shows it as saved")
	# limit and modal guard
	for i in 60:   # 120 real changes: place then erase the same free cell
		e._paint_cell(Vector2i(5, 5), "box")
		e._paint_cell(Vector2i(5, 5), "floor")
	check(e.undo_stack.size() == e.UNDO_LIMIT, "history is capped at %d steps" % e.UNDO_LIMIT)
	e._request_back()
	await frames()
	var w = e.walls.size()
	e._unhandled_input(key(KEY_Z))
	check(e.walls.size() == w, "Z does nothing while a dialog is open")
	e._leave_action("discard")
	await frames(4)
	check(state.editor_history.is_empty(), "leaving to the menu forgets the history")

	# ---- 5. minimum window size
	check(state.min_window_size(Vector2i(1440, 900)) == Vector2i(960, 600), "minimum window is 960x600")
	check(state.min_window_size(Vector2i(900, 563)) == Vector2i(900, 563), "on a tiny screen the minimum never exceeds the fitted size")

	print("V7.13 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("V713 SUITE PASSED")
	quit(1 if failures else 0)
