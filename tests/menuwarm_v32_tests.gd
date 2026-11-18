extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok, note):
	checks += 1
	if not ok:
		failures += 1
		push_error(note)
	else: print("PASS ", note)
func key(code, echo_key := false):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.echo = echo_key
	return e
func run():
	var editor = load("res://level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._paint_cell(Vector2i(1,1), "wall")
	for dialog in [editor.overwrite_dialog, editor.discard_dialog]:
		for code in [KEY_ENTER, KEY_SPACE]:
			dialog.popup_centered()
			# Before deferred default-focus correction, carried accept is already safe.
			dialog._input(key(code))
			check(not dialog.visible, "early accept cancels")
			await process_frame
			await process_frame
			editor.slot_popup.hide()
			dialog.popup_centered()
			await process_frame
			await process_frame
			check(dialog.get_cancel_button().has_focus(), "settled initial focus is Cancel")
			dialog._input(key(code, true))
			check(dialog.visible and not dialog.keyboard_choice_made, "repeat/echo is consumed without selecting destructive action")
			dialog._input(key(code))
			check(not dialog.visible, "unselected ordinary accept cancels")
			await process_frame
			await process_frame
			editor.slot_popup.hide()
		dialog.popup_centered()
		await process_frame
		dialog._input(key(KEY_TAB))
		check(dialog.keyboard_choice_made, "explicit navigation arms keyboard choice")
		dialog.get_ok_button().grab_focus()
		check(dialog.get_ok_button().has_focus() and not dialog.get_ok_button().disabled, "explicit destructive choice remains selectable")
		dialog.hide()
		await process_frame
	check(editor.dirty and editor.walls.has(Vector2i(1,1)), "safe cancellation preserves draft")
	editor.queue_free()
	await process_frame
	var game = load("res://game.gd").new()
	# Independent product expectations. Do not derive expectations from the map fields or implementation.
	var expected = {1:false,2:false,3:false,4:true,5:true,6:true,7:true,8:true,9:true,10:true,11:true,12:true,13:true,14:true,15:true,16:true}
	for id in expected:
		var result = game.Store.load_path("res://levels/demo_%d.json" % id, true)
		check(result.ok, "level %d loads" % id)
		game.initial_data = result.data
		check(game._shortcut_text().contains("Shift") == expected[id], "independent level %d Shift expectation" % id)
	var cases = [
		[{"pull_charges":0},false,"custom no pull"],
		[{"pull_charges":1},true,"custom one pull"],
		[{"pull_charges":2},true,"custom two pulls"],
		[{"pull_charges":0,"tool":[2,2],"bench":[3,2]},true,"custom initially empty tool map"],
		[{"pull_charges":0,"tool":[-1,-1]},false,"invalid sentinel is not a tool"],
	]
	for c in cases:
		game.initial_data = c[0]
		check(game._shortcut_text().contains("Shift") == c[1], c[2])
	game.initial_data = {"pull_charges":1}
	game.pull_charges = 0
	check(game._shortcut_text().contains("Shift"), "spent charge retains capability")
	game.free()
	print("MENUWARM V3.2 TESTS: ",checks-failures,"/",checks)
	quit(1 if failures else 0)
