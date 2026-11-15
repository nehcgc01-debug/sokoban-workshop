extends RefCounted
## V7.11: Web builds keep user:// in memory and sync it to IndexedDB later. Measured in Chromium:
## a record written at a win was still missing from IndexedDB 300 ms later and present at 1.5 s,
## so closing or reloading the tab right after a win could lose it. localStorage writes are
## synchronous, so on Web every save is mirrored there too and reconciled on the next start.
## On desktop this does nothing unless a test enables the in-memory stand-in.

const PREFIX = "kuro_sukobann_lab6:"  # Lab: never shares browser storage with the official build
static var use_fake := false
static var fake := {}

static func available() -> bool:
	return use_fake or OS.has_feature("web")

static func _storage():
	return JavaScriptBridge.get_interface("localStorage")

static func has_text(key: String) -> bool:
	if use_fake:
		return fake.has(key)
	if not OS.has_feature("web"):
		return false
	var storage = _storage()
	return storage != null and storage.getItem(PREFIX + key) != null

static func get_text(key: String) -> String:
	if use_fake:
		return String(fake.get(key, ""))
	if not has_text(key):
		return ""
	return String(_storage().getItem(PREFIX + key))

static func set_text(key: String, text: String) -> void:
	if use_fake:
		fake[key] = text
	elif OS.has_feature("web"):
		var storage = _storage()
		if storage != null:
			storage.setItem(PREFIX + key, text)

static func erase(key: String) -> void:
	if use_fake:
		fake.erase(key)
	elif OS.has_feature("web"):
		var storage = _storage()
		if storage != null:
			storage.removeItem(PREFIX + key)
