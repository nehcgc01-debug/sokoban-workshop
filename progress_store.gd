extends RefCounted
# Progress is independent from level JSON: editing a level never rewrites records.
const Catalog = preload("res://level_catalog.gd")
const PATH = "user://progress.cfg"
const Mirror = preload("res://web_mirror.gd")

## ---------------- Lab 4: protected writes ----------------
## Why: in an exported game Godot's own "safe save" is off (FileAccess.backup_save defaults to false;
## only the editor turns it on), so ConfigFile.save() truncates the record file and writes it in
## place. A failure half way could leave a damaged file. Every write now goes:
##   1. new content -> progress.cfg.new, read back and compared byte for byte
##   2. its MD5 -> progress.cfg.new.ok (read back), so a later start can tell a complete .new
##      from a half-written one
##   3. the current file -> progress.cfg.bak (read back and compared)
##   4. DirAccess.rename(.new -> progress.cfg)
##        Linux/macOS: rename(2), replaces the file in one step on the same disk.
##        Windows (Godot 4.6.1 DirAccessWindows::rename): deletes the old file, then MoveFileW.
##        Between those two calls neither file is at the final name; steps 2 and 3 cover that.
##   5. progress.cfg read back and compared; then .new.ok is removed.
## recover() (menu start) finishes an interrupted write from a verified .new, or brings back
## .bak when the file is missing. Nothing here can protect against a disk that lies about what
## it wrote, or against hardware failure; tests simulate faults, they do not cut power.
const NEW = PATH + ".new"
const NEW_OK = PATH + ".new.ok"
const BAK = PATH + ".bak"
## Tests only: name of a step to fail ("write_new", "partial_new", "verify_new", "mark", "backup",
## "replace", "replace_removed", "verify_final") or to stop at as if the game were killed
## ("crash_after_mark", "crash_after_remove"). Always "" in normal play.
static var fault := ""
## What the last write did: {"stage": failed step or "", "old": "none" / "unchanged" / "backup" /
## "unknown" / "corrupt"} — "old" is measured after the failure, never assumed.
static var last_report: Dictionary = {}

static func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)

static func _write_bytes(path: String, data: PackedByteArray) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	var ok = f.get_error() == OK
	f.close()
	return ok

static func encode(records: Dictionary) -> String:
	var ids = records.keys()
	ids.sort()
	var text = "[builtin]\n\n"
	for id in ids:
		text += "%d=%d\n" % [int(id), int(records[id])]
	return text

static func _records_of(bytes: PackedByteArray) -> Dictionary:
	var out = {}
	var cfg = ConfigFile.new()
	if bytes.is_empty() or cfg.parse(bytes.get_string_from_utf8()) != OK or not cfg.has_section("builtin"):
		return out
	for key in cfg.get_section_keys("builtin"):
		var value = cfg.get_value("builtin", key, -1)
		if (value is int) and value >= 0 and key.is_valid_int():
			out[int(key)] = value
	return out

## Lab 5: a pair (temporary file, its .ok marker) counts only if the marker holds the MD5 of a
## complete, readable record. Recovery sources are such pairs; they are never deleted until the
## records they hold are safely in progress.cfg.
static func _pair_verified(tmp: String, ok: String) -> bool:
	if not FileAccess.file_exists(tmp) or not FileAccess.file_exists(ok):
		return false
	var data = _bytes(tmp)
	return not data.is_empty() and _looks_healthy(data) and _bytes(ok).get_string_from_utf8().strip_edges() == data.get_string_from_utf8().md5_text()

static func _new_verified() -> bool:
	return _pair_verified(NEW, NEW_OK)

