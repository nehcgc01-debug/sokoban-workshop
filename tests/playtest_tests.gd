extends SceneTree
## V7.11: opt-in playtest log. Off by default; one line per attempt with what actually happened.
const Playtest = preload("res://playtest_log.gd")
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
func key(code: int, ctrl := false, shift := false) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e
func move(game, route: String) -> void:
	for c in route:
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c.to_upper()], c == c.to_lower())
func open_level(id: int):
	var state = root.get_node("GameState")
	state.preview_data = {}
	state.selected_builtin = id
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	return current_scene
func lines() -> Array:
	var out = []
	for l in Playtest.read_all().split("\n"):
		if not l.strip_edges().is_empty():
			out.append(JSON.parse_string(l))
	return out

func run():
	# off by default
	check(not Playtest.enabled(), "playtest log is off by default")
	var game = await open_level(1)
	check(game.attempt.is_empty(), "no attempt is tracked while off")
	move(game, "RRR")
	game.leave_game()
	await process_frame
	check(Playtest.attempt_count() == 0, "nothing is written while off")

	# facilitator turns it on from the menu
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	var menu = current_scene
	check(menu.playtest_label.text.is_empty(), "players see no indicator while off")
	menu._unhandled_key_input(key(KEY_P, true, true))
	check(Playtest.enabled() and menu.playtest_label.text.contains("试玩记录中"), "Ctrl+Shift+P turns it on and shows the indicator")
	menu.notice.hide()

	# one attempt on map 6 with a mistake, a rewind, hints, an undo, a restart and a win
	game = await open_level(6)
	game.try_move(Vector2i.RIGHT, true)            # habitual pull -> dead
	check(game.attempt.dead_entries == 1 and game.attempt.pulls_used == 1 and game.attempt.first_dead_at >= 0, "dead entry and pull counted")
	game.rewind_to_last_solvable()                  # B
	check(game.attempt.rewinds == 1 and game.attempt.undos == 0, "B counts as a rewind, not as undos")
	game.request_hint()
	game.request_hint()
	check(game.attempt.max_hint == 2 and game.attempt.hint_at.size() == 2, "hint levels and their times are recorded")
	move(game, "L")
	game.undo_move()
	check(game.attempt.undos == 1, "a normal undo is counted")
	game.restart_level()
	check(game.attempt.restarts == 1, "a restart is counted")
	move(game, "LRRRUULLLDLDUd")
	check(game.level_complete and game.attempt.solved and game.attempt.solve_moves == 14, "the win and its move count are recorded")
	check(game.attempt.moves_made == 1 + 1 + 14, "moves_made includes undone and restarted moves (%d)" % game.attempt.moves_made)
	game.next_level()
	await process_frame
	await process_frame
	var rows = lines()
	check(rows.size() == 1 and int(rows[0].level) == 6 and rows[0].end == "win_then_next" and rows[0].solved, "one line written when moving on")
	check(int(rows[0].position) == 7 and rows[0].has("at_utc") and not rows[0].has("finished"), "line has play position and time, no internal fields")

	# leaving unsolved, and the next level's attempt was started automatically
	game = current_scene
	check(not game.attempt.is_empty() and int(game.attempt.level) == 7, "next level starts a new attempt")
	move(game, "UR")
	game.leave_game()
	await process_frame
	await process_frame
	rows = lines()
	check(rows.size() == 2 and rows[1].end == "left_unsolved" and not rows[1].solved and int(rows[1].moves_made) == 2, "leaving unsolved is recorded")

	# test plays from the editor are not part of the study
	var state = root.get_node("GameState")
	state.preview_data = {"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0}
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	check(current_scene.attempt.is_empty(), "editor test plays are not logged")
	state.preview_data = {}

	# export and turn off
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	menu = current_scene
	check(menu.playtest_label.text.contains("2 次"), "indicator shows the attempt count")
	menu._unhandled_key_input(key(KEY_E, true, true))
	var exported = menu.notice.dialog_text.get_slice("\n", 1)
	check(FileAccess.file_exists(exported) and FileAccess.get_file_as_string(exported) == Playtest.read_all(), "Ctrl+Shift+E exports an exact copy (%s)" % exported)
	menu.notice.hide()
	menu._unhandled_key_input(key(KEY_P, true, true))
	check(not Playtest.enabled() and Playtest.attempt_count() == 2 and menu.playtest_label.text.is_empty(), "turning it off keeps the data and hides the indicator")
	print("PLAYTEST TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("PLAYTEST SUITE PASSED")
	quit(1 if failures else 0)
