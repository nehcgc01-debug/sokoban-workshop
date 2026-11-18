extends Node
## One persistent music player, independent of the existing synthesized effects.
signal changed
const SETTINGS_PATH = "user://music_settings.cfg"
const Mirror = preload("res://web_mirror.gd")
var volume := 0.35
var muted := false
var player: AudioStreamPlayer

func _ready() -> void:
	var cfg = ConfigFile.new()
	var ok = cfg.load(SETTINGS_PATH) == OK
	if not ok and Mirror.available() and Mirror.has_text(SETTINGS_PATH):
		ok = cfg.parse(Mirror.get_text(SETTINGS_PATH)) == OK
	if ok:
		var v = cfg.get_value("music", "volume", 0.35)
		if v is float or v is int:
			volume = clampf(float(v), 0.0, 1.0)
		var m = cfg.get_value("music", "muted", false)
		if m is bool:
			muted = m
	player = AudioStreamPlayer.new()
	add_child(player)
	var stream = load("res://music/forget_me_not_in_f_major_looped.ogg") as AudioStreamOggVorbis
	stream.loop = true
	player.stream = stream
	_apply()
	# Avoid a known OGG playback teardown leak in headless Dummy-audio tests.
	if DisplayServer.get_name() != "headless":
		player.play()
		_apply()

func _apply() -> void:
	# Menu UI experiment: muting also drops the gain, because Godot ignores stream_paused on a player
	# that is not playing yet (seen on 4.6.3 headless); silence must not depend on play order.
	player.volume_db = -80.0 if muted or volume <= 0.001 else linear_to_db(volume)
	player.stream_paused = muted

func _save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("music", "volume", volume)
	cfg.set_value("music", "muted", muted)
	if cfg.save(SETTINGS_PATH) == OK and Mirror.available():
		Mirror.set_text(SETTINGS_PATH, FileAccess.get_file_as_string(SETTINGS_PATH))

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply()
	_save()
	changed.emit()

func toggle_mute() -> void:
	muted = not muted
	_apply()
	_save()
	changed.emit()

func label_text() -> String:
	return "音乐：关" if muted else "音乐：开"

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