## A record file that exists but is empty or not in the expected format (Lab 5: 0 bytes counts as
## damaged; only a missing file means "nothing recorded yet").
static func _file_damaged(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = _bytes(path)
	return data.is_empty() or not _looks_healthy(data)

static func _file_ok(path: String) -> bool:
	return FileAccess.file_exists(path) and not _file_damaged(path)

## Recovery writes use their own temporary pair (progress.cfg.rec, .rec2, ...), never one that is
## being recovered from. All pairs that exist: [[tmp, ok], ...].
const REC = PATH + ".rec"
const RESTORE = PATH + ".restore"   # "the backup still has to be put back" (survives a failed restore)
static func _rec_pairs() -> Array:
	var out = []
	for f in DirAccess.get_files_at(PATH.get_base_dir()):
		var full = PATH.get_base_dir().path_join(f)
		if f.begins_with(REC.get_file()) and not f.ends_with(".ok"):
			out.append([full, full + ".ok"])
	return out

static func _sources() -> Array:
	var out = []
	for pair in [[NEW, NEW_OK]] + _rec_pairs():
		if _pair_verified(pair[0], pair[1]):
			out.append(pair)
	return out

## Lab 6: set when a restore from the backup is needed but neither the .restore marker nor the
## restore itself could be written. Blocks record() for the rest of this run; after a restart
## _restore_needed() still sees the situation from the files themselves.
static var restore_blocked := false

## A damaged record file was set aside and the backup has not been put back yet. Two signs, so it
## does not depend on being able to write anything: the .restore marker, or (no progress.cfg, a
## valid .bak, and a .corrupt copy at least as new as the .bak). A record file the player deleted
## leaves no .corrupt copy, so it is still not brought back.
static func _restore_needed() -> bool:
	if FileAccess.file_exists(PATH) or not _file_ok(BAK):
		return false
	if FileAccess.file_exists(RESTORE) or restore_blocked:
		return true
	var bak_time = FileAccess.get_modified_time(BAK)
	for f in DirAccess.get_files_at(PATH.get_base_dir()):
		# 2 s of slack: in a normal save the temporary file (later progress.cfg) is written just
		# before the .bak copy, so a file damaged without being rewritten can be a moment older.
		if f.begins_with(PATH.get_file() + ".corrupt") and FileAccess.get_modified_time(PATH.get_base_dir().path_join(f)) + 2 >= bak_time:
			return true
	return false

## Anything left by a write that did not finish: temporary files, markers, a pending restore.
static func transaction_pending() -> bool:
	if FileAccess.file_exists(NEW) or FileAccess.file_exists(NEW_OK) or FileAccess.file_exists(RESTORE) or _restore_needed():
		return true
	for pair in _rec_pairs():
		if FileAccess.file_exists(pair[0]) or FileAccess.file_exists(pair[1]):
			return true
	for f in DirAccess.get_files_at(PATH.get_base_dir()):
		if f.begins_with(REC.get_file()) and f.ends_with(".ok"):
			return true
	return false

static func _remove(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(_abs(p))

static func _remove_all_pending() -> void:
	_remove([NEW, NEW_OK, RESTORE])
	for f in DirAccess.get_files_at(PATH.get_base_dir()):
		if f.begins_with(REC.get_file()):
			_remove([PATH.get_base_dir().path_join(f)])

static func _free_rec_pair() -> Array:
	var n = 1
	while true:
		var tmp = REC if n == 1 else "%s%d" % [REC, n]
		if not FileAccess.file_exists(tmp) and not FileAccess.file_exists(tmp + ".ok"):
			return [tmp, tmp + ".ok"]
		n += 1
	return []

## Writes text through steps 1–5 using the temporary pair tmp / tmp_ok. On failure last_report says
## which step failed and what the old file looks like now. Only this call's own temporary files
## are ever removed, and only when nothing was replaced.
static func safe_write(text: String, tmp: String = NEW, tmp_ok: String = NEW_OK) -> Error:
	var data = text.to_utf8_buffer()
	var old_exists = FileAccess.file_exists(PATH)
	var old = _bytes(PATH)
	last_report = {"stage": "", "old": "none"}
	var stage = _steps(data, old_exists, old, tmp, tmp_ok)
	if stage.is_empty():
		return OK
	last_report["stage"] = stage
	if stage.begins_with("crash_"):
		last_report["old"] = "unknown"
		return ERR_FILE_CANT_WRITE     # the "killed" process leaves every file as it was
	# Measure, do not assume: is the old record still there, byte for byte?
	if not old_exists:
		last_report["old"] = "none"
	elif FileAccess.file_exists(PATH) and _bytes(PATH) == old:
		last_report["old"] = "unchanged"
	elif not FileAccess.file_exists(PATH) and _bytes(BAK) == old:
		last_report["old"] = "backup"   # recover() or the next retry brings it back
	else:
		last_report["old"] = "unknown"
	if last_report["old"] in ["unchanged", "none"]:
		_remove([tmp_ok, tmp])          # nothing was replaced: this call's temporary files are not needed
	return ERR_FILE_CANT_WRITE

static func _steps(data: PackedByteArray, old_exists: bool, old: PackedByteArray, tmp: String, tmp_ok: String) -> String:
	# 1. the new content beside the real file
	if fault == "write_new":
		return "write_new"
	var written = data.slice(0, data.size() / 2) if fault == "partial_new" else data
	if not _write_bytes(tmp, written):
		return "write_new"
	if fault == "verify_new" or _bytes(tmp) != data:
		return "verify_new"
	# 2. proof that the temporary file is complete
	if fault == "mark" or not _write_bytes(tmp_ok, data.get_string_from_utf8().md5_text().to_utf8_buffer()) or not _pair_verified(tmp, tmp_ok):
		return "mark"
	if fault == "crash_after_mark":
		return "crash_after_mark"
	# 3. a copy of the record being replaced (never of a damaged one: record() refuses those first)
	if old_exists:
		if fault == "backup" or DirAccess.copy_absolute(_abs(PATH), _abs(BAK)) != OK or _bytes(BAK) != old:
			return "backup"
	# 4. replace
	if fault in ["replace_removed", "crash_after_remove"] and old_exists:
		DirAccess.remove_absolute(_abs(PATH))   # the first half of a Windows replace
		return "replace" if fault == "replace_removed" else "crash_after_remove"
	if fault == "replace" or DirAccess.rename_absolute(_abs(tmp), _abs(PATH)) != OK:
		return "replace"
	# 5. check the result
	if fault == "verify_final" or _bytes(PATH) != data:
		return "verify_final"
	_remove([tmp_ok])
	return ""

## Lab 4/5: call once at start (main menu), after check_integrity(), and before any record write
## while a write is unfinished. Puts every record that is safely somewhere back into progress.cfg:
##   the current file if readable, otherwise the backup (only when a write was interrupted, or
##   allow_backup: check_integrity() has just set a damaged file aside), plus every verified
##   temporary pair, merged by taking the fewest moves per level.
## While this has not succeeded, its sources (.new, .rec*, .bak, the .restore marker) stay as they
## are and record() refuses to write. Returns a player-facing message, or "".
static func recover(allow_backup: bool = false) -> String:
	if _file_damaged(PATH):
		return ""   # an unreadable file that could not be moved aside: never overwrite it
	var path_ok = _file_ok(PATH)
	var sources = _sources()
	var marker_failed = false
	var must_restore = not path_ok and _file_ok(BAK) and (allow_backup or _restore_needed())
	if allow_backup and not path_ok and _file_ok(BAK) and not FileAccess.file_exists(RESTORE):
		# remembered even if the restore below fails; Lab 6: the result is checked, and a failure
		# does not cancel the restore, it only means nothing durable remembers it.
		marker_failed = not _write_bytes(RESTORE, "1".to_utf8_buffer()) or not FileAccess.file_exists(RESTORE)
	var restoring = must_restore or FileAccess.file_exists(RESTORE)
	var interrupted = must_restore or transaction_pending()
	if path_ok and sources.is_empty():
		_remove_all_pending()   # leftovers of writes that never reached the real file; the file wins
		return ""
	if not interrupted:
		return ""
	var merged = _records_of(_bytes(PATH)) if path_ok else {}
	var from_backup = false
	if not path_ok and _file_ok(BAK):
		merged = _records_of(_bytes(BAK))
		from_backup = true
	for pair in sources:
		var newer = _records_of(_bytes(pair[0]))
		for id in newer:
			if not merged.has(id) or newer[id] < merged[id]:
				merged[id] = newer[id]
	if merged.is_empty():
		if not path_ok and not FileAccess.file_exists(BAK):
			_remove_all_pending()   # nothing anywhere to recover
		return ""
	var text = encode(merged)
	if path_ok and _bytes(PATH) == text.to_utf8_buffer():
		_remove_all_pending()
		return ""
	var own = _free_rec_pair()
	if safe_write(text, own[0], own[1]) != OK:
		if must_restore:
			restore_blocked = true
		var why = "\n（恢复标记 %s 也无法写入。）" % RESTORE.get_file() if marker_failed else ""
		return "上次保存没有完成，自动恢复也没有成功。\n恢复所需的文件都已保留，下次启动会再试；\n在恢复完成前，新成绩不会写入。" + why
	restore_blocked = false
	_remove_all_pending()
	if Mirror.available():
		Mirror.set_text(PATH, text)
	if not sources.is_empty():
		return "上次保存在中途被打断，已经补完通关记录。"
	if from_backup and restoring:
		var note = "\n注意：恢复标记 %s 无法写入，请检查存档文件夹。" % RESTORE.get_file() if marker_failed else ""
		return "已经从备份 %s 恢复。\n最后一次通关的成绩可能不在里面。" % BAK.get_file() + note
	return "通关记录文件不见了，已经从备份 %s 恢复。\n最后一次通关的成绩可能不在里面。" % BAK.get_file() if from_backup else ""

static func check_integrity() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	# ConfigFile.load() accepts text or binary garbage as an empty file (verified in Godot 4.6.1)
	# and logs engine errors on truncated files. This game only ever writes "[builtin]" followed by
	# "<id>=<moves>" lines, so check the text against exactly that before trusting it.
	var bytes = FileAccess.get_file_as_bytes(PATH)
	if not bytes.is_empty() and _looks_healthy(bytes):
		return ""
	# Lab 5: an existing but empty (0-byte) file is damaged too: it is set aside like any other.
	# V7.10: unique name, never replace an earlier copy.
	var target = PATH + ".corrupt"
	var n = 2
	while FileAccess.file_exists(target):
		target = PATH + ".corrupt.%d" % n
		n += 1
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(target)) != OK:
		return "通关记录文件无法读取，也无法另存。\n为避免覆盖，本次游玩不会写入新记录。"
	if bytes.is_empty():
		return "通关记录文件是空的（0 字节），无法读取。\n原文件已另存为 %s，记录将从头开始。" % target.get_file()
	return "通关记录文件已损坏，无法读取。\n原文件已另存为 %s，记录将从头开始。" % target.get_file()

static func _looks_healthy(bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return true
	var text = bytes.get_string_from_utf8()
	if text.is_empty():
		return false
	var line_ok = RegEx.create_from_string("^\\s*(\\[builtin\\]|\\d+\\s*=\\s*\\d+)\\s*$")
	var saw_section = false
	for line in text.split("\n"):
		if line.strip_edges().is_empty():
			continue
		if line_ok.search(line) == null:
			return false
		if line.strip_edges() == "[builtin]":
			saw_section = true
		elif not saw_section:
			# V7.10.1: ConfigFile places keys before the first header in an
			# empty section. Do not silently accept and lose those records.
			return false
	return saw_section

static func best_moves(index: int) -> int:
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return -1
	var value = cfg.get_value("builtin", str(index), -1)
	return int(value) if (value is int or value is float) and value >= 0 else -1

static func record(index: int, moves: int) -> Error:
	if not Catalog.has_level(index) or moves < 0:
		return ERR_INVALID_PARAMETER
	if _file_damaged(PATH):
		last_report = {"stage": "corrupt", "old": "corrupt"}
		return ERR_FILE_CORRUPT  # V7.10: never overwrite an unreadable (Lab 5: or empty) record file
	if transaction_pending():
		# Lab 5: an earlier write did not finish. Put its records back first; until that worked this
		# write must not start, or it would be taken for a first save and drop the older records.
		recover()
		if transaction_pending():
			last_report = {"stage": "recover", "old": "unchanged" if _file_ok(PATH) else ("backup" if _file_ok(BAK) else "unknown")}
			return ERR_BUSY
	var records = _records_of(_bytes(PATH))
	var old = best_moves(index)
	if old >= 0 and old <= moves:
		last_report = {"stage": "", "old": "unchanged"}
		return OK
	records[index] = moves
	var text = encode(records)
	var status = safe_write(text)
	if status == OK and Mirror.available():
		Mirror.set_text(PATH, text)
	return status

## V7.11 (Web): merge the synchronous localStorage copy back into the file. Keeps the best
## (lowest) moves per level from both, so it can only add or improve records, never lose one.
## Call after check_integrity(). Returns how many records were recovered.
static func reconcile_mirror() -> int:
	if not Mirror.available() or not Mirror.has_text(PATH):
		return 0
	var mirror_text = Mirror.get_text(PATH)
	if not _looks_healthy(mirror_text.to_utf8_buffer()):
		return 0
	if _file_damaged(PATH) or transaction_pending():
		return 0  # never overwrite an unreadable file; never write while a recovery is unfinished
	var from_mirror = ConfigFile.new()
	from_mirror.parse(mirror_text)
	var cfg = ConfigFile.new()
	if FileAccess.file_exists(PATH):
		cfg.load(PATH)
	var recovered = 0
	if from_mirror.has_section("builtin"):
		for key in from_mirror.get_section_keys("builtin"):
			var value = from_mirror.get_value("builtin", key, -1)
			if not (value is int) or value < 0 or not Catalog.has_level(int(key)):
				continue
			var current = cfg.get_value("builtin", key, -1)
			if not (current is int) or current < 0 or value < current:
				cfg.set_value("builtin", key, value)
				recovered += 1
	if recovered > 0:
		var merged = {}
		for key in cfg.get_section_keys("builtin"):
			var v = cfg.get_value("builtin", key, -1)
			if (v is int) and v >= 0 and key.is_valid_int():
				merged[int(key)] = v
		if safe_write(encode(merged)) == OK:
			Mirror.set_text(PATH, FileAccess.get_file_as_string(PATH))
	return recovered
