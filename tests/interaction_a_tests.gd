extends SceneTree
# Interaction pass A: visible slider focus, value read-out, state label vs. M hint.
# Keys go through the root viewport (real routing), not straight into a control.
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok, note):
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func press(code, shift := false):
	for down in [true, false]:
		var e = InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		e.shift_pressed = shift
		root.push_input(e)
		await process_frame
func run():
	var audio = root.get_node("AudioService")
	var music = root.get_node("MusicService")
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 3: await process_frame
	var art = menu.menu_art_node
	# --- labels: state only, hint elsewhere
	check(audio.label_text() == "音效：开" and menu.audio_button.text == "音效：开", "sound button shows the state only")
	var note_found = false
	for child in menu.get_children():
		if child is Label and child.text.contains("M：切换音效"):
			note_found = true
	check(note_found, "menu key hints carry 'M：切换音效'")
	var music_was = music.muted
	await press(KEY_M)
	check(audio.muted and menu.audio_button.text == "音效：关", "M mutes sound effects and the label follows")
	check(music.muted == music_was and menu.music_button.text == music.label_text(), "M does not touch music")
	await press(KEY_M)
	check(not audio.muted and menu.audio_button.text == "音效：开", "M turns sound effects back on")
	# --- percent read-outs
	check(menu.volume_percent.text == "%d%%" % int(menu.volume_slider.value), "sound row shows its percent")
	check(menu.music_percent.text == "%d%%" % int(menu.music_slider.value), "music row shows its percent")
	# --- rings stay in the menu column and clear of the neighbours
	for s in [menu.volume_slider, menu.music_slider]:
		var ring = menu.slider_focus_rect(s).grow(3)
		check(art.MENU_ZONE.encloses(ring), "focus ring stays inside the menu column")
		check(not ring.intersects(menu.audio_button.get_global_rect()) and not ring.intersects(menu.music_button.get_global_rect()), "focus ring clears the toggle buttons")
	check(not menu.slider_focus_rect(menu.volume_slider).grow(3).intersects(menu.slider_focus_rect(menu.music_slider).grow(3)), "the two rings never touch")
	check(menu.volume_percent.get_global_rect().end.x <= art.MENU_ZONE.end.x and menu.volume_percent.get_global_rect().position.x >= menu.volume_slider.get_global_rect().end.x, "percent sits right of the slider, inside the column")
	# --- Tab reaches the sliders in order
	var first = menu.first_focus()
	first.grab_focus()
	await process_frame
	var order = []
	for i in 7:
		await press(KEY_TAB)
		order.append(root.gui_get_focus_owner())
	check(order[3] == menu.volume_slider and order[5] == menu.music_slider, "Tab reaches sound slider 4th and music slider 6th")
	check(order[2] == menu.audio_button or order[2] is Button, "the toggle comes right before its slider")
	check(order[6] == first, "Tab wraps back to the first button")
	# --- focus state on the sound slider
	menu.volume_slider.grab_focus()
	await process_frame
	check(menu.volume_percent.get_theme_color("font_color") == menu.FOCUS_GOLD, "focused slider: percent turns gold")
	check(menu.music_percent.get_theme_color("font_color") == menu.SLIDER_TEXT, "the other row stays quiet")
	var before = menu.volume_slider.value
	await press(KEY_RIGHT)
	check(menu.volume_slider.value == before + 5 and root.gui_get_focus_owner() == menu.volume_slider, "Right raises the value by one step and keeps focus")
	check(menu.volume_percent.text == "%d%%" % int(before + 5), "percent follows the key")
	await press(KEY_LEFT)
	await press(KEY_LEFT)
	check(menu.volume_slider.value == before - 5, "Left lowers the value")
	var cfg = ConfigFile.new()
	cfg.load("user://settings.cfg")
	check(absf(float(cfg.get_value("audio", "volume", -1.0)) - (before - 5) / 100.0) < 0.001, "sound volume is saved")
	# --- music slider
	await press(KEY_TAB)
	await press(KEY_TAB)
	check(root.gui_get_focus_owner() == menu.music_slider, "Tab, Tab moves on to the music slider")
	check(menu.volume_percent.get_theme_color("font_color") == menu.SLIDER_TEXT and menu.music_percent.get_theme_color("font_color") == menu.FOCUS_GOLD, "focus marker moved with it")
	var mbefore = menu.music_slider.value
	var sound_now = menu.volume_slider.value
	await press(KEY_RIGHT)
	check(menu.music_slider.value == mbefore + 5 and menu.volume_slider.value == sound_now, "Right changes music only")
	cfg = ConfigFile.new()
	cfg.load("user://music_settings.cfg")
	check(absf(float(cfg.get_value("music", "volume", -1.0)) - (mbefore + 5) / 100.0) < 0.001, "music volume is saved")
	await press(KEY_TAB)
	check(menu.music_percent.get_theme_color("font_color") == menu.SLIDER_TEXT, "leaving the slider clears its marker")
	# --- Shift+Tab walks back
	await press(KEY_TAB, true)
	check(root.gui_get_focus_owner() == menu.music_slider, "Shift+Tab returns to the music slider")
	menu.queue_free()
	await process_frame
	# --- in a level: same state label, hint in the shortcut row
	var gs = root.get_node("GameState")
	gs.preview_data = {}
	gs.selected_builtin = 1
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	for i in 3: await process_frame
	check(game.audio_button.text == "音效：开", "level: sound button shows the state only")
	check(game.shortcuts_label.text.contains("M 切换音效"), "level: shortcut row carries the M hint")
	await press(KEY_M)
	check(game.audio_button.text == "音效：关" and music.muted == music_was, "level: M mutes effects only")
	await press(KEY_M)
	print("INTERACTION A TESTS: %d/%d" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
