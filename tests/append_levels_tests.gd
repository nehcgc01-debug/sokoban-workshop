extends SceneTree
const Progress = preload("res://progress_store.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, message):
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
 else: print("PASS ",message)
func key(code, shift=false):
 var e = InputEventKey.new()
 e.keycode = code
 e.pressed = true
 e.shift_pressed = shift
 return e
func run():
 var state = root.get_node("GameState")
 var routes = ["RRR", "RRRLLLDRRR", "LLURDRURLU", "r", "rDLLURURRRDDLLLULD", "LRRRUULLLDLDUd", "URDRDRDLLUULUlDRRUL"]
 # Simulate an existing V7.2 record; do not renumber or clear it.
 check(Progress.record(5,18) == OK, "old level5 record writes")
 state.selected_builtin = 1
 change_scene_to_file("res://game.tscn")
 await process_frame
 await process_frame
 for i in range(7):
  var game = current_scene
  check(state.selected_builtin == i+1, "keyboard chain reaches level%d" % (i+1))
  for c in routes[i]:
   var code = {"R":KEY_RIGHT,"L":KEY_LEFT,"U":KEY_UP,"D":KEY_DOWN}[c.to_upper()]
   game._input(key(code,c == c.to_lower()))
  check(game.level_complete and game.moves == routes[i].length(), "actual gameplay solves level%d at optimum" % (i+1))
  if i>=5:
   game.undo_move()
   check(not game.level_complete, "new level undo exits victory")
   var last = routes[i][-1]
   game._input(key({"R":KEY_RIGHT,"L":KEY_LEFT,"U":KEY_UP,"D":KEY_DOWN}[last.to_upper()],last==last.to_lower()))
   check(game.level_complete, "new level final move reproducible")
  game._unhandled_input(key(KEY_ENTER))
  await process_frame
  await process_frame
 check(current_scene.has_method("_show_levels"), "level7 Enter returns menu")
 check(Progress.best_moves(5)==18, "existing level5 best preserved")
 check(Progress.best_moves(6)==14 and Progress.best_moves(7)==19, "new records saved separately")
 current_scene._show_levels()
 await process_frame
 check(current_scene.builtin_buttons.size()==7, "all seven selector buttons exist")
 var inside = true
 for b in current_scene.builtin_buttons:
  inside = inside and current_scene.selector.get_global_rect().encloses(b.get_global_rect())
 check(inside and current_scene.selector.get_global_rect().end.y<=720, "selector cards fully inside viewport")
 print("APPEND LEVELS TESTS: ",checks-failures,"/",checks)
 quit(1 if failures else 0)
