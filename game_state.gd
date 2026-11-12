extends Node

var selected_slot = 1
var selected_builtin = 1
var preview_data: Dictionary = {}
var editor_snapshot: Dictionary = {}

# V7.8: fonts/NotoSansCJK-Regular.ttc holds 10 faces; Godot uses face 0 (Noto Sans CJK JP) by
# default, which draws Japanese glyph forms for some Simplified Chinese characters (e.g. 关, 骨, 直).
# Wrap the shared project theme font in a FontVariation that selects face 2 (Noto Sans CJK SC).
# The font file itself is unchanged.
const SC_FACE_INDEX = 2
var ui_font_face = ""

func _init() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or theme.default_font == null:
		return
	var base: Font = theme.default_font
	if base is FontVariation:
		base = (base as FontVariation).base_font
	if base == null or base.get_face_count() <= SC_FACE_INDEX:
		return
	var sc := FontVariation.new()
	sc.base_font = base
	sc.variation_face_index = SC_FACE_INDEX
	theme.default_font = sc
	ui_font_face = sc.get_font_name()

func selected_path() -> String:
	if selected_builtin > 0:
		return "res://levels/demo_%d.json" % selected_builtin
	return "user://custom_level.json" if selected_slot == 1 else "user://custom_level_%d.json" % selected_slot
