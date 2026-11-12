extends SceneTree
var checks = 0
var failures = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)
	else: print("PASS " + message)
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var state = root.get_node("GameState")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	check(current_scene.name == "MainMenu", "main menu launches")
	current_scene._show_levels()
	check(current_scene.slot_buttons[0].disabled and current_scene.slot_buttons[1].disabled and current_scene.slot_buttons[2].disabled, "fresh user has three empty disabled slots")
	current_scene._play_builtin(2)
	await process_frame
	await process_frame
	check(current_scene.loaded and state.selected_builtin == 2, "first-run demo starts without save files")
	current_scene.try_move(Vector2i.RIGHT)
	current_scene.restart_level()
	check(current_scene.moves == 0 and current_scene.initial_data.boxes.size() == 2, "restart keeps chosen demo")
	current_scene.leave_game()
	await process_frame
	await process_frame
	check(current_scene.name == "MainMenu", "game returns to menu")
	current_scene._open_editor()
	await process_frame
	await process_frame
	check(current_scene.name == "LevelEditor", "menu opens editor")
	current_scene._paint_cell(Vector2i(1,1), "player")
	current_scene._paint_cell(Vector2i(2,1), "box")
	current_scene._paint_cell(Vector2i(3,1), "goal")
	var design = current_scene._serialize().duplicate(true)
	current_scene._preview()
	await process_frame
	await process_frame
	check(current_scene.name == "Game" and current_scene.is_preview, "editor preview starts")
	current_scene.try_move(Vector2i.RIGHT)
	check(current_scene.level_complete, "preview can be completed")
	current_scene.leave_game()
	await process_frame
	await process_frame
	check(current_scene.name == "LevelEditor" and current_scene._serialize() == design and current_scene.dirty, "return from preview restores unmodified unsaved design")
	check(not FileAccess.file_exists("user://custom_level.json"), "preview never writes slot 1")
	current_scene._open_slots("save")
	current_scene._choose_slot(2)
	current_scene._confirm_slot()
	check(FileAccess.file_exists("user://custom_level_2.json"), "editor saves slot 2")
	current_scene._request_back()
	await process_frame
	await process_frame
	current_scene._show_levels()
	check(not current_scene.slot_buttons[1].disabled, "menu refresh sees new slot")
	current_scene._play_slot(2)
	await process_frame
	await process_frame
	check(current_scene.loaded and state.selected_builtin == 0 and state.selected_slot == 2, "custom slot starts correct map")
	current_scene.try_move(Vector2i.RIGHT)
	check(current_scene.level_complete, "custom map wins")
	print("NAVIGATION TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
