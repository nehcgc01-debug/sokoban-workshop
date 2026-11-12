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
	if not (charge is int or charge is float) or not is_finite(float(charge)) or (float(charge) != 0.0 and float(charge) != 1.0):
		return "牵引次数只能为 0 或 1。"
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
	if playable:
		if data.boxes.is_empty():
			return "请至少放置一个箱子和一个目标点。"
		if data.boxes.size() != data.goals.size():
			return "箱子数量必须与目标点数量相同。"
	return ""

static func normalize(data: Dictionary) -> Dictionary:
	var result = {"walls": [], "goals": [], "boxes": [], "player": [int(data.player[0]), int(data.player[1])]}
	for key in ["walls", "goals", "boxes"]:
		for p in data[key]:
			result[key].append([int(p[0]), int(p[1])])
	result["pull_charges"] = int(data.get("pull_charges", 0))
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
		return {"ok": false, "error": "JSON 格式错误，第 %d 行。" % json.get_error_line(), "data": {}}
	var problem = validate(json.data, playable)
	if not problem.is_empty():
		return {"ok": false, "error": problem, "data": {}}
	return {"ok": true, "error": "", "data": normalize(json.data)}

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
	return ""
