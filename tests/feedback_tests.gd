extends SceneTree
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(ok, message):
 checks+=1
 if not ok:
  failures+=1
  push_error(message)
 else:print("PASS ",message)
func run():
 var state=root.get_node("GameState")
 state.selected_builtin=6
 var game=load("res://game.tscn").instantiate()
 root.add_child(game)
 await process_frame
 game.walls={Vector2i(0,0):true};game.goals={Vector2i(4,4):true};game.boxes=[Vector2i(1,1)];game.player_pos=Vector2i(2,1);game.pull_charges=0
 game.try_move(Vector2i.LEFT)
 check(game.has_permanent_corner() and game.hint_button.disabled,"proven corner disables misleading hint button")
 var e=InputEventKey.new();e.keycode=KEY_H;e.pressed=true
 game._input(e)
 check(game.hint_level==0 and game.status_label.text.contains("已无法移出"),"H during warning does not secretly advance")
 game.undo_move();game._input(e)
 check(game.hint_level==1 and not game.hint_button.disabled,"after undo next H starts at first hint")
 game.queue_free();await process_frame
 state.preview_data={"walls":[],"goals":[[3,3]],"boxes":[[0,0]],"player":[1,1],"pull_charges":0}
 game=load("res://game.tscn").instantiate();root.add_child(game);await process_frame
 check(game.preview_starts_blocked and game.status_label.text.contains("返回编辑器修改"),"starting preview deadlock recommends editing")
 game.try_move(Vector2i.RIGHT)
 check(game.status_label.text.contains("返回编辑器修改") and not game.status_label.text.contains("R 重开"),"walking does not replace initial-deadlock advice")
 game.restart_level()
 check(game.status_label.text.contains("起点"),"restart retains correct preview advice")
 game.queue_free();await process_frame
 state.preview_data={}
 var menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await process_frame
 menu._show_levels()
 var art_visible=false
 for c in menu.get_children():
  if c is Node2D and c.visible:art_visible=true
 check(art_visible and menu.selector_shade.visible,"warm background remains with shade")
 menu._hide_levels();menu._show_levels()
 check(menu.selector_shade.visible and menu.selector.visible,"repeat selector entry keeps consistent presentation")
 menu.queue_free();await process_frame
 print("FEEDBACK TESTS: ",checks-failures,"/",checks)
 quit(1 if failures else 0)
