extends SceneTree
const Recovery=preload("res://draft_recovery.gd")
var checks=0
func _initialize(): call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:
		push_error(label)
		quit(1)
		assert(ok,label)
	print("PASS ",label)
func run():
	var state=root.get_node("GameState")
	state.suppress_quit_for_test=true
	Recovery.clear()
	state.editor_snapshot={}
	var e=load("res://level_editor.tscn").instantiate()
	root.add_child(e);current_scene=e
	await process_frame
	check(not auto_accept_quit,"OS close is intercepted")
	check(e.dirty_label.text.contains("新建未保存"),"blank editor does not claim disk save")
	e._paint_cell(Vector2i(1,1),"wall")
	check(Recovery.load_draft().walls==[[1,1]],"editing persists independent recovery draft")
	check(not FileAccess.file_exists("user://custom_level.json"),"autosave does not touch numbered slots")
	state._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(state.close_dialog.visible and not state.quit_requested,"window close with dirty draft asks first")
	check(e._modal_open(),"close prompt blocks editor input")
	state.request_quit()
	check(state.close_dialog.visible and not state.quit_requested,"repeated close stays safe")
	state.close_dialog.hide();state.close_dialog.canceled.emit()
	check(e.dirty and not state.quit_requested,"cancel keeps draft and process")
	state._keep_and_quit()
	check(state.quit_requested and Recovery.load_draft().walls==[[1,1]],"keep-and-exit saves recovery before quit")
	state.quit_requested=false
	current_scene=null;e.queue_free();await process_frame
	state.editor_snapshot={}
	e=load("res://level_editor.tscn").instantiate();root.add_child(e);current_scene=e;await process_frame
	check(e.walls.has(Vector2i(1,1)) and e.dirty,"fresh editor restores recoverable draft")
	check(e.status_label.text.contains("已恢复"),"recovery is disclosed")
	e._paint_cell(Vector2i(2,1),"box");e._paint_cell(Vector2i(3,1),"goal");e._paint_cell(Vector2i(4,1),"player")
	e._snapshot()
	current_scene=null;e.queue_free();await process_frame
	state.request_quit()
	check(state.close_dialog.visible and not state.quit_requested,"preview/menu snapshot remains protected")
	state.close_dialog.hide()
	state._close_action("discard")
	check(state.quit_requested and Recovery.load_draft().is_empty(),"explicit discard clears recovery")
	state.quit_requested=false;state.editor_snapshot={}
	e=load("res://level_editor.tscn").instantiate();root.add_child(e);current_scene=e;await process_frame
	check(e.walls.is_empty() and not e.dirty,"discarded draft does not reappear")
	e._paint_cell(Vector2i(3,3),"wall")
	# Use a nonempty directory at the fixed temporary path to inject a write failure.
	var temp=Recovery.PATH+".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp))
	var f=FileAccess.open(temp+"/block",FileAccess.WRITE);f.store_string("x");f.close()
	e._paint_cell(Vector2i(4,3),"wall")
	state._keep_and_quit()
	check(not state.quit_requested and state.close_error.visible,"failed recovery write never quits")
	check(e.walls.has(Vector2i(4,3)),"failed write leaves in-memory map intact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp+"/block"));DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	state.close_error.hide()
	state._keep_and_quit()
	check(state.quit_requested and Recovery.load_draft().walls.size()==2,"retry after write failure recovers latest map")
	state.quit_requested=false
	e.pending_slot=2;e.pending_data=e._serialize();e._save_pending()
	check(not e.dirty and Recovery.load_draft().is_empty(),"named save clears recovery")
	check(e.dirty_label.text.contains("存档 2 已保存"),"named save has truthful status")
	state.request_quit()
	check(state.quit_requested,"clean editor closes without unnecessary prompt")
	state.quit_requested=false
	e._paint_cell(Vector2i(5,3),"wall")
	e.share_dialog.hide();e._open_share_dialog("copy","KURO0-example")
	check(e.share_edit.text=="KURO0-example" and e.share_note.text.contains("未能确认"),"manual copy fallback exposes complete code without false success")
	current_scene=null;e.queue_free();await process_frame
	print("CLOSE DRAFT TESTS: ",checks,"/",checks)
	quit()
