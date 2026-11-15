extends SceneTree
## V7.10 regressions for the external review of V7.9 (items 1-6 + hint copy).
const Store = preload("res://level_store.gd")
const Progress = preload("res://progress_store.gd")
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
func demo(id: int) -> Dictionary:
	return Store.load_path("res://levels/demo_%d.json" % id).data
func write(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
func move(game, route: String) -> void:
	for c in route:
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c.to_upper()], c == c.to_lower())

func run():
	var state = root.get_node("GameState")

	# ---- 1. editor check: no threads, finishes in frames, cancellable, instant exit
	state.editor_snapshot = {}
	change_scene_to_file("res://level_editor.tscn")
	await process_frame
	await process_frame
	var editor = current_scene
	check(not "check_thread" in editor, "editor no longer uses a Thread (single-threaded Web safe)")
	editor._apply_data({"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0})
	editor._start_check()
	var frames = 0
	while editor.check_job != null and frames < 60:
		await process_frame
		frames += 1
	check(editor.check_job == null and editor.status_label.text.contains("有解"), "one-push map is checked within a few frames (%d)" % frames)
	var open3 = {"walls": [], "goals": [[4, 1], [4, 3], [5, 4]], "boxes": [[2, 1], [2, 3], [3, 4]], "player": [3, 2], "pull_charges": 1}
	editor._apply_data(open3)
	editor._start_check()
	var worst_frame = 0
	for i in 20:
		var t = Time.get_ticks_usec()
		await process_frame
		worst_frame = maxi(worst_frame, Time.get_ticks_usec() - t)
	check(editor.check_job != null and worst_frame < 60000, "long check keeps frames short (worst %.1f ms)" % (worst_frame / 1000.0))
	editor._start_check()  # pressing V again cancels
	check(editor.check_job == null and editor.status_label.text.contains("取消"), "pressing V again cancels the check")
	editor._start_check()
	editor._paint_cell(Vector2i(0, 0), "wall")
	check(editor.check_job == null and editor.status_label.text.contains("已改动"), "editing the map cancels a running check")
	editor._start_check()
	var t_exit = Time.get_ticks_msec()
	editor.dirty = false
	editor._request_back()
	await process_frame
	await process_frame
	check(Time.get_ticks_msec() - t_exit < 500 and current_scene != editor, "leaving the editor mid-check is immediate (%d ms)" % (Time.get_ticks_msec() - t_exit))

	# ---- 2. unfinished draft vs broken file
	var p1 = Store.slot_path(1)
	check(Store.save_path(p1, {"walls": [[0, 0]], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": 0}).is_empty(), "an empty draft saves")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	var menu = current_scene
	menu._show_levels()
	check(menu.slot_buttons[0].text.contains("草稿未完成") and not menu.slot_buttons[0].text.contains("损坏"), "draft slot is labelled as an unfinished draft")
	menu._play_slot(1)
	await process_frame
	check(menu.draft_dialog.visible and not menu.recovery.visible, "playing a draft offers the editor, not recovery")
	menu.draft_dialog.hide()
	menu._open_draft()
	await process_frame
	await process_frame
	check(current_scene.has_method("_start_check") and current_scene.save_slot == 1 and current_scene.walls.has(Vector2i(0, 0)) and not current_scene.dirty, "draft opens in the editor, bound to its slot, unmodified")
	write(p1, "{ broken")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	menu = current_scene
	menu._show_levels()
	check(menu.slot_buttons[0].text.contains("文件损坏"), "unreadable file is labelled as damaged")
	menu._play_slot(1)
	await process_frame
	check(menu.recovery.visible and not menu.draft_dialog.visible, "unreadable file goes to recovery")
	menu.recovery.hide()

	# ---- 3. corrupt copies are never replaced; failure stops recovery
	write(p1, "{ first broken")
	check(Store.set_aside(p1).is_empty(), "first broken file set aside")
	write(p1, "{ second broken")
	check(Store.set_aside(p1).is_empty(), "second broken file set aside")
	check(FileAccess.get_file_as_string(p1 + ".corrupt") == "{ first broken" and FileAccess.get_file_as_string(p1 + ".corrupt.2") == "{ second broken", "both corrupt copies kept under distinct names")
	var good = {"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0}
	Store.save_path(p1, good)
	Store.save_path(p1, good)  # creates .bak
	write(p1, "{ third broken")
	check(Store.restore_backup(p1).is_empty() and Store.load_path(p1).ok and FileAccess.get_file_as_string(p1 + ".corrupt.3") == "{ third broken", "restore keeps the third copy too")
	write(Progress.PATH, "garbage")
	Progress.check_integrity()
	write(Progress.PATH, "more garbage")
	Progress.check_integrity()
	check(FileAccess.get_file_as_string(Progress.PATH + ".corrupt") == "garbage" and FileAccess.get_file_as_string(Progress.PATH + ".corrupt.2") == "more garbage", "progress corrupt copies are not replaced either")
	write(Progress.PATH, "still broken")
	check(Progress.record(1, 3) != OK and FileAccess.get_file_as_string(Progress.PATH) == "still broken", "a win never overwrites an unreadable record file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))

	# ---- 4. every panel text keeps >= 8 px above the buttons below it
	var worst_gap = 999.0
	var worst_case = ""
	for id in Catalog.ORDER + Catalog.LAB_ORDER + Catalog.LAB_EXTRA:   # Lab: the lab maps' texts must fit too
		state.selected_builtin = id
		change_scene_to_file("res://game.tscn")
		await process_frame
		await process_frame
		var g = current_scene
		var texts = [g.status_label.text, "最后一条提示会直接给出关键步骤。\n再按一次 H 查看；继续移动则取消。",
			"这一局已经无解：工具箱上不了台。\nB 回到出错前（撤销 99 步）\nR 重开 · Esc 回编辑器",
			"非目标角落中的箱子已无法移出。\nB 回到出错前（撤销 99 步）\nR 重开本关",
			"关卡完成！共 999 步。\n最佳 999 步 · 最优 99 ★\n" + (Catalog.insight(id) if not Catalog.insight(id).is_empty() else "Z 可撤销复盘，R 再挑战最优。"),
			"最后一关完成！共 999 步。\n木箱归位，灯火仍暖。\n" + Catalog.insight(id)]
		var h = Catalog.hints(id)
		for k in h.size():
			texts.append("提示 %d / 3 · H 查看\n%s" % [k + 1, h[k]])
		for t in texts:
			g.status_label.text = t
			await process_frame
			var gap = g.undo_button.position.y - (g.status_label.position.y + g.status_label.get_line_count() * g.status_label.get_line_height())
			if gap < worst_gap:
				worst_gap = gap
				worst_case = "id %d: %s" % [id, t.replace("\n", " | ")]
	check(worst_gap >= 8.0, "all status texts clear the buttons by >= 8 px (worst %.0f px: %s)" % [worst_gap, worst_case])
	check(Catalog.hints(8)[1].contains("原来站的位置"), "map 8 hint explains where the pulled box ends up")

	# ---- 5. summary shows when the set is completed on a middle map
	for id in Catalog.ORDER:
		if id != 2:
			Progress.record(id, Catalog.optimal(id))
	state.selected_builtin = 2
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	var g2 = current_scene
	move(g2, "RRRLLLDRRR")
	check(g2.level_complete and g2.finale_panel.visible, "completing the set on map 2 (not last) shows the summary")
	check(g2.next_button.visible and not g2.editor_end_button.visible, "Next button keeps its place; editor is offered via E in the panel")
	var ev = InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	g2._input(ev)
	await process_frame
	await process_frame
	check(current_scene.has_method("_start_check"), "E opens the editor from the mid-map summary")
	state.selected_builtin = 2
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	g2 = current_scene
	move(g2, "RRRLLLDRRR")
	check(not g2.finale_panel.visible, "replaying a middle map later does not repeat the summary")

	# ---- 6. share codes: every single-cell change is caught; clean-profile import plays
	var undetected = 0
	var tried = 0
	for id in Catalog.ORDER:
		var code = Store.share_code(demo(id))
		var head = code.find("-") + 1
		var tail = code.rfind("-")
		for i in range(head, tail):
			if code[i] == "/":
				continue
			for ch in Store.SHARE_LETTERS:
				if ch == code[i]:
					continue
				tried += 1
				if Store.parse_share_code(code.substr(0, i) + ch + code.substr(i + 1)).ok:
					undetected += 1
	check(undetected == 0, "all %d single-cell typos over 11 maps are rejected" % tried)
	check(not Store.parse_share_code("KURO1-WWWWWWW/WOOOOOW/WOPBGOW/WOOOOOW/WOOOOOW/WWWWWWW-AB").ok, "old 2-digit V7.9 codes get a clear message")
	var draft_code_body = "KURO0-WWWWWWW/WOOOOOW/WOOBGOW/WOOOOOW/WOOOOOW/WWWWWWW"
	state.editor_snapshot = {}
	change_scene_to_file("res://level_editor.tscn")
	await process_frame
	await process_frame
	editor = current_scene
	editor.dirty = false
	editor._import_share_code(draft_code_body + "-" + Store._checksum(draft_code_body))
	check(editor.status_label.text.contains("未完成的草稿") and editor.status_label.text.contains("玩家"), "importing a draft code says what is missing")
	editor.dirty = false
	editor._import_share_code(Store.share_code(demo(9)))
	editor._preview()
	await process_frame
	await process_frame
	var g9 = current_scene
	move(g9, "UDLLUURlDDRRUULLDLU")
	check(g9.is_preview and g9.level_complete, "a shared map imported on a clean profile can be test-played to the end")
	state.preview_data = {}
	print("V7.10 suite: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("V710 SUITE PASSED")
	quit(1 if failures else 0)
