extends RefCounted
## Single validation/serialization boundary shared by menu, gameplay and editor.
const WIDTH = 7
const HEIGHT = 6

static func slot_path(slot: int) -> String:
	if slot < 1 or slot > 3:
		return ""
	return "user://custom_level.json" if slot == 1 else "user://custom_level_%d.json" % slot

static func valid_point(point: Variant, allow_missing: bool = false) -> bool:
	if not point is Array or point.size() != 2:
		return false
	for number in point:
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floor(float(number)):
			return false
	if allow_missing and int(point[0]) == -1 and int(point[1]) == -1:
		return true
	return int(point[0]) >= 0 and int(point[0]) < WIDTH and int(point[1]) >= 0 and int(point[1]) < HEIGHT

static func validate(data: Variant, playable: bool = true) -> String:
	if not data is Dictionary:
		return "关卡内容不是有效的数据对象。"
	var charge = data.get("pull_charges", 0)
	if not (charge is int or charge is float) or not is_finite(float(charge)) or not float(charge) in [0.0, 1.0, 2.0]:
		return "开局牵引次数只能为 0、1 或 2。"
	for key in ["walls", "goals", "boxes", "player"]:
		if not data.has(key):
			return "关卡缺少字段：" + key
	for key in ["walls", "goals", "boxes"]:
		if not data[key] is Array or data[key].size() > WIDTH * HEIGHT:
			return "关卡列表无效：" + key
		var seen = {}
		for point in data[key]:
			if not valid_point(point):
				return "关卡坐标越界或格式错误：" + key
			var cell = Vector2i(int(point[0]), int(point[1]))
			if seen.has(cell):
				return "关卡含重复坐标：" + key
			seen[cell] = true
	if not valid_point(data.player, not playable):
		return "请先放置一个位于地图内的玩家起点。"
	var wall_cells = {}
	for p in data.walls:
		wall_cells[Vector2i(int(p[0]), int(p[1]))] = true
	for key in ["goals", "boxes"]:
		for p in data[key]:
			if wall_cells.has(Vector2i(int(p[0]), int(p[1]))):
				return "墙不能与箱子或目标点重叠。"
	var player = Vector2i(int(data.player[0]), int(data.player[1]))
	if wall_cells.has(player):
		return "玩家不能位于墙内。"
	for p in data.boxes:
		if Vector2i(int(p[0]), int(p[1])) == player:
			return "玩家不能与箱子重叠。"
	# Lab: optional tool crate and bench (each at most one; absent or [-1, -1] = none).
	for key in ["tool", "bench"]:
		if data.has(key) and not valid_point(data[key], true):
			return "工具箱或工作台的坐标无效。"
	var tool = cell_of(data, "tool")
	var bench = cell_of(data, "bench")
	var goal_cells = {}
	for p in data.goals:
		goal_cells[Vector2i(int(p[0]), int(p[1]))] = true
	var box_cells = {}
	for p in data.boxes:
		box_cells[Vector2i(int(p[0]), int(p[1]))] = true
	if tool != NONE:
		if wall_cells.has(tool) or box_cells.has(tool) or goal_cells.has(tool) or tool == player:
			return "工具箱要放在空地上（不能和墙、箱子、光圈或玩家重叠）。"
	if bench != NONE:
		if wall_cells.has(bench) or box_cells.has(bench) or goal_cells.has(bench) or bench == tool:
			return "工作台要放在空地上（不能和墙、箱子、光圈或工具箱重叠）。"
	if playable:
		if data.boxes.is_empty():
			return "请至少放置一个箱子和一个目标点。"
		if data.boxes.size() != data.goals.size():
			return "箱子数量必须与目标点数量相同。"
		if (tool == NONE) != (bench == NONE):
			return "工具箱和工作台要成对放置：工具箱只有推上工作台才会打开。"
	return ""

const NONE = Vector2i(-1, -1)

