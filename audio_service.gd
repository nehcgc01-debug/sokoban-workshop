extends Node
## Original synthesized effects; no recordings, samples or third-party music.
signal muted_changed(value: bool)
var muted = false
var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var next_voice = 0
var played_count = 0
var last_sound = ""

func _ready() -> void:
	for effect in ["push", "goal", "win"]:
		streams[effect] = _synthesize(effect)
	for i in range(4):
		var player = AudioStreamPlayer.new()
		player.volume_db = -16.0
		add_child(player)
		players.append(player)

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
	muted_changed.emit(muted)

func label_text() -> String:
	return "音效：关  M" if muted else "音效：开  M"

func play_effect(effect: String) -> bool:
	if muted or not streams.has(effect) or players.is_empty():
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
