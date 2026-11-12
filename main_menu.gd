extends Control
const Store = preload("res://level_store.gd")
const Progress = preload("res://progress_store.gd")
const Catalog = preload("res://level_catalog.gd")
const LEVEL_NAMES = Catalog.NAMES
var menu_choices: VBoxContainer
var builtin_buttons: Array[Button] = []
var selector: PanelContainer
var notice: AcceptDialog
var slot_buttons: Array[Button] = []
var audio_button: Button
var selector_shade: ColorRect
var hidden_menu_items: Array[CanvasItem] = []

func _ready() -> void:
	GameState.preview_data = {}
	_build_menu()

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
	var eyebrow = label("灯火未熄 · 今晚的归位工作", 17, Color("bfa983"))
	eyebrow.position = Vector2(78, 80)
	add_child(eyebrow)
	var title = label("推箱工坊", 62, Color("f3dfb5"))
	title.position = Vector2(72, 112)
	add_child(title)
	var subtitle = label("把木箱送回金色光圈。", 24, Color("9bb6a9"))
	subtitle.position = Vector2(80, 206)
	add_child(subtitle)
	var choices = VBoxContainer.new()
	menu_choices = choices
	choices.position = Vector2(80, 280)
	choices.size = Vector2(340, 240)
	choices.add_theme_constant_override("separation", 15)
	add_child(choices)
	choices.add_child(button("开始归位 · 选择关卡", _show_levels, 64))
	choices.add_child(button("布置工坊 · 关卡编辑器", _open_editor, 58))
	choices.add_child(button("离开工坊", func(): get_tree().quit(), 48))
	var note = label("方向键 / WASD 移动 · Z 撤销 · R 重开\nShift + 方向键：牵引关卡中拉箱", 17, Color("8ca497"))
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
	var footer = label("%d 道小谜题  /  一次牵引  /  关卡创作" % Catalog.COUNT, 16, Color("899d8e"))
	footer.position = Vector2(80, 660)
	add_child(footer)
	audio_button = button(AudioService.label_text(), AudioService.toggle_mute, 38)
	audio_button.position = Vector2(80, 604)
	audio_button.size = Vector2(174, 38)
	audio_button.add_theme_font_size_override("font_size", 16)
	add_child(audio_button)
	AudioService.muted_changed.connect(func(_muted: bool): audio_button.text = AudioService.label_text())
	_build_selector()
	notice = AcceptDialog.new()
	notice.title = "暂时无法进入"
	notice.min_size = Vector2i(480, 160)
	add_child(notice)

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
	column.add_child(label("工坊地图", 27))
	column.add_child(label("01–05 入门篇  ·  06–07 挑战篇", 19, Color("66e1cf")))
	var builtins = GridContainer.new()
	builtins.columns = 3
	builtins.add_theme_constant_override("h_separation", 12)
	builtins.add_theme_constant_override("v_separation", 10)
	column.add_child(builtins)
	var names = LEVEL_NAMES
	for index in range(1, Catalog.COUNT + 1):
		var b = button(names[index - 1], _play_builtin.bind(index), 52)
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		builtins.add_child(b)
		builtin_buttons.append(b)
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
	column.add_child(label("空存档可以到「设计自己的关卡」中创建。", 16, Color("b6ad95")))
	column.add_child(button("返回主菜单", _hide_levels, 44))

func _show_levels() -> void:
	for index in range(1, Catalog.COUNT + 1):
		var best = Progress.best_moves(index)
		builtin_buttons[index - 1].text = LEVEL_NAMES[index - 1] + ("\n已完成 · 最佳 %d 步" % best if best >= 0 else "\n未完成")
	for index in range(1, 4):
		var b = slot_buttons[index - 1]
		var path = Store.slot_path(index)
		b.disabled = not FileAccess.file_exists(path)
		b.text = "存档 %d（空）" % index if b.disabled else "存档 %d" % index
		if not b.disabled:
			var result = Store.load_path(path)
			b.text = "存档 %d · 待修正" % index if not result.ok else "存档 %d · 游玩" % index
	hidden_menu_items.clear()
	for child in get_children():
		if child is Control and not child is TextureRect and child != selector and child != selector_shade and child.visible:
			hidden_menu_items.append(child)
			child.hide()
	selector_shade.show()	
	selector.show()
	builtin_buttons[0].grab_focus()

func _hide_levels() -> void:
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
	if not result.ok:
		notice.dialog_text = result.error + "\n请在关卡编辑器检查此地图。"
		notice.popup_centered()
		return
	GameState.preview_data = {}
	GameState.selected_builtin = builtin
	GameState.selected_slot = slot
	get_tree().change_scene_to_file("res://game.tscn")

func _open_editor() -> void:
	get_tree().change_scene_to_file("res://level_editor.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and selector.visible:
		_hide_levels()
		get_viewport().set_input_as_handled()