## Lab: Vector2i of an optional single-cell field, or NONE.
static func cell_of(data: Dictionary, key: String) -> Vector2i:
	var p = data.get(key, null)
	if p is Array and p.size() == 2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float):
		return Vector2i(int(p[0]), int(p[1]))
	return NONE

## Lab: true when the map uses anything the official V7.13.1 cannot read (tool crate, bench, 2 pulls).
static func uses_lab_features(data: Dictionary) -> bool:
	return cell_of(data, "tool") != NONE or cell_of(data, "bench") != NONE or int(data.get("pull_charges", 0)) > 1

static func normalize(data: Dictionary) -> Dictionary:
	var result = {"walls": [], "goals": [], "boxes": [], "player": [int(data.player[0]), int(data.player[1])]}
	for key in ["walls", "goals", "boxes"]:
		for p in data[key]:
			result[key].append([int(p[0]), int(p[1])])
	result["pull_charges"] = int(data.get("pull_charges", 0))
	# Lab: written only when present, so maps without them keep their old form and fingerprints.
	for key in ["tool", "bench"]:
		var cell = cell_of(data, key)
		if cell != NONE:
			result[key] = [cell.x, cell.y]
	return result

static func load_path(path: String, playable: bool = true) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "没有找到关卡文件。", "data": {}}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法打开关卡文件。", "data": {}}
	if file.get_length() > 262144:
		return {"ok": false, "error": "关卡文件过大。", "data": {}}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		var line = json.get_error_line()
		return {"ok": false, "error": "JSON 格式错误，第 %d 行。" % line if line > 0 else "文件内容不是有效的 JSON。", "data": {}}
	var problem = validate(json.data, playable)
	if not problem.is_empty():
		return {"ok": false, "error": problem, "data": {}}
	return {"ok": true, "error": "", "data": normalize(json.data)}

## V7.9: canonical form (sorted lists) so the same map always has the same fingerprint.
static func canonical(data: Dictionary) -> Dictionary:
	var c = normalize(data)
	for key in ["walls", "goals", "boxes"]:
		c[key].sort_custom(func(a, b): return a[1] * WIDTH + a[0] < b[1] * WIDTH + b[0])
	return c

static func fingerprint(data: Dictionary) -> String:
	return JSON.stringify(canonical(data)).md5_text()

## V7.9: maps proven solvable (editor check or a finished test play). Keyed by fingerprint, so any
## edit to a saved map makes it "unverified" again automatically. Stored apart from level files.
const VERIFIED_PATH = "user://verified_levels.cfg"
const Mirror = preload("res://web_mirror.gd")

static func mark_verified(data: Dictionary) -> void:
	if not validate(data, true).is_empty():
		return
	var cfg = ConfigFile.new()
	if FileAccess.file_exists(VERIFIED_PATH):
		cfg.load(VERIFIED_PATH)
	cfg.set_value("verified", fingerprint(data), true)
	cfg.save(VERIFIED_PATH)

static func is_verified(data: Dictionary) -> bool:
	if not FileAccess.file_exists(VERIFIED_PATH) or not validate(data, true).is_empty():
		return false
	var cfg = ConfigFile.new()
	if cfg.load(VERIFIED_PATH) != OK:
		return false
	return cfg.get_value("verified", fingerprint(data), false) == true

## V7.9 share code: "KURO<pull>-" + 6 rows of 7 letters separated by "/" + "-" + checksum.
## W wall, O floor, G goal, B box, X box on goal, P player, Q player on goal.
## Lab: maps with a tool crate, a bench or 2 starting pulls use "KUROT<pull>-" and three more
## letters: T tool crate, K bench, J player on the bench. Every other map keeps the old form, so
## codes copied here still work in V7.13.1 (which rejects a KUROT code with an error message).
const SHARE_LETTERS = "WOGBXPQ"
const LAB_LETTERS = "TKJ"

