extends SceneTree
## Menu UI experiment: the warm workshop main menu.
## Progress-driven layers, stable controls, separated sound/music rows, button states, map and editor round trips.
const Progress = preload("res://progress_store.gd")
const Catalog = preload("res://level_catalog.gd")
var checks := 0
var failures := 0

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(note)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func clear_progress() -> void:
	for suffix in ["", ".bak", ".new", ".new.ok", ".restore", ".corrupt"]:
		var path = ProjectSettings.globalize_path(Progress.PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func seed_progress(ids: Array) -> void:
	clear_progress()
	for id in ids:
		check(Progress.record(id, 99) == OK, "seed record %d" % id)

func open_menu() -> Control:
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	return current_scene

func controls(menu: Control) -> Array:
	var out = []
	for b in menu.menu_choices.get_children():
		out.append(b)
	out.append_array([menu.audio_button, menu.volume_slider, menu.music_button, menu.music_slider])
	return out

func rects(menu: Control) -> Array:
	var out = []
	for c in controls(menu):
		out.append(c.get_global_rect())
	return out

func run() -> void:
	var stages = {
		"early": [],
		"mid": [1, 2, 3, 4, 5, 6, 12, 13],
		"full": Catalog.ORDER + [12, 13, 14, 15],
	}
	var expected = {
		"early": {"shelf_crates": 1, "floor_crates": 2, "rope": "none", "tools": 0, "tray_home": 0, "finale": false, "nook_lit": 0},
		"mid": {"shelf_crates": 3, "floor_crates": 0, "rope": "loose", "tools": 1, "tray_home": 1, "finale": false, "nook_lit": 2},
		"full": {"shelf_crates": 3, "floor_crates": 0, "rope": "hung", "tools": 5, "tray_home": 2, "finale": true, "nook_lit": 4},
	}
	var first_rects = []
	for stage in stages.keys():
		seed_progress(stages[stage])
		var bytes_before = FileAccess.get_file_as_bytes(Progress.PATH) if FileAccess.file_exists(Progress.PATH) else PackedByteArray()
		var menu = await open_menu()
		var art = menu.menu_art_node
		var state: Dictionary = art.workshop_state()
		for key in expected[stage]:
			check(state[key] == expected[stage][key], "%s: %s is %s (expected %s)" % [stage, key, str(state[key]), str(expected[stage][key])])
		# controls never move with progress
		var now = rects(menu)
		if first_rects.is_empty():
			first_rects = now
		else:
			check(now == first_rects, "%s: every menu control keeps the same position and size as at the start" % stage)
		# decorations stay out of the menu column and away from every control
		for r in art.prop_rects():
			check(not r.intersects(art.MENU_ZONE), "%s: prop %s stays out of the menu column" % [stage, str(r)])
			for c in now:
				check(not r.intersects(c), "%s: prop %s does not touch control %s" % [stage, str(r), str(c)])
		for child in menu.get_children():
			if child is Label and child.visible and not String(child.text).is_empty():
				for r in art.prop_rects():
					check(not r.intersects(child.get_global_rect()), "%s: prop %s does not cover the text '%s'" % [stage, str(r), child.text.left(12)])
		var want = menu.menu_choices.get_child(1 if stage == "full" else 0)
		check(want.has_focus() and menu.first_focus() == want, "%s: first keyboard focus is on %s" % [stage, want.text])
		for child in menu.get_children():
			if child is TextureRect and child.visible:
				var p = child.get_global_rect()
				check(not p.intersects(art.board_rect()) and not p.intersects(art.TRAY), "%s: the character %s stays clear of the board %s and its tray" % [stage, str(p), str(art.board_rect())])
				check(p.end.y <= 704.0 and p.position.x >= art.TRAY.end.x, "%s: the character stands right of the tray, above the bottom bar" % stage)

		var after = FileAccess.get_file_as_bytes(Progress.PATH) if FileAccess.file_exists(Progress.PATH) else PackedByteArray()
		check(after == bytes_before, "%s: showing the menu does not write the progress file" % stage)

	var menu = await open_menu()
	# ---- sound and music rows: separate, with a real gap, nothing overlapping
	var all = rects(menu)
	for i in all.size():
		for j in range(i + 1, all.size()):
			check(not all[i].intersects(all[j]), "controls %d and %d do not overlap" % [i, j])
	var gap = menu.music_button.get_global_rect().position.y - menu.audio_button.get_global_rect().end.y
	check(gap >= 12.0, "sound row and music row are at least 12 px apart (%.0f)" % gap)
	check(menu.audio_button.size.y == 34.0 and menu.music_button.size.y == 34.0, "toggle buttons are the stated 34 px tall")
	# Menu tidy (post-exam): the developer footer line was removed; the facilitator line keeps its spot.
	check(menu.footer_label == null, "no developer footer line on the first screen")
	check(menu.playtest_label.position.y >= menu.music_button.get_global_rect().end.y + 10, "facilitator line sits below the music row")
	check(menu.audio_button.text.contains("音效") and menu.music_button.text.contains("音乐"), "each row names what it controls")
	var AudioService = root.get_node("AudioService")
	var MusicService = root.get_node("MusicService")
	var sound_muted = AudioService.muted
	menu.music_button.emit_signal("pressed")
	check(MusicService.muted and menu.music_button.text.contains("关") and AudioService.muted == sound_muted, "music toggle updates its own label and leaves sound effects alone")
	menu.music_button.emit_signal("pressed")
	check(not MusicService.muted, "music toggles back")
	menu.music_slider.value = 20
	check(absf(MusicService.volume - 0.2) < 0.001 and absf(AudioService.volume - menu.volume_slider.value / 100.0) < 0.01, "music slider sets music volume only")

	# ---- five button states, each different in shape as well as colour
	var play: Button = menu.menu_choices.get_child(0)
	var normal = play.get_theme_stylebox("normal") as StyleBoxFlat
	var hover = play.get_theme_stylebox("hover") as StyleBoxFlat
	var pressed = play.get_theme_stylebox("pressed") as StyleBoxFlat
	var disabled = play.get_theme_stylebox("disabled") as StyleBoxFlat
	check(normal != null and hover != null and pressed != null and disabled != null, "menu buttons carry their own state styles")
	check(normal.bg_color != hover.bg_color and normal.bg_color != pressed.bg_color and disabled.bg_color != normal.bg_color, "default, hover, pressed and disabled differ")
	check(normal.border_width_bottom == 4 and pressed.border_width_bottom == 0 and pressed.content_margin_top > normal.content_margin_top, "pressed sinks: the lip disappears and the label moves down")
	check(play.get_theme_stylebox("focus") is StyleBoxEmpty and play.draw.get_connections().size() > 0, "focus is drawn by the ring + ▶ marker routine, not by a colour swap")
	check(play.get_theme_color("font_disabled_color").v < play.get_theme_color("font_color").v, "disabled text is dimmer but still drawn")

	# ---- keyboard: menu -> map -> back; music row hides with the menu and returns
	menu._show_levels()
	await frames()
	check(menu.selector.visible and not menu.music_button.is_visible_in_tree() and not menu.audio_button.is_visible_in_tree(), "map hides both audio rows")
	check(menu.builtin_buttons[0].has_focus(), "map focuses the first order")
	var card = menu.builtin_buttons[0]
	check(card.get_meta("card", false) and card.get_theme_stylebox("pressed") is StyleBoxFlat, "map cards share the state styles and keep their chapter tab")
	var esc = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await frames(3)
	check(not menu.selector.visible and menu.music_button.is_visible_in_tree() and menu.menu_choices.get_child(0).has_focus(), "Esc closes the map, restores both rows, focus back on 开始游戏")
	var slot: Button = null
	menu._show_levels()
	await frames()
	for b in menu.slot_buttons:
		if b.disabled: slot = b
	check(slot != null and slot.get_theme_stylebox("disabled") is StyleBoxFlat, "an empty save slot shows the disabled state")
	menu._hide_levels()
	await frames()

	# ---- editor entry and back
	menu.menu_choices.get_child(1).emit_signal("pressed")
	await frames(4)
	check(current_scene.scene_file_path == "res://level_editor.tscn", "关卡编辑器 opens the editor")
	change_scene_to_file("res://main_menu.tscn")
	await frames(3)
	check(current_scene.first_focus().has_focus(), "back on the menu, the first focus rule applies again (%s)" % current_scene.first_focus().text)

	# ---- the rest nook keeps the lab-2/3 contract
	seed_progress([12])
	menu = await open_menu()
	check(menu.menu_art_node.corner_title().contains("委托 1 / 4") and not menu.menu_art_node.corner_title().contains("实验") and menu.menu_art_node.corner_done() == 1, "rest nook still counts lab requests separately")
	check(FileAccess.get_file_as_string("res://menu_art.gd").find("ThemeDB.fallback_font") < 0, "menu art draws with the project font")

	clear_progress()
	print("MENUWARM TESTS: %d/%d" % [checks - failures, checks])
	if failures == 0:
		print("MENUWARM SUITE PASSED")
	quit(1 if failures > 0 else 0)
