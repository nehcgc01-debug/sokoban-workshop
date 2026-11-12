extends Node

var selected_slot = 1
var selected_builtin = 1
var preview_data: Dictionary = {}
var editor_snapshot: Dictionary = {}

func selected_path() -> String:
	if selected_builtin > 0:
		return "res://levels/demo_%d.json" % selected_builtin
	return "user://custom_level.json" if selected_slot == 1 else "user://custom_level_%d.json" % selected_slot
