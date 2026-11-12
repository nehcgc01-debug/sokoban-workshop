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
 state.preview_data = {}
 state.selected_builtin = 4
 var game = load("res://game.tscn").instantiate()
 root.add_child(game)
 await process_frame
 check(game.pull_charges == 1 and game._play_hint().contains("Shift"), "initial pull instruction available")
 check(game.try_move(Vector2i.UP), "ordinary step succeeds")
 check(game.pull_charges == 1 and game._play_hint().contains("还剩 1 次") and not game._play_hint().contains("已用过"), "ordinary movement never claims pull spent")
 check(not game.try_move(Vector2i.RIGHT, true), "invalid pull rejected")
 check(game.pull_charges == 1 and not game._play_hint().contains("已用过"), "failed pull keeps available tutorial")
 game.undo_move()
 check(game.pull_charges == 1 and game._play_hint().contains("按住 Shift"), "undo restores initial positional hint")
 check(game.try_move(Vector2i.RIGHT, true), "valid pull succeeds")
 check(game.pull_charges == 0 and game._play_hint().contains("已用过"), "only actual consumption shows spent hint")
 game.undo_move()
 check(game.pull_charges == 1 and not game._play_hint().contains("已用过"), "undo spent pull restores available hint")
 game.restart_level()
 check(game.pull_charges == 1 and game._play_hint().contains("按住 Shift"), "restart restores tutorial")
 game.queue_free()
 await process_frame
 print("TUTORIAL STATE TESTS: ", checks-failures, "/", checks)
 quit(1 if failures else 0)
