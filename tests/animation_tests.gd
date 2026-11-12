extends SceneTree
var failures = 0
var checks = 0
func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state = root.get_node("GameState")
	state.preview_data = {"walls":[[1,0]],"goals":[[5,4]],"boxes":[[2,2]],"player":[1,2],"pull_charges":1}
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(game.facing == Vector2i.DOWN and not game.current_data().animating, "initial facing down, idle")
	check(game.try_move(Vector2i.RIGHT), "animated push accepted")
	var data = game.current_data()
	check(game.player_pos == Vector2i(2,2) and game.boxes == [Vector2i(3,2)], "logical push immediate")
	check(data.visual_player == Vector2(1,2) and data.visual_boxes[Vector2i(3,2)] == Vector2(2,2), "visual push starts at old cells")
	check(data.facing == Vector2i.RIGHT and data.effort and not data.pulling_visual, "push faces box with effort")
	game._process(0.09)
	data = game.current_data()
	check(data.visual_player.is_equal_approx(Vector2(1.5,2)) and data.visual_boxes[Vector2i(3,2)].is_equal_approx(Vector2(2.5,2)), "player and box interpolate halfway")
	game._process(0.10)
	check(not game.current_data().animating and game.current_data().effort, "sweat lingers after movement")
	game._process(0.25)
	check(not game.current_data().effort, "effort ends at idle")
	game.undo_move()
	check(game.facing == Vector2i.DOWN and not game.current_data().animating and game.player_pos == Vector2i(1,2), "undo restores facing and clears visual state")
	game.try_move(Vector2i.RIGHT)
	check(game.try_move(Vector2i.LEFT, true), "pull allowed during previous animation")
	data = game.current_data()
	check(data.facing == Vector2i.RIGHT and data.effort and data.pulling_visual, "pull faces box behind travel")
	check(data.visual_player == Vector2(2,2) and data.visual_boxes[Vector2i(2,2)] == Vector2(3,2), "new visual transition begins at logical origin")
	game.restart_level()
	check(game.facing == Vector2i.DOWN and not game.current_data().effort and not game.current_data().animating, "restart clears movement and sweat")
	game.try_move(Vector2i.UP)
	game.try_move(Vector2i.UP)
	check(game.moves == 1 and game.history.size() == 1 and game.facing == Vector2i.UP, "blocked move faces wall but never counts")
	game.undo_move()
	check(game.facing == Vector2i.DOWN, "undo restores pre-turn orientation")
	game.try_move(Vector2i.DOWN)
	game.try_move(Vector2i.RIGHT)
	check(game.moves == 2 and game.player_pos == Vector2i(2,3), "rapid commands preserve logical movement")
	game._process(1.0)
	check(game.current_data().visual_player == Vector2(2,3), "rapid movement settles at final cell")
	game.queue_free()
	await process_frame
	print("ANIMATION TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
