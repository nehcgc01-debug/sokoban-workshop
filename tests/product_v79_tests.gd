extends SceneTree
## V7.9 product-level checks: focus, final-hint confirmation, save/progress recovery.
const Store = preload("res://level_store.gd")
const Progress = preload("res://progress_store.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)
func _key(code):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func run():
	# --- progress file corruption is detected, moved aside, and reported
	var f: FileAccess
	for sample in [PackedByteArray([0, 255, 13, 91, 91, 200, 7]), "[builtin]\n1=".to_utf8_buffer(), "garbage [[[".to_utf8_buffer()]:
		f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
		f.store_buffer(sample)
		f.close()
		check(not Progress.check_integrity().is_empty(), "corrupt progress variant detected (%d bytes)" % sample.size())
	f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0, 255, 13, 91, 91, 200, 7]))
	f.close()
	var msg = Progress.check_integrity()
	check(not msg.is_empty() and msg.contains("已损坏"), "corrupt progress is reported to the player")
	check(not FileAccess.file_exists(Progress.PATH) and FileAccess.file_exists(Progress.PATH + ".corrupt"), "corrupt progress is moved aside, not overwritten")
	check(Progress.record(1, 3) == OK and Progress.best_moves(1) == 3, "recording works again after recovery")
	check(Progress.check_integrity().is_empty(), "healthy progress file reports nothing")

	# --- slot recovery: backup restore and set-aside never delete data
	var path = Store.slot_path(2)
	var level = {"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0}
	check(Store.save_path(path, level).is_empty(), "first save")
	level["goals"] = [[4, 2]]
	check(Store.save_path(path, level).is_empty(), "second save creates .bak")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	check(not Store.load_path(path).ok and Store.backup_usable(path), "broken slot with usable backup")
	check(Store.restore_backup(path).is_empty() and Store.load_path(path).ok, "restore from backup loads again")
	check(FileAccess.file_exists(path + ".corrupt"), "broken file kept as .corrupt")
	check(Store.set_aside(path).is_empty() and not FileAccess.file_exists(path), "set aside empties the slot")
	check(not Store.restore_backup(Store.slot_path(3)).is_empty(), "restore without backup refuses")

	# --- catalog text must fit the three-line win panel
	var Catalog = load("res://level_catalog.gd")
	var longest = 0
	for id in Catalog.ORDER:
		longest = maxi(longest, Catalog.insight(id).length())
	check(longest <= 16, "every insight line fits one panel line (longest %d chars)" % longest)

	# --- recovery dialog focus is never on the destructive choice
	var p1 = Store.slot_path(1)
	level["goals"] = [[3, 2]]
	Store.save_path(p1, level)
	level["goals"] = [[4, 2]]
	Store.save_path(p1, level)
	f = FileAccess.open(p1, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	current_scene._show_levels()
	current_scene._play_slot(1)
	await process_frame
	await process_frame
	var focused = current_scene.recovery.gui_get_focus_owner()
	check(current_scene.recovery.visible and focused == current_scene.restore_button, "recovery dialog focuses 从备份恢复 when a backup exists")
	current_scene.recovery.hide()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p1 + ".bak"))
	current_scene._play_slot(1)
	await process_frame
	await process_frame
	focused = current_scene.recovery.gui_get_focus_owner()
	check(focused == current_scene.recovery.get_cancel_button() and not current_scene.restore_button.visible, "without backup: restore hidden, focus on 取消")
	current_scene.recovery.hide()
	Store.set_aside(p1)

	# --- menu: keyboard focus on 开始游戏
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	await process_frame
	var menu = current_scene
	var owner = menu.get_viewport().gui_get_focus_owner()
	check(owner != null and owner is Button and owner.text == "开始游戏", "menu opens with focus on 开始游戏")

	# --- final hint needs one confirmation; any move cancels it
	var state = root.get_node("GameState")
	state.selected_builtin = 6
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	var game = current_scene
	game._input(_key(KEY_H))
	game._input(_key(KEY_H))
	check(game.hint_level == 2, "two presses reach hint 2")
	game._input(_key(KEY_H))
	check(game.hint_level == 2 and game.hint_final_armed and game.status_label.text.contains("关键步骤"), "third press asks before revealing the key step")
	game.try_move(Vector2i.LEFT)
	check(not game.hint_final_armed and game.hint_level == 2, "moving cancels the pending confirmation")
	game._input(_key(KEY_H))
	game._input(_key(KEY_H))
	check(game.hint_level == 3 and game.status_label.text.contains("3 / 3"), "confirming shows the final hint")
	# --- end-of-night summary only when every map has a record
	var last = Catalog.last_id()
	var route = "RURRDLDDLLRRRUULULLDRURDUlDRRUL"
	state.selected_builtin = last
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	game = current_scene
	for c in route:
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c.to_upper()], c == c.to_lower())
	check(game.level_complete and not game.finale_panel.visible, "summary hidden while other maps are unfinished")
	for id in Catalog.ORDER:
		Progress.record(id, Catalog.optimal(id))
	game.undo_move()
	game.try_move(Vector2i.LEFT)
	check(game.finale_panel.visible and game.finale_label.text.contains("全部归位") and game.finale_label.text.contains("★ %d / %d" % [Catalog.COUNT, Catalog.COUNT]), "summary shows when all maps are done, with star count")
	check(game.finale_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and game.next_button.has_focus(), "summary never steals focus from the Enter action")
	game.undo_move()
	check(not game.finale_panel.visible, "undo hides the summary")
	print("V79 product suite: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("V79 PRODUCT SUITE PASSED")
	quit(1 if failures else 0)
