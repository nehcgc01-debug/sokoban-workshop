extends "res://tests/lab4_tests.gd"
## Lab 5: an interrupted write whose recovery fails again, and an empty (0-byte) record file.
## Every case uses this suite's throw-away user:// folder. Faults are injected in code; they are not
## real power cuts or full disks.

const OLD = {1: 3, 12: 8}

func files() -> String:
	var out = []
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("progress.cfg"):
			out.append(f)
	out.sort()
	return ", ".join(out)

func wipe_all() -> void:
	wipe()
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("progress.cfg"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))

## progress.cfg = OLD, then saving 13=35 is cut between the Windows delete and move.
func interrupted_replace() -> void:
	wipe_all()
	check(Prog.record(1, 3) == OK and Prog.record(12, 8) == OK, "setup: records 1=3 and 12=8 saved normally")
	Prog.fault = "crash_after_remove"
	Prog.record(13, 35)
	Prog.fault = ""

func source_ok() -> bool:
	return Prog._pair_verified(Prog.NEW, Prog.NEW_OK) and Prog._records_of(FileAccess.get_file_as_bytes(Prog.NEW)).get(13, -1) == 35

func menu_start() -> String:
	change_scene_to_file("res://main_menu.tscn")
	await frames(4)
	var text = current_scene.notice.dialog_text if current_scene.notice.visible else ""
	current_scene.notice.hide()
	return text

