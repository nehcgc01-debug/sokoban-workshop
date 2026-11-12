extends SceneTree
var count = 0
func check(value: bool, description: String) -> void:
	count += 1
	if not value:
		push_error(description)
		quit(1)
	else: print("PASS ", description)
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var state = root.get_node("GameState")
	var progress = load("res://progress_store.gd")
	check(progress.best_moves(1) == -1, "fresh profile has no score")
	state.selected_builtin = 1
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	check(not current_scene.next_button.visible, "next level hidden before win")
	for i in range(3): current_scene.try_move(Vector2i.RIGHT)
	check(current_scene.level_complete and current_scene.next_button.visible, "win offers next level")
	check(progress.best_moves(1) == 3, "win persists best steps")
	progress.record(1, 8)
	check(progress.best_moves(1) == 3, "worse score preserves best")
	current_scene.undo_move()
	check(not current_scene.next_button.visible, "undo win hides next")
	check(progress.best_moves(1) == 3, "undo preserves achieved record")
	current_scene.try_move(Vector2i.RIGHT)
	current_scene.next_level()
	await process_frame
	await process_frame
	check(state.selected_builtin == 2 and current_scene.loaded, "next loads following demo")
	current_scene.restart_level()
	check(not current_scene.next_button.visible and current_scene.moves == 0, "restart resets victory CTA")
	print("PRODUCT TESTS: ", count)
	quit(0)