static func share_code(data: Dictionary) -> String:
	var c = canonical(data)
	var grid = []
	for y in HEIGHT:
		var row = []
		for x in WIDTH: row.append("O")
		grid.append(row)
	for p in c.walls: grid[p[1]][p[0]] = "W"
	for p in c.goals: grid[p[1]][p[0]] = "G"
	for p in c.boxes: grid[p[1]][p[0]] = "X" if grid[p[1]][p[0]] == "G" else "B"
	var tool = cell_of(c, "tool")
	var bench = cell_of(c, "bench")
	if tool != NONE: grid[tool.y][tool.x] = "T"
	if bench != NONE: grid[bench.y][bench.x] = "K"
	if valid_point(c.player):
		var under = grid[c.player[1]][c.player[0]]
		grid[c.player[1]][c.player[0]] = "Q" if under == "G" else ("J" if under == "K" else "P")
	var rows = []
	for row in grid: rows.append("".join(row))
	var body = ("KUROT%d-%s" if uses_lab_features(c) else "KURO%d-%s") % [c.pull_charges, "/".join(rows)]
	return body + "-" + _checksum(body)

## V7.10: 6 hex digits of MD5 (16.7 M values). V7.9 used 2 hex digits (256 values), which let
## some single-cell typos through. Every single-cell change of every built-in map is tested.
static func _checksum(body: String) -> String:
	return body.md5_text().substr(0, 6).to_upper()

## Returns {"ok", "error", "data"}; never trusts the text beyond the same validation as files.
static func parse_share_code(text: String) -> Dictionary:
	var code = text.strip_edges().to_upper().replace(" ", "").replace("\n", "")
	var parts = code.split("-")
	if parts.size() == 3 and parts[0].begins_with("KURO") and not parts[0] in ["KURO0", "KURO1", "KUROT0", "KUROT1", "KUROT2"]:
		return {"ok": false, "error": "这是更新版本的推箱工坊分享码，当前版本无法读取。", "data": {}}
	if parts.size() != 3 and parts[0] in ["KURO0", "KURO1", "KUROT0", "KUROT1", "KUROT2"]:
		# Lab 3: the right start but cut short (or two codes pasted together) is not "someone else's code".
		return {"ok": false, "error": "分享码不完整（应有三段，用 - 连接）。", "data": {}}
	if parts.size() != 3 or not parts[0] in ["KURO0", "KURO1", "KUROT0", "KUROT1", "KUROT2"]:
		return {"ok": false, "error": "这不是推箱工坊的分享码。", "data": {}}
	var lab_code = parts[0].begins_with("KUROT")
	if parts[2].length() == 2:
		return {"ok": false, "error": "这是旧版（V7.9）的分享码，请让对方用新版重新复制。", "data": {}}
	if _checksum(parts[0] + "-" + parts[1]) != parts[2]:
		return {"ok": false, "error": "分享码不完整或抄错了（校验不通过）。", "data": {}}
	var rows = parts[1].split("/")
	if rows.size() != HEIGHT:
		return {"ok": false, "error": "分享码的地图行数不对。", "data": {}}
	var data = {"walls": [], "goals": [], "boxes": [], "player": [-1, -1], "pull_charges": int(parts[0].substr(5 if lab_code else 4))}
	if parts[1].count("P") + parts[1].count("Q") + parts[1].count("J") > 1:
		return {"ok": false, "error": "分享码里有不止一个玩家起点。", "data": {}}
	if parts[1].count("T") > 1 or parts[1].count("K") + parts[1].count("J") > 1:
		return {"ok": false, "error": "分享码里的工具箱或工作台多于一个。", "data": {}}
	for y in HEIGHT:
		if rows[y].length() != WIDTH:
			return {"ok": false, "error": "分享码的地图宽度不对。", "data": {}}
		for x in WIDTH:
			var ch = rows[y][x]
			if not SHARE_LETTERS.contains(ch) and not (lab_code and LAB_LETTERS.contains(ch)):
				return {"ok": false, "error": "分享码含有无法识别的字符。", "data": {}}
			match ch:
				"W": data.walls.append([x, y])
				"G": data.goals.append([x, y])
				"B": data.boxes.append([x, y])
				"X":
					data.boxes.append([x, y])
					data.goals.append([x, y])
				"P": data.player = [x, y]
				"Q":
					data.player = [x, y]
					data.goals.append([x, y])
				"T": data["tool"] = [x, y]
				"K": data["bench"] = [x, y]
				"J":
					data.player = [x, y]
					data["bench"] = [x, y]
	var problem = validate(data, false)
	if not problem.is_empty():
		return {"ok": false, "error": problem, "data": {}}
	return {"ok": true, "error": "", "data": normalize(data)}