func run():
	var state = root.get_node("GameState")
	var full = Prog.encode({1: 3, 12: 8, 13: 35})
	# =============== 1. replace interrupted -> recovery fails -> fault cleared -> retry / restart ===============
	for f in ["write_new", "partial_new", "verify_new", "mark", "replace"]:
		interrupted_replace()
		var bak = FileAccess.get_file_as_bytes(Prog.BAK)
		check(not FileAccess.file_exists(Prog.PATH) and Prog.encode(OLD).to_utf8_buffer() == bak and source_ok(), "[%s] after the interrupted replace: no progress.cfg, .bak = old records, verified .new holds 13=35" % f)
		Prog.fault = f
		var note = Prog.recover()
		check(note.contains("没有成功") and note.contains("不会写入"), "[%s] the recovery fails and says new results will wait" % f)
		check(FileAccess.get_file_as_bytes(Prog.BAK) == bak and source_ok() and not FileAccess.file_exists(Prog.PATH), "[%s] after the failed recovery: .bak byte-identical, .new + .new.ok intact (%s)" % [f, files()])
		check(Prog.record(14, 28) == ERR_BUSY and Prog.last_report.stage == "recover" and Prog.last_report.old == "backup", "[%s] a new result while the fault is still there is refused (not taken for a first save)" % f)
		check(FileAccess.get_file_as_bytes(Prog.BAK) == bak and source_ok() and not FileAccess.file_exists(Prog.PATH), "[%s] ... and the refusal touched nothing" % f)
		Prog.fault = ""
		if f in ["write_new", "verify_new", "replace"]:
			# fault cleared, the player retries the same result
			check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full and not Prog.transaction_pending(), "[%s] retry after the fault is gone: 1=3, 12=8 and 13=35 all in progress.cfg, nothing pending (%s)" % [f, files()])
			check(Prog.record(14, 28) == OK and Prog.best_moves(1) == 3 and Prog.best_moves(12) == 8 and Prog.best_moves(13) == 35 and Prog.best_moves(14) == 28, "[%s] and the next result is added normally" % f)
		else:
			# fault cleared, the game is restarted
			var msg = await menu_start()
			check(text_of(Prog.PATH) == full and not Prog.transaction_pending() and msg.contains("打断"), "[%s] restart after the fault is gone: all three records back, the player is told (%s)" % [f, msg.replace("\n", " | ")])
	# the recovery itself is killed half way, twice
	interrupted_replace()
	Prog.fault = "crash_after_mark"
	Prog.recover()
	check(source_ok() and Prog._sources().size() == 2 and not FileAccess.file_exists(Prog.PATH), "recovery killed after writing its own temporary file: both pairs verified, nothing deleted")
	Prog.fault = "crash_after_mark"
	Prog.recover()
	check(Prog._sources().size() == 3, "killed again: a third pair, the earlier ones untouched (%s)" % files())
	Prog.fault = ""
	var msg2 = await menu_start()
	check(text_of(Prog.PATH) == full and not Prog.transaction_pending() and msg2.contains("打断"), "next start: everything merged once, all temporary files gone (%s)" % files())
	# progress.cfg present (killed before the replace) and the recovery's replace is cut in half
	wipe_all()
	Prog.record(1, 3)
	Prog.record(12, 8)
	Prog.fault = "crash_after_mark"
	Prog.record(13, 35)
	Prog.fault = "replace_removed"
	Prog.recover()
	Prog.fault = ""
	check(not FileAccess.file_exists(Prog.PATH) and text_of(Prog.BAK) == Prog.encode(OLD) and source_ok(), "recovery cut in half by a Windows-like replace: no progress.cfg, .bak = old, the original .new still there")
	check(Prog.record(14, 28) == OK and Prog.best_moves(1) == 3 and Prog.best_moves(12) == 8 and Prog.best_moves(13) == 35 and Prog.best_moves(14) == 28 and not Prog.transaction_pending(), "the next save first finishes the recovery, then adds its own result")
	# the panel when a win is refused
	interrupted_replace()
	Prog.fault = "write_new"
	Prog.recover()
	state.fresh_fixtures.clear()
	var g = await play(12)
	route(g, "RRRDDLLr")
	check(g.progress_save_failed and g.progress_save_error == ERR_BUSY and g.status_label.text.contains("还没恢复") and g.ability_label.text.contains("按 Y 重试") and state.fresh_fixtures.is_empty(), "a win while the recovery keeps failing: 'not saved, the earlier save is not restored yet', Y offered")
	var gap = g.undo_button.position.y - (g.status_label.position.y + g.status_label.get_line_count() * g.status_label.get_line_height())
	check(gap >= 0.0 and g.status_label.get_line_count() == 3 and g.ability_label.get_line_count() == 1, "that text fits (%.0f px)" % gap)
	Prog.fault = ""
	g._unhandled_input(key_event(KEY_Y))
	check(not g.progress_save_failed and text_of(Prog.PATH) == full, "Y after the fault is gone: the earlier records and 13=35 are back, 12=8 kept")

	# =============== 2. empty (0-byte) record file ===============
	wipe_all()
	put(Prog.BAK, Prog.encode(OLD))
	put(Prog.PATH, "")
	var bak_bytes = FileAccess.get_file_as_bytes(Prog.BAK)
	check(Prog._file_damaged(Prog.PATH) and not Prog._file_damaged("user://does_not_exist.cfg"), "an existing 0-byte file is damaged; a missing file is not")
	check(Prog.record(13, 35) == ERR_FILE_CORRUPT and FileAccess.get_file_as_bytes(Prog.PATH).is_empty() and FileAccess.get_file_as_bytes(Prog.BAK) == bak_bytes, "empty file: no write, it stays 0 bytes, the valid .bak is not overwritten by it")
	var m = await menu_start()
	check(FileAccess.file_exists(Prog.PATH + ".corrupt") and FileAccess.get_file_as_bytes(Prog.PATH + ".corrupt").is_empty(), "next start: the empty file is kept as .corrupt (evidence)")
	check(text_of(Prog.PATH) == Prog.encode(OLD) and m.contains("0 字节") and m.contains("从备份") and not m.contains("从头开始") and not m.contains("不见了") and not Prog.transaction_pending(), "... and the backup is restored; the text says so without claiming the file went missing (%s)" % m.replace("\n", " | "))
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full, "after that a new result is added to the restored records")
	# empty file, valid backup, the restore fails: the backup and the 'restore pending' mark survive
	wipe_all()
	put(Prog.BAK, Prog.encode(OLD))
	put(Prog.PATH, "")
	Prog.fault = "write_new"
	var m2 = await menu_start()
	Prog.fault = ""
	check(not FileAccess.file_exists(Prog.PATH) and FileAccess.get_file_as_bytes(Prog.BAK) == bak_bytes and FileAccess.file_exists(Prog.RESTORE) and m2.contains("没有成功"), "restore fails: .bak untouched, the pending restore is remembered (%s)" % files())
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full and not Prog.transaction_pending(), "the next save restores the backup first, then adds 13=35")
	# empty file, no backup
	wipe_all()
	put(Prog.PATH, "")
	var m3 = await menu_start()
	check(FileAccess.file_exists(Prog.PATH + ".corrupt") and not FileAccess.file_exists(Prog.PATH) and m3.contains("0 字节") and m3.contains("从头开始") and not Prog.transaction_pending(), "empty file, no backup: set aside, 'starting over' (%s)" % m3.replace("\n", " | "))
	check(Prog.record(12, 8) == OK and text_of(Prog.PATH) == Prog.encode({12: 8}), "then the first result is saved normally")
	# whitespace only counts as damaged too
	wipe_all()
	put(Prog.PATH, "\n\n")
	check(Prog._file_damaged(Prog.PATH) and Prog.record(12, 8) == ERR_FILE_CORRUPT, "a file with only blank lines is damaged as well")
	# first start, no file at all
	wipe_all()
	var m4 = await menu_start()
	check(m4.is_empty() and not FileAccess.file_exists(Prog.PATH) and not Prog.transaction_pending(), "first start without any file: no message, nothing created")
	check(Prog.record(12, 8) == OK and text_of(Prog.PATH) == Prog.encode({12: 8}) and not FileAccess.file_exists(Prog.BAK), "first save creates progress.cfg only")
	# deleted on purpose (no unfinished write): the old backup is not brought back
	wipe_all()
	Prog.record(1, 3)
	Prog.record(12, 8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Prog.PATH))
	var m5 = await menu_start()
	check(m5.is_empty() and not FileAccess.file_exists(Prog.PATH), "progress.cfg deleted on purpose: no message, not resurrected from .bak")

	# =============== 3. older record files still read and extend correctly ===============
	wipe_all()
	var cfg = ConfigFile.new()
	cfg.set_value("builtin", "1", 3)
	cfg.set_value("builtin", "12", 8)
	cfg.save(Prog.PATH)   # exactly what V7.13.1 and Lab 1–3 wrote
	var before = FileAccess.get_file_as_bytes(Prog.PATH)
	var m6 = await menu_start()
	check(m6.is_empty() and FileAccess.get_file_as_bytes(Prog.PATH) == before and Prog.best_moves(1) == 3 and Prog.best_moves(12) == 8, "a file written by ConfigFile.save (old versions) is read as is, untouched at start")
	check(Prog.record(13, 35) == OK and Prog.best_moves(1) == 3 and Prog.best_moves(12) == 8 and Prog.best_moves(13) == 35 and FileAccess.get_file_as_bytes(Prog.BAK) == before, "a new result keeps the old ones; the old file is the backup")
	wipe_all()
	put(Prog.PATH, "[builtin]\r\n\r\n1=3\r\n12=8\r\n")
	check(not Prog._file_damaged(Prog.PATH) and Prog.best_moves(12) == 8 and Prog.record(13, 35) == OK and Prog.best_moves(1) == 3, "Windows line endings are fine")
	wipe_all()
	put(Prog.PATH, "[builtin]\n")
	check(not Prog._file_damaged(Prog.PATH) and Prog.record(12, 8) == OK and Prog.best_moves(12) == 8, "a section with no records yet is not damaged")
	wipe_all()

	print("LAB5 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB5 SUITE PASSED")
	quit(1 if failures > 0 else 0)
