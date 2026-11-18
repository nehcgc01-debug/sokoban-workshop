extends SceneTree
const Catalog = preload("res://level_catalog.gd")
const Progress = preload("res://progress_store.gd")
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
	for suffix in ["", ".bak", ".tmp"]:
		var p = Progress.PATH + suffix
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for id in ids: Progress.record(id, Catalog.optimal(id) + 2)
func run():
	var cases = [
		["fresh", [], 0, 1, "把木箱送回金色光圈。"],
		["mid", [1, 2, 3], 0, 4, "把木箱送回金色光圈。"],
		["main done", Catalog.ORDER, 0, 12, "主线已归位，休息角还有 4 张委托。"],
		["requests partly done", Catalog.ORDER + [12, 14], 0, 13, "主线已归位，休息角还有 2 张委托。"],
		["overtime optional", Catalog.ORDER + Catalog.LAB_ORDER, 1, 1, "工坊归整好了。来布置一张你自己的工单？"],
		["all content done", Catalog.ORDER + Catalog.LAB_ORDER + Catalog.LAB_EXTRA, 1, 1, "工坊归整好了。来布置一张你自己的工单？"],
	]
	var gs = root.get_node("GameState")
	for c in cases:
		seed_progress(c[1])
		gs.map_return_pending = false
		var before = FileAccess.get_file_as_bytes(Progress.PATH) if FileAccess.file_exists(Progress.PATH) else PackedByteArray()
		var menu = load("res://main_menu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		for i in 3: await process_frame
		check(root.gui_get_focus_owner() == menu.menu_choices.get_child(c[2]), c[0] + ": menu initial focus")
		var visible_copy = false
		for l in menu.get_children():
			if l is Label and l.text == c[4]: visible_copy = l.visible
		check(visible_copy, c[0] + ": state-specific invitation is actually displayed")
		menu._show_levels()
		check(root.gui_get_focus_owner() == menu._card_for(c[3]), c[0] + ": map recommendation")
		var all_enabled = true
		for b in menu.builtin_buttons + menu.lab_buttons:
			all_enabled = all_enabled and not b.disabled
		check(all_enabled, c[0] + ": free selection includes overtime")
		menu.lab_buttons[-1].grab_focus()
		menu._hide_levels()
		menu._show_levels()
		check(root.gui_get_focus_owner() == menu.lab_buttons[-1], c[0] + ": manual overtime choice is remembered")
		var after = FileAccess.get_file_as_bytes(Progress.PATH) if FileAccess.file_exists(Progress.PATH) else PackedByteArray()
		check(before == after, c[0] + ": invitations and focus never rewrite progress")
		menu.queue_free()
		await process_frame
		await process_frame
	print("BLIND PREP TESTS: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
