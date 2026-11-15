extends "res://tests/lab2_tests.gd"
## Lab 3: guides and hints never describe a step that is already done.
## 1. For every lab map, walk every reachable state through the real game (try_move / undo_move) and,
##    wherever a guide is on screen (not dead, not complete), check what the shown text claims
##    against the board. The claims below are written here, independently of the catalog conditions.
## 2. Undo, B and restart bring the matching text back.
## 3. Share-code example text, manual fallback for copy and paste.
## 4. Main line vs lab progress labels.
## 5. Retrying a failed progress save, without touching an unreadable record file.

const DIRS = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]

func _has(boxes: Array, x: int, y: int) -> bool:
	return boxes.has(Vector2i(x, y))

## What each stage's guide and hints assert, as predicates on the board.
func claim(id: int, stage: String, g) -> String:
	var b: Array = g.boxes
	var c: int = g.pull_charges
	var t: Vector2i = g.tool_cell
	var opened = t == NONE and Store.cell_of(g.initial_data, "tool") != NONE
	var ok = true
	match [id, stage]:
		[12, ""]: ok = c == 0 and t == Vector2i(3, 1) and _has(b, 1, 3)
		[12, "open"]: ok = c == 1 and _has(b, 1, 3)
		[13, ""], [16, ""]: ok = c == 1 and t == Vector2i(3, 4) and _has(b, 2, 4)
		[13, "used_a"], [16, "used_a"]: ok = not opened and c == 0 and t == Vector2i(3, 3) and _has(b, 2, 4)
		[13, "used"], [16, "used"]: ok = not opened and c == 0 and t.y < 4 and _has(b, 2, 4)
		[13, "open"], [16, "open"]: ok = opened and c == 1 and _has(b, 2, 4)
		[13, "out"]: ok = opened and c == 0 and _has(b, 2, 3)
		[13, "carry"], [16, "carry"]: ok = opened and c == 0 and not _has(b, 2, 4)
		[16, "out"]: ok = opened and c == 0 and _has(b, 3, 4) and not _has(b, 2, 4)
		[14, ""]: ok = c == 2 and not opened and t == Vector2i(3, 2)
		[14, "used"]: ok = c == 1 and not opened and t == Vector2i(3, 2)
		[14, "open"]: ok = opened and c >= 1 and b[0].y > 1
		[14, "top"]: ok = opened and c >= 1 and _has(b, 3, 1)
		[14, "top_right"]: ok = opened and c >= 1 and _has(b, 5, 1)
		[15, ""]: ok = c == 1 and (b[0].y == 2 or b[1].y == 2)
		[15, "pulled"]: ok = c == 0 and _has(b, 4, 3) and not _has(b, 4, 4) and (b[0].y == 4 or b[1].y == 4)
		[15, "pulled_one"]: ok = c == 0 and _has(b, 4, 3) and _has(b, 4, 4)
		[15, "last"]: ok = c == 0 and _has(b, 5, 3) and ((b[0].y == 4 and b[0].x < 4) or (b[1].y == 4 and b[1].x < 4))
		_: return "no claim written for stage '%s'" % stage
	return "" if ok else "claim of stage '%s' is false here" % stage

func state_key(g) -> String:
	var b = g.boxes.duplicate()
	b.sort()
	return "%s|%s|%s|%d" % [g.player_pos, b, g.tool_cell, g.pull_charges]

func explore(id: int) -> Dictionary:
	var g = await play(id)
	var seen = {state_key(g): true}
	var shown = {}
	var bad = []
	var stack = [0]
	var visits = 0
	var check_here = func():
		if g.dead_now or g.level_complete:
			return
		var stage = g._phase()
		shown[stage] = int(shown.get(stage, 0)) + 1
		var problem = claim(id, stage, g)
		if g.status_label.text != Catalog.guide(id, stage):
			problem = "shown text is not the guide of stage '%s'" % stage
		if not problem.is_empty() and bad.size() < 5:
			bad.append("%s at player %s boxes %s tool %s charges %d" % [problem, g.player_pos, g.boxes, g.tool_cell, g.pull_charges])
	check_here.call()
	while not stack.is_empty():
		var i: int = stack.back()
		if i >= 8 or (i == 0 and (g.dead_now or g.level_complete)):
			stack.pop_back()
			if not stack.is_empty():
				g.undo_move()
			continue
		stack[stack.size() - 1] = i + 1
		if not g.try_move(DIRS[i % 4], i >= 4):
			continue
		var k = state_key(g)
		if seen.has(k):
			g.undo_move()
			continue
		seen[k] = true
		visits += 1
		check_here.call()
		stack.append(0)
	return {"states": seen.size(), "shown": shown, "bad": bad}