## V7.9: recovery for a slot that fails to load. Neither action deletes data.
static func backup_usable(path: String) -> bool:
	return FileAccess.file_exists(path + ".bak") and load_path(path + ".bak", false).ok

## V7.10: never replace an earlier .corrupt copy. Picks name.corrupt, name.corrupt.2, ...
static func free_aside_path(path: String) -> String:
	var candidate = path + ".corrupt"
	var n = 2
	while FileAccess.file_exists(candidate):
		candidate = path + ".corrupt.%d" % n
		n += 1
	return candidate

## Moves a file aside under a fresh name. Returns the new res/user path, or "" on failure.
static func move_aside(path: String) -> String:
	var target = free_aside_path(path)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target)) != OK:
		return ""
	return target

## V7.10: restore only after the broken file is safely moved aside; stop if that fails.
static func restore_backup(path: String) -> String:
	if not path in [slot_path(1), slot_path(2), slot_path(3)] or not backup_usable(path):
		return "没有可用的备份。"
	if FileAccess.file_exists(path) and move_aside(path).is_empty():
		return "无法先另存损坏的文件，已停止恢复，原文件保持不变。"
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path + ".bak"), ProjectSettings.globalize_path(path)) != OK:
		return "无法从备份恢复。损坏的文件已另存，备份仍在。"
	if Mirror.available():
		Mirror.set_text(path, FileAccess.get_file_as_string(path))
	return ""

static func set_aside(path: String) -> String:
	if not path in [slot_path(1), slot_path(2), slot_path(3)] or not FileAccess.file_exists(path):
		return "存档不存在。"
	if move_aside(path).is_empty():
		return "无法另存这个存档，已停止，原文件保持不变。"
	if Mirror.available():
		Mirror.erase(path)  # a cleared slot must not come back from the Web copy
	return ""

static func save_path(path: String, data: Dictionary) -> String:
	if not path in [slot_path(1), slot_path(2), slot_path(3)]:
		return "只能保存到三个自定义存档槽。"
	var problem = validate(data, false)
	if not problem.is_empty():
		return problem
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入存档，请检查磁盘空间与访问权限。"
	file.store_string(JSON.stringify(normalize(data), "  "))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return "写入失败，原存档未替换。"
	var verify = load_path(temporary, false)
	if not verify.ok:
		return "保存验证失败，原存档未替换。"
	var full_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(full_path, full_path + ".bak") != OK:
			return "无法备份已有存档，已取消覆盖。"
	var status = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), full_path)
	if status != OK:
		return "无法替换存档。原文件及备份保持可用。"
	if Mirror.available():
		Mirror.set_text(path, FileAccess.get_file_as_string(path))
	return ""

## V7.11 (Web): the localStorage copy always reflects the latest save, clear or restore of a
## slot, so it wins over a file that the browser had not yet synced. Returns slots repaired.
static func reconcile_mirror() -> int:
	if not Mirror.available():
		return 0
	var repaired = 0
	for index in range(1, 4):
		var path = slot_path(index)
		if not Mirror.has_text(path):
			continue
		var text = Mirror.get_text(path)
		var parsed = JSON.new()
		if parsed.parse(text) != OK or not parsed.data is Dictionary or not validate(parsed.data, false).is_empty():
			continue
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
			continue
		if FileAccess.file_exists(path) and not load_path(path, false).ok and move_aside(path).is_empty():
			continue  # never overwrite an unreadable file we could not keep
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(text)
		f.close()
		repaired += 1
	return repaired
