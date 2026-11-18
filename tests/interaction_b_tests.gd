extends SceneTree
# Flow pass B: player-facing names for the extra maps, the compact record line, and where the
# map opens. Ids, codes, order and save keys must not move.
const Catalog = preload("res://level_catalog.gd")
const Progress = preload("res://progress_store.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok, note):
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func wipe():
	for f in ["progress.cfg", "progress.cfg.bak", "progress.cfg.tmp"]:
		if FileAccess.file_exists("user://" + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
func seed_progress(ids: Array):
	wipe()
	for id in ids:
		Progress.record(id, Catalog.optimal(id))
func open_menu():
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 3: await process_frame
	return menu
func focus_after_open(menu):
	menu._show_levels()
	await process_frame
	return root.gui_get_focus_owner()
func close(menu):
	menu.queue_free()
	await process_frame
	await process_frame
func run():
	var gs = root.get_node("GameState")
	# --- nothing internal moved
	check(Catalog.ORDER == [1, 2, 3, 4, 5, 8, 6, 7, 9, 10, 11] and Catalog.LAB_ORDER == [12, 13, 14, 15] and Catalog.LAB_EXTRA == [16], "orders unchanged")
	check(Catalog.code(12) == "T1" and Catalog.code(13) == "T2" and Catalog.code(15) == "C1" and Catalog.code(16) == "T2b", "internal codes unchanged")
	for id in [12, 13, 14, 15, 16]:
		check(FileAccess.file_exists("res://levels/demo_%d.json" % id), "level file %d still at its path" % id)
	# --- names
	check(Catalog.display_name(12).begins_with("委托1") and Catalog.display_name(15).begins_with("委托4") and Catalog.display_name(16).begins_with("加班"), "cards: 委托1–4 and 加班")
	check(Catalog.display_name(1).begins_with("01") and Catalog.display_name(11).begins_with("11"), "main cards keep 01–11")
	check(Catalog.level_title(13) == "休息角委托 2 · 绳子在箱里" and Catalog.level_title(16).begins_with("加班单 · "), "level titles name the kind of order")
	for id in [12, 13, 14, 15, 16]:
		for text in [Catalog.display_name(id), Catalog.level_title(id), Catalog.order_text(id), String(Catalog.LEVELS[id].get("guide", ""))]:
			check(not text.contains("实验") and not text.contains("对照") and not text.contains("T1") and not text.contains("T2") and not text.contains("C1"), "no developer term in '%s'" % text.left(18))
	check(Catalog.order_text(1).begins_with("工单 01") and Catalog.order_text(12).begins_with("委托 · 小满") and Catalog.order_text(16).begins_with("加班单 · "), "order lines tell main / request / overtime apart")
	# --- map on a fresh save
	wipe()
	gs.map_return_pending = false
	var menu = await open_menu()
	var tags = []
	for l in menu.selector.find_children("*", "Label", true, false):
		tags.append(l.text)
	check(tags.has("休息角\n委托") and not "\n".join(tags).contains("实验"), "map row is named 休息角委托")
	check(await focus_after_open(menu) == menu.builtin_buttons[0], "fresh save: map opens on 01")
	check(menu.builtin_buttons[0].text.ends_with("未完成 · 最优 3"), "unfinished record line")
	# manual choice in this visit is kept
	menu.lab_buttons[2].grab_focus()
	await process_frame
	menu._hide_levels()
	await process_frame
	check(await focus_after_open(menu) == menu.lab_buttons[2], "reopening in the same visit returns to the card the player chose")
	menu._hide_levels()
	await close(menu)
	# --- mid save: next unfinished main order (play order, not id order)
	seed_progress([1, 2, 3, 4, 5])
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.builtin_buttons[5] and Catalog.ORDER[5] == 8, "5 done: map opens on the 6th order (id 8)")
	check(menu.builtin_buttons[0].text.ends_with("★ 最优 3 步"), "optimal record line")
	Progress.record(8, 20)
	menu._show_levels()
	check(menu.builtin_buttons[5].text.ends_with("最佳 20 · 最优 14"), "above-optimal record line")
	# every card can still be reached and started: free choice intact
	var disabled = 0
	for b in menu.builtin_buttons + menu.lab_buttons:
		if b.disabled: disabled += 1
	check(disabled == 0, "all built-in cards stay selectable")
	menu._hide_levels()
	await close(menu)
	# --- back from a level left unsolved: that level
	seed_progress([1, 2, 3])
	gs.selected_builtin = 7
	gs.map_return_pending = true
	gs.map_return_solved = false
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.builtin_buttons[Catalog.ORDER.find(7)], "left 7 unsolved: map opens on it again")
	check(not gs.map_return_pending, "the return hint is used once")
	menu._hide_levels()
	await close(menu)
	# --- back from a solved level: next unfinished after it in its list
	seed_progress([1, 2, 3, 4])
	gs.selected_builtin = 2
	gs.map_return_pending = true
	gs.map_return_solved = true
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.builtin_buttons[4], "replayed 02 (solved): map moves on to the next unfinished order")
	menu._hide_levels()
	await close(menu)
	# --- back from a solved request: next unfinished request
	seed_progress([1, 12])
	gs.selected_builtin = 12
	gs.map_return_pending = true
	gs.map_return_solved = true
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.lab_buttons[1], "solved request 1: map opens on request 2")
	menu._hide_levels()
	await close(menu)
	# --- overtime map left unsolved
	gs.selected_builtin = 16
	gs.map_return_pending = true
	gs.map_return_solved = false
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.lab_buttons[4], "left the overtime map unsolved: map opens on it")
	menu._hide_levels()
	await close(menu)
	# --- main line done: first unfinished request; everything done: 01
	seed_progress(Catalog.ORDER)
	gs.selected_builtin = 11
	gs.map_return_pending = true
	gs.map_return_solved = true
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.lab_buttons[0], "night finished: map opens on request 1")
	menu._hide_levels()
	await close(menu)
	seed_progress(Catalog.ORDER + [12, 13])
	gs.map_return_pending = false
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.lab_buttons[2], "night + 2 requests done: map opens on request 3")
	menu._hide_levels()
	await close(menu)
	seed_progress(Catalog.ORDER + Catalog.LAB_ORDER + Catalog.LAB_EXTRA)
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.builtin_buttons[0], "everything done: map opens on 01")
	# --- a fully cleared map still fits the window
	await process_frame
	var panel = menu.selector.get_global_rect()
	check(panel.position.x >= 0 and panel.end.x <= 1152 and panel.end.y <= 720, "full save: map panel fits 1152x720 (%s)" % str(panel))
	var widest = 0.0
	for b in menu.builtin_buttons + menu.lab_buttons:
		widest = maxf(widest, b.size.x)
		check(b.get_global_rect().end.x <= panel.end.x, "card '%s' stays inside the panel" % b.text.left(8))
	check(widest <= 170.0, "no card grows past its column (%d px)" % int(widest))
	menu._hide_levels()
	await close(menu)
	# --- back from a custom slot that no longer exists falls back safely
	seed_progress([1])
	gs.selected_builtin = 0
	gs.selected_slot = 2
	gs.map_return_pending = true
	gs.map_return_solved = false
	menu = await open_menu()
	check(await focus_after_open(menu) == menu.builtin_buttons[1], "back from an empty slot: falls back to the next unfinished order")
	await close(menu)
	# --- the game sets the hint when leaving
	gs.preview_data = {}
	gs.selected_builtin = 1
	gs.map_return_pending = false
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for i in 3: await process_frame
	check(game.headline_label.text.contains("今晚的工单"), "main map headline unchanged")
	game.queue_free()
	await process_frame
	gs.selected_builtin = 16
	game = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for i in 3: await process_frame
	check(game.headline_label.text.contains("加班单（主线之外）") and game.title_label.text == "加班单 · 抄近路", "overtime map is headed 加班单, not a request")
	game.leave_game()
	check(gs.map_return_pending and not gs.map_return_solved, "leaving an unsolved level marks it for the map")
	wipe()
	print("INTERACTION B TESTS: %d/%d" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
