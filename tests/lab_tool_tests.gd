extends SceneTree
## Lab: tool crate rules, feedback, dead checks, file / share-code compatibility, editor support.
const Store = preload("res://level_store.gd")
const Catalog = preload("res://level_catalog.gd")
const DeadSolver = preload("res://dead_state_solver.gd")
const Progress = preload("res://progress_store.gd")
const Recovery = preload("res://draft_recovery.gd")
const NONE = Vector2i(-1, -1)
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
func frames(n := 2) -> void:
	for i in n:
		await process_frame
func level(id: int) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://levels/demo_%d.json" % id))
func play(id: int):
	var state = root.get_node("GameState")
	state.preview_data = {}
	state.selected_builtin = id
	state.selected_slot = 0
	change_scene_to_file("res://game.tscn")
	await frames()
	return current_scene
func preview(data: Dictionary):
	var state = root.get_node("GameState")
	state.preview_data = data.duplicate(true)
	change_scene_to_file("res://game.tscn")
	await frames()
	return current_scene
func route(game, moves: String) -> void:
	for c in moves:
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c.to_upper()], c == c.to_lower())
func key(code: int, shift := false) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e
func rows_to_data(rows: Array, charges: int) -> Dictionary:
	var d = {"walls": [], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": charges}
	for y in rows.size():
		for x in rows[y].length():
			var ch = rows[y][x]
			if ch == "#": d.walls.append([x, y])
			if ch in [".", "*", "+"]: d.goals.append([x, y])
			if ch in ["$", "*"]: d.boxes.append([x, y])
			if ch in ["@", "+"]: d.player = [x, y]
			if ch == "T": d["tool"] = [x, y]
			if ch == "K": d["bench"] = [x, y]
	return d

func run():
	var state = root.get_node("GameState")
	state.suppress_quit_for_test = true

	# ---------------- solver vs an independent Python BFS on every reachable lab state ----------------
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/lab_dead_fixture.json"))
	for id in Catalog.LAB_ORDER:
		var d = level(id)
		var walls = {}
		var goals = {}
		for w in d.walls: walls[Vector2i(int(w[0]), int(w[1]))] = true
		for g in d.goals: goals[Vector2i(int(g[0]), int(g[1]))] = true
		var solver = DeadSolver.new(walls, goals, Store.cell_of(d, "bench"))
		var wrong = 0
		var unknown = 0
		for row in fixture[str(id)]:
			var boxes: Array = []
			for b in row[2]: boxes.append(Vector2i(int(b[0]), int(b[1])))
			var got = solver.status(Vector2i(int(row[0]), int(row[1])), boxes, int(row[3]), 20000, Vector2i(int(row[4]), int(row[5])))
			if got == "unknown": unknown += 1
			elif (got == "solvable") != (int(row[6]) == 1): wrong += 1
		check(wrong == 0 and unknown == 0, "lab map %s: all %d reachable states agree with the Python BFS" % [Catalog.code(id), fixture[str(id)].size()])

	var longest = 0
	for id in Catalog.LAB_ORDER + [5]:
		longest = maxi(longest, Catalog.insight(id).length())
	check(longest <= 16, "lab and level-5 insight lines fit one panel line (longest %d)" % longest)

	# ---------------- format, validation, compatibility ----------------
	var t1 = level(12)
	check(Store.validate(t1, true).is_empty() and Store.uses_lab_features(t1), "T1 is a valid lab map")
	var lone = t1.duplicate(true)
	lone.erase("bench")
	check(Store.validate(lone, true).contains("成对"), "a crate without a bench is refused for play, with the reason")
	check(Store.validate(lone, false).is_empty(), "…but can still be saved as a draft")
	var clash = t1.duplicate(true)
	clash["tool"] = clash.goals[0]
	check(Store.validate(clash, false).contains("工具箱"), "a crate on a goal is refused")
	var three = t1.duplicate(true)
	three["pull_charges"] = 3
	check(Store.validate(three, false).contains("0、1 或 2"), "more than 2 starting pulls is refused")
	var classic = level(9)
	check(not Store.canonical(classic).has("tool") and not Store.uses_lab_features(classic), "old maps keep their exact old form (no new keys)")
	check(Store.share_code(classic) == "KURO1-WWWWWWW/WGWWOWW/WOOOOOW/WOOWBWW/WGOBPOW/WWWWWWW-D795C1", "old maps keep the exact V7.13.1 share code")
	var code1 = Store.share_code(t1)
	check(code1.begins_with("KUROT0-") and code1.contains("T") and code1.contains("K"), "a crate map gets a KUROT code (%s)" % code1)
	var back = Store.parse_share_code(code1)
	check(back.ok and Store.canonical(back.data) == Store.canonical(t1), "KUROT code round-trips the crate and the bench")
	var two = level(9)
	two["pull_charges"] = 2
	check(Store.share_code(two).begins_with("KUROT2-") and Store.parse_share_code(Store.share_code(two)).data.pull_charges == 2, "2 starting pulls round-trip in a KUROT code")
	var future = Store.parse_share_code("KURO7-OOOOOOO/OOOOOOO/OOOOOOO/OOOOOOO/OOOOOOO/OOOOOOO-000000")
	check(not future.ok and future.error.contains("更新版本"), "an unknown future code says it needs a newer version")
	var smuggled = Store.share_code(classic).replace("WOOWBWW", "WOOWTWW")
	check(not Store.parse_share_code(smuggled).ok, "a crate letter inside an old-style code is rejected, not silently accepted")
	var player_on_bench = t1.duplicate(true)
	player_on_bench.player = player_on_bench.bench.duplicate()
	var pb = Store.parse_share_code(Store.share_code(player_on_bench))
	check(pb.ok and Store.cell_of(pb.data, "player") == Store.cell_of(player_on_bench, "bench") and Store.cell_of(pb.data, "bench") == Store.cell_of(player_on_bench, "bench"), "player standing on the bench survives a share code")
	# an old (V7.13.1) slot file loads, plays and saves back without new keys
	var old_text = '{"walls": [[0,0]], "goals": [[3,2]], "boxes": [[2,2]], "player": [1,2], "pull_charges": 1}'
	var f = FileAccess.open(Store.slot_path(1), FileAccess.WRITE)
	f.store_string(old_text)
	f.close()
	var loaded = Store.load_path(Store.slot_path(1))
	check(loaded.ok and not loaded.data.has("tool"), "an old slot file loads unchanged")
	check(Store.save_path(Store.slot_path(1), loaded.data).is_empty() and not FileAccess.get_file_as_string(Store.slot_path(1)).contains("tool"), "re-saving an old map writes no new fields")
	check(Store.save_path(Store.slot_path(2), t1).is_empty() and Store.cell_of(Store.load_path(Store.slot_path(2)).data, "tool") == Store.cell_of(t1, "tool"), "a crate map saves and loads in a slot")
	Recovery.save_draft(t1, 0)
	check(Store.cell_of(Recovery.load_draft(), "bench") == Store.cell_of(t1, "bench"), "draft recovery keeps the crate and the bench")
	Recovery.clear()

	# ---------------- T1: open the crate, get the pull ----------------
	var g = await play(12)
	check(g.pull_charges == 0 and g.tool_cell == Vector2i(3, 1) and g.charge_slots == 2, "T1 starts with no pull, a crate and two meter slots")
	check(g.ability_label.text.contains("工作台") and g.status_label.text.contains("工作台"), "T1 says what the crate is for")
	g.try_move(Vector2i.RIGHT, true)
	check(g.ability_label.text.contains("工具箱推上工作台") and g.history.is_empty(), "pulling with no charge explains where a pull comes from")
	route(g, "R")
	check(g.tool_cell == Vector2i(3, 1) and g.player_pos == Vector2i(2, 1), "walking up to the crate does not move it")
	route(g, "R")
	check(g.tool_cell == NONE and g.pull_charges == 1 and g.event_text.contains("+1") and g.open_fx_text == "+1 牵引", "pushing the crate onto the bench opens it: +1 pull, clear feedback")
	check(g.current_data().get("bench_used", false) and not g.current_data().has("tool"), "the bench now shows the opened crate and nothing blocks it")
	g.undo_move()
	check(g.tool_cell == Vector2i(3, 1) and g.pull_charges == 0 and g.event_text.contains("合上"), "undo closes the crate and puts it back")
	route(g, "RRDDLLr")
	check(g.level_complete and g.moves == 8 and Progress.best_moves(12) == 8, "T1 solved in its optimal 8 moves and recorded")
	check(g.status_label.text.contains("顿悟") and g.next_button.visible, "T1 win shows the insight and the next lab map")
	g.restart_level()
	check(g.tool_cell == Vector2i(3, 1) and g.pull_charges == 0 and not g.level_complete, "restart restores the closed crate and the charges")

	# every pull-panel text stays inside the side panel (it ends at y = 619)
	var worst = 0.0
	var worst_text = ""
	for id in Catalog.LAB_ORDER + [4, 6]:
		g = await play(id)
		var texts = [g._ability_text(), "开箱时牵引已满（2 / 2），绳子浪费了。\nZ 撤销：先用掉一次再开箱。",
			"工具箱打开了：牵引 +1（2 / 2）。", "牵引用完了。工具箱推上工作台可再得 1 次。", "已撤销：工具箱合上，回到原处。",
			"已回到出错前（再走那一步就会无解）。\n" + g._ability_text()]
		for t in texts:
			g.ability_label.text = t
			await process_frame
			var bottom = g.ability_label.position.y + g.ability_label.get_line_count() * g.ability_label.get_line_height()
			if bottom > worst:
				worst = bottom
				worst_text = t.replace("\n", " | ")
	check(worst <= 619.0, "pull-panel texts stay inside the panel (lowest edge %.0f: %s)" % [worst, worst_text])

	# ---------------- crate rules on small maps ----------------
	# pulling the crate spends a pull; pulling it onto the bench opens it and refunds that pull
	var pull_map = rows_to_data(["#######", "#     #", "#  T  #", "#  @  #", "#K$. ##", "#######"], 1)
	g = await preview(pull_map)
	route(g, "d")
	check(g.tool_cell == Vector2i(3, 3) and g.pull_charges == 0 and g.player_pos == Vector2i(3, 4), "pulling the crate spends a pull and moves it like a box")
	var bench_pull = rows_to_data(["#######", "#   T #", "#   K #", "#$.   #", "#     #", "#######"], 1)
	bench_pull.player = [4, 2]
	g = await preview(bench_pull)
	route(g, "d")
	check(g.tool_cell == NONE and g.pull_charges == 1 and g.player_pos == Vector2i(4, 3), "pulling the crate onto the bench opens it and returns the pull")
	# the crate blocks boxes, the player and pulls; it never counts toward the goals
	g = await preview(rows_to_data(["#######", "# @$T.#", "#     #", "#  K  #", "#     #", "#######"], 0))
	route(g, "R")
	check(g.boxes[0] == Vector2i(3, 1) and g.player_pos == Vector2i(2, 1), "a box cannot be pushed into the crate")
	g = await preview(rows_to_data(["#######", "#@T#. #", "# $   #", "#  K  #", "#     #", "#######"], 0))
	route(g, "R")
	check(g.tool_cell == Vector2i(2, 1), "the crate cannot be pushed into a wall")
	g = await preview(rows_to_data(["#######", "#@$.  #", "#     #", "# T K #", "#     #", "#######"], 0))
	route(g, "R")
	check(g.level_complete and g.tool_cell == Vector2i(2, 3), "a map can be won with the crate still closed (it is not a cargo box)")
	# opening at the cap wastes the rope, and says so
	g = await preview(rows_to_data(["#######", "#@TK  #", "#     #", "#$.   #", "#     #", "#######"], 2))
	route(g, "R")
	check(g.tool_cell == NONE and g.pull_charges == 2 and g.open_fx_wasted and g.event_text.contains("已满"), "opening at 2 / 2 keeps 2 and explains the rope was wasted")
	g.undo_move()
	check(g.tool_cell == Vector2i(2, 1) and g.pull_charges == 2, "undo brings the unopened crate back")

	# ---------------- T2: dead checks with the crate, B rewinds ----------------
	g = await play(13)
	check(g.pull_charges == 1 and g.hint_button.visible, "T2 has one pull and hints")
	g.player_pos = Vector2i(2, 3)   # stand above the corner box (reachable)
	route(g, "u")                   # spend the only pull on the cargo box first
	check(g.dead_now and g.dead_rewind_steps == 1 and g.status_label.text.contains("B 回到出错前") and g.status_label.text.contains("这次牵引之后") and g.ability_label.text.contains("工具箱"), "spending the pull on the box first is dead; the message blames that pull, states the stranded crate below, and offers B")
	check(g.hint_button.disabled and g.hint_button.text.contains("B"), "the hint button says to press B first")
	g._unhandled_input(key(KEY_B))
	check(not g.dead_now and g.pull_charges == 1, "B goes back to before the mistake")
	g.restart_level()
	route(g, "DDuRDDLURULDLUDuRDDLURUULLDRURDLDRR")
	check(g.level_complete and g.moves == Catalog.optimal(13), "T2 optimal route works (%d moves)" % g.moves)

	# ---------------- T3: opening while full is the trap ----------------
	g = await play(14)
	check(g.pull_charges == 2 and g.charge_slots == 2 and g.tool_cell == Vector2i(3, 2), "T3 starts full (2 / 2) with the crate under the bench")
	g.player_pos = Vector2i(3, 3)
	route(g, "U")
	check(g.tool_cell == NONE and g.pull_charges == 2 and g.open_fx_wasted and g.dead_now, "opening at 2 / 2 wastes the rope and the exact check calls it dead")
	g._unhandled_input(key(KEY_B))
	check(g.tool_cell == Vector2i(3, 2) and g.pull_charges == 2 and not g.dead_now, "B closes the crate again")
	g.restart_level()
	route(g, "DDLLLrULLDRURuRRDDLLUDRRUULr")
	check(g.level_complete and g.moves == Catalog.optimal(14) and g.pulls == 3, "T3 optimal route: 3 pulls, crate opened at 1 / 2 (%d moves)" % g.moves)

	# ---------------- control map: no new rule ----------------
	var c1 = level(15)
	check(not c1.has("tool") and not Store.uses_lab_features(c1), "C1 uses only the existing rules")
	g = await play(15)
	route(g, "LDRRDRdLURLULLDDRR")
	check(g.level_complete and g.moves == Catalog.optimal(15), "C1 optimal route works")

	# ---------------- custom maps: exact check, or an honest "unknown" ----------------
	var custom_dead = rows_to_data(["#######", "#     #", "# $   #", "# @   #", "#    .#", "#######"], 0)
	g = await preview(custom_dead)
	check(not g.dead_now, "test play starts solvable")
	route(g, "U")        # push the box against the top wall: it can never come down again
	check(g.dead_now and g.status_label.text.contains("Esc") and g.dead_rewind_steps > 0, "test play: dead state found exactly, the message offers B and the editor")
	var huge = {"walls": [[3, 0], [2, 1], [4, 1], [3, 2]], "goals": [[3, 1], [1, 4], [5, 4]], "boxes": [[1, 3], [3, 3], [5, 3]], "player": [0, 5], "pull_charges": 2}
	g = await preview(huge)
	check(g.judge_pending and not g.dead_now and not g.status_label.text.contains("无解"), "a heavy map is judged in slices: nothing is claimed while the search runs")
	g.finish_judgement()
	check(g.dead_unknown and not g.dead_now and not g.status_label.text.contains("无解"), "beyond the solver cap no dead claim is made")
	g = await preview(rows_to_data(["#######", "#$ @  #", "#     #", "#    .#", "#     #", "#######"], 0))
	check(g.dead_now and g.dead_rewind_steps == 0 and g.status_label.text.contains("起点") and g.status_label.text.contains("编辑器"), "a map that starts dead says so and points to the editor")

	# ---------------- level 5: optional hints and an insight ----------------
	g = await play(5)
	check(g.hint_button.visible and Catalog.hints(5).size() == 3 and g.status_label.text.contains("推不动"), "level 5 now has graded hints and an observation prompt")
	g.request_hint()
	check(g.status_label.text.contains("提示 1 / 3"), "first hint shows")
	g.restart_level()
	route(g, "rDLLURURRRDDLLLULD")
	check(g.level_complete and g.status_label.text.contains("顿悟"), "level 5 win names the idea")

	# ---------------- editor: place, check, play, undo ----------------
	state.editor_snapshot = {}
	state.editor_history = {}
	change_scene_to_file("res://level_editor.tscn")
	await frames(3)
	var e = current_scene
	e._apply_data(level(13))
	e.dirty = true
	e._start_check()
	var guard = 0
	while e.check_job != null and guard < 600:
		await process_frame
		guard += 1
	check(e.status_label.text.contains("必须把工具箱推上工作台") and e.check_label.text.contains("有解"), "editor check: T2 needs the crate (shown next to the button)")
	var optional = rows_to_data(["#######", "#@$.  #", "#     #", "# T K #", "#     #", "#######"], 0)
	e._apply_data(optional)
	e._start_check()
	guard = 0
	while e.check_job != null and guard < 600:
		await process_frame
		guard += 1
	check(e.status_label.text.contains("只是可选项"), "editor check: an optional crate is reported as optional")
	e._apply_data(rows_to_data(["#######", "#     #", "#     #", "#     #", "#     #", "#######"], 0))
	e._unhandled_input(key(KEY_6))
	e._paint_cell(Vector2i(2, 2), e.selected_tool)
	e._paint_cell(Vector2i(3, 3), "tool")
	check(e.tool_cell == Vector2i(3, 3) and e._serialize().tool == [3, 3], "key 6 selects the crate; placing it again moves it")
	e._unhandled_input(key(KEY_7))
	e._paint_cell(Vector2i(3, 3), e.selected_tool)
	check(e.bench_cell == Vector2i(3, 3) and e.tool_cell == NONE, "a bench placed on the crate replaces it")
	e._undo()
	check(e.tool_cell == Vector2i(3, 3) and e.bench_cell == NONE, "undo restores the crate")
	e._paint_cell(Vector2i(3, 3), "floor")
	check(e.tool_cell == NONE, "erasing removes the crate")
	e.pull_toggle.button_pressed = true
	e.pull_two.button_pressed = true
	check(e.pull_charges == 2 and e._serialize().pull_charges == 2, "the second switch gives 2 starting pulls")
	e.pull_toggle.button_pressed = false
	check(e.pull_charges == 0 and not e.pull_two.button_pressed, "turning pulls off clears both switches")
	e._apply_data(lone)
	e._preview()
	await frames()
	check(e.error_dialog.visible and e.error_dialog.dialog_text.contains("成对"), "test play of a crate without a bench explains what is missing")
	e.error_dialog.hide()
	e._apply_data(t1)
	e._preview()
	await frames(3)
	check(current_scene != e and current_scene.tool_cell == Vector2i(3, 1), "test play carries the crate into the game")

	print("LAB TOOL TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB TOOL SUITE PASSED")
	quit(1 if failures else 0)
