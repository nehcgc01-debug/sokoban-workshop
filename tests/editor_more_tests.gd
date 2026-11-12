extends SceneTree
var checks = 0
func _initialize() -> void: call_deferred("run_tests")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	print("PASS ", message)
func run_tests() -> void:
	var editor = load("res://level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._paint_cell(Vector2i(1,1), "player")
	editor._paint_cell(Vector2i(2,1), "box")
	editor._paint_cell(Vector2i(3,1), "goal")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	check(not editor.dirty, "first save succeeds")
	editor._paint_cell(Vector2i(0,0), "wall")
	editor._open_slots("save")
	editor._choose_slot(1)
	editor._confirm_slot()
	editor.save_slot = 2
	editor.overwrite_dialog.hide()
	editor._overwrite_confirmed()
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://custom_level.json"))
	check(data.walls.size() == 1 and not FileAccess.file_exists("user://custom_level_2.json"), "overwrite uses captured slot, not later selection")
	var file = FileAccess.open("user://custom_level_3.json", FileAccess.WRITE)
	file.store_string("{broken json")
	file.close()
	var before = editor._serialize()
	editor._open_slots("load")
	editor._choose_slot(3)
	editor._confirm_slot()
	check(before == editor._serialize() and editor.slot_popup.visible, "malformed load preserves draft and displays error")
	editor.slot_popup.hide()
	editor._paint_cell(Vector2i(1,1), "floor")
	editor._preview()
	check(editor.error_dialog.visible and root.get_node("GameState").preview_data.is_empty(), "invalid preview blocked without scene change")
	print("MORE EDITOR TESTS PASSED: ", checks)
	quit(0)
