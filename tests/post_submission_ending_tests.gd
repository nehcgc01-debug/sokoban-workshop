extends SceneTree
const Catalog = preload("res://level_catalog.gd")
const Progress = preload("res://progress_store.gd")
const ROUTE = "RURRDLDDLLRRRUULULLDRURDUlDRRUL"
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, note):
	checks += 1
	if ok: print("PASS ", note)
	else:
		failures += 1
		push_error(note)
func seed_progress(ids):
	for suffix in ["", ".bak", ".tmp", ".new", ".new.ok"]:
		var p = Progress.PATH + suffix
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for id in ids: Progress.record(id, Catalog.optimal(id) + 2)
func run():
	var expected = OS.get_environment("KURO_EXPECTED_USER_DIR").replace("\\", "/").simplify_path()
	var actual = OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if expected.is_empty() or actual.to_lower() != expected.to_lower():
		push_error("Refusing write tests without verified isolated user directory")
		quit(2)
		return
	print("ISOLATED_USER_DIR=", actual)
	var gs = root.get_node("GameState")
	var cases = [["requests remaining", Catalog.ORDER + [12,14], 2, 0, 13],
		["requests complete; overtime absent", Catalog.ORDER + Catalog.LAB_ORDER, 0, 1, 1],
		["all content complete", Catalog.ORDER + Catalog.LAB_ORDER + Catalog.LAB_EXTRA, 0, 1, 1]]
	for c in cases:
		var existing = c[1].duplicate()
		existing.erase(11)
		seed_progress(existing)
		gs.selected_builtin = 11
		gs.map_return_pending = false
		change_scene_to_file("res://game.tscn")
		for i in 3: await process_frame
		var game = current_scene
		check(not game.finale_panel.visible, c[0] + ": no ending before win")
		for move in ROUTE:
			game.try_move({"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}[move.to_upper()], move == move.to_lower())
		check(game.level_complete and game.finale_panel.visible, c[0] + ": actual level 11 route reaches summary")
		if c[2] > 0:
			check(game.finale_label.text.contains("还有 2 张委托") and game.finale_label.text.contains("Enter / N"), c[0] + ": ending invites menu and remaining requests")
			check(not game.finale_label.text.contains("按 E 打开"), c[0] + ": editor is not the primary summary invitation")
		else:
			check(game.finale_label.text.contains("按 E") and game.finale_label.text.contains("重玩"), c[0] + ": ending invites creation or replay")
			check(not game.finale_label.text.contains("还有"), c[0] + ": no false remaining request")
		check(game.editor_end_button.visible, c[0] + ": secondary editor access remains")
		game.undo_move()
		check(not game.finale_panel.visible and not game.editor_end_button.visible, c[0] + ": undo removes ending invitation")
		game.try_move(Vector2i.LEFT)
		game.progress_save_failed = true
		game._update_status()
		check(not game.finale_panel.visible and game.status_label.text.contains("未保存"), c[0] + ": failed save keeps warning and hides summary")
		game.progress_save_failed = false
		game._update_status()
		game.leave_game()
		for i in 3: await process_frame
		var menu = current_scene
		check(root.gui_get_focus_owner() == menu.menu_choices.get_child(c[3]), c[0] + ": returned menu invitation agrees")
		menu._show_levels()
		check(root.gui_get_focus_owner() == menu._card_for(c[4]), c[0] + ": selection recommends expected request or replay")
		var all_enabled = true
		for b in menu.builtin_buttons + menu.lab_buttons: all_enabled = all_enabled and not b.disabled
		check(all_enabled, c[0] + ": all cards remain freely selectable")
		check(Progress.best_moves(16) < 0 if c[0].contains("overtime absent") else true, c[0] + ": overtime is not required")
	print("POST SUBMISSION ENDING TESTS: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
