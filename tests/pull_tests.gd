extends SceneTree
const Store = preload("res://level_store.gd")
var checks = 0
var failures = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else: print("PASS ", message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state = root.get_node("GameState")
	var basic = {"walls":[],"goals":[[5,2]],"boxes":[[1,2]],"player":[2,2]}
	check(Store.validate(basic).is_empty(), "old schema accepted")
	check(Store.normalize(basic).pull_charges == 0, "old maps default no pull")
	for bad in [-1,2,0.5,"1",true,null]:
		var data = basic.duplicate(true)
		data.pull_charges = bad
		check(not Store.validate(data).is_empty(), "bad charge rejected: " + str(bad))
	basic.pull_charges = 1.0
	check(Store.validate(basic).is_empty() and Store.normalize(basic).pull_charges == 1, "JSON float charge normalizes")
	check(Store.save_path(Store.slot_path(3),basic).is_empty() and Store.load_path(Store.slot_path(3)).data.pull_charges == 1, "charge persists through storage")
	state.preview_data = basic.duplicate(true)
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.pull_charges == 1, "preview receives charge")
	check(not game.try_move(Vector2i.UP,true), "missing rear box rejects pull")
	check(game.moves == 0 and game.history.is_empty() and game.pull_charges == 1, "failed pull consumes nothing")
	game.walls[Vector2i(3,2)] = true
	check(not game.try_move(Vector2i.RIGHT,true), "wall in retreat cell blocks pull")
	game.walls.clear()
	game.boxes.append(Vector2i(3,2))
	check(not game.try_move(Vector2i.RIGHT,true), "box in retreat cell blocks pull")
	game.boxes.pop_back()
	check(game.try_move(Vector2i.RIGHT,true), "valid pull succeeds")
	check(game.player_pos == Vector2i(3,2) and game.boxes == [Vector2i(2,2)], "pull moves player and rear box correctly")
	check(game.moves == 1 and game.pushes == 0 and game.pulls == 1 and game.pull_charges == 0, "pull counts one move and consumes one charge")
	check(not game.try_move(Vector2i.RIGHT,true), "second pull cannot spend exhausted charge")
	game.undo_move()
	check(game.pull_charges == 1 and game.pulls == 0 and game.moves == 0 and game.player_pos == Vector2i(2,2), "undo refunds charge and restores all counters")
	check(game.try_move(Vector2i.DOWN), "normal walking does not require pull")
	check(game.pull_charges == 1, "normal movement preserves charge")
	game.restart_level()
	check(game.pull_charges == 1 and game.history.is_empty(), "restart restores charge")
	check(state.preview_data == basic, "pull never mutates editor preview")
	check(not game.try_pull(Vector2i.ZERO), "zero-direction pull rejected")
	var event = InputEventKey.new()
	event.keycode = KEY_RIGHT
	event.pressed = true
	event.shift_pressed = true
	game._unhandled_input(event)
	check(game.pulls == 1 and game.pull_charges == 0, "Shift right input dispatches pull")
	game.restart_level()
	game.player_pos = Vector2i(6,2)
	game.boxes = [Vector2i(5,2)]
	check(not game.try_pull(Vector2i.RIGHT) and game.pull_charges == 1, "boundary blocks pull without consumption")
	game.restart_level()
	game.pull_charges = 0
	check(not game.try_pull(Vector2i.RIGHT) and game.moves == 0, "zero-charge classic mode rejects pull")

	game.queue_free()
	await process_frame
	var routes = ["r", "rDLLURURRRDDLLLULD"]
	var dirs = {"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}
	for index in range(2):
		state.preview_data = {}
		state.selected_builtin = index+4
		game = load("res://game.tscn").instantiate()
		root.add_child(game)
		await process_frame
		var valid = true
		for letter in routes[index]:
			valid = game.try_move(dirs[letter.to_upper()], letter == letter.to_lower()) and valid
		check(valid and game.level_complete and game.pulls == 1, "demo %d engine solution succeeds with exactly one pull" % (index+4))
		game.undo_move()
		check(not game.level_complete, "undo can leave victory for demo %d" % (index+4))
		game.restart_level()
		check(not game.level_complete and game.pull_charges == 1, "restart pull demo %d" % (index+4))
		game.queue_free()
		await process_frame
	print("PULL TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
