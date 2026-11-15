extends "res://tests/lab3_tests.gd"
## Lab 4:
## 1. Protected record writes: first save, overwrite, every injected failure, interrupted writes and
##    recovery on the next start, damaged files, retry; what the panel says in each case.
## 2. Dialogs fit their text (error and share dialogs), keep focus on a button or the text box.
## 3. Hints belong to a stage: a new stage shows its guide, hints open only on request, the
##    step-revealing hint asks once per stage, undo / B / restart never open or consume a level.
## Every test here uses the suite's own throw-away user:// folder.

const Prog = preload("res://progress_store.gd")

func wipe() -> void:
	Prog.fault = ""
	for p in [Prog.PATH, Prog.NEW, Prog.NEW_OK, Prog.BAK]:
		if FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("progress.cfg.corrupt"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))

func put(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func text_of(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"

func pending() -> bool:
	return FileAccess.file_exists(Prog.NEW) or FileAccess.file_exists(Prog.NEW_OK)

func run():
	var state = root.get_node("GameState")
	# =============== 1. protected writes ===============
	wipe()
	var a = Prog.encode({12: 8})
	var ab = Prog.encode({12: 8, 13: 35})
	check(Prog.record(12, 8) == OK and text_of(Prog.PATH) == a and not pending() and not FileAccess.file_exists(Prog.BAK) and Prog.last_report.old == "none", "first save: the file holds exactly the record, no temporary files, no backup yet")
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == ab and text_of(Prog.BAK) == a and not pending(), "overwrite: new content in place, the previous file kept as .bak")
	check(Prog.record(12, 9) == OK and text_of(Prog.PATH) == ab, "a worse result changes nothing")
	check(Prog.record(12, 7) == OK and Prog.best_moves(12) == 7 and Prog.best_moves(13) == 35, "a better result replaces only its own line")
	var base = text_of(Prog.PATH)
	for f in ["write_new", "partial_new", "verify_new", "mark", "backup", "replace"]:
		put(Prog.PATH, base)
		Prog.fault = f
		var err = Prog.record(14, 28)
		Prog.fault = ""
		var expected_stage = "verify_new" if f == "partial_new" else f
		check(err != OK and Prog.last_report.stage == expected_stage and Prog.last_report.old == "unchanged" and text_of(Prog.PATH) == base and not pending(), "fault '%s': fails at '%s', the old file is byte-identical (measured: %s), no temporary files left" % [f, Prog.last_report.stage, Prog.last_report.old])
	put(Prog.PATH, base)
	Prog.fault = "verify_final"
	check(Prog.record(14, 28) != OK and Prog.last_report.stage == "verify_final" and Prog.last_report.old == "unknown" and text_of(Prog.BAK) == base, "fault after the replace: reported as 'cannot confirm', the old content is in .bak")
	Prog.fault = ""
	# Windows-like half replace: the old file is deleted, the move does not happen
	wipe()
	put(Prog.PATH, ab)
	Prog.fault = "replace_removed"
	check(Prog.record(14, 28) != OK and Prog.last_report.old == "backup" and not FileAccess.file_exists(Prog.PATH) and text_of(Prog.BAK) == ab and pending(), "half replace: no record file, old content in .bak, verified .new kept, reported as 'in the backup'")
	Prog.fault = ""
	check(Prog.record(14, 28) == OK and Prog.best_moves(12) == 8 and Prog.best_moves(13) == 35 and Prog.best_moves(14) == 28 and not pending(), "retry after a half replace: the old records come back together with the new one")
	# killed after .new was verified, before the replace
	wipe()
	put(Prog.PATH, ab)
	Prog.fault = "crash_after_mark"
	Prog.record(14, 28)
	Prog.fault = ""
	check(text_of(Prog.PATH) == ab and pending(), "killed before the replace: the old file is untouched, .new and .new.ok remain")
	var note = Prog.recover()
	check(Prog.best_moves(14) == 28 and Prog.best_moves(13) == 35 and not pending() and note.contains("打断"), "next start: the interrupted write is completed (%s)" % note)
	# killed between the Windows delete and move
	wipe()
	put(Prog.PATH, ab)
	Prog.fault = "crash_after_remove"
	Prog.record(14, 28)
	Prog.fault = ""
	check(not FileAccess.file_exists(Prog.PATH) and text_of(Prog.BAK) == ab and pending(), "killed between delete and move: no record file at all")
	change_scene_to_file("res://main_menu.tscn")   # what the next start does
	await frames(4)
	check(Prog.best_moves(12) == 8 and Prog.best_moves(13) == 35 and Prog.best_moves(14) == 28 and not pending() and current_scene.notice.visible and current_scene.notice.dialog_text.contains("打断"), "next start through the menu: all records back, the player is told")
	current_scene.notice.hide()
	# a half-written .new (killed while writing it) is never trusted
	wipe()
	put(Prog.PATH, ab)
	put(Prog.NEW, "[builtin]\n\n12=8\n13=3")   # cut inside "35"
	check(Prog.recover() == "" and text_of(Prog.PATH) == ab and not pending(), "an unverified .new is dropped; the real file wins")
	wipe()
	put(Prog.BAK, ab)
	put(Prog.NEW, "[builtin]\n\n12=8\n13=3")
	put(Prog.NEW_OK, "0123")
	var back = Prog.recover()
	check(text_of(Prog.PATH) == ab and back.contains("备份") and not pending(), "file missing, .new unverified: the backup comes back and the text says the last result may be missing")
	# a record file deleted on purpose is not resurrected
	wipe()
	put(Prog.BAK, ab)
	check(Prog.recover() == "" and not FileAccess.file_exists(Prog.PATH), "no record file and no sign of an interrupted write: the backup is left alone")
	# damaged record file: never overwritten; at the next start it is set aside and the backup restored
	wipe()
	put(Prog.BAK, ab)
	put(Prog.PATH, "not a record\n12=1")
	var bad_bytes = FileAccess.get_file_as_bytes(Prog.PATH)
	check(Prog.record(14, 28) == ERR_FILE_CORRUPT and FileAccess.get_file_as_bytes(Prog.PATH) == bad_bytes and not pending() and Prog.last_report.old == "corrupt", "damaged file: no write, byte-identical, nothing temporary")
	change_scene_to_file("res://main_menu.tscn")
	await frames(4)
	var msg = current_scene.notice.dialog_text
	check(FileAccess.file_exists(Prog.PATH + ".corrupt") and FileAccess.get_file_as_bytes(Prog.PATH + ".corrupt") == bad_bytes and text_of(Prog.PATH) == ab and msg.contains("另存为") and msg.contains("备份") and not msg.contains("从头开始"), "next start: the damaged file is kept as .corrupt and the backup restored (%s)" % msg.replace("\n", " | "))
	current_scene.notice.hide()
	# the panel after a failed win, for each measured outcome
	var cases = [["replace", "原有记录已核对，内容没有变", true], ["replace_removed", "原有记录在备份里", true], ["verify_final", "无法确认原有记录", true]]
	for c in cases:
		wipe()
		put(Prog.PATH, Prog.encode({1: 3}))
		state.fresh_fixtures.clear()
		state.fresh_fixture = 0
		var g = await play(12)
		Prog.fault = c[0]
		route(g, "RRRDDLLr")
		Prog.fault = ""
		check(g.level_complete and g.progress_save_failed and g.status_label.text.contains("这次成绩未保存") and g.status_label.text.contains(c[1]), "%s: the panel says the result is not saved and '%s'" % [c[0], c[1]])
		check(g.ability_label.text.contains("休息角这次不会点亮") and g.ability_label.text.contains("按 Y 重试") and g.retry_button.visible and not g.retry_button.disabled and state.fresh_fixtures.is_empty(), "%s: under the retry button: the corner will not light, Y retries" % c[0])
		var rb = Rect2(g.retry_button.position, g.retry_button.size)
		var lab = Rect2(g.ability_label.position, Vector2(g.ability_label.size.x, g.ability_label.get_line_count() * g.ability_label.get_line_height()))
		check(not rb.intersects(lab) and lab.end.y <= 619.0 and g.ability_label.get_line_count() == 1 and g.ability_label.get_visible_line_count() == 1, "%s: the note is below the button, one line, inside the panel (ends at %.0f)" % [c[0], lab.end.y])
		var gap = g.undo_button.position.y - (g.status_label.position.y + g.status_label.get_line_count() * g.status_label.get_line_height())
		check(gap >= 0.0 and g.status_label.get_line_count() == 3, "%s: the status is three lines and fits above the buttons (%.0f px)" % [c[0], gap])
		g._unhandled_input(key_event(KEY_Y))
		check(not g.progress_save_failed and Prog.best_moves(12) == 8 and Prog.best_moves(1) == 3 and not g.retry_button.visible and state.fresh_fixtures == [12] and g.ability_label.position.y == 538.0, "%s: Y saves, earlier records are intact, the corner will light, the note goes back to its place" % c[0])
	# a main map: the note names the best moves, not the corner
	wipe()
	var gm = await play(1)
	Prog.fault = "write_new"
	gm.boxes = []
	for q in gm.goals:
		gm.boxes.append(q)
	gm._update_status()
	Prog.fault = ""
	check(gm.status_label.text.contains("这一关之前没有记录") and gm.ability_label.text.contains("最佳步数这次不更新"), "main map, first save fails: 'no earlier record' and the best moves will not change")
	wipe()

	# =============== 2. dialogs fit their text ===============
	state.preview_data = {}
	state.editor_snapshot = {}
	state.editor_history = {}
	change_scene_to_file("res://level_editor.tscn")
	await frames(3)
	var e = current_scene
	var view = e.get_viewport().get_visible_rect()
	var messages = []
	for code in ["KUROT1-WWW", "hello", "KURO1-WWWWWWW/WOOOOOW-ABCDEF", "KURO9-A-B", "KURO1-WWWWWWW/WOOOOOW/WOPBGOW/WOOOOOW/WOOOOOW/WWWWWWW-AB", "KUROT1-WWW-WWW-WWW"]:
		messages.append("无法导入：" + Store.parse_share_code(code).error + "\n" + e.SHARE_FORMATS)
	messages.append("分享前请先让关卡可以试玩：\n地图上必须有玩家起点。")
	messages.append("短")
	messages.append("这是一段特意写得很长的说明文字，用来检查弹窗会不会按实际排出的行数加高。".repeat(4))
	for m in messages:
		e._show_error(m)
		await frames(20)
		var d = e.error_dialog
		var lab = d.get_label()
		var rect = Rect2(d.position, d.size)
		check(d.visible and lab.get_visible_line_count() == lab.get_line_count() and view.encloses(rect) and not e.dialog_fit_clipped, "error dialog shows all %d lines and stays in the window (%s): %s" % [lab.get_line_count(), str(rect), m.left(24).replace("\n", " ")])
		check(d.get_ok_button().has_focus() and d.get_ok_button().is_visible_in_tree(), "error dialog: the OK button is visible and focused, Enter closes it")
		d.hide()
		await frames()
	# forced: a narrow dialog must grow
	e.error_dialog.dialog_text = messages[0]
	e.error_dialog.popup_centered(Vector2i(380, 120))
	e._fit_to_text(e.error_dialog, e.error_dialog.get_label())
	await frames(20)
	check(e.error_dialog.get_label().get_visible_line_count() == e.error_dialog.get_label().get_line_count() and e.error_dialog.size.y > 120, "a dialog opened too small grows to %d px and then shows every line" % e.error_dialog.size.y)
	e.error_dialog.hide()
	# far too much text: it stops at the window edge and says so (never larger than the window)
	e._show_error("很长的一行字。".repeat(220))
	await frames(24)
	var lab3 = e.error_dialog.get_label()
	check(e.dialog_text_shortened and view.encloses(Rect2(e.error_dialog.position, e.error_dialog.size)) and lab3.get_visible_line_count() == lab3.get_line_count() and e.error_dialog.dialog_text.ends_with("…"), "an absurd text is cut with '…' and the dialog stays inside the window")
	e.error_dialog.hide()
	await frames()
	# share dialog in both modes
	for mode in ["paste", "copy"]:
		if mode == "paste":
			e._paste_share_code()
		else:
			e._apply_data(level(13))
			e._copy_share_code()
		await frames(20)
		var sd = e.share_dialog
		check(sd.visible and e.share_note.get_visible_line_count() == e.share_note.get_line_count() and view.encloses(Rect2(sd.position, sd.size)), "share dialog (%s): every note line visible, inside the window" % mode)
		var edit_rect = Rect2(e.share_edit.global_position, e.share_edit.size)
		var ok_rect = Rect2(sd.get_ok_button().global_position, sd.get_ok_button().size)
		check(e.share_edit.has_focus() and not edit_rect.intersects(ok_rect) and edit_rect.end.y <= ok_rect.position.y, "share dialog (%s): the text box has focus and sits above the buttons" % mode)
		sd.hide()
		await frames()
	# different window sizes: the layout is in logical pixels (stretch mode canvas_items)
	var sizes = []
	for sz in [Vector2i(960, 600), Vector2i(1152, 720), Vector2i(1600, 1000)]:
		root.size = sz
		await frames(3)
		e._show_error(messages[0])
		await frames(20)
		var lab2 = e.error_dialog.get_label()
		sizes.append("%s -> view %s, lines %d/%d" % [sz, e.get_viewport().get_visible_rect().size, lab2.get_visible_line_count(), lab2.get_line_count()])
		check(lab2.get_visible_line_count() == lab2.get_line_count(), "window %s: the error dialog still shows every line" % str(sz))
		e.error_dialog.hide()
		await frames()
	print("window sizes: ", sizes)
	root.size = Vector2i(1152, 720)
	await frames(3)

	# =============== 3. hints belong to a stage ===============
	# 3a. scripted walk for each staged map: what must be on screen at each point
	var walks = {
		13: ["DDuRDDLURULDLUDuRDDLURUULLDRURDLDRR", "LDDu"],
		16: ["DDuRDDLURULDLURDDrULLDRR", "LDDu"],
		14: ["DDLLLrULLDRURuRRDDLLUDRRUULr", "DDLLU"],
		15: ["LDRRDRdLURLULLDDRR", "LDRRDRdLUURRDL"],
	}
	for id in walks:
		var g = await play(id)
		check(g.hint_level == 0 and g.status_label.text == Catalog.guide(id, ""), "%s start: the start guide" % Catalog.code(id))
		g.request_hint()
		g.request_hint()
		check(g.hint_level == 2 and g.status_label.text == "提示 2 / 3 · H 查看\n" + Catalog.hints(id, "")[1], "%s start: H, H -> hint 2 of the start stage" % Catalog.code(id))
		g.request_hint()
		check(g.hint_level == 2 and g.hint_final_armed and g.status_label.text.contains("关键步骤"), "%s: the third H only warns" % Catalog.code(id))
		g.request_hint()
		check(g.hint_level == 3 and g.status_label.text.ends_with(Catalog.hints(id, "")[2]) and g.hint_seen[""] == 3, "%s: the fourth H shows hint 3" % Catalog.code(id))
		var r: String = walks[id][0]
		var stages_seen = [""]
		for i in r.length() - 1:
			var before_stage = g._phase()
			var before_level = g.hint_level
			route(g, r[i])
			var now = g._phase()
			if now != before_stage:
				stages_seen.append(now)
				check(g.hint_level == 0 and g.status_label.text == Catalog.guide(id, now), "%s step %d: entering stage '%s' shows its guide, not hint %d" % [Catalog.code(id), i + 1, now, before_level])
				if not g.hint_seen.has(now):
					g.request_hint()
					check(g.hint_level == 1 and g.status_label.text.ends_with(Catalog.hints(id, now)[0]), "%s stage '%s': one H opens hint 1 of this stage only" % [Catalog.code(id), now])
					g.request_hint()
					g.request_hint()
					check(g.hint_level == 2 and g.hint_final_armed, "%s stage '%s': hint 3 asks again in a new stage" % [Catalog.code(id), now])
					g.hint_level = 0   # leave it closed for the rest of the walk (a move also closes the warning)
					g.hint_final_armed = false
					g._update_status()
			elif before_level > 0:
				check(g.hint_level == before_level, "%s step %d: a move inside the stage keeps the open hint" % [Catalog.code(id), i + 1])
		check(stages_seen.size() >= 2, "%s: the walk passed through %s" % [Catalog.code(id), str(stages_seen)])
		# undo back into the start stage, where hint 3 was opened earlier
		g.restart_level()
		check(g._phase() == "" and g.hint_level == 0 and g.status_label.text == Catalog.guide(id, ""), "%s restart from a later stage: the start guide, no hint open" % Catalog.code(id))
		g.request_hint()
		g.request_hint()
		g.request_hint()
		check(g.hint_level == 3 and not g.hint_final_armed and g.hint_seen[""] == 3, "%s: a hint already opened in this stage is re-shown without asking again (H x3 -> hint 3)" % Catalog.code(id))
		# a mistake and B
		var mistake: String = walks[id][1]
		g.restart_level()
		g.hint_level = 0
		g._update_status()
		route(g, mistake.left(mistake.length() - 1))
		var stage_before = g._phase()
		g.request_hint()
		var level_before = g.hint_level
		route(g, mistake.right(1))
		check(g.dead_now and g.hint_button.disabled, "%s: the decisive mistake is dead and the hint button is off" % Catalog.code(id))
		g.request_hint()
		check(g.hint_level <= level_before, "%s: H while dead opens nothing" % Catalog.code(id))
		g._unhandled_input(key_event(KEY_B))
		var stage_after = g._phase()
		var expect_text = Catalog.guide(id, stage_after) if g.hint_level == 0 else "提示 %d / 3 · H 查看\n%s" % [g.hint_level, Catalog.hints(id, stage_after)[g.hint_level - 1]]
		check(not g.dead_now and stage_after == stage_before and g.hint_level <= level_before and g.status_label.text == expect_text, "%s B: back in stage '%s', hint level %d (was %d), text matches the stage" % [Catalog.code(id), stage_after, g.hint_level, level_before])
		g.undo_move()
		g.undo_move()
		var s2 = g._phase()
		var t2 = Catalog.guide(id, s2) if g.hint_level == 0 else "提示 %d / 3 · H 查看\n%s" % [g.hint_level, Catalog.hints(id, s2)[g.hint_level - 1]]
		check(g.status_label.text == t2, "%s undo twice: the text matches stage '%s' at hint level %d" % [Catalog.code(id), s2, g.hint_level])
	# 3b. random play: after every action the panel matches the board and no level appears unasked
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261115
	for id in walks:
		var g = await play(id)
		var problems = []
		var seen_before = {}
		for step in 600:
			var lvl_before = g.hint_level
			seen_before = g.hint_seen.duplicate()
			var roll = rng.randi_range(0, 99)
			var action = ""
			if roll < 55:
				action = "move"
				g.try_move(DIRS[rng.randi_range(0, 3)], rng.randf() < 0.3)
			elif roll < 70:
				action = "H"
				g.request_hint()
			elif roll < 82:
				action = "Z"
				g.undo_move()
			elif roll < 90:
				action = "B"
				g._unhandled_input(key_event(KEY_B))
			elif roll < 95:
				action = "R"
				g.restart_level()
			else:
				action = "Z"
				g.undo_move()
			for k in g.hint_seen:
				if action != "H" and int(g.hint_seen[k]) != int(seen_before.get(k, 0)):
					problems.append("step %d %s changed what was opened in stage '%s'" % [step, action, k])
			if action != "H" and g.hint_level > lvl_before:
				problems.append("step %d %s raised the hint level %d -> %d" % [step, action, lvl_before, g.hint_level])
			if g.level_complete or g.dead_now or g.hint_final_armed or has_corner(g):
				continue
			var st = g._phase()
			var expect = Catalog.guide(id, st) if g.hint_level == 0 else "提示 %d / 3 · H 查看\n%s" % [g.hint_level, Catalog.hints(id, st)[g.hint_level - 1]]
			if g.hint_stage != st or g.status_label.text != expect:
				problems.append("step %d after %s: stage '%s' level %d shows '%s'" % [step, action, st, g.hint_level, g.status_label.text.left(20)])
			if g.hint_level > int(g.hint_seen.get(st, 0)):
				problems.append("step %d: hint %d shown but only %d opened in '%s'" % [step, g.hint_level, int(g.hint_seen.get(st, 0)), st])
			if problems.size() > 4:
				break
		check(problems.is_empty(), "%s: 600 random moves / H / Z / B / R: panel always matches the stage, no level opened or consumed unasked %s" % [Catalog.code(id), str(problems)])

	print("LAB4 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB4 SUITE PASSED")
	quit(1 if failures > 0 else 0)

func has_corner(g) -> bool:
	return g.has_permanent_corner()
