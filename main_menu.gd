extends Control
const Store = preload("res://level_store.gd")
const Progress = preload("res://progress_store.gd")
const Catalog = preload("res://level_catalog.gd")
var menu_choices: VBoxContainer
var builtin_buttons: Array[Button] = []
var menu_art_node: Node2D
var lab_buttons: Array[Button] = []   # Lab: T1-T3 and the control map, in Catalog.LAB_ORDER
const CHAPTER_COLORS = {"入门篇": Color("57c9b0"), "牵引篇": Color("f3bc66"), "挑战篇": Color("e08a52"), "工具篇 · 实验": Color("ef7a6c"), "对照 · 实验": Color("a9b4a4")}
var selector: PanelContainer
var notice: AcceptDialog
var recovery: ConfirmationDialog
var recovery_slot = 0
var restore_button: Button
var draft_dialog: ConfirmationDialog
const Playtest = preload("res://playtest_log.gd")
const DraftRecovery = preload("res://draft_recovery.gd")
var playtest_label: Label
var volume_slider: HSlider
var draft_slot = 0
var draft_data: Dictionary = {}
var slot_buttons: Array[Button] = []
var audio_button: Button
var selector_shade: ColorRect
var hidden_menu_items: Array[CanvasItem] = []

func _ready() -> void:
	GameState.preview_data = {}
	var progress_problem = Progress.check_integrity()
	# Lab 4: finish or undo a record write that was interrupted last time.
	var recovered_note = Progress.recover(progress_problem.contains("另存为"))
	if not recovered_note.is_empty():
		progress_problem = (progress_problem.replace("记录将从头开始。", "") + "\n" + recovered_note).strip_edges() if not progress_problem.is_empty() else recovered_note
	# V7.11: on Web, bring back saves the browser had not synced before the tab closed.
	var restored = Progress.reconcile_mirror()
	Store.reconcile_mirror()
	if restored > 0 and not progress_problem.is_empty():
		progress_problem += "\n已从浏览器的同步备份中恢复 %d 条记录。" % restored
	_build_menu()
	# V7.9: keyboard players can press Enter right away.
	menu_choices.get_child(0).call_deferred("grab_focus")
	if not progress_problem.is_empty():
		notice.title = "通关记录"
		notice.dialog_text = progress_problem
		notice.call_deferred("popup_centered")

func label(text_value: String, size: int, color: Color = Color("f2dfbd")) -> Label:
	var item = Label.new()
	item.text = text_value
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	return item

func button(text_value: String, action: Callable, height: int = 50) -> Button:
	var item = Button.new()
	item.text = text_value
	item.custom_minimum_size = Vector2(0, height)
	item.pressed.connect(action)
	return item

