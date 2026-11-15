extends SceneTree
## V7.11: Web save mirror (logic tested with the in-memory stand-in), share dialog, Ctrl shortcuts.
const Store = preload("res://level_store.gd")
const Progress = preload("res://progress_store.gd")
const Mirror = preload("res://web_mirror.gd")
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
func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func key(code: int, ctrl := false) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e

func run():
	Mirror.use_fake = true
	Mirror.fake.clear()

	# ---- progress: a record the browser never synced comes back from the mirror
	check(Progress.record(1, 3) == OK and Mirror.get_text(Progress.PATH).contains("1=3"), "a win is mirrored synchronously")
	check(Progress.record(2, 12) == OK, "second record")
	remove(Progress.PATH)  # simulate: tab closed before IndexedDB sync
	check(Progress.best_moves(1) == -1, "file lost (simulated unsynced write)")
	check(Progress.reconcile_mirror() == 2 and Progress.best_moves(1) == 3 and Progress.best_moves(2) == 12, "both records recovered from the mirror")
	# merge keeps the best of both and never makes a record worse
	var f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_string("[builtin]\n1=5\n2=10\n")
	f.close()
	check(Progress.reconcile_mirror() == 1 and Progress.best_moves(1) == 3 and Progress.best_moves(2) == 10, "merge takes the lower moves per level from either side")
	check(Progress.reconcile_mirror() == 0, "reconcile is idempotent")
	f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	check(Progress.reconcile_mirror() == 0 and FileAccess.get_file_as_string(Progress.PATH) == "garbage", "never overwrites an unreadable progress file")
	remove(Progress.PATH)
	Mirror.set_text(Progress.PATH, "1=3\n[builtin]\n")
	check(Progress.reconcile_mirror() == 0, "a malformed mirror is ignored")

	# ---- slots
	var p1 = Store.slot_path(1)
	var level = {"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0}
	check(Store.save_path(p1, level).is_empty() and Mirror.has_text(p1), "slot save is mirrored")
	remove(p1)
	check(Store.reconcile_mirror() == 1 and Store.load_path(p1).ok, "unsynced slot is restored from the mirror")
	check(Store.reconcile_mirror() == 0, "slot reconcile is idempotent")
	level["goals"] = [[4, 2]]
	Store.save_path(p1, level)
	f = FileAccess.open(p1, FileAccess.WRITE)
	f.store_string(JSON.stringify({"walls": [], "goals": [[3, 2]], "boxes": [[2, 2]], "player": [1, 2], "pull_charges": 0}))
	f.close()  # file holds an older version (newer save not yet synced)
	check(Store.reconcile_mirror() == 1 and Store.load_path(p1).data.goals[0] == [4, 2], "mirror (latest save) wins over a stale file")
	check(Store.set_aside(p1).is_empty() and not Mirror.has_text(p1), "clearing a slot also clears its mirror")
	check(Store.reconcile_mirror() == 0 and not FileAccess.file_exists(p1), "a cleared slot does not come back")
	Store.save_path(p1, level)
	level["goals"] = [[5, 2]]
	Store.save_path(p1, level)  # .bak holds goal 4,2
	f = FileAccess.open(p1, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	check(Store.restore_backup(p1).is_empty() and Mirror.get_text(p1) == FileAccess.get_file_as_string(p1), "restore from backup updates the mirror")
	Mirror.use_fake = false
	check(not Mirror.available(), "desktop build does not use the mirror")

	# ---- editor: Ctrl shortcuts and paste dialog
	root.get_node("GameState").editor_snapshot = {}
	change_scene_to_file("res://level_editor.tscn")
	await process_frame
	await process_frame
	var editor = current_scene
	editor._unhandled_input(key(KEY_V, true))
	check(editor.share_dialog.visible and editor.share_mode == "paste" and editor.check_job == null, "Ctrl+V opens the paste box and does not start a check")
	var code = Store.share_code(Store.load_path("res://levels/demo_9.json").data)
	editor.share_edit.text = code
	editor.share_dialog.get_ok_button().pressed.emit()
	await process_frame
	check(not editor.share_dialog.visible and Store.canonical(editor._serialize()) == Store.canonical(Store.load_path("res://levels/demo_9.json").data), "pasting into the box and confirming imports the map")
	editor._unhandled_input(key(KEY_C, true))
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		check(not editor.share_dialog.visible and editor.status_label.text.contains("KURO1-"), "Ctrl+C copies to the system clipboard")
	else:
		check(editor.share_dialog.visible and editor.share_mode == "copy" and editor.share_edit.text.begins_with("KURO1-"), "Ctrl+C without a system clipboard shows the code to copy by hand")
		editor.share_dialog.hide()
	editor._unhandled_input(key(KEY_V))
	check(editor.check_job != null, "plain V still starts the check")
	editor._cancel_check()
	editor._unhandled_input(key(KEY_P))
	check(editor.share_dialog.visible, "P opens the paste box")
	editor.share_dialog.hide()
	editor.share_edit.text = "not a code"
	editor._open_share_dialog("paste", "not a code")
	editor.share_dialog.get_ok_button().pressed.emit()
	await process_frame
	check(editor.error_dialog.visible, "a bad code in the box shows the error dialog")
	editor.error_dialog.hide()

	# ---- desktop keeps the quit button
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	var labels = []
	for b in current_scene.menu_choices.get_children():
		if b is Button: labels.append(b.text)
	check(labels.has("离开工坊"), "desktop menu keeps 离开工坊")
	# ---- audio settings persist; defaults keep the original loudness
	var sound = root.get_node("AudioService")
	check(absf(sound.volume_db_for(sound.DEFAULT_VOLUME) - (-16.0)) < 0.01 and sound.volume_db_for(1.0) < -12.0, "default volume is the original -16 dB; maximum stays below -12 dB")
	sound.set_volume(0.35)
	sound.set_muted(true)
	sound.volume = 0.9
	sound.muted = false
	sound.load_settings()
	check(absf(sound.volume - 0.35) < 0.001 and sound.muted and absf(sound.players[0].volume_db - sound.volume_db_for(0.35)) < 0.01, "volume and mute come back after a restart")
	sound.set_muted(false)
	sound.set_volume(0.0)
	check(not sound.play_effect("push"), "volume 0 plays nothing")
	var sf = FileAccess.open(sound.SETTINGS_PATH, FileAccess.WRITE)
	sf.store_string("[audio]\nvolume=\"loud\"\nmuted=3\n")
	sf.close()
	sound.load_settings()
	check(absf(sound.volume - sound.DEFAULT_VOLUME) < 0.001 and not sound.muted, "a damaged settings file falls back to defaults")
	sound.set_volume(sound.DEFAULT_VOLUME)
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	current_scene.volume_slider.value = 50
	check(absf(sound.volume - 0.5) < 0.001, "menu volume slider drives the shared volume")
	sound.set_volume(sound.DEFAULT_VOLUME)
	print("V7.11 suite: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("V711 SUITE PASSED")
	quit(1 if failures else 0)
