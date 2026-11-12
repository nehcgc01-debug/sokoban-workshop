extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var state = root.get_node("GameState")
	var routes = ["RRR", "RRRLLLDRRR", "LLURDRURLU"]
	var dirs = {"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}
	for i in range(3):
		state.preview_data = {}
		state.selected_builtin = i+1
		var game = load("res://game.tscn").instantiate()
		root.add_child(game)
		await process_frame
		for letter in routes[i]:
			if not game.try_move(dirs[letter]):
				push_error("Demo %d blocked at %s" % [i+1,letter]); quit(1); return
		if not game.level_complete:
			push_error("Demo %d not complete" % (i+1)); quit(1); return
		print("PASS demo %d completes in %d moves" % [i+1, game.moves])
		game.queue_free()
		await process_frame
	print("DEMO TESTS: 3/3")
	quit()
