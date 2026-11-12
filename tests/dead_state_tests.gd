extends SceneTree
## V7.7: exact dead-state check, B rewind, work-order context and optimal-step display.
## dead_state_fixture.json lists every reachable state of the 7 built-in maps with the
## ground-truth answer from an independent Python BFS (tests/solve_levels.py rules).
const DeadSolver = preload("res://dead_state_solver.gd")
const Catalog = preload("res://level_catalog.gd")
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

func run():
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dead_state_fixture.json"))
	for i in range(1, Catalog.COUNT + 1):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/demo_%d.json" % i))
		var walls = {}
		var goals = {}
		for w in d["walls"]: walls[Vector2i(int(w[0]), int(w[1]))] = true
		for g in d["goals"]: goals[Vector2i(int(g[0]), int(g[1]))] = true
		var solver = DeadSolver.new(walls, goals)
		var false_dead = 0
		var missed_dead = 0
		var unknown = 0
		var t0 = Time.get_ticks_usec()
		for row in fixture[str(i)]:
			var boxes: Array = []
			for b in row[2]: boxes.append(Vector2i(int(b[0]), int(b[1])))
			var got = solver.status(Vector2i(int(row[0]), int(row[1])), boxes, int(row[3]))
			if got == "unknown": unknown += 1
			elif got == "dead" and int(row[4]) == 1: false_dead += 1
			elif got == "solvable" and int(row[4]) == 0: missed_dead += 1
		var ms = (Time.get_ticks_usec() - t0) / 1000.0
		check(false_dead == 0 and missed_dead == 0 and unknown == 0,
			"map %d: %d states, 0 false alarms, 0 missed dead states, 0 unknown (%.0f ms total)" % [i, fixture[str(i)].size(), ms])
	check(root.get_node("GameState").ui_font_face == "Noto Sans CJK SC", "V7.8: UI font uses the Simplified Chinese face of the bundled TTC (got %s)" % root.get_node("GameState").ui_font_face)
	check(ThemeDB.get_project_theme().default_font is FontVariation and ThemeDB.get_project_theme().default_font.variation_face_index == 2, "V7.8: project theme font selects TTC face 2")
	check(Catalog.OPTIMAL.size() == Catalog.COUNT and Catalog.ORDERS.size() == Catalog.COUNT, "catalog has optimal steps and a work order for every map")

	var state = root.get_node("GameState")
	state.preview_data = {}
	state.selected_builtin = 6
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	var game = current_scene
	check(game.order_label.text.begins_with("工单 06"), "map 6 shows its work order")
	check(game.title_label.text.contains("6") and game.title_label.text.contains("挑战篇"), "title keeps number and chapter")
	game.try_move(Vector2i.RIGHT, true)
	check(game.pull_charges == 0 and game.dead_rewind_steps == 1 and game.status_label.text.contains("无解"), "habitual first pull on map 6 is reported dead immediately")
	check(game.hint_button.disabled, "hint is paused while the board is dead")
	var hint_before = game.hint_level
	game._input(_key(KEY_H))
	game._input(_key(KEY_H))
	check(game.hint_level == hint_before, "V7.8 regression: H does not advance hints on a non-corner dead board")
	game.request_hint()
	check(game.hint_level == hint_before, "V7.8 regression: hint button action also blocked while dead")
	game._input(_key(KEY_B))
	check(game.pull_charges == 1 and game.moves == 0 and game.dead_rewind_steps == 0, "B rewinds exactly to the last solvable state and refunds the pull")
	check(game.hint_level == hint_before and not game.hint_button.disabled, "V7.8 regression: hint level unchanged after B, button re-enabled")
	game._input(_key(KEY_H))
	check(game.hint_level == hint_before + 1, "after B, H advances normally")
	var t1 = Time.get_ticks_usec()
	for c in "LRRRUULLLDLDU":
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c])
	var per_move_ms = (Time.get_ticks_usec() - t1) / 1000.0 / 13.0
	check(game.dead_rewind_steps == 0 and not game.status_label.text.contains("无解") and not game.status_label.text.contains("已无法移出"), "intended corner setup at step 13 is not flagged (pull still available)")
	check(per_move_ms < 5.0, "average move with exact check < 5 ms (%.2f ms)" % per_move_ms)
	game.try_move(Vector2i.DOWN, true)
	check(game.level_complete and game.status_label.text.contains("最优 14") and game.status_label.text.contains("顿悟"), "win shows optimal steps and the insight line")
	game._input(_key(KEY_B))
	check(game.level_complete, "B does nothing on a won board")

	state.selected_builtin = 1
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	game = current_scene
	check(game.headline_label.text == "推箱工坊 / PLAY" and game.order_label.text.begins_with("工单 01"), "intro chapter keeps the day headline")
	for c in "DRU":
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c])
	check(game.status_label.text.contains("无解") and game.dead_rewind_steps == 1, "box pushed against the far wall on map 1 is reported dead (corner check missed this)")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	var texts = []
	for b in current_scene.menu_choices.get_children():
		if b is Button: texts.append(b.text)
	check(texts.has("开始游戏") and texts.has("关卡编辑器"), "V7.8: main menu buttons read 开始游戏 / 关卡编辑器 (%s)" % str(texts))
	print("Dead-state suite: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("DEAD STATE SUITE PASSED")
	quit(1 if failures else 0)

func _key(code):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
