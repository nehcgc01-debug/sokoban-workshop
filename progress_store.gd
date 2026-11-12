extends RefCounted
# Progress is independent from level JSON: editing a level never rewrites records.
const Catalog = preload("res://level_catalog.gd")
const PATH = "user://progress.cfg"

static func best_moves(index: int) -> int:
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return -1
	var value = cfg.get_value("builtin", str(index), -1)
	return int(value) if (value is int or value is float) and value >= 0 else -1

static func record(index: int, moves: int) -> Error:
	if index < 1 or index > Catalog.COUNT or moves < 0:
		return ERR_INVALID_PARAMETER
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	var old = best_moves(index)
	if old >= 0 and old <= moves:
		return OK
	cfg.set_value("builtin", str(index), moves)
	return cfg.save(PATH)
