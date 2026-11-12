extends SceneTree
var checks = 0
var failures = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)
func _initialize() -> void: call_deferred("run_tests")
func key(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
func open_builtin(index: int) -> void:
	var state = root.get_node("GameState")
	state.preview_data.clear()
	state.selected_builtin = index
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
func solve_first(game: Node) -> void:
	for i in range(3): game.try_move(Vector2i.RIGHT)
func run_tests() -> void:
	await open_builtin(1)
	var game = current_scene
	check(game.return_button.focus_mode == Control.FOCUS_ALL and game.next_button.focus_mode == Control.FOCUS_ALL, "game buttons are keyboard focusable")
	game.return_button.grab_focus()
	Input.parse_input_event(key(KEY_RIGHT))
	await process_frame
	var release_right = key(KEY_RIGHT)
	release_right.pressed = false
	Input.parse_input_event(release_right)
	check(game.player_pos == Vector2i(2,2) and game.moves == 1, "right moves player while menu button has focus")
	game._input(key(KEY_Z))
	check(game.moves == 0, "undo shortcut works while button focused")
	game._input(key(KEY_N))
	check(root.get_node("GameState").selected_builtin == 1 and not game.level_complete, "N cannot skip incomplete level")
	for code in [KEY_ENTER, KEY_SPACE, KEY_N]:
		await open_builtin(1)
		game = current_scene
		solve_first(game)
		check(game.level_complete and game.next_button.visible, "victory exposes Continue for key " + str(code))
		check(root.gui_get_focus_owner() == game.next_button, "victory focuses Continue for key " + str(code))
		# Direct event handler verifies no-focus keyboard fallback as well as N.
		game._unhandled_input(key(code))
		await process_frame
		await process_frame
		check(root.get_node("GameState").selected_builtin == 2 and current_scene.title_label.text.contains("2"), "key advances to actual next scene " + str(code))
	await open_builtin(1)
	game = current_scene
	solve_first(game)
	# Native GUI ui_accept activation (not calling the pressed callback directly).
	Input.parse_input_event(key(KEY_SPACE))
	await process_frame
	await process_frame
	check(root.get_node("GameState").selected_builtin == 2, "focused Continue activates through native Space input")
	await open_builtin(7)
	game = current_scene
	for step in "URDRDRDLLUULUlDRRUL":
		var direction = {"l":Vector2i.LEFT,"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}[step]
		game.try_move(direction, step == "l")
	check(game.level_complete and game.next_button.visible and not game.return_button.visible, "last-level victory has only one menu-return button")
	game.undo_move()
	check(game.return_button.visible and not game.next_button.visible, "undo restores ordinary return action")
	game.try_move(Vector2i.LEFT)
	check(game.level_complete, "last level can be completed again after undo")
	game._input(key(KEY_N))
	await process_frame
	await process_frame
	check(current_scene.has_method("_show_levels"), "N after final victory returns to main menu")
	var state = root.get_node("GameState")
	state.preview_data = {"walls":[],"goals":[[3,2]],"boxes":[[2,2]],"player":[1,2],"pull_charges":0}
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	game = current_scene
	game.try_move(Vector2i.RIGHT)
	check(game.level_complete and not game.next_button.visible and game.return_button.visible, "preview victory keeps editor-return action")
	check(root.gui_get_focus_owner() == game.return_button, "preview victory focuses return to editor")
	game._input(key(KEY_N))
	check(current_scene == game and game.is_preview, "N does not advance preview into built-in levels")
	print("KEYBOARD PROGRESS TESTS: ", checks-failures, "/", checks)
	quit(1 if failures else 0)
