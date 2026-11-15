extends SceneTree
## V7.12: a draft kept on close is never silently replaced; leaving the editor offers keep / discard / cancel.
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
func frames(n := 2) -> void:
	for i in n:
		await process_frame
func to_scene(path: String):
	change_scene_to_file(path)
	await frames()
	return current_scene
func walls_of(d: Dictionary) -> Array:
	var w = d.get("walls", []).duplicate()
	w.sort()
	return w

const KEPT = {"walls": [[1, 1], [2, 1], [3, 1]], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": 0}
const SLOT_DRAFT = {"walls": [[0, 0]], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": 0}

func write_slot(slot: int, data: Dictionary) -> void:
	var f = FileAccess.open(Store.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func open_slot_draft_from_menu(slot: int):
	var menu = await to_scene("res://main_menu.tscn")
	menu._play_slot(slot)
	menu._open_draft()
	await frames(3)
	return current_scene

func run():
	var state = root.get_node("GameState")
	state.suppress_quit_for_test = true

	# ---- 1. the reported loss: kept draft, then an unfinished slot draft is opened from the level list
	Recovery.save_draft(KEPT, 2)
	write_slot(2, SLOT_DRAFT)
	var menu = await to_scene("res://main_menu.tscn")
	check(menu.menu_choices.get_child(1).text.contains("有未保存草稿"), "menu shows that a kept draft is waiting")
	var e = await open_slot_draft_from_menu(2)
	check(e.conflict_dialog.visible and e._modal_open(), "opening another map asks about the kept draft and blocks editing")
	check(walls_of(Recovery.load_draft()) == walls_of(KEPT), "while undecided the kept draft is untouched")
	e._unhandled_input(_key(KEY_1))
	check(walls_of(Recovery.load_draft()) == walls_of(KEPT), "input during the question changes nothing")
	state.request_quit()
	check(state.quit_requested and not state.close_dialog.visible and walls_of(Recovery.load_draft()) == walls_of(KEPT), "closing the window while undecided keeps the kept draft")
	state.quit_requested = false

	# restore (the default button)
	e.conflict_dialog.get_ok_button().pressed.emit()
	await frames()
	check(walls_of(e._serialize()) == walls_of(KEPT) and e.dirty and not e.conflict_dialog.visible, "restore puts the kept draft on screen as unsaved work")
	check(e.status_label.text.contains("基于存档 2"), "restore says which slot the draft was based on")
	check(walls_of(Recovery.load_draft()) == walls_of(KEPT), "kept draft is still protected after restoring")
	e._paint_cell(Vector2i(4, 1), "wall")
	check(Recovery.load_draft().walls.size() == 4, "edits after restoring keep auto-protecting")
	check(FileAccess.get_file_as_string(Store.slot_path(2)) == JSON.stringify(SLOT_DRAFT), "slot 2 file was never written")

	# closing the question box with Esc / x is the safe choice (restore)
	Recovery.save_draft(KEPT, 0)
	state.editor_snapshot = {}
	e = await open_slot_draft_from_menu(2)
	check(e.conflict_dialog.visible, "question appears again for a new kept draft")
	e.conflict_dialog.canceled.emit()
	e.conflict_dialog.hide()
	await frames()
	check(walls_of(e._serialize()) == walls_of(KEPT) and not e.status_label.text.contains("基于存档"), "closing the box restores; a new map shows no base slot")

	# explicit discard
	state.editor_snapshot = {}
	e = await open_slot_draft_from_menu(2)
	e._conflict_action("discard")
	await frames()
	check(Recovery.load_draft().is_empty() and walls_of(e._serialize()) == walls_of(SLOT_DRAFT), "discard drops the kept draft and opens the requested map")
	check(not e.conflict_dialog.visible and not e._modal_open(), "editor is usable after discarding")

	# no question when the kept draft is the very map being opened (return from a test play)
	e._paint_cell(Vector2i(5, 5), "wall")
	e._snapshot()
	var snap = state.editor_snapshot.duplicate(true)
	state.editor_snapshot = snap
	e = await to_scene("res://level_editor.tscn")
	await frames()
	check(not e.conflict_dialog.visible and e.dirty, "returning to the same draft does not ask")

	# ---- 2. leaving the editor: keep / discard / cancel, Enter keeps
	e._request_back()
	await frames()
	check(e.leave_dialog.visible and e.leave_dialog.get_ok_button().has_focus(), "Esc with changes opens keep/discard/cancel with focus on keep")
	check(e.leave_dialog.get_ok_button().text.contains("保留"), "the default button keeps the work")
	e.leave_dialog.get_cancel_button().pressed.emit()
	await frames()
	check(current_scene == e and e.dirty, "cancel stays in the editor")
	e._request_back()
	await frames()
	e.leave_dialog.get_ok_button().pressed.emit()
	await frames(3)
	check(current_scene.name != "LevelEditor" and walls_of(Recovery.load_draft()).has([5, 5]), "keep returns to the menu and keeps the draft")
	check(current_scene.menu_choices.get_child(1).text.contains("有未保存草稿"), "menu then shows the waiting draft")
	e = await to_scene("res://level_editor.tscn")
	await frames()
	check(walls_of(e._serialize()).has([5, 5]) and e.dirty and e.status_label.text.contains("已恢复"), "editor brings the kept draft back")
	e._request_back()
	await frames()
	e._leave_action("discard")
	await frames(3)
	check(current_scene.name != "LevelEditor" and Recovery.load_draft().is_empty(), "discard and return clears the draft")
	check(current_scene.menu_choices.get_child(1).text == "关卡编辑器", "menu label returns to normal")

	# keep fails -> stay
	e = await to_scene("res://level_editor.tscn")
	await frames()
	e._paint_cell(Vector2i(1, 4), "wall")
	var temp = Recovery.PATH + ".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp))
	var f = FileAccess.open(temp + "/block", FileAccess.WRITE)
	f.store_string("x")
	f.close()
	e._request_back()
	await frames()
	e.leave_dialog.get_ok_button().pressed.emit()
	await frames(3)
	check(current_scene == e and e.error_dialog.visible and e.walls.has(Vector2i(1, 4)), "if keeping fails the editor stays open with the map")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp + "/block"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	e.error_dialog.hide()

	# ---- 3. truthful slot status: opening the slot list and cancelling does not forget the slot
	e._apply_data(SLOT_DRAFT)
	e.pending_slot = 3
	e.pending_data = e._serialize()
	e._save_pending()
	check(e.dirty_label.text.contains("存档 3 已保存"), "saved to slot 3")
	e._open_slots("load")
	e.slot_popup.hide()
	e._refresh_status()
	check(e.dirty_label.text.contains("存档 3 已保存"), "cancelling the slot list keeps the slot in the status")
	e._paint_cell(Vector2i(6, 5), "wall")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(Recovery.PATH)).get("origin_slot", 0)) == 3, "the auto-kept draft remembers it came from slot 3")

	print("DRAFT KEEP TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("DRAFT KEEP SUITE PASSED")
	quit(1 if failures else 0)

func _key(code: int) -> InputEventKey:
	var k = InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
