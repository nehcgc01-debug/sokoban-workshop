extends RefCounted
## V7.11: opt-in playtest log for blind tests. Off by default; a facilitator turns it on from the
## main menu (Ctrl+Shift+P) before handing over the game. Nothing leaves the device unless the
## facilitator exports it (Ctrl+Shift+E). One JSON line per attempt at a level.
const PATH = "user://playtest_log.jsonl"
const FLAG = "user://playtest_enabled"
const Mirror = preload("res://web_mirror.gd")

static func enabled() -> bool:
	return FileAccess.file_exists(FLAG)

static func set_enabled(on: bool) -> void:
	if on:
		var f = FileAccess.open(FLAG, FileAccess.WRITE)
		if f:
			f.store_string("1")
			f.close()
	elif FileAccess.file_exists(FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAG))

static func read_all() -> String:
	var text = FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
	# Web: the synchronous copy may hold lines the browser had not synced yet.
	if Mirror.available() and Mirror.has_text(PATH) and Mirror.get_text(PATH).length() > text.length():
		text = Mirror.get_text(PATH)
	return text

static func attempt_count() -> int:
	var n = 0
	for line in read_all().split("\n"):
		if not line.strip_edges().is_empty():
			n += 1
	return n

static func append(entry: Dictionary) -> void:
	var text = read_all() + JSON.stringify(entry) + "\n"
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	if Mirror.available():
		Mirror.set_text(PATH, text)

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if Mirror.available():
		Mirror.erase(PATH)

## Desktop: writes a timestamped copy next to the save data and returns its full path.
## Web: starts a browser download and returns the file name.
static func export_copy() -> String:
	var text = read_all()
	var name = "kuro_playtest_%s.jsonl" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), name, "application/json")
		return name
	var path = "user://" + name
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(path)

## ---- one attempt (a visit to a level from entering until leaving) ----
static func new_attempt(level_id: int, position: int, slot: int) -> Dictionary:
	return {"level": level_id, "position": position, "slot": slot, "started": Time.get_unix_time_from_system(),
		"moves_made": 0, "undos": 0, "restarts": 0, "max_hint": 0, "hint_at": [], "rewinds": 0,
		"dead_entries": 0, "first_dead_at": -1.0, "pulls_used": 0, "solved": false, "solve_moves": -1,
		"solve_at": -1.0, "end": "", "seconds": 0.0, "finished": false}

static func seconds_since(attempt: Dictionary) -> float:
	return snappedf(Time.get_unix_time_from_system() - float(attempt.started), 0.1)

static func finish(attempt: Dictionary, how: String) -> void:
	if attempt.is_empty() or attempt.finished:
		return
	attempt.finished = true
	attempt.end = how
	attempt.seconds = seconds_since(attempt)
	var entry = attempt.duplicate(true)
	entry.erase("finished")
	entry.erase("started")
	entry["at_utc"] = Time.get_datetime_string_from_unix_time(int(attempt.started), true)
	append(entry)
