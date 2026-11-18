extends ConfirmationDialog
## Destructive confirmation requires an explicit choice after each opening.
## A carried/repeated accept key must never activate the engine's default OK.
var keyboard_choice_made := false
func _ready() -> void:
	about_to_popup.connect(_prepare_safe_focus)
func _prepare_safe_focus() -> void:
	keyboard_choice_made = false
	get_cancel_button().grab_focus()
	_focus_cancel.call_deferred()
func _focus_cancel() -> void:
	if visible and not keyboard_choice_made:
		get_cancel_button().grab_focus()
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	if event.is_action_pressed("ui_accept"):
		if event.echo:
			set_input_as_handled()
			return
		if not keyboard_choice_made:
			set_input_as_handled()
			hide()
			canceled.emit()
	elif event.is_pressed() and not event.echo and (event.is_action("ui_focus_next") or event.is_action("ui_focus_prev") or event.is_action("ui_left") or event.is_action("ui_right") or event.is_action("ui_up") or event.is_action("ui_down")):
		keyboard_choice_made = true