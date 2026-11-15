extends SceneTree
## V7.9 creator loop: share codes, verified fingerprints, editor solvability check, paste import.
const Store = preload("res://level_store.gd")
const Catalog = preload("res://level_catalog.gd")
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
func demo(id: int) -> Dictionary:
	return Store.load_path("res://levels/demo_%d.json" % id).data

func wait_check(editor) -> bool:
	for i in 1200:
		await process_frame
		if editor.check_job == null:
			return true
	return false

func run():
	# --- share codes
	var all_round_trip = true
	for id in Catalog.ORDER:
		var d = demo(id)
		var parsed = Store.parse_share_code(Store.share_code(d))
		all_round_trip = all_round_trip and parsed.ok and Store.canonical(parsed.data) == Store.canonical(d)
	check(all_round_trip, "share code round-trips every built-in level exactly")
	var code = Store.share_code(demo(6))
	check(code.begins_with("KURO1-") and code.length() <= 60, "share code is short and labelled (%d chars)" % code.length())
	check(Store.parse_share_code("  " + code.to_lower() + "\n").ok, "share code tolerates case and surrounding whitespace")
	var tampered = code.substr(0, 10) + ("W" if code[10] != "W" else "O") + code.substr(11)
	check(not Store.parse_share_code(tampered).ok, "a single changed cell fails the checksum")
	check(not Store.parse_share_code("hello").ok and not Store.parse_share_code("").ok, "random text is rejected")
	var two_players = "KURO0-PPOOOOO/OOOOOOO/OOOOOOO/OOOOOOO/OOOOOOO/OOOOOOO"
	two_players += "-" + Store._checksum(two_players)
	check(not Store.parse_share_code(two_players).ok, "two player starts are rejected")
	var d1 = demo(1)
	var shuffled = d1.duplicate(true)
	shuffled.walls.reverse()
	check(Store.fingerprint(d1) == Store.fingerprint(shuffled), "fingerprint ignores list order")

	# --- verified fingerprints
	check(not Store.is_verified(d1), "fresh profile: nothing verified")
	Store.mark_verified(d1)
	check(Store.is_verified(d1) and Store.is_verified(shuffled), "verified map is recognised")
	var edited = d1.duplicate(true)
	edited.walls.append([3, 4])
	check(not Store.is_verified(edited), "any edit makes the map unverified again")

	# --- editor background check
	root.get_node("GameState").editor_snapshot = {}
	change_scene_to_file("res://level_editor.tscn")
	await process_frame
	await process_frame
	var editor = current_scene
	editor._apply_data(demo(6))
	editor._start_check()
	check(editor.check_job != null and editor.check_button.text.contains("取消"), "check runs in slices; its button turns into Cancel")
	check(await wait_check(editor) and editor.status_label.text.contains("有解") and editor.status_label.text.contains("必须用到牵引"), "map 6: solvable and needs the pull")
	check(Store.is_verified(demo(6)) and editor.check_label.text.contains("有解"), "successful check marks the map verified")
	var no_pull = demo(6)
	no_pull.pull_charges = 0
	editor._apply_data(no_pull)
	editor._start_check()
	check(await wait_check(editor) and editor.status_label.text.contains("无解"), "map 6 without pull is reported unsolvable")
	editor._apply_data(demo(1))
	editor._start_check()
	check(await wait_check(editor) and editor.status_label.text.contains("有解") and not editor.status_label.text.contains("牵引"), "classic map 1 solvable, no pull note")
	var open3 = {"walls": [], "goals": [[4, 1], [4, 3], [5, 4]], "boxes": [[2, 1], [2, 3], [3, 4]], "player": [3, 2], "pull_charges": 1}
	var t0 = Time.get_ticks_msec()
	editor._apply_data(open3)
	editor._start_check()
	var frames_seen = 0
	while editor.check_job != null and frames_seen < 3000:
		await process_frame
		frames_seen += 1
	check(editor.check_job == null and (editor.status_label.text.contains("没有得出结论") or editor.status_label.text.contains("有解")), "huge open map ends with a result or an honest 'no conclusion' (%d ms, %d frames)" % [Time.get_ticks_msec() - t0, frames_seen])
	check(frames_seen > 2, "UI kept rendering frames while the check ran")

	# --- paste import
	editor.dirty = false
	editor._import_share_code(Store.share_code(demo(7)))
	check(Store.canonical(editor._serialize()) == Store.canonical(demo(7)) and editor.dirty and editor.save_slot == 0, "pasted code loads as an unsaved draft")
	editor._import_share_code("KURO1-broken")
	check(editor.error_dialog.visible, "bad code shows an error instead of changing the map")
	editor.error_dialog.hide()

	# --- finishing a test play verifies the map
	var state = root.get_node("GameState")
	var d2 = demo(2)
	check(not Store.is_verified(d2), "map 2 not yet verified")
	state.preview_data = d2.duplicate(true)
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	var game = current_scene
	for c in "RRRLLLDRRR":
		game.try_move({"R": Vector2i.RIGHT, "L": Vector2i.LEFT, "U": Vector2i.UP, "D": Vector2i.DOWN}[c])
	check(game.level_complete and Store.is_verified(d2), "winning a test play marks the map verified")
	state.preview_data = {}
	print("Creator suite: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("CREATOR SUITE PASSED")
	quit(1 if failures else 0)
