extends Node

var _players := {}


func _init(settings: Dictionary) -> void:
	for sound: String in ["kick", "whistle", "crowd"]:
		var player := AudioStreamPlayer.new()
		player.stream = _make(sound, settings[sound], int(settings.mix_rate))
		player.volume_db = settings[sound].volume_db
		add_child(player)
		_players[sound] = player


func _ready() -> void:
	play("crowd")
	play("whistle")


func play(sound: String) -> void:
	_players[sound].play()


static func _make(sound: String, s: Dictionary, rate: int) -> AudioStreamWAV:
	var count := int(s.seconds * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var low := 0.0
	for i in count:
		var time := float(i) / rate
		var fade: float = 1.0 - time / s.seconds
		var value := 0.0
		match sound:
			"kick":
				low = lerpf(low, rng.randf_range(-1.0, 1.0), s.brightness)
				value = (low + sin(TAU * s.tone_hz * time)) * 0.5 * fade * fade
			"whistle":
				value = sin(TAU * s.tone_hz * time + s.trill_depth * sin(TAU * s.trill_hz * time)) * minf(1.0, fade * 8.0)
			"crowd":
				low = lerpf(low, rng.randf_range(-1.0, 1.0), s.brightness)
				value = low * minf(1.0, minf(time, s.seconds - time) * 4.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	if sound == "crowd":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav
