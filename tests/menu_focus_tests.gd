extends SceneTree
const Progress = preload("res://progress_store.gd")
var checks = 0
var failures = 0
func check(value: bool, message: String) -> void:
    checks += 1
    if value: print("PASS ", message)
    else:
        failures += 1
        push_error("FAIL " + message)
func _initialize() -> void:
    call_deferred("run_tests")
func run_tests() -> void:
    change_scene_to_file("res://main_menu.tscn")
    await process_frame
    await process_frame
    var menu = current_scene
    var play = menu.menu_choices.get_child(0)
    play.grab_focus()
    menu._show_levels()
    check(not menu.audio_button.is_visible_in_tree(), "hidden mute button cannot enter selector focus chain")
    check(not menu.menu_choices.is_visible_in_tree(), "underlying menu hidden during selection")
    check(root.gui_get_focus_owner() == menu.builtin_buttons[0], "selector focuses first playable demo")
    var next = menu.builtin_buttons[0].find_next_valid_focus()
    check(menu.selector.is_ancestor_of(next), "next focus stays within selector")
    check(menu.builtin_buttons[0].text.contains("未完成"), "fresh profile shows incomplete status")
    menu._hide_levels()
    check(menu.audio_button.is_visible_in_tree(), "closing selector restores mute button")
    check(menu.menu_choices.is_visible_in_tree() and not menu.selector.visible, "closing selector restores menu")
    check(root.gui_get_focus_owner() == play, "closing selector restores Play focus")
    Progress.record(1, 3)
    menu._show_levels()
    check(menu.builtin_buttons[0].text.contains("最佳 3 步"), "opening selector refreshes best moves")
    var event = InputEventAction.new()
    event.action = "ui_cancel"
    event.pressed = true
    menu._unhandled_key_input(event)
    check(not menu.selector.visible and root.gui_get_focus_owner() == play, "Escape closes selector and restores focus")
    print("MENU FOCUS TESTS: ", checks-failures, "/", checks)
    quit(1 if failures else 0)
