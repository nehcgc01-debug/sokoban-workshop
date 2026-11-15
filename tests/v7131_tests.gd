extends SceneTree
const R = preload("res://draft_recovery.gd")
var failures = 0
var checks = 0
func _initialize(): call_deferred("run")
func check(ok, text):
 checks += 1
 if not ok:
  failures += 1
  print("FAIL ", text)
 else: print("PASS ", text)
func frames():
 await process_frame
 await process_frame
func block():
 DirAccess.make_dir_absolute(ProjectSettings.globalize_path(R.PATH + ".tmp"))
 var f = FileAccess.open(R.PATH + ".tmp/block", FileAccess.WRITE)
 f.store_string("fault injection")
 f.close()
func unblock():
 DirAccess.remove_absolute(ProjectSettings.globalize_path(R.PATH + ".tmp/block"))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(R.PATH + ".tmp"))
func run():
 var state = root.get_node("GameState")
 state.suppress_quit_for_test = true
 var d = {"walls": [[1,1]], "boxes": [], "goals": [], "player": [-1,-1], "pull_charges": 0}
 R.save_draft(d, 2)
 change_scene_to_file("res://level_editor.tscn")
 await frames()
 var e = current_scene
 check(e.draft_origin == 2, "restored origin is 2")
 state.request_quit()
 state._keep_and_quit()
 check(R.load_draft().get("_origin") == 2, "OS close keep preserves restored origin")
 check(state.quit_requested, "successful keep exits")
 state.quit_requested = false
 state.close_dialog.hide() # Simulate the confirmation signal auto-hide before next scenario.
 state.editor_snapshot = {}
 change_scene_to_file("res://main_menu.tscn")
 await frames()
 change_scene_to_file("res://level_editor.tscn")
 await frames()
 e = current_scene
 check(e.status_label.text.contains("基于存档 2"), "second restoration retains origin wording")
 block()
 e._paint_cell(Vector2i(2,2), "wall")
 check(not e.recovery_issue.is_empty(), "write failure persists flag")
 var old_error = e.recovery_issue
 check(e.status_label.text == old_error, "failure status shown")
 e._request_back()
 await frames()
 e._keep_and_leave()
 await frames()
 check(e.error_dialog.visible and not e.leave_dialog.visible, "leave failure shows only error modal")
 check(current_scene == e and e.dirty, "leave failure keeps editable draft")
 e.error_dialog.hide()
 state.request_quit()
 state._keep_and_quit()
 await frames()
 check(state.close_error.visible and not state.close_dialog.visible, "close failure shows only error modal")
 check(not state.quit_requested, "close failure never exits")
 state.close_error.hide()
 unblock()
 e._refresh_status()
 check(e.recovery_issue.is_empty(), "same-content retry clears flag")
 check(e.status_label.text != old_error, "same-content success clears stale status")
 check(not e.dirty_label.text.contains("自动保护失败"), "success clears dirty-label error")
 check(R.load_draft().walls.has([2,2]), "successful retry actually protects current map")
 state.request_quit()
 state._keep_and_quit()
 check(R.load_draft().get("_origin") == 2, "retry close still retains origin")
 # Desktop geometry must additionally be tested through real F11. These assertions
 # guard the persistence plumbing, not window-manager behaviour in headless mode.
 var source = FileAccess.get_file_as_string("res://game_state.gd")
 check(source.contains("saved_window_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())"), "fullscreen captures size and position")
 check(source.contains("DisplayServer.window_set_size(saved_window_rect.size)") and source.contains("DisplayServer.window_set_position(saved_window_rect.position)"), "fullscreen restores size and position")
 print("V7131 TESTS: %d checks, %d failures" % [checks, failures])
 if failures == 0: print("V7131 SUITE PASSED")
 quit(1 if failures else 0)
