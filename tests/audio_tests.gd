extends SceneTree
var checks = 0
var failures = 0
func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var sound = root.get_node("AudioService")
	check(sound.streams.size() == 3 and sound.players.size() == 4, "three original effects and bounded voice pool")
	for name in ["push", "goal", "win"]:
		var stream: AudioStreamWAV = sound.streams[name]
		check(stream.mix_rate == 22050 and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.data.size() > 4000, "valid mono PCM " + name)
	check(not sound.play_effect("invalid"), "unknown sound is ignored")
	check(sound.play_effect("push") and sound.last_sound == "push", "unmuted plays effect")
	var before: int = sound.played_count
	sound.set_muted(true)
	check(not sound.play_effect("goal") and sound.played_count == before, "muted never starts playback")
	var stopped = true
	for player in sound.players: stopped = stopped and not player.playing
	check(stopped, "mute immediately stops all voices")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	check(sound.muted and current_scene.audio_button.text.contains("关"), "mute survives scene change and updates menu")
	sound.toggle_mute()
	check(current_scene.audio_button.text.contains("开"), "button updates from shared state")
	root.get_node("GameState").selected_builtin = 2
	change_scene_to_file("res://game.tscn")
	await process_frame
	await process_frame
	check(not sound.muted and current_scene.audio_button.text.contains("开"), "game shares sound preference")
	current_scene.try_move(Vector2i.RIGHT)
	check(sound.last_sound == "push", "push produces wooden effect")
	current_scene.try_move(Vector2i.RIGHT)
	current_scene.try_move(Vector2i.RIGHT)
	check(sound.last_sound == "goal", "nonfinal goal produces goal effect")
	for dir in [Vector2i.LEFT, Vector2i.LEFT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT]: current_scene.try_move(dir)
	check(current_scene.level_complete and sound.last_sound == "win", "final goal produces completion melody")
	before = sound.played_count
	current_scene.undo_move()
	current_scene.restart_level()
	check(sound.played_count == before, "undo and restart do not accidentally play victory")
	var event = InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	sound._input(event)
	check(sound.muted and current_scene.audio_button.text.contains("关"), "M shortcut updates current scene")
	print("AUDIO TESTS: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