func _build_menu() -> void:
	var art = Node2D.new()
	art.set_script(preload("res://menu_art.gd"))
	add_child(art)
	menu_art_node = art
	# V7.7: the menu follows the night's progress (situation, not story).
	var done = 0
	for id in Catalog.ORDER:
		if Progress.best_moves(id) >= 0:
			done += 1
	var eyebrow_text = "灯火未熄 · 今晚的主线工单 %d / %d" % [done, Catalog.COUNT]
	if done >= Catalog.COUNT:
		eyebrow_text = "灯火仍暖 · 今晚 %d 张主线工单全部归位" % Catalog.COUNT
	var eyebrow = label(eyebrow_text, 17, Color("bfa983") if done < Catalog.COUNT else Color("f3bc66"))
	eyebrow.position = Vector2(78, 80)
	add_child(eyebrow)
	var title = label("推箱工坊", 62, Color("f3dfb5"))
	title.position = Vector2(72, 112)
	add_child(title)
	# Lab: this build is an experiment with its own save folder; say so where everyone looks first.
	var badge = PanelContainer.new()
	var bstyle = StyleBoxFlat.new()
	bstyle.bg_color = Color("ef7a6c")
	bstyle.set_corner_radius_all(9)
	bstyle.content_margin_left = 10
	bstyle.content_margin_right = 10
	bstyle.content_margin_top = 2
	bstyle.content_margin_bottom = 3
	badge.add_theme_stylebox_override("panel", bstyle)
	badge.add_child(label("实验版 3 · 工具箱与休息角", 16, Color("2a1e18")))
	badge.position = Vector2(338, 136)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	var subtitle = label("把木箱送回金色光圈。" if done < Catalog.COUNT else "工坊归整好了。来布置一张你自己的工单？", 24, Color("9bb6a9"))
	subtitle.position = Vector2(80, 206)
	add_child(subtitle)
	var choices = VBoxContainer.new()
	menu_choices = choices
	choices.position = Vector2(80, 280)
	choices.size = Vector2(340, 240)
	choices.add_theme_constant_override("separation", 15)
	add_child(choices)
	choices.add_child(button("开始游戏", _show_levels, 64))
	# V7.12: a kept draft is visible from the menu, so the promise "next time it comes back" is discoverable.
	choices.add_child(button("关卡编辑器 · 有未保存草稿" if DraftRecovery.has_draft() else "关卡编辑器", _open_editor, 58))
	# V7.11: a browser tab cannot be closed by the game, so Web builds have no quit button.
	if not OS.has_feature("web"):
		choices.add_child(button("离开工坊", func(): GameState.request_quit(), 48))
	var note = label("方向键 / WASD 移动 · Z 撤销 · R 重开" + ("" if OS.has_feature("web") else " · F11 全屏") + "\nShift + 方向键：牵引关卡中拉箱", 17, Color("8ca497"))
	note.position = Vector2(80, 540)
	add_child(note)
	if ResourceLoader.exists("res://art/player.png"):
		var portrait = TextureRect.new()
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		portrait.texture = load("res://art/player.png")
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.position = Vector2(960, 400)
		portrait.size = Vector2(150, 230)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait)
	var feature = label("一推一拉，让工坊慢慢归整。", 22, Color("edcc94"))
	feature.position = Vector2(555, 620)
	add_child(feature)
	var footer = label("%d 张主线工单 + %d 张实验委托  /  牵引与工具箱  /  关卡创作" % [Catalog.COUNT, Catalog.LAB_ORDER.size()], 16, Color("899d8e"))
	footer.position = Vector2(80, 660)
	add_child(footer)
	# V7.11: facilitator-only indicator; players never see it unless the log was turned on.
	playtest_label = label("", 15, Color("e0a070"))
	playtest_label.position = Vector2(80, 686)
	add_child(playtest_label)
	_refresh_playtest_label()
	audio_button = button(AudioService.label_text(), AudioService.toggle_mute, 38)
	audio_button.position = Vector2(80, 604)
	audio_button.size = Vector2(174, 38)
	audio_button.add_theme_font_size_override("font_size", 16)
	add_child(audio_button)
	AudioService.muted_changed.connect(func(_muted: bool): audio_button.text = AudioService.label_text())
	# V7.11: remembered volume; dragging plays a short sample so the level can be judged.
	var vol_label = label("音量", 16, Color("899d8e"))
	vol_label.position = Vector2(270, 612)
	add_child(vol_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.value = round(AudioService.volume * 100)
	volume_slider.position = Vector2(312, 614)
	volume_slider.size = Vector2(140, 24)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(func(_changed): AudioService.play_effect("goal"))
	_style_slider(volume_slider)
	add_child(volume_slider)
	_build_selector()
	notice = AcceptDialog.new()
	notice.title = "暂时无法进入"
	notice.ok_button_text = "知道了"
	notice.min_size = Vector2i(480, 160)
	add_child(notice)
	recovery = ConfirmationDialog.new()
	recovery.title = "存档无法读取"
	recovery.min_size = Vector2i(520, 180)
	recovery.ok_button_text = "清空此存档位"
	recovery.cancel_button_text = "取消"
	restore_button = recovery.add_button("从备份恢复", true, "restore")
	recovery.confirmed.connect(_recover_slot.bind("clear"))
	recovery.custom_action.connect(func(action): recovery.hide(); _recover_slot(action))
	add_child(recovery)
	draft_dialog = ConfirmationDialog.new()
	draft_dialog.title = "未完成的草稿"
	draft_dialog.ok_button_text = "回编辑器继续"
	draft_dialog.cancel_button_text = "取消"
	draft_dialog.min_size = Vector2i(480, 160)
	draft_dialog.confirmed.connect(_open_draft)
	add_child(draft_dialog)

func _build_selector() -> void:
	selector_shade = ColorRect.new()
	selector_shade.color = Color(0.08, 0.06, 0.04, 0.28)
	selector_shade.size = Vector2(1152, 720)
	selector_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector_shade.hide()
	add_child(selector_shade)
	selector = PanelContainer.new()
	selector.position = Vector2(80, 145)
	selector.size = Vector2(980, 550)
	selector.visible = false
	add_child(selector)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	selector.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.add_child(label("工坊地图", 27))
	var legend = label("★ = 达到最优步数 · 方向键选择 · Enter 开始 · Esc 返回", 16, Color("b6ad95"))
	legend.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(legend)
	column.add_child(head)
	# Lab: one row per chapter, a coloured tab on every card, so the night's structure is visible.
	var rows = [["入门篇", []], ["牵引篇", []], ["挑战篇", []], ["工具篇 · 实验", []]]
	for id in Catalog.ORDER:
		for r in rows:
			if r[0] == Catalog.chapter(id): r[1].append(id)
	rows[3][1] = Catalog.LAB_ORDER + Catalog.LAB_EXTRA
	for r in rows:
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var tag = label(r[0].replace(" · 实验", "\n实验"), 16, CHAPTER_COLORS.get(r[0], Color("f2dfbd")))
		tag.custom_minimum_size = Vector2(96, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(tag)
		var grid = GridContainer.new()
		grid.columns = 5
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		line.add_child(grid)
		for id in r[1]:
			var b = button(Catalog.display_name(id), _play_builtin.bind(id), 54)
			b.add_theme_font_size_override("font_size", 16)
			b.custom_minimum_size.x = 160
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var tab = CHAPTER_COLORS.get(Catalog.chapter(id), Color("f2dfbd"))
			b.add_theme_stylebox_override("normal", _card_style(Color("2f3a30"), tab))
			b.add_theme_stylebox_override("hover", _card_style(Color("3d4b3d"), tab))
			grid.add_child(b)
			if Catalog.is_lab(id):
				lab_buttons.append(b)
			else:
				builtin_buttons.append(b)   # chapters follow ORDER, so this stays in play order
		column.add_child(line)
	column.add_child(label("我的作品  ·  三个创作存档", 19, Color("f3b462")))
	var custom = HBoxContainer.new()
	custom.add_theme_constant_override("separation", 12)
	column.add_child(custom)
	for index in range(1, 4):
		var b = button("存档 %d" % index, _play_slot.bind(index), 50)
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom.add_child(b)
		slot_buttons.append(b)
	column.add_child(label("空存档可以在「关卡编辑器」中创建。", 16, Color("b6ad95")))
	column.add_child(button("返回主菜单", _hide_levels, 44))

func _card_style(bg: Color, tab: Color) -> StyleBoxFlat:
	var st = StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = tab
	st.border_width_left = 6
	st.set_corner_radius_all(8)
	st.content_margin_left = 14
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st

func _all_cards(node: Node) -> Array:
	var out = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_all_cards(child))
	return out

func _show_levels() -> void:
	var lab_ids = Catalog.LAB_ORDER + Catalog.LAB_EXTRA
	for i in lab_ids.size():
		var id = lab_ids[i]
		var best = Progress.best_moves(id)
		var optimal = Catalog.optimal(id)
		lab_buttons[i].text = Catalog.display_name(id) + ("\n最佳 %d · 最优 %d" % [best, optimal] + (" ★" if best <= optimal else "") if best >= 0 else "\n未完成 · 最优 %d" % optimal)
	for i in Catalog.ORDER.size():
		var id = Catalog.ORDER[i]
		var best = Progress.best_moves(id)
		var optimal = Catalog.optimal(id)
		var record = "\n未完成 · 最优 %d" % optimal
		if best >= 0:
			record = "\n最佳 %d 步 · 最优 %d" % [best, optimal] + (" ★" if best <= optimal else "")
		builtin_buttons[i].text = Catalog.display_name(id) + record
	for index in range(1, 4):
		var b = slot_buttons[index - 1]
		var path = Store.slot_path(index)
		b.disabled = not FileAccess.file_exists(path)
		b.text = "存档 %d（空）" % index if b.disabled else "存档 %d" % index
		if not b.disabled:
			var result = Store.load_path(path)
			b.text = _slot_text(index, result, path)
	hidden_menu_items.clear()
	for child in get_children():
		if child is Control and not child is TextureRect and child != selector and child != selector_shade and child.visible:
			hidden_menu_items.append(child)
			child.hide()
	selector_shade.show()	
	selector.show()
	menu_art_node.corner_visible = false
	builtin_buttons[0].grab_focus()

func _hide_levels() -> void:
	menu_art_node.corner_visible = true
	selector.hide()
	selector_shade.hide()
	for item in hidden_menu_items:
		item.show()
	hidden_menu_items.clear()
	menu_choices.show()
	audio_button.show()
	menu_choices.get_child(0).grab_focus()

func _play_builtin(index: int) -> void:
	_start("res://levels/demo_%d.json" % index, index, 1)

func _play_slot(index: int) -> void:
	_start(Store.slot_path(index), 0, index)

func _start(path: String, builtin: int, slot: int) -> void:
	var result = Store.load_path(path)
	if not result.ok and slot > 0 and builtin == 0:
		var draft = Store.load_path(path, false)
		if draft.ok:
			# V7.10: a readable but unfinished draft is not a broken file.
			draft_slot = slot
			draft_data = draft.data
			draft_dialog.dialog_text = "存档 %d 是还没完成的草稿：%s\n回到关卡编辑器继续完善？" % [slot, result.error]
			draft_dialog.popup_centered()
			return
	if not result.ok:
		if slot > 0 and builtin == 0:
			# V7.9: offer real recovery instead of pointing to the editor (which cannot open it either).
			recovery_slot = slot
			var has_backup = Store.backup_usable(path)
			restore_button.visible = has_backup
			recovery.dialog_text = result.error + "\n" + ("可以恢复上一次保存的版本，或清空这个存档位。" if has_backup else "没有可用的备份。可以清空这个存档位重新创作。") + "\n原文件会另存为 .corrupt，不会被删除。"
			recovery.popup_centered()
			# Never leave Enter on the destructive choice.
			# Deferred: the dialog focuses its OK button while it opens.
			(restore_button if has_backup else recovery.get_cancel_button()).call_deferred("grab_focus")
			return
		notice.title = "暂时无法进入"
		notice.dialog_text = result.error
		notice.popup_centered()
		return
	GameState.preview_data = {}
	GameState.selected_builtin = builtin
	GameState.selected_slot = slot
	get_tree().change_scene_to_file("res://game.tscn")

func _slot_text(index: int, loaded: Dictionary, path: String) -> String:
	if loaded.ok:
		return "存档 %d · 游玩" % index + (" · ✓已验证" if Store.is_verified(loaded.data) else " · 未验证")
	return "存档 %d · 草稿未完成" % index if Store.load_path(path, false).ok else "存档 %d · 文件损坏" % index

func _open_draft() -> void:
	var snapshot = draft_data.duplicate(true)
	snapshot["_dirty"] = false
	snapshot["_slot"] = draft_slot
	snapshot["_tool"] = "wall"
	GameState.editor_snapshot = snapshot
	GameState.preview_data = {}
	get_tree().change_scene_to_file("res://level_editor.tscn")

func _recover_slot(action: String) -> void:
	var path = Store.slot_path(recovery_slot)
	var problem = Store.restore_backup(path) if action == "restore" else Store.set_aside(path)
	notice.title = "存档"
	notice.dialog_text = problem if not problem.is_empty() else ("已从备份恢复存档 %d。" % recovery_slot if action == "restore" else "存档 %d 已清空，原文件另存为 .corrupt。" % recovery_slot)
	notice.popup_centered()
	_refresh_slots()

func _refresh_slots() -> void:
	for index in range(1, 4):
		var b = slot_buttons[index - 1]
		var path = Store.slot_path(index)
		b.disabled = not FileAccess.file_exists(path)
		b.text = "存档 %d（空）" % index if b.disabled else "存档 %d" % index
		if not b.disabled:
			var loaded = Store.load_path(path)
			b.text = _slot_text(index, loaded, path)

func _open_editor() -> void:
	get_tree().change_scene_to_file("res://level_editor.tscn")

func _on_volume_changed(value: float) -> void:
	AudioService.set_volume(value / 100.0)

func _refresh_playtest_label() -> void:
	playtest_label.text = "● 试玩记录中 · 已记录 %d 次尝试 · Ctrl+Shift+E 导出 · Ctrl+Shift+P 关闭" % Playtest.attempt_count() if Playtest.enabled() else ""

func _toggle_playtest() -> void:
	Playtest.set_enabled(not Playtest.enabled())
	_refresh_playtest_label()
	notice.title = "试玩记录"
	notice.dialog_text = "试玩记录已开启。每次进入关卡都会记录用时、步数、撤销、提示等，只保存在本机。\n盲测结束后在主菜单按 Ctrl+Shift+E 导出。" if Playtest.enabled() else "试玩记录已关闭（已记录的数据保留）。"
	notice.popup_centered()

func _export_playtest() -> void:
	notice.title = "导出试玩记录"
	if Playtest.attempt_count() == 0:
		notice.dialog_text = "还没有试玩记录。"
	else:
		var where = Playtest.export_copy()
		notice.dialog_text = ("已导出 %d 次尝试：\n%s" % [Playtest.attempt_count(), where]) if not where.is_empty() else "导出失败，请检查磁盘权限。"
	notice.popup_centered()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.shift_pressed:
		if event.keycode == KEY_P:
			_toggle_playtest()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E:
			_export_playtest()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and selector.visible:
		_hide_levels()
		get_viewport().set_input_as_handled()

## V7.12: the volume slider uses the workshop palette instead of Godot's default grey.
func _style_slider(s: HSlider) -> void:
	var track = StyleBoxFlat.new()
	track.bg_color = Color("1d2621")
	track.border_color = Color("4a5a4c")
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var filled = StyleBoxFlat.new()
	filled.bg_color = Color("6f8f6a")
	filled.set_corner_radius_all(4)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	var filled_hot = filled.duplicate()
	filled_hot.bg_color = Color("8fae86")
	var focus = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.88, 0.73, 0.43, 1)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(6)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled_hot)
	s.add_theme_stylebox_override("focus", focus)
	s.add_theme_icon_override("grabber", _dot_texture(Color("e0ba6e"), Color("5b4a2c")))
	s.add_theme_icon_override("grabber_highlight", _dot_texture(Color("f2d391"), Color("5b4a2c")))

func _dot_texture(fill: Color, rim: Color) -> Texture2D:
	var n = 16
	var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c = Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var d = Vector2(x, y).distance_to(c)
			if d <= 6.0:
				img.set_pixel(x, y, fill)
			elif d <= 7.3:
				img.set_pixel(x, y, rim.lerp(Color(rim, 0.0), clampf(d - 6.6, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