func run():
	var state = root.get_node("GameState")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	# =============== 1. every shown guide matches the board ===============
	for id in Catalog.LAB_ORDER + Catalog.LAB_EXTRA:
		var r = await explore(id)
		var listed = [""]
		for st in Catalog.LEVELS[id].get("stages", []):
			listed.append(String(st["id"]))
		var unused = []
		for s in listed:
			if not r.shown.has(s):
				unused.append(s)
		check(r.bad.is_empty(), "%s: over %d reachable states the shown guide never contradicts the board %s" % [Catalog.code(id), r.states, str(r.bad)])
		check(unused.is_empty(), "%s: every stage is reached at least once (%s)" % [Catalog.code(id), str(r.shown)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))

	# =============== 2. undo, B and restart ===============
	var g = await play(13)
	route(g, "DDuRDDLURULDLUDu")
	check(g._phase() == "out" and g.status_label.text.contains("货箱出了墙角") and not g.status_label.text.contains("墙角的货箱"), "T2: after pulling the cargo out the guide no longer asks for it")
	g.request_hint()
	check(g.status_label.text.contains("左边是墙") and not g.status_label.text.contains("拉"), "T2: hint 1 after the pull talks about pushing, not pulling")
	g.undo_move()
	check(g._phase() == "open" and g.hint_level == 0 and g.status_label.text == Catalog.guide(13, "open"), "T2 undo: back in the corner, the corner stage's guide is back (Lab 4: not a hint)")
	g.hint_level = 0
	route(g, "u")
	route(g, "D")   # push the cargo box straight back into the corner: decisive
	check(g.dead_now and g.dead_rewind_steps == 1, "T2: pushing the cargo back into the corner is dead (B = 1)")
	g._unhandled_input(key_event(KEY_B))
	check(not g.dead_now and g._phase() == "out" and g.status_label.text.contains("货箱出了墙角"), "T2 B: the text matches the restored board")
	route(g, "RDDLU")
	check(g._phase() == "carry" and g.status_label.text.contains("在路上") and _has(g.boxes, 2, 2), "T2: once the cargo is on its way the guide says so")
	g.restart_level()
	check(g._phase() == "" and g.status_label.text.contains("每次牵引花在谁身上") and g.hint_level == 0, "T2 restart: start text")
	g = await play(15)
	route(g, "LDRRDRd")
	check(g._phase() == "pulled" and g.status_label.text.contains("下来了") and not g.status_label.text.contains("要去哪一行"), "C1: after the pull the guide no longer asks where the box should go")
	route(g, "LUR")
	check(g._phase() == "last" and g.status_label.text.contains("右边的光圈满了"), "C1: one box home, the guide is about the other")
	g.undo_move()
	check(g._phase() == "pulled", "C1 undo: back to the 'pulled' text")
	g.restart_level()
	check(g._phase() == "" and g.status_label.text.contains("要去哪一行"), "C1 restart: start text")
	g = await play(16)
	route(g, "DDuRDDLURULDLURDDr")
	check(g._phase() == "out" and g.status_label.text.contains("同一行"), "T2b: after the pull right the guide says only pushing is left")
	g._unhandled_input(key_event(KEY_Z))
	check(g._phase() == "open", "T2b undo (Z key): corner text back")
	g = await play(14)
	route(g, "DDLLLrULLDRURuRRDDLLUDRRUU")
	check(g._phase() == "top" and g.status_label.text.contains("光圈就在它右边") and not g.status_label.text.contains("得先上去"), "T3: box in the top row, the guide stops asking it to go up")

	# =============== 3. share codes: both formats named, manual fallback ===============
	state.preview_data = {}
	state.editor_snapshot = {}
	state.editor_history = {}
	change_scene_to_file("res://level_editor.tscn")
	await frames(3)
	var e = current_scene
	check(e.share_edit.placeholder_text.contains("KURO1-") and e.share_edit.placeholder_text.contains("KUROT2-") and e.share_edit.placeholder_text.contains("工具箱"), "share box example names the plain and the toolbox format (%s)" % e.share_edit.placeholder_text)
	var has_clip = DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	e._paste_share_code()
	await frames()
	check(e.share_dialog.visible and e.share_mode == "paste" and e.share_edit.editable and e.share_edit.has_focus(), "paste: the dialog opens with the text box focused and editable")
	check(e.share_note.text.contains("KURO0-") and e.share_note.text.contains("KUROT0-") and e.share_note.text.contains("开局牵引"), "paste: the note lists both formats")
	if not has_clip:
		check(e.share_edit.text.is_empty() and e.share_note.text.contains("没有分享码") and e.share_note.text.contains("直接输入"), "paste without a readable clipboard: says so and offers typing (clipboard feature: %s)" % has_clip)
	var t2code = Store.share_code(level(13))
	e.share_edit.text = t2code   # typed by hand
	e._share_dialog_confirmed()
	await frames()
	if e.discard_dialog.visible:
		e._discard_confirmed()
		e.discard_dialog.hide()   # the real OK button hides it; calling the handler directly does not
		await frames()
	var got = e._serialize()
	check(t2code.begins_with("KUROT1-") and Store.cell_of(got, "tool") == Vector2i(3, 4) and Store.cell_of(got, "bench") == Vector2i(2, 1) and int(got["pull_charges"]) == 1, "a typed KUROT1 code imports the crate, the bench and 1 pull")
	var c1code = Store.share_code(level(7))
	e._paste_share_code()
	await frames()
	e.share_edit.text = c1code
	e._share_dialog_confirmed()
	await frames()
	if e.discard_dialog.visible:
		e._discard_confirmed()
		e.discard_dialog.hide()   # the real OK button hides it; calling the handler directly does not
		await frames()
	check(c1code.begins_with("KURO") and not c1code.begins_with("KUROT") and Store.share_code(e._serialize()) == c1code, "a typed plain KURO code (map 7) still imports unchanged")
	e._paste_share_code()
	await frames()
	e.share_edit.text = "KUROT1-WWW"
	e._share_dialog_confirmed()
	await frames()
	check(e.error_dialog.visible and e.error_dialog.dialog_text.contains("KUROT0-") and e.error_dialog.dialog_text.contains("KURO1-") and e.error_dialog.dialog_autowrap, "a broken code: the error names both formats and wraps")
	check(e.error_dialog.dialog_text.contains("不完整") and not e.error_dialog.dialog_text.contains("不是推箱工坊"), "a cut-off code is called incomplete, not someone else's code")
	check(Store.parse_share_code("hello").error.contains("不是推箱工坊") and Store.parse_share_code(t2code.substr(0, t2code.length() - 3)).error.contains("校验") and Store.parse_share_code(t2code + "-" + t2code).error.contains("不完整"), "parser: foreign text / wrong checksum / two codes pasted together each get their own message")
	e.error_dialog.hide()
	e._copy_share_code()
	await frames()
	if not has_clip:
		check(e.share_dialog.visible and e.share_mode == "copy" and e.share_edit.text == Store.share_code(e._serialize()) and not e.share_edit.editable and e.share_note.text.contains("Ctrl+C"), "copy without a clipboard: the full code is shown, selected, read-only, with Ctrl+C / copy-by-hand advice")
	e.share_dialog.hide()

	# =============== 4. main line vs lab progress ===============
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	Progress.record(12, 8)
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	var art = null
	var eyebrow = ""
	for child in current_scene.get_children():
		if child.has_method("corner_title"): art = child
		if child is Label and String(child.text).contains("灯火"): eyebrow = child.text
	check(eyebrow.contains("主线工单 0 / 11"), "menu: the main line says '主线工单 0 / 11' although a lab request is done (%s)" % eyebrow)
	check(art.corner_title().contains("实验委托 1 / 4"), "menu: the rest corner counts lab requests separately (%s)" % art.corner_title())
	g = await play(12)
	check(g.headline_label.text.contains("实验委托") and g.headline_label.text.contains("不计入主线") and g.order_label.text.begins_with("实验委托 T1"), "lab map: headline and order line say 'lab request, not main line'")
	g = await play(1)
	check(g.order_label.text.begins_with("工单 01") and not g.headline_label.text.contains("实验"), "main map 1 keeps '工单 01'")

	# =============== 5. retry after a failed record write ===============
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(Progress.PATH))   # a folder where the file should be: the write fails
	state.fresh_fixtures.clear()
	g = await play(12)
	route(g, "RRRDDLLr")
	check(g.level_complete and g.progress_save_failed and g.progress_save_error != ERR_FILE_CORRUPT and g.retry_button.visible and not g.retry_button.disabled, "write fails: the retry button appears")
	check(g.status_label.text.contains("未保存") and g.ability_label.text.contains("按 Y 重试") and g.ability_label.text.contains("休息角") and g._fixture_target() == 1.0, "write fails: status says so, the note says how to retry and that the corner will not change; the lamp still lights on the board")
	check(g.next_button.visible, "write fails: Next is still there")
	g._unhandled_input(key_event(KEY_Y))
	check(g.progress_save_failed and g.retry_button.visible, "Y while the cause is still there: still failed, still offered")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	g._unhandled_input(key_event(KEY_Y))
	check(not g.progress_save_failed and not g.retry_button.visible and Progress.best_moves(12) == 8 and state.fresh_fixtures == [12], "Y after fixing it: saved, the button goes, the corner will light")
	check(g.ability_label.text.contains("记录已保存") or g.ability_label.text.contains("小满"), "after a successful retry the panel confirms it")
	await frames()
	check(g.next_button.has_focus(), "after a successful retry Next has the focus again")
	# an unreadable record file is never overwritten, not even by a retry
	var f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_string("not a record\n12=1")
	f.close()
	var before = FileAccess.get_file_as_bytes(Progress.PATH)
	g = await play(14)
	route(g, "DDLLLrULLDRURuRRDDLLUDRRUULr")
	check(g.level_complete and g.progress_save_error == ERR_FILE_CORRUPT and g.retry_button.visible and g.retry_button.disabled and g.status_label.text.contains("另存"), "unreadable file: no write, retry disabled, the text says the menu will set it aside")
	g._unhandled_input(key_event(KEY_Y))
	check(FileAccess.get_file_as_bytes(Progress.PATH) == before, "unreadable file: byte-identical after the win and after Y")
	# the last main map shows the same retry
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(Progress.PATH))
	g = await play(Catalog.ORDER[Catalog.ORDER.size() - 1])
	g.boxes = []
	for q in g.goals:
		g.boxes.append(q)
	g._update_status()
	check(g.level_complete and g.retry_button.visible and g.status_label.text.begins_with("最后一关完成") and g.ability_label.text.contains("按 Y 重试") and g.ability_label.text.contains("最佳步数"), "last main map: same retry text")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	# all failure texts fit above the buttons
	for t in ["关卡完成！共 99 步。\n" + "通关记录未保存，原记录没改动。\n确认存档文件夹可写，再按 Y 重试。", "最后一关完成！共 99 步。\n记录文件读不了，为免覆盖未保存。\n回主菜单会另存坏文件，再通关即可。"]:
		g.status_label.text = t
		await process_frame
		var gap = g.undo_button.position.y - (g.status_label.position.y + g.status_label.get_line_count() * g.status_label.get_line_height())
		check(gap >= 0.0, "failure text fits above the buttons (%.0f px): %s" % [gap, t.replace("\n", " | ")])

	print("LAB3 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB3 SUITE PASSED")
	quit(1 if failures > 0 else 0)

func key_event(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
