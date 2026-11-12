extends SceneTree
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, note: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(note)
 else: print("PASS ", note)
func run() -> void:
 var state = root.get_node("GameState")
 var editor = load("res://level_editor.tscn").instantiate()
 root.add_child(editor)
 await process_frame
 var original = FileAccess.get_file_as_string("res://levels/user_custom_level.json")
 editor._paint_cell(Vector2i(1,1), "wall")
 editor._open_slots("original")
 editor._choose_slot(1)
 check(editor.selection_label.text.contains("原始草稿") and not editor.selection_label.text.contains("存档"), "original picker names original draft not save slot")
 editor._confirm_slot()
 check(editor.discard_dialog.dialog_text.contains("原始草稿 1") and not editor.discard_dialog.dialog_text.contains("存档 1"), "dirty import confirmation names actual source")
 check(editor.discard_dialog.dialog_text.contains("标准推箱规则未找到解"), "original warning scoped to tested standard rules")
 editor.discard_dialog.get_cancel_button().pressed.emit()
 await process_frame
 check(editor.walls.has(Vector2i(1,1)) and editor.dirty, "cancel original import preserves draft")
 editor._choose_slot(1)
 editor._confirm_slot()
 editor.discard_dialog.hide()
 editor._discard_confirmed()
 check(editor.status_label.text.contains("未找到解") and editor.dirty, "imported draft remains editable with caution")
 check(FileAccess.get_file_as_string("res://levels/user_custom_level.json") == original, "original source unchanged")
 editor.queue_free()
 await process_frame
 state.editor_snapshot = {}
 state.preview_data = {}
 state.selected_builtin = 7
 var game = load("res://game.tscn").instantiate()
 root.add_child(game)
 await process_frame
 check(not game._play_hint().contains("墙边") and game._play_hint().contains("观察"), "final puzzle offers rules not specific box solution")
 for c in "URDRDRDLLUULUlDRRUL":
  var direction = {"l":Vector2i.LEFT,"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}[c]
  game.try_move(direction, c == "l")
 check(game.level_complete and game.status_label.text.contains("最后一关完成"), "final level has clear ending")
 check(game.next_button.position.y == 424 and not game.return_button.visible, "single ending action fills former empty button slot")
 game.progress_save_failed = true
 game._update_status()
 check(game.status_label.text.contains("未保存"), "ending preserves save-failure warning")
 game.undo_move()
 check(not game.level_complete and game.return_button.visible, "undo restores play and normal return")
 game.queue_free()
 await process_frame
 var menu = load("res://main_menu.tscn").instantiate()
 root.add_child(menu)
 await process_frame
 var has_shift = false
 for child in menu.get_children():
  if child is Label and child.text.contains("Shift + 方向键"): has_shift = true
 check(has_shift, "main menu explains pull shortcut")
 menu.queue_free()
 await process_frame
 print("COPY REVIEW TESTS: ",checks-failures,"/",checks)
 quit(1 if failures else 0)
