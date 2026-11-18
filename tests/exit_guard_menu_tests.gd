extends SceneTree
## MenuWarm v3: no draft, the player presses 离开工坊 (and keeps pressing / closing the window).
## Shutdown starts once, new sounds are refused, the real quit is replaced by GameState.quit_hook.
var checks := 0
var failures := 0
var quits := 0
var quit_times: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state = root.get_node("GameState")
	var au = root.get_node("AudioService")
	var music = root.get_node("MusicService")
	state.editor_snapshot = {}
	state.quit_hook = func():
		quits += 1
		quit_times.append(Time.get_ticks_msec())
	change_scene_to_file("res://main_menu.tscn")
	# Let the menu settle first: the drain is a scene-tree timer, so a press made at the end of the
	# long scene-loading frame would see that frame's delta and finish early (documented limitation).
	await create_timer(0.3).timeout
	for i in 5:
		await process_frame
	var menu = current_scene
	var leave: Button = null
	for b in menu.menu_choices.get_children():
		if b.text == "离开工坊":
			leave = b
	check(leave != null, "the menu has 离开工坊 on desktop")
	check(not au.shutting_down and au.play_effect("goal"), "before leaving, sound effects play")
	var t0 = Time.get_ticks_msec()
	leave.emit_signal("pressed")
	check(state.audio_shutdown_pending and au.shutting_down and au.players.is_empty() and au.streams.is_empty(), "离开工坊 with no draft starts the shutdown at once")
	check(not au.play_effect("push"), "sound effects are refused during the drain")
	check(music.player.stream == null, "music is released")
	check(not state.close_dialog.visible, "no draft, no dialog")
	leave.emit_signal("pressed")
	state._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	state._finish_quit()
	await create_timer(0.03).timeout
	check(quits == 0, "nothing quits before the drain ends")
	await create_timer(0.25).timeout
	check(quits == 1, "repeated presses and window-close requests still quit exactly once (%d)" % quits)
	if not quit_times.is_empty():
		check(quit_times[0] - t0 >= 90, "the quit came after the ~0.1 s drain, not at once (%d ms)" % (quit_times[0] - t0))
	print("EXIT GUARD MENU TESTS: %d/%d" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
