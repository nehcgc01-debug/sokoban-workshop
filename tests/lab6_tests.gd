extends "res://tests/lab5_tests.gd"
## Lab 6: the ".restore" marker cannot be written (a folder of that name is in the way).
## Faults here are a real folder in the throw-away user:// directory plus the code-level fault
## switch; neither is a power cut or a full disk.

func block_marker() -> void:
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(Prog.RESTORE))

func unblock_marker() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Prog.RESTORE)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prog.RESTORE))

## .bak = 1=3 12=8, progress.cfg = 0 bytes, a folder where .restore would go.
func damaged_with_backup() -> PackedByteArray:
	wipe_all()
	unblock_marker()
	Prog.restore_blocked = false
	put(Prog.BAK, Prog.encode(OLD))
	put(Prog.PATH, "")
	block_marker()
	return FileAccess.get_file_as_bytes(Prog.BAK)

func corrupt_copy() -> String:
	return Prog.PATH + ".corrupt"

func run():
	var full = Prog.encode({1: 3, 12: 8, 13: 35})
	# =============== 1. the reported case: marker blocked, restore itself possible ===============
	var bak = damaged_with_backup()
	var msg = await menu_start()
	check(text_of(Prog.PATH) == Prog.encode(OLD) and msg.contains("从备份") and msg.contains("恢复标记") and msg.contains("无法写入"), "marker cannot be written: the backup is restored anyway, and the player is told about the marker (%s)" % msg.replace("\n", " | "))
	check(FileAccess.file_exists(corrupt_copy()) and FileAccess.get_file_as_bytes(corrupt_copy()).is_empty() and FileAccess.get_file_as_bytes(Prog.BAK) == bak and not Prog.transaction_pending(), "the 0-byte file is kept as .corrupt, .bak unchanged, nothing pending")
	unblock_marker()
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full and text_of(Prog.BAK) == Prog.encode(OLD), "after removing the folder: saving 13=35 keeps 1=3 and 12=8; .bak is the previous record")

	# =============== 2. marker blocked AND the restore fails ===============
	for ending in ["same run, fault cleared", "restart, fault cleared", "restart, fault still there"]:
		bak = damaged_with_backup()
		Prog.check_integrity()
		Prog.fault = "write_new"
		var note = Prog.recover(true)
		check(note.contains("没有成功") and note.contains("恢复标记") and note.contains("不会写入"), "[%s] marker and restore both fail: an explicit error, no success claimed" % ending)
		check(not FileAccess.file_exists(Prog.PATH) and FileAccess.get_file_as_bytes(Prog.BAK) == bak and FileAccess.file_exists(corrupt_copy()) and Prog.transaction_pending() and Prog.restore_blocked, "[%s] no progress.cfg, .bak byte-identical, .corrupt kept, the restore counts as pending (%s)" % [ending, files()])
		for i in 3:
			check(Prog.record(13, 35) == ERR_BUSY, "[%s] save attempt %d while the fault lasts is refused" % [ending, i + 1])
		var again = await menu_start()   # (fault still on) another start does not damage anything
		check(not FileAccess.file_exists(Prog.PATH) and FileAccess.get_file_as_bytes(Prog.BAK) == bak and again.contains("没有成功"), "[%s] a start during the fault changes nothing and says so" % ending)
		match ending:
			"same run, fault cleared":
				Prog.fault = ""
				unblock_marker()
				check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full and not Prog.transaction_pending() and not Prog.restore_blocked, "[%s] the next save restores the backup first, then adds 13=35" % ending)
			"restart, fault cleared":
				Prog.fault = ""
				Prog.restore_blocked = false   # a new process: nothing in memory, the marker folder still there
				check(Prog.transaction_pending() and Prog._restore_needed(), "[%s] after a restart the pending restore is still recognised from the files alone" % ending)
				var m = await menu_start()
				check(text_of(Prog.PATH) == Prog.encode(OLD) and m.contains("从备份") and not Prog.transaction_pending(), "[%s] the start restores the backup (%s)" % [ending, m.replace("\n", " | ")])
				check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full and text_of(Prog.BAK) == Prog.encode(OLD), "[%s] then 13=35 is added; .bak holds the previous record" % ending)
			"restart, fault still there":
				Prog.restore_blocked = false
				check(Prog.record(13, 35) == ERR_BUSY and not FileAccess.file_exists(Prog.PATH) and FileAccess.get_file_as_bytes(Prog.BAK) == bak, "[%s] still refused after the restart, data untouched" % ending)
				Prog.fault = ""
				var m2 = await menu_start()
				check(text_of(Prog.PATH) == Prog.encode(OLD) and m2.contains("从备份"), "[%s] once the fault is gone the next start restores" % ending)
		Prog.fault = ""
		unblock_marker()

	# =============== 3. no valid backup ===============
	wipe_all()
	put(Prog.PATH, "")
	block_marker()
	var m3 = await menu_start()
	check(m3.contains("从头开始") and not FileAccess.file_exists(Prog.PATH) and not Prog.transaction_pending() and FileAccess.file_exists(corrupt_copy()), "no backup: set aside, 'starting over', nothing pending (%s)" % m3.replace("\n", " | "))
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == Prog.encode({13: 35}), "no backup: the first result is saved normally")
	unblock_marker()
	wipe_all()
	put(Prog.BAK, "garbage")
	put(Prog.PATH, "")
	var m4 = await menu_start()
	check(m4.contains("从头开始") and text_of(Prog.BAK) == "garbage" and not Prog.transaction_pending(), "an unreadable .bak is not used and not overwritten")
	# first start, no file, a stray folder named like the marker
	wipe_all()
	block_marker()
	var m5 = await menu_start()
	check(m5.is_empty() and not Prog.transaction_pending() and Prog.record(12, 8) == OK and text_of(Prog.PATH) == Prog.encode({12: 8}), "first start without files (marker folder present): no message, first save normal")
	unblock_marker()
	# a record file deleted on purpose later is still not brought back
	wipe_all()
	damaged_with_backup()
	await menu_start()
	unblock_marker()
	OS.delay_msec(3100)
	Prog.record(13, 35)   # a normal save after the restore makes a newer .bak
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Prog.PATH))
	var m6 = await menu_start()
	check(m6.is_empty() and not FileAccess.file_exists(Prog.PATH), "progress.cfg deleted on purpose after a later save: the old .corrupt does not trigger a restore")
	wipe_all()

	# =============== 4. the two Lab 5 probes again ===============
	interrupted_replace()
	Prog.fault = "write_new"
	Prog.recover()
	Prog.fault = ""
	check(Prog.record(13, 35) == OK and text_of(Prog.PATH) == full, "Lab 5 probe 1 (interrupted replace, failed recovery, retry): 1, 12 and 13 all kept")
	wipe_all()
	put(Prog.BAK, Prog.encode(OLD))
	put(Prog.PATH, "")
	var m7 = await menu_start()
	check(text_of(Prog.PATH) == Prog.encode(OLD) and m7.contains("0 字节"), "Lab 5 probe 2 (empty progress.cfg, valid .bak): restored from the backup")
	wipe_all()

	print("LAB6 TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("LAB6 SUITE PASSED")
	quit(1 if failures > 0 else 0)
