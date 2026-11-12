extends SceneTree
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, message):
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
 else: print("PASS ",message)
func run():
 var state = root.get_node("GameState")
 state.selected_builtin = 6
 var game = load("res://game.tscn").instantiate()
 root.add_child(game)
 await process_frame
 check(game.hint_level==0 and not game._play_hint().contains("上方箱子"), "challenge defaults to unspoiled rules")
 check(game.title_label.text.contains("挑战篇") and game.hint_button.visible,"challenge chapter and optional button visible")
 var h = InputEventKey.new()
 h.keycode=KEY_H; h.pressed=true
 game._input(h)
 check(game.hint_level==1 and game.moves==0,"H requests first hint without moving")
 game.hint_button.pressed.emit()
 check(game.hint_level==2,"hint button requests second hint")
 game.restart_level()
 check(game.hint_level==2,"restart preserves requested hints")
 game.request_hint();game.request_hint()
 check(game.hint_level==3,"hint depth capped at three")
 for c in "LRRRUULLLDLDU":
  game.try_move({"R":Vector2i.RIGHT,"L":Vector2i.LEFT,"U":Vector2i.UP,"D":Vector2i.DOWN}[c])
 check(not game.has_permanent_corner() and game.pull_charges==1,"A deliberate corner never falsely warned while pull remains")
 game.try_move(Vector2i.DOWN,true)
 check(game.level_complete and not game.hint_button.visible,"hint does not cover final action")
 var before=game.hint_level
 game.request_hint()
 check(game.hint_level==before,"hint ignored after victory")
 game.restart_level()
 game.walls={Vector2i(1,0):true,Vector2i(0,1):true}
 game.boxes=[Vector2i(1,1)];game.goals={Vector2i(4,4):true};game.pull_charges=0
 check(game.has_permanent_corner(),"fixed wall corner proves deadlock")
 game.goals[Vector2i(1,1)]=true
 check(not game.has_permanent_corner(),"goal corners excluded")
 game.goals.clear();game.walls.clear();game.boxes=[Vector2i(0,0)]
 check(game.has_permanent_corner(),"board boundary corner detected")
 game.boxes=[Vector2i(2,0)]
 check(not game.has_permanent_corner(),"straight boundary is not corner")
 game.boxes=[Vector2i(2,2),Vector2i(1,2),Vector2i(2,1)]
 check(not game.has_permanent_corner(),"movable neighboring boxes not permanent geometry")
 game.boxes=[Vector2i(0,0)];game.pull_charges=1
 check(not game.has_permanent_corner(),"any remaining pull suppresses warning")
 game.walls={Vector2i(0,0):true};game.goals={Vector2i(4,4):true};game.boxes=[Vector2i(1,1)];game.player_pos=Vector2i(2,1);game.pull_charges=0;game.level_complete=false;game.history.clear()
 game.try_move(Vector2i.LEFT)
 check(game.status_label.text.contains("已无法移出"),"push into proven corner shows warning")
 game.undo_move()
 check(not game.status_label.text.contains("已无法移出"),"undo clears stale corner warning")
 game.is_preview=true;game.hint_level=0
 game.request_hint()
 check(game.hint_level==0,"editor preview never receives built-in hints")
 game.is_preview=false;state.selected_builtin=2
 game.request_hint()
 check(game.hint_level==0,"other builtins never receive challenge hints")
 game.queue_free()
 await process_frame
 var menu=load("res://main_menu.tscn").instantiate()
 root.add_child(menu)
 await process_frame
 menu._show_levels()
 var no_background=true
 for c in menu.get_children():
  if c is Label and c.visible:no_background=false
 check(no_background,"selector hides overlapping menu labels")
 menu._hide_levels()
 check(menu.menu_choices.visible and menu.audio_button.visible,"menu restored on selector close")
 menu.queue_free()
 await process_frame
 print("GUIDANCE TESTS: ",checks-failures,"/",checks)
 quit(1 if failures else 0)
