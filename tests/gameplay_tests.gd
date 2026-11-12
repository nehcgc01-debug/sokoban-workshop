extends SceneTree
var failures = 0
var checks = 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var state = root.get_node("GameState")
	state.preview_data = {"walls":[[0,0]],"goals":[[3,2]],"boxes":[[2,2]],"player":[1,2]}
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.loaded, "valid preview loaded")
	check(game.try_move(Vector2i.RIGHT), "push succeeds")
	check(game.level_complete and game.moves == 1 and game.pushes == 1, "push onto goal completes and counts")
	check(not game.try_move(Vector2i.RIGHT), "movement blocked after completion")
	game.undo_move()
	check(not game.level_complete and game.player_pos == Vector2i(1,2) and game.boxes == [Vector2i(2,2)], "undo restores player/box/win")
	check(game.moves == 0 and game.pushes == 0, "undo restores counters")
	game.try_move(Vector2i.UP)
	game.restart_level()
	check(game.player_pos == Vector2i(1,2) and game.history.is_empty(), "restart initial state")
	check(state.preview_data["boxes"] == [[2,2]], "gameplay never mutates preview design")
	game.player_pos = Vector2i(0,1)
	check(not game.try_move(Vector2i.UP), "wall collision")
	check(not game.try_move(Vector2i.LEFT), "boundary collision")
	game.player_pos = Vector2i(1,2)
	game.boxes = [Vector2i(2,2), Vector2i(3,2)]
	check(not game.try_move(Vector2i.RIGHT), "two boxes cannot push")
	game.boxes = [Vector2i(0,1)]
	game.player_pos = Vector2i(0,2)
	check(not game.try_move(Vector2i.UP), "box into wall blocked")
	game.boxes = [Vector2i(0,2)]
	game.player_pos = Vector2i(1,2)
	check(not game.try_move(Vector2i.LEFT), "box outside grid blocked")
	game.queue_free()
	await process_frame
	state.preview_data = {"walls":[], "goals":[], "boxes":[], "player":[-1,-1]}
	game = load("res://game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(not game.loaded and not game.try_move(Vector2i.RIGHT), "invalid preview safely blocks play")
	print("GAMEPLAY TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
