extends SceneTree
const Store = preload("res://level_store.gd")
var checks = 0
func _initialize(): call_deferred("run_tests")
func check(ok: bool, note: String):
 checks += 1
 if not ok:
  push_error(note)
  quit(1)
  assert(ok)
 print("PASS ",note)
func run_tests():
 var editor = load("res://level_editor.tscn").instantiate()
 root.add_child(editor)
 await process_frame
 check(editor.pull_charges == 0, "new editor defaults no ability")
 editor._set_pull_enabled(true)
 check(editor.dirty and editor._serialize().pull_charges == 1, "toggle changes draft and marks dirty")
 editor._paint_cell(Vector2i(1,1), "player")
 editor._paint_cell(Vector2i(2,1), "box")
 editor._paint_cell(Vector2i(3,1), "goal")
 editor._open_slots("save")
 editor._choose_slot(1)
 editor._confirm_slot()
 var saved = Store.load_path(Store.slot_path(1), true)
 check(saved.ok and saved.data.pull_charges == 1, "saved ability persists")
 editor._apply_data(saved.data)
 check(editor.pull_toggle.button_pressed, "load restores ability control")
 editor._snapshot()
 check(root.get_node("GameState").editor_snapshot.pull_charges == 1, "preview snapshot retains ability")
 editor._apply_data({"walls":[], "goals":[], "boxes":[], "player":[-1,-1]})
 check(editor.pull_charges == 0 and not editor.pull_toggle.button_pressed, "legacy/clear data resets ability")
 print("EDITOR PULL TESTS PASSED: ", checks)
 quit(0)
