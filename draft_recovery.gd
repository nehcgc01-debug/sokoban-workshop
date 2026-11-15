extends RefCounted
# Separate recovery draft; never overwrites a numbered user slot.
const Store = preload("res://level_store.gd")
const Mirror = preload("res://web_mirror.gd")
const PATH = "user://editor_recovery.json"

static func save_draft(data: Dictionary, origin_slot: int = -1) -> String:
	if not Store.validate(data, false).is_empty():
		return "恢复草稿内容无效。"
	var clean = Store.normalize(data)
	# V7.12: remember which slot the draft was based on (0 = new map), only for the message on restore.
	var slot = origin_slot
	if slot < 0:
		slot = int(data.get("_slot", 0))
		if slot <= 0:
			slot = int(data.get("_origin", 0))
	if slot >= 1 and slot <= 3:
		clean["origin_slot"] = slot
	return _write(clean)

## V7.12: true when a recoverable draft is waiting (menu shows it; editor protects it).
static func has_draft() -> bool:
	return not load_draft().is_empty()

static func clear() -> String:
	# A tombstone also prevents an older Web mirror from reviving a discarded draft.
	return _write({})

static func _write(data: Dictionary) -> String:
	var text = JSON.stringify(data)
	var tmp = PATH + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return "恢复草稿无法写入，请先保存到存档槽。"
	f.store_string(text)
	f.flush()
	var err = f.get_error()
	f.close()
	if err != OK: return "恢复草稿写入失败，请先保存到存档槽。"
	if FileAccess.get_file_as_string(tmp) != text: return "恢复草稿验证失败。"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH)) != OK:
		return "恢复草稿替换失败，请先保存到存档槽。"
	if Mirror.available(): Mirror.set_text(PATH, text)
	return ""

static func load_draft() -> Dictionary:
	var text = Mirror.get_text(PATH) if Mirror.available() and Mirror.has_text(PATH) else FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else "{}"
	var value = JSON.parse_string(text)
	if value is Dictionary and not value.is_empty() and Store.validate(value, false).is_empty():
		var data = Store.normalize(value)
		data["_dirty"] = true
		data["_slot"] = 0
		var origin = value.get("origin_slot", 0)
		data["_origin"] = int(origin) if (origin is int or origin is float) and int(origin) >= 1 and int(origin) <= 3 else 0
		data["_tool"] = "wall"
		return data
	return {}
