extends SceneTree
## Lab 2: dead-state cause (only what the move history proves), sliced judgement that never blocks,
## state-aware guides and hints, the work-order fixtures and the rest corner, editor verdict label.
const Store = preload("res://level_store.gd")
const Catalog = preload("res://level_catalog.gd")
const DeadSolver = preload("res://dead_state_solver.gd")
const Progress = preload("res://progress_store.gd")
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
func key(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
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
func panel(g) -> String:
	return g.status_label.text + "\n" + g.ability_label.text
func lines_fit(label: Label, text: String, limit_y: float) -> float:
	label.text = text
	return limit_y - (label.position.y + label.get_line_count() * label.get_line_height())

const HUGE = {"walls": [[3, 0], [2, 1], [4, 1], [3, 2]], "goals": [[3, 1], [1, 4], [5, 4]], "boxes": [[1, 3], [3, 3], [5, 3]], "player": [0, 5], "pull_charges": 2}

func run():
	var state = root.get_node("GameState")
	# =============== 1. dead-state cause ===============
	# 1a. the reported case: an optional crate stuck in a corner from the start, a cargo push kills
	var reported = rows_to_data(["#######", "#T    #", "#  $  #", "#  @. #", "#    K#", "#######"], 0)
	var g = await preview(reported)
	check(not g.dead_now and not g.judge_pending, "reported map: starts solvable although the optional crate can never open")
	route(g, "U")
	g.finish_judgement()
	check(g.dead_now and g.dead_reason == "push" and g.dead_rewind_steps == 1, "reported map: pushing the cargo box up is the decisive move (reason push, B = 1 step)")
	check(not g.status_label.text.contains("工具箱") and not g.ability_label.text.contains("到不了") and not g.ability_label.text.contains("上不了") and g.status_label.text.contains("这一步推箱之后") and g.status_label.text.contains("B 回到出错前") and g.status_label.text.contains("Esc"), "reported map: the message blames the push, never the crate, and offers B / R / Esc")
	g._unhandled_input(key(KEY_B))
	check(not g.dead_now and g.boxes == [Vector2i(3, 2)], "reported map: B returns to the state before the push")
	# 1b. an optional crate pushed into a corner by the player: still solvable, so nothing is claimed
	var optional = rows_to_data(["#######", "#     #", "# T$  #", "# @ . #", "#    K#", "#######"], 0)
	g = await preview(optional)
	route(g, "U")   # push the crate against the top wall: with no pull it can never come back
	g.finish_judgement()
	check(g.tool_cell == Vector2i(2, 1) and g._crate_cannot_reach_bench(g.player_pos, g.tool_cell, 0), "optional map: the crate is now provably unable to reach the bench")
	check(not g.dead_now and not g.status_label.text.contains("无解"), "optional map: a lost optional crate alone is not a dead state and shows no warning")
	route(g, "RR")  # now the real mistake: the cargo box goes to the right wall
	g.finish_judgement()
	check(g.dead_now and g.dead_reason == "push" and not g.dead_crate_lost and not g.status_label.text.contains("工具箱") and not g.ability_label.text.contains("到不了"), "optional map: the later cargo mistake is a push; the crate lost earlier is not blamed")
	# 1c. the crate is required and the player pushes it where it can never reach the bench
	var required = rows_to_data(["#######", "#  K  #", "#  T  #", "#  @  #", "#$.   #", "#######"], 0)
	g = await preview(required)
	check(not g.dead_now, "required map: starts solvable")
	route(g, "RUL")
	g.finish_judgement()
	check(not g.dead_now, "required map: one push to the left is still fine")
	route(g, "L")
	g.finish_judgement()
	check(g.dead_now and g.dead_reason == "tool_stuck" and g.dead_crate_lost and g.dead_rewind_steps == 1, "required map: pushing the crate against the wall is decisive (reason tool_stuck)")
	check(g.status_label.text.contains("工具箱上不了工作台") and g.ability_label.text.contains("到不了工作台"), "required map: here the crate is named, with the rule under the buttons")
	# 1d. T2: the only pull spent on the cargo box; the crate is a proven casualty, not the headline
	g = await play(13)
	route(g, "LDDu")
	check(g.dead_now and g.dead_reason == "pull" and g.dead_crate_lost and g.dead_rewind_steps == 1, "T2: the pull on the cargo box is decisive (reason pull) and it also strands the crate")
	check(g.status_label.text.contains("这次牵引之后") and g.ability_label.text.contains("工具箱还没打开"), "T2: headline = the pull; the stranded crate is stated as a fact below")
	g.restart_level()
	route(g, "DDuD")
	check(g.dead_now and g.dead_reason == "tool_stuck", "T2: pulling the crate out and pushing it back is tool_stuck")
	g.restart_level()
	route(g, "DDuRDDLURULDLUDuD")
	check(g.dead_now and g.dead_reason == "push" and not g.dead_crate_lost and not panel(g).contains("工具箱还没"), "T2: after the crate is open, a bad cargo push is just a bad push")
	# 1e. T3: moving the crate away from the bench kills the attempt, but it could still be opened
	g = await play(14)
	route(g, "LLD")
	check(g.dead_now and g.dead_reason == "tool_moved" and not g.dead_crate_lost, "T3: crate pushed away = tool_moved (not claimed to be unreachable)")
	check(g.status_label.text.contains("动了工具箱之后") and not panel(g).contains("上不了"), "T3: the text does not say the crate cannot reach the bench")
	# 1f. T3: opening at the cap. The meter still shows 2, so the text must not just say "not enough"
	g.restart_level()
	route(g, "DDLLU")
	check(g.dead_now and g.dead_reason == "waste_short" and g.pull_charges == 2 and g.dead_rewind_steps == 1, "T3: opening while full is decisive, and one more pull would have been enough (proved)")
	check(g.status_label.text.contains("满额开箱没加次数") and g.ability_label.text.contains("还有 2 次") and g.ability_label.text.contains("正缺那一次") and not panel(g).contains("牵引不够用了"), "T3: the text agrees with the meter (2 left, the wasted one is what is missing)")
	check(not panel(g).contains("先用掉"), "T3: the dead-state text does not hand out the solution")
	g._unhandled_input(key(KEY_B))
	check(not g.dead_now and g.tool_cell == Vector2i(3, 2) and g.pull_charges == 2 and g.ability_label.text.contains("已回到出错前"), "T3: B closes the crate again and says so")
	g.restart_level()
	route(g, "DDLLLrr")
	check(g.dead_now and g.dead_reason == "pull" and not g.dead_crate_lost and g.pull_charges == 0, "T3: a second pull in the wrong place = pull, crate still fine")
	g.restart_level()
	route(g, "DDLLLrL")
	check(g.dead_now and g.dead_reason == "push" and g.pull_charges == 1 and not panel(g).contains("不够"), "T3: dead with a pull left never says 'not enough'")
	# 1g. maps that are dead before the first move: no cause, the right place to fix them
	g = await preview(rows_to_data(["#######", "#$ @  #", "#     #", "#    .#", "#     #", "#######"], 0))
	g.finish_judgement()
	check(g.dead_now and g.dead_from_start and g.status_label.text.contains("起点") and g.status_label.text.contains("Esc") and not g.status_label.text.contains("B "), "test play of a map that starts dead: says so, Esc to the editor, no B")
	Store.save_path(Store.slot_path(2), rows_to_data(["#######", "#$ @  #", "#     #", "#    .#", "#     #", "#######"], 0))
	state.preview_data = {}
	state.selected_builtin = 0
	state.selected_slot = 2
	change_scene_to_file("res://game.tscn")
	await frames()
	g = current_scene
	g.finish_judgement()
	check(g.dead_now and g.dead_from_start and g.status_label.text.contains("存档") and g.status_label.text.contains("编辑器") and not g.status_label.text.contains("Esc 回编辑器"), "a custom save that starts dead points to the level editor (Esc goes to the menu here)")
	# a custom save: B, R are offered, Esc-to-editor is not
	Store.save_path(Store.slot_path(2), reported)
	change_scene_to_file("res://game.tscn")
	await frames()
	g = current_scene
	route(g, "U")
	g.finish_judgement()
	check(g.dead_now and g.status_label.text.contains("B 回到出错前") and g.status_label.text.contains("R 重开本关") and not g.status_label.text.contains("Esc"), "custom save: B and R, no editor shortcut that does not exist there")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.slot_path(2)))

	# =============== 2. the judgement never blocks ===============
	var t0 = Time.get_ticks_msec()
	g = await preview(HUGE)
	var enter_ms = Time.get_ticks_msec() - t0
	check(g.judge_pending and not g.dead_now and not g.dead_unknown, "huge map: the scene is up while the search is still running (entered in %d ms)" % enter_ms)
	check(g.judge_job != null and g.judge_job.expanded < g.JUDGE_SYNC_STATES * 3, "huge map: the head start is small (%d states after two frames)" % g.judge_job.expanded)
	check(g.judge_label.text.contains("检查中") and not g.status_label.text.contains("无解"), "huge map: the panel says 'checking', never 'dead'")
	# moving works while it runs and cancels the old search
	var old_job = g.judge_job
	check(g.try_move(Vector2i.RIGHT) and g.player_pos == Vector2i(1, 5), "huge map: the player can move while the search runs")
	check(old_job.result == "canceled" and g.judge_job != null and g.judge_job != old_job and g.judge_pending and g.judge_job.expanded == 0, "huge map: moving cancels the old search and starts one for the new state, with no search work inside the key press")
	old_job = g.judge_job
	g.undo_move()
	check(old_job.result == "canceled" and g.judge_pending, "huge map: undo cancels too")
	old_job = g.judge_job
	g.restart_level()
	check(old_job.result == "canceled" and g.judge_pending, "huge map: restart cancels too")
	# let it run: one bounded slice per frame, then "cannot tell"
	var worst_slice = 0
	var guard = 0
	while g.judge_pending and guard < 4000:
		var f0 = Time.get_ticks_usec()
		g._process(0.0)
		worst_slice = maxi(worst_slice, Time.get_ticks_usec() - f0)
		guard += 1
	check(not g.judge_pending and g.dead_unknown and not g.dead_now and guard > 20 and guard <= 130, "huge map: out of budget the answer is 'unknown' after %d slices (about 0.6 s of search in total)" % guard)
	check(worst_slice < 40000, "huge map: the longest slice took %.1f ms (budget 6 ms, limit 40 ms)" % (worst_slice / 1000.0))
	check(g.judge_label.text.contains("无法判断") and not panel(g).contains("无解"), "huge map: the panel says it cannot tell and makes no dead claim")
	g.try_move(Vector2i.RIGHT)
	check(not g.judge_pending and g.dead_unknown and g.judge_job == null, "huge map: after giving up no new search is started on later moves")
	g.restart_level()
	check(not g.judge_pending and g.dead_unknown, "huge map: nor after a restart")
	# leaving while a search runs
	g = await preview(HUGE)
	check(g.judge_pending, "huge map again: search running")
	g.leave_game()
	await frames(3)
	check(current_scene != null and current_scene.scene_file_path.contains("level_editor"), "leaving during a search goes back to the editor without errors")
	# a normal result that needs more than the head start: finished a few frames later, then shown
	g = await preview(level(11))
	route(g, "RUR")
	g.finish_judgement()
	check(not g.dead_now, "level 11 as a test play: fine before the bad push")
	route(g, "D")
	var was_pending = g.judge_pending
	var before_text = g.status_label.text
	guard = 0
	while g.judge_pending and guard < 2000:
		await process_frame
		guard += 1
	check(was_pending and not before_text.contains("无解"), "sliced result: right after the move nothing is claimed yet")
	check(g.dead_now and g.dead_reason == "push" and g.dead_rewind_steps == 1 and g.status_label.text.contains("B 回到出错前") and g.judge_label.text.is_empty(), "sliced result: %d frames later the panel shows the proven dead state with B" % guard)
	check(g.hint_button.disabled or not g.hint_button.visible, "sliced result: hint gate follows")
	# the same position judged at once gives the same answer (slicing does not change results)
	var g2 = await play(11)
	route(g2, "RURD")
	check(g2.dead_now and g2.dead_reason == "push" and g2.dead_rewind_steps == 1 and not g2.judge_pending and g2.judge_slices == 0, "built-in map: judged inside the move, no slices, same answer")
	# solver: proofs are shared, 'unknown' is never stored as a proof
	var walls = {}
	for p in HUGE.walls: walls[Vector2i(p[0], p[1])] = true
	var goals = {}
	for p in HUGE.goals: goals[Vector2i(p[0], p[1])] = true
	var boxes = []
	for p in HUGE.boxes: boxes.append(Vector2i(p[0], p[1]))
	var solver = DeadSolver.new(walls, goals)
	check(solver.status(Vector2i(0, 5), boxes, 2, 300) == "unknown" and solver.cache.is_empty(), "solver: a capped search proves nothing and stores nothing")
	var j2 = solver.start_job(Vector2i(0, 5), boxes, 2, 1000000)
	check(not j2.step(0, 50) and j2.expanded == 50, "solver: a slice stops after the requested number of states")
	j2.cancel()
	check(j2.result == "canceled" and j2.step(0) and solver.cache.is_empty(), "solver: a cancelled job stays cancelled and proves nothing")
	var d11 = level(11)
	var w11 = {}
	for p in d11.walls: w11[Vector2i(int(p[0]), int(p[1]))] = true
	var g11 = {}
	for p in d11.goals: g11[Vector2i(int(p[0]), int(p[1]))] = true
	var b11 = []
	for p in d11.boxes: b11.append(Vector2i(int(p[0]), int(p[1])))
	var s11 = DeadSolver.new(w11, g11)
	var start11 = Vector2i(int(d11.player[0]), int(d11.player[1]))
	check(s11.status(start11, b11, 1, 20) == "unknown", "solver: level 11 under a tiny cap is unknown")
	var job = s11.start_job(start11, b11, 1, 20000)
	var steps = 0
	while not job.step(0, 10):
		steps += 1
	check(job.result == "solvable" and steps > 3 and s11.status(start11, b11, 1, 20) == "solvable", "solver: with the real cap it is solved over %d slices, and the proof is then reused even under the tiny cap" % steps)

	# =============== 3. guides and hints follow the board ===============
	g = await play(14)
	check(g.status_label.text.contains("已是上限") and g.ability_label.text.contains("牵引已满（2 / 2）") and g.ability_label.text.contains("次数不会增加"), "T3 start: the rule 'opening while full adds nothing' is on screen before any mistake")
	check(not panel(g).contains("先用掉") and not panel(g).contains("往右拉"), "T3 start: no solution in the standing text")
	g.request_hint()
	check(g.status_label.text.contains("提示 1 / 3") and g.status_label.text.contains("已经满了"), "T3 start: hint 1 is about being full")
	route(g, "DDLLLr")
	check(g._phase() == "used" and g.hint_level == 0 and g.status_label.text == Catalog.guide(14, "used") and not g.status_label.text.contains("已经满了"), "T3 after spending a pull: a new stage shows its guide, not a hint (Lab 4)")
	check(not g.ability_label.text.contains("牵引已满"), "T3 after spending a pull: the 'full' note is gone")
	route(g, "U")
	g.request_hint()
	check(g._phase() == "open" and g.tool_cell == NONE and g.pull_charges == 2 and g.status_label.text.contains("光圈在顶上"), "T3 after opening: hint 1 (asked for) is about the cargo box, not about opening")
	g.hint_level = 0
	g._update_status()
	check(g.status_label.text.contains("工具箱开了"), "T3 after opening: the standing guide is updated too")
	g.undo_move()
	check(g._phase() == "used" and g.status_label.text.contains("腾出了一个空位"), "T3 undo: the guide goes back with the board")
	g = await play(13)
	check(g.status_label.text.contains("每次牵引花在谁身上"), "T2 start guide")
	route(g, "DDu")
	check(g._phase() == "used_a" and g.status_label.text.contains("工具箱能推了"), "T2 after pulling the crate: guide updated")
	route(g, "RDDLURULDLU")
	check(g._phase() == "open" and g.status_label.text.contains("还了你 1 次") and g.pull_charges == 1, "T2 after opening: guide updated")
	g.request_hint()
	check(g.status_label.text.contains("墙角的货箱还在等"), "T2 after opening: hint 1 no longer talks about the crate")
	g = await play(12)
	route(g, "RR")
	check(g.status_label.text.contains("到手"), "T1 after opening: the guide says what to do with the new pull")
	# every phase text fits the panel
	var worst = 999.0
	var worst_text = ""
	for id in Catalog.LAB_ORDER + Catalog.LAB_EXTRA:
		g = await play(id)
		var texts = []
		var stage_ids = [""]
		for st in Catalog.LEVELS[id].get("stages", []):
			stage_ids.append(String(st["id"]))
		for ph in stage_ids:
			texts.append(Catalog.guide(id, ph))
			var hs = Catalog.hints(id, ph)
			for i in hs.size():
				texts.append("提示 %d / 3 · H 查看\n%s" % [i + 1, hs[i]])
		for head in g.DEAD_HEADS.values():
			texts.append("%s\nB 回到出错前（撤销 99 步）\nR 重开 · Esc 回编辑器" % head)
		for t in texts:
			g.status_label.text = t
			await process_frame
			var gap = g.undo_button.position.y - (g.status_label.position.y + g.status_label.get_line_count() * g.status_label.get_line_height())
			if gap < worst:
				worst = gap
				worst_text = "id %d: %s" % [id, t.replace("\n", " | ")]
		var low = [g._thanks_text(), "上限 2 次，满额开箱不加次数。\n计量器里还有 2 次，但这一局正缺那一次。", "上限 2 次，满额开箱不加次数。\n工具箱已经用掉，不会再有第二个。", "工具箱要上工作台才会打开；\n从它现在的位置，已经到不了工作台。", "工具箱还没打开，\n而且现在也到不了工作台了。", "牵引已满（2 / 2）。此时开箱：\n工具箱照样消失，次数不会增加。", "开箱时牵引已满（2 / 2）：\n工具箱打开了，次数没有增加。Z 可撤销。"]
		for t in low:
			g.ability_label.text = t
			await process_frame
			var gap2 = 619.0 - (g.ability_label.position.y + g.ability_label.get_line_count() * g.ability_label.get_line_height())
			if gap2 < worst:
				worst = gap2
				worst_text = "id %d (lower): %s" % [id, t.replace("\n", " | ")]
		check(g.order_label.get_minimum_size().x <= 640.0 or g.order_label.get_theme_font("font").get_string_size(g.order_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x <= 640.0, "%s: the request fits one line above the board" % Catalog.code(id))
	check(worst >= 0.0, "every lab text fits its place (tightest %.0f px: %s)" % [worst, worst_text])

	# =============== 4. the work order, its fixture and the rest corner ===============
	check(Catalog.corner_ids() == [12, 13, 14, 15], "four lab orders carry a fixture")
	for id in Catalog.LAB_ORDER:
		var fx = Catalog.fixture(id)
		var d = level(id)
		var cell = [int(fx.cell[0]), int(fx.cell[1])]
		var is_wall = false
		for w in d.walls:
			if int(w[0]) == cell[0] and int(w[1]) == cell[1]: is_wall = true
		var near_goal = false
		for q in d.goals:
			if absi(int(q[0]) - cell[0]) + absi(int(q[1]) - cell[1]) == 1: near_goal = true
		check(is_wall and near_goal and not Catalog.ask(id).is_empty() and not Catalog.thanks(id).is_empty(), "%s: the fixture sits in a wall cell next to a goal, with a request and a thank-you" % Catalog.code(id))
	g = await play(12)
	check(g.fixture_kind == "lamp" and g.fixture_cell == Vector2i(2, 2) and g._fixture_target() == 0.0 and not g.fixture_done_before, "T1 first visit: the lamp is there and dark")
	check(g.order_label.text.contains("小满") and g.order_label.text.contains("灯油") and g.order_label.text.contains("门灯"), "T1: the order says who asks, what for, and names the thing that will change")
	route(g, "RRRDDLL")
	check(g._fixture_target() == 0.0, "T1: still dark one move before the end")
	route(g, "r")
	check(g.level_complete and g._fixture_target() == 1.0 and state.fresh_fixture == 12, "T1: the last pull lights the lamp")
	check(g.ability_label.text.contains("小满") and g.ability_label.text.contains("休息角") and g.ability_label.text.contains("门灯"), "T1: the thank-you is beside the board and names the lasting change")
	check(g.next_button.visible and g.next_button.has_focus() and not g.finale_panel.visible, "T1: Next is focused at once; nothing covers the board")
	for i in 40:
		g._process(0.05)
	check(is_equal_approx(g.fixture_level, 1.0), "T1: the drawn light reaches full brightness")
	g.undo_move()
	check(not g.level_complete and g._fixture_target() < 0.5 and g._fixture_target() > 0.0, "T1 undo: the lamp drops to the kept low level (the record stays)")
	check(Progress.best_moves(12) == 8, "T1 undo: the record is kept")
	g.restart_level()
	check(g._fixture_target() < 0.5 and g._fixture_target() > 0.0, "T1 restart: same")
	g = await play(12)
	check(g.fixture_done_before and g._fixture_target() < 0.5 and g._fixture_target() > 0.0 and is_equal_approx(g.fixture_level, g._fixture_target()), "T1 replay: starts at the kept low level, not dark")
	route(g, "RRRDDLLr")
	check(g._fixture_target() == 1.0, "T1 replay: full again when done")
	# the rest corner on the menu reads the same records
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	var art = null
	for child in current_scene.get_children():
		if child.has_method("refresh_corner"): art = child
	check(art != null and art.corner.size() == 4 and art.corner_done() == 1 and art.corner[0].done and not art.corner[1].done, "menu: the rest corner shows T1's lamp lit and the other three dark")
	check(art.fresh_ids == [12] and state.fresh_fixture == 0 and state.fresh_fixtures.is_empty(), "menu: the new item pulses once and the flag is consumed")
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	for child in current_scene.get_children():
		if child.has_method("refresh_corner"): art = child
	check(art.fresh_ids.is_empty() and art.corner_done() == 1, "menu again: still lit, no second pulse")
	# the other three
	for pair in [[13, "DDuRDDLURULDLUDuRDDLURUULLDRURDLDRR", "stove", "老周"], [14, "DDLLLrULLDRURuRRDDLLUDRRUULr", "kettle", "阿婆"], [15, "LDRRDRdLURLULLDDRR", "cat", "小满"]]:
		g = await play(pair[0])
		check(g.fixture_kind == pair[2] and g.order_label.text.contains(pair[3]) and g._fixture_target() == 0.0, "%s: fixture %s, request from %s, dark at first" % [Catalog.code(pair[0]), pair[2], pair[3]])
		route(g, pair[1])
		check(g.level_complete and g._fixture_target() == 1.0 and g.ability_label.text.contains(pair[3]), "%s: done -> fixture on, thanks shown" % Catalog.code(pair[0]))
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	for child in current_scene.get_children():
		if child.has_method("refresh_corner"): art = child
	check(art.corner_done() == 4 and art.fresh_ids == [13, 14, 15], "menu: all four fixtures are on, and the three finished since the last visit all pulse")
	# T2b: the shorter candidate sits beside T2, outside the chain, without a fixture
	check(Catalog.is_lab(16) and Catalog.next_id(16) == 0 and Catalog.next_id(15) == 0 and Catalog.next_id(13) == 14 and Catalog.fixture(16).is_empty() and Catalog.corner_ids() == [12, 13, 14, 15], "T2b is a lab map outside the T1 -> C1 chain; the rest corner still has four items")
	g = await play(16)
	check(g.pull_charges == 1 and g.tool_cell == Vector2i(3, 4) and g.fixture_kind.is_empty() and g.title_label.text.contains("加班单") and not g.title_label.text.contains("T2b") and Catalog.code(16) == "T2b", "T2b loads with one pull and a crate, no fixture")
	route(g, "LDDu")
	check(g.dead_now and g.dead_reason == "pull" and g.dead_crate_lost, "T2b keeps T2's trap: the pull on the cargo box first is decisive")
	g.restart_level()
	route(g, "DDuRDDLURULDLURDDrULLDRR")
	check(g.level_complete and g.moves == 24 and g.next_button.text.contains("返回主菜单") and g._thanks_text().is_empty(), "T2b: solved in its 24-move optimum; the button leads back to the menu")
	# a level without a fixture is untouched; a failed save lights the board but promises nothing
	g = await play(1)
	check(g.fixture_kind.is_empty() and g._fixture_target() == 0.0 and g._thanks_text().is_empty(), "level 1 has no fixture and no thank-you line")
	# the 11-map ending is not triggered by a lab order
	for id in Catalog.ORDER:
		Progress.record(id, Catalog.optimal(id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	for id in Catalog.ORDER:
		Progress.record(id, Catalog.optimal(id))
	g = await play(12)
	route(g, "RRRDDLLr")
	check(g.level_complete and not g.finale_panel.visible and not g.finished_set_now, "finishing a lab order for the first time does not show the 11-map ending")
	state.fresh_fixture = 0
	state.fresh_fixtures.clear()
	var f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	g = await play(13)
	route(g, "DDuRDDLURULDLUDuRDDLURUULLDRURDLDRR")
	check(g.level_complete and g.progress_save_failed and g._fixture_target() == 1.0 and (g.status_label.text.contains("未保存") or g.status_label.text.contains("读不了")) and g.retry_button.visible and state.fresh_fixture == 0 and state.fresh_fixtures.is_empty(), "failed save: the stove lights on the board, the text says the corner will not change")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))

	# =============== 5. editor: one sentence, one short verdict ===============
	state.preview_data = {}
	state.editor_snapshot = {}
	state.editor_history = {}
	change_scene_to_file("res://level_editor.tscn")
	await frames(3)
	var e = current_scene
	e._apply_data(level(13))
	e._refresh_status()
	check(e.check_label.text.contains("尚未检查") and not e.dirty_label.text.contains("已验证"), "editor: an unchecked map says so next to the button")
	e._start_check()
	check(e.check_label.text.contains("检查中"), "editor: 'checking' while it runs")
	guard = 0
	while e.check_job != null and guard < 600:
		await process_frame
		guard += 1
	check(e.status_label.text.contains("必须把工具箱推上工作台") and e.check_label.text == "✓ 有解 · 必须开箱", "editor: the sentence appears once (message card); next to the button only '%s'" % e.check_label.text)
	check(e.check_label.text != e.status_label.text and not e.dirty_label.text.contains("有解") and not e.dirty_label.text.contains("已验证"), "editor: no third copy in the status line")
	e._paint_cell(Vector2i(4, 4), "wall")
	check(e.check_label.text.contains("尚未检查"), "editor: any edit replaces the verdict with 'not checked yet'")
	e._undo()
	check(e.check_label.text == "✓ 有解 · 必须开箱" or e.check_label.text.contains("已验证可解"), "editor: undoing the edit brings the verified state back (%s)" % e.check_label.text)
	e._apply_data(rows_to_data(["#######", "#$ @  #", "#     #", "#    .#", "#     #", "#######"], 0))
	e._start_check()
	guard = 0
	while e.check_job != null and guard < 600:
		await process_frame
		guard += 1
	check(e.check_label.text == "✗ 无解" and e.status_label.text.contains("无解"), "editor: an unsolvable map gets the short red verdict")
	# test play of a heavy map from the editor: the editor hands over at once
	e._apply_data(HUGE)
	t0 = Time.get_ticks_msec()
	e._preview()
	await frames(2)
	g = current_scene
	check(g != null and g.is_preview and g.judge_pending and not g.dead_now, "editor test play of the huge map: the game scene is up with the search still running (%d ms)" % (Time.get_ticks_msec() - t0))
	g.leave_game()
	await frames(3)

	# =============== 6. hand-drawn text uses the bundled font (Web has no system CJK fallback) ===============
	var BoardView = load("res://board_view.gd")
	check(BoardView.ui_font() == ThemeDB.get_project_theme().default_font and BoardView.ui_font() is FontVariation, "hand-drawn text uses the project font (Simplified Chinese face)")
	var offenders = []
	for file in ["game.gd", "menu_art.gd", "fixture_art.gd", "level_editor.gd", "main_menu.gd"]:
		if FileAccess.get_file_as_string("res://" + file).contains("ThemeDB.fallback_font"):
			offenders.append(file)
	check(offenders.is_empty(), "no scene draws text with the engine fallback font (%s)" % str(offenders))

	print("LAB2 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB2 SUITE PASSED")
	quit(1 if failures > 0 else 0)
