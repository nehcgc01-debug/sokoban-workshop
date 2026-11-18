extends SceneTree
## MenuWarm v3: the shutdown drain only starts after a confirmed exit, and repeated close requests
## during the drain neither re-ask about the draft nor quit twice. Draft path (editor with changes).
## The final quit is replaced by GameState.quit_hook so the suite can observe it.
const Recovery = preload("res://draft_recovery.gd")
var checks := 0
var failures := 0
var quits := 0
var quit_at := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)

func _initialize() -> void:
	call_deferred("run")

func audio_alive(au) -> bool:
	return not au.shutting_down and not au.players.is_empty() and au.streams.size() == 3

func run() -> void:
	var state = root.get_node("GameState")
	var au = root.get_node("AudioService")
	var music = root.get_node("MusicService")
	state.quit_hook = func():
		quits += 1
		quit_at = Time.get_ticks_msec()
	Recovery.clear()
	state.editor_snapshot = {}
	var e = load("res://level_editor.tscn").instantiate()
	root.add_child(e)
	current_scene = e
	await process_frame
	e._paint_cell(Vector2i(1, 1), "wall")

	# 1. asking to close with a draft only opens the dialog
	state.request_quit()
	check(state.close_dialog.visible and audio_alive(au) and not state.audio_shutdown_pending, "close request with a draft asks first and leaves audio alone")
	# 2. cancel
	state.close_dialog.hide()
	state.close_dialog.canceled.emit()
	await create_timer(0.15).timeout
	check(audio_alive(au) and au.play_effect("push") and quits == 0 and music.player.stream != null, "cancel keeps sound effects and music, nothing quits")

	# 3. keep fails (blocked temp path): no shutdown, no quit
	var temp = Recovery.PATH + ".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp))
	var f = FileAccess.open(temp + "/block", FileAccess.WRITE)
	f.store_string("x")
	f.close()
	state._keep_and_quit()
	await create_timer(0.15).timeout
	check(state.close_error.visible and audio_alive(au) and quits == 0 and not state.audio_shutdown_pending, "a failed keep shows the error and leaves audio running")
	state.close_error.hide()

	# 4. discard fails the same way: no shutdown, no quit
	state.request_quit()
	state.close_dialog.hide()
	state._close_action("discard")
	await create_timer(0.15).timeout
	check(state.close_error.visible and audio_alive(au) and quits == 0, "a failed discard shows the error and leaves audio running")
	state.close_error.hide()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp + "/block"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

	# 5. keep succeeds: shutdown starts once; repeated requests inside the drain are ignored
	var t0 = Time.get_ticks_msec()
	state._keep_and_quit()
	check(state.audio_shutdown_pending and au.shutting_down and not au.play_effect("push"), "confirmed keep starts the shutdown and refuses new sound effects")
	check(music.player.stream == null and not music.player.playing, "music is stopped and released")
	check(Recovery.load_draft().walls == [[1, 1]], "the draft was saved before the shutdown began")
	state.request_quit()
	state._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	check(not state.close_dialog.visible, "a second close (Alt+F4 / title-bar ×) during the drain does not re-ask about the draft")
	await create_timer(0.05).timeout
	state.request_quit()
	await create_timer(0.2).timeout
	check(quits == 1, "the game quits exactly once (%d)" % quits)
	check(quit_at - t0 >= 90, "the quit came after the ~0.1 s drain, not at once (%d ms)" % (quit_at - t0))

	current_scene = null
	e.queue_free()
	await process_frame
	Recovery.clear()
	print("EXIT GUARD DRAFT TESTS: %d/%d" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
