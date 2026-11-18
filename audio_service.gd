extends Node
## Original synthesized effects; no recordings, samples or third-party music.
signal muted_changed(value: bool)
signal volume_changed(value: float)
## V7.11: mute and volume are remembered between sessions (user://settings.cfg, mirrored on Web).
const SETTINGS_PATH = "user://settings.cfg"
const Mirror = preload("res://web_mirror.gd")
## Measured with the synthesized effects: peaks -4..-6 dBFS, so at the default (0.7) the loudest
## effect peaks near -22 dBFS. Volume 1.0 is +3 dB over the old fixed level; never above it.
const DEFAULT_VOLUME = 0.7
const BASE_DB = -16.0
var volume = DEFAULT_VOLUME
var muted = false
var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var next_voice = 0
var played_count = 0
var last_sound = ""
var shutting_down = false

func _ready() -> void:
	for effect in ["push", "goal", "win"]:
		streams[effect] = _synthesize(effect)
	for i in range(4):
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	load_settings()

func load_settings() -> void:
	var cfg = ConfigFile.new()
	var ok = cfg.load(SETTINGS_PATH) == OK
	if not ok and Mirror.available() and Mirror.has_text(SETTINGS_PATH):
		ok = cfg.parse(Mirror.get_text(SETTINGS_PATH)) == OK
	var v = cfg.get_value("audio", "volume", DEFAULT_VOLUME) if ok else DEFAULT_VOLUME
	volume = clampf(float(v), 0.0, 1.0) if (v is float or v is int) else DEFAULT_VOLUME
	var m = cfg.get_value("audio", "muted", false) if ok else false
	muted = m if m is bool else false
	_apply_volume()

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "volume", snappedf(volume, 0.01))
	cfg.set_value("audio", "muted", muted)
	if cfg.save(SETTINGS_PATH) == OK and Mirror.available():
		Mirror.set_text(SETTINGS_PATH, FileAccess.get_file_as_string(SETTINGS_PATH))

## 0 = silent, DEFAULT_VOLUME = the original fixed -16 dB, 1.0 = about +3 dB.
func volume_db_for(value: float) -> float:
	if value <= 0.001:
		return -80.0
	return BASE_DB + linear_to_db(value / DEFAULT_VOLUME)

func _apply_volume() -> void:
	for player in players:
		player.volume_db = volume_db_for(volume)

func set_volume(value: float, persist: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	if persist:
		save_settings()
	volume_changed.emit(volume)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()

func toggle_mute() -> void:
	set_muted(not muted)

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for player in players:
			player.stop()
	save_settings()
	muted_changed.emit(muted)

func label_text() -> String:
	# Interaction pass A: the label is the state only; the M hint sits with the other key hints
	# ("M：切换音效"), so it is not read as a switch for every sound. M still toggles effects only.
	return "音效：关" if muted else "音效：开"

func play_effect(effect: String) -> bool:
	if shutting_down or muted or volume <= 0.001 or not streams.has(effect) or players.is_empty():
		return false
	var player = players[next_voice]
	next_voice = (next_voice + 1) % players.size()
	player.stream = streams[effect]
	player.play()
	played_count += 1
	last_sound = effect
	return true

func _synthesize(effect: String) -> AudioStreamWAV:
	var rate = 22050
	var duration = 0.11 if effect == "push" else (0.24 if effect == "goal" else 0.6)
	var count = int(duration * rate)
	var bytes = PackedByteArray()
	bytes.resize(count * 2)
	var noise = RandomNumberGenerator.new()
	noise.seed = 6812
	var filtered_noise = 0.0
	for i in range(count):
		var t = float(i) / rate
		var amplitude = 0.0
		if effect == "push":
			filtered_noise = filtered_noise * 0.8 + noise.randf_range(-1.0, 1.0) * 0.2
			amplitude = (sin(TAU * 155.0 * t) * 0.5 + filtered_noise * 0.5) * exp(-t * 40.0)
		elif effect == "goal":
			amplitude = (sin(TAU * 660.0 * t) + sin(TAU * 880.0 * t) * 0.4) * exp(-t * 13.0) * 0.42
		else:
			var note = mini(int(t / 0.16), 2)
			var frequencies = [523.25, 659.25, 783.99]
			var local_t = t - note * 0.16
			amplitude = sin(TAU * frequencies[note] * local_t) * exp(-local_t * 12.0) * 0.5
		# Short attack and final fade avoid discontinuity clicks.
		amplitude *= minf(t / 0.004, 1.0) * minf((duration - t) / 0.015, 1.0)
		bytes.encode_s16(i * 2, int(clampf(amplitude, -0.8, 0.8) * 32767.0))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

## Release active playback before the autoload leaves the tree.
func begin_shutdown() -> void:
	shutting_down = true
	for voice in players:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	players.clear()
	streams.clear()

func _exit_tree() -> void:
	begin_shutdown()
