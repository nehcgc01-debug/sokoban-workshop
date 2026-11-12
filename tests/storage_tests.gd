extends SceneTree
const Store = preload("res://level_store.gd")
var checks = 0
var failures = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)
	else: print("PASS " + message)
func _initialize() -> void:
	var valid = {"walls": [[0.0,0.0]], "goals": [[3.0,2.0]], "boxes": [[2.0,2.0]], "player": [1.0,2.0]}
	check(Store.validate(valid).is_empty(), "JSON float coordinates accepted")
	check(not Store.validate({}).is_empty(), "missing fields rejected")
	check(not Store.validate([]).is_empty(), "nonobject rejected")
	var broken = valid.duplicate(true)
	broken.player = [-1,-1]
	check(not Store.validate(broken).is_empty(), "missing player blocks play")
	check(Store.validate(broken, false).is_empty(), "draft without player may save")
	broken = valid.duplicate(true)
	broken.boxes = [[8,2]]
	check(not Store.validate(broken).is_empty(), "out of bounds rejected")
	broken.boxes = [[2.5,2]]
	check(not Store.validate(broken).is_empty(), "fractional coordinates rejected")
	broken.boxes = [[2,2],[2,2]]
	check(not Store.validate(broken).is_empty(), "duplicates rejected")
	broken = valid.duplicate(true)
	broken.goals = []
	check(not Store.validate(broken).is_empty(), "goal count mismatch rejected")
	broken = valid.duplicate(true)
	broken.walls = [[2,2]]
	check(not Store.validate(broken).is_empty(), "box inside wall rejected")
	broken = valid.duplicate(true)
	broken.player = [2,2]
	check(not Store.validate(broken).is_empty(), "player inside box rejected")
	check(not Store.load_path("user://missing.json").ok, "missing file reports error")
	var f = FileAccess.open("user://broken.json", FileAccess.WRITE)
	f.store_string("{nope}")
	f.close()
	check(not Store.load_path("user://broken.json").ok, "broken JSON reports error")
	check(not Store.save_path("res://bad.json", valid).is_empty(), "unauthorized save destination rejected")
	check(Store.save_path(Store.slot_path(3), valid).is_empty(), "new save succeeds")
	var first = FileAccess.get_file_as_string(Store.slot_path(3))
	check(Store.load_path(Store.slot_path(3)).ok, "saved data reloads")
	valid.player = [1,3]
	check(Store.save_path(Store.slot_path(3), valid).is_empty(), "overwrite succeeds")
	check(FileAccess.get_file_as_string(Store.slot_path(3)+".bak") == first, "previous save backed up")
	check(Store.load_path(Store.slot_path(3)).data.player == [1,3], "overwrite persists updated data")
	for i in range(1,4):
		check(Store.load_path("res://levels/demo_%d.json" % i).ok, "demo %d valid" % i)
	for name in ["user_custom_level.json","user_custom_level_2.json"]:
		check(Store.load_path("res://levels/"+name,false).ok, "original preserved map valid " + name)
	print("STORAGE TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
