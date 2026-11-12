extends SceneTree
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(ok,message):
 checks+=1
 if not ok:
  failures+=1
  push_error(message)
 else:print("PASS ",message)
func event(code):
 var e=InputEventKey.new();e.keycode=code;e.pressed=true;return e
func run():
 var state=root.get_node("GameState")
 state.selected_builtin=7
 change_scene_to_file("res://game.tscn")
 await process_frame;await process_frame
 var game=current_scene
 check(not game.editor_end_button.visible,"editor invitation hidden before victory")
 game._input(event(KEY_E))
 check(current_scene==game,"E cannot bypass incomplete puzzle")
 for c in "URDRDRDLLUULUlDRRUL":
  game.try_move({"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}[c.to_upper()],c==c.to_lower())
 check(game.level_complete and game.editor_end_button.visible,"final win shows editor invitation")
 check(game.status_label.text.contains("灯火仍暖") and not game.status_label.text.contains("全部"),"ending warm but not falsely all-level completion")
 check(game.editor_end_button.position.y>game.next_button.position.y,"editor and menu actions occupy separate rows")
 game.undo_move()
 check(not game.editor_end_button.visible,"undo hides ending-only invitation")
 game.try_move(Vector2i.LEFT)
 game.progress_save_failed=true;game._update_status()
 check(game.status_label.text.contains("未保存"),"new ending preserves save failure warning")
 state.editor_snapshot={"walls":[[2,2]],"goals":[],"boxes":[],"player":[-1,-1],"pull_charges":0,"_dirty":true,"_slot":2,"_tool":"box"}
 game._input(event(KEY_E))
 await process_frame;await process_frame
 check(current_scene.has_method("_paint_cell"),"keyboard E enters real editor scene")
 check(current_scene.walls.has(Vector2i(2,2)) and current_scene.dirty and current_scene.save_slot==2,"ending entry preserves existing unsaved editor draft")
 check(state.preview_data.is_empty(),"ending editor entry never masquerades as preview")
 print("WORKSHOP ENDING TESTS: ",checks-failures,"/",checks)
 quit(1 if failures else 0)
