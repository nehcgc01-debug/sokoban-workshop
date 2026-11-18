extends SceneTree
var started = 0
func _initialize():
	call_deferred("run")
func run():
	root.get_node("AudioService").play_effect("win")
	root.get_node("MusicService").player.play()
	await create_timer(0.1).timeout
	started = Time.get_ticks_msec()
	root.tree_exiting.connect(func(): print("QUIT_DRAIN_MS=", Time.get_ticks_msec() - started))
	root.get_node("GameState").request_quit()
