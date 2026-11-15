extends SceneTree
## V7.12: window size follows the screen; F11 is a no-op where there is no real window.
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

func size_for(usable: Vector2i) -> Vector2i:
	var k = root.get_node("GameState").window_scale_for(usable)
	return Vector2i(roundi(1152 * k), roundi(720 * k))

func run():
	var state = root.get_node("GameState")
	check(size_for(Vector2i(1920, 1040)) == Vector2i(1440, 900), "1080p desktop: 1.25x (1440x900)")
	check(size_for(Vector2i(2560, 1400)) == Vector2i(1728, 1080), "1440p desktop: 1.5x")
	check(size_for(Vector2i(3840, 2100)) == Vector2i(2880, 1800), "4K desktop: 2.5x")
	var small = size_for(Vector2i(1366, 728))
	check(small.y <= 728 * 0.88 + 1 and small.x < 1152, "1366x768 laptop: shrinks to fit above the taskbar (%s)" % small)
	check(size_for(Vector2i(1280, 820)) == Vector2i(1152, 720), "a screen just above the design size keeps it")
	check(size_for(Vector2i(400, 300)).x >= 576, "never below half size")
	check(not state._real_desktop_window(), "headless run has no real window to resize")
	var e = InputEventKey.new()
	e.keycode = KEY_F11
	e.pressed = true
	var mode_before = DisplayServer.window_get_mode()
	state._input(e)
	check(DisplayServer.window_get_mode() == mode_before, "F11 does nothing without a real window")
	change_scene_to_file("res://main_menu.tscn")
	await process_frame
	await process_frame
	var menu = current_scene
	check(menu.volume_slider.has_theme_stylebox_override("slider") and menu.volume_slider.has_theme_icon_override("grabber"), "volume slider uses the workshop style")
	print("WINDOW TESTS: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("WINDOW SUITE PASSED")
	quit(1 if failures else 0)
