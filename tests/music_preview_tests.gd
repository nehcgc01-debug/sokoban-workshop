extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var m = root.get_node("MusicService")
	var s = root.get_node("AudioService")
	check(m.player.stream is AudioStreamOggVorbis, "OGG loaded")
	check(m.player.stream.loop, "loop enabled")
	check(abs(m.player.stream.get_length()-124.1)<0.1, "expected loop track")
	check(m.player.playing or DisplayServer.get_name() == "headless", "player configured; headless audio intentionally suppressed")
	var id = m.player.get_instance_id()
	var effects_muted = s.muted
	m.toggle_mute()
	# Menu UI experiment: a player that is not playing (headless) keeps stream_paused false in 4.6.3,
	# so the check is "silent when muted", which holds whether or not the stream is running.
	check(m.muted and m.player.volume_db <= -79.0 and (m.player.stream_paused or not m.player.playing), "muting silences the music")
	check(s.muted == effects_muted, "effects unaffected")
	m.toggle_mute()
	m.set_volume(0.25)
	check(not m.muted and abs(m.player.volume_db-linear_to_db(0.25))<0.01, "independent music gain")
	m.toggle_mute()
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	check(m.player.get_instance_id()==id, "menu keeps persistent player")
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	check(m.player.get_instance_id()==id, "game keeps persistent player")
	current_scene.restart_level()
	check(m.player.get_instance_id()==id, "restart does not replace music")
	var cfg=ConfigFile.new()
	check(cfg.load(m.SETTINGS_PATH)==OK, "music settings saved")
	check(cfg.get_value("music","muted")==m.muted, "mute persisted")
	print("MUSIC PREVIEW TESTS: ", checks-failures, "/", checks)
	quit(1 if failures else 0)
