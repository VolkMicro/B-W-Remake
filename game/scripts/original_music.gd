# Music is assembled in memory from original, ordered SAD segments.
# This is a provisional alignment-based player, not the original music director.
class_name OriginalMusic
extends Node

const Data := preload("res://scripts/data.gd")
var error := ""
var _host := ""
var _player := AudioStreamPlayer.new()
var _current := ""
var _requested := ""
var _requested_age := 0.0
var _failed_mode := ""
var _thread: Thread
var _worker_mode := ""


func _init() -> void:
	add_child(_player)


func configure(host_folder: String) -> bool:
	_host = host_folder
	var rules: Dictionary = Data.MUSIC_RULES["soundtrack"]
	for mode in Data.MUSIC_MODES.values():
		var source: Dictionary = Data.AUDIO_SOURCES[mode["source"]]
		if not FileAccess.file_exists(_host.path_join(source["path"])):
			error = "Original music bank is missing"
			return false
	if not FileAccess.file_exists(MpegAudio.executable_path()):
		error = "Audio decoder is unavailable"
		return false
	_requested = rules["default_mode"]
	_requested_age = float(rules["debounce_seconds"])
	_player.name = "OriginalIslandMusic"
	return true


func set_alignment(alignment: float) -> void:
	var rules: Dictionary = Data.MUSIC_RULES["soundtrack"]
	var good: String = rules["good_mode"]
	var evil: String = rules["evil_mode"]
	var next: String = rules["default_mode"]
	if alignment >= float(Data.MUSIC_MODES[good]["min_alignment"]):
		next = good
	elif alignment <= float(Data.MUSIC_MODES[evil]["max_alignment"]):
		next = evil
	if next != _requested:
		_requested = next
		_requested_age = 0.0
		_failed_mode = ""


func _process(delta: float) -> void:
	_requested_age += delta
	if _thread != null and _thread.is_started() and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		if _worker_mode == _requested:
			if result.get("ok", false):
				_play_result(result)
			else:
				error = str(result.get("error", "Original music could not be decoded"))
				_failed_mode = _worker_mode
	if _thread == null and _requested != _current and _requested != _failed_mode and _requested_age >= float(Data.MUSIC_RULES["soundtrack"]["debounce_seconds"]):
		_start_decode(_requested)


func _start_decode(mode: String) -> void:
	var row: Dictionary = Data.MUSIC_MODES[mode]
	var source: Dictionary = Data.AUDIO_SOURCES[row["source"]]
	_worker_mode = mode
	_thread = Thread.new()
	var rc := _thread.start(decode_track.bind(_host.path_join(source["path"]), row["section_prefix"], MpegAudio.executable_path(), 0))
	if rc != OK:
		error = "Could not start original music worker"
		_thread = null
		_failed_mode = mode


func _play_result(result: Dictionary) -> void:
	var old_position := _player.get_playback_position() if _player.playing else 0.0
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = int(result["sample_rate"])
	wave.stereo = int(result["channels"]) == 2
	wave.data = result["pcm"]
	if bool(Data.MUSIC_RULES["soundtrack"]["loop"]):
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_begin = 0
		wave.loop_end = wave.data.size() / (2 * int(result["channels"]))
	_player.stop()
	_player.stream = wave
	_player.volume_db = float(Data.MUSIC_MODES[_worker_mode]["volume_db"])
	_current = _worker_mode
	_player.play(fposmod(old_position, maxf(wave.get_length(), 0.1)))


static func decode_track(path: String, prefix: String, decoder: String, limit: int) -> Dictionary:
	var bank := SoundBank.new()
	if not bank.open(path):
		return {"ok":false,"error":bank.error}
	var names: Array[String] = []
	for key in bank.entries:
		if key.begins_with(prefix):
			names.append(key)
	names.sort()
	var max_sections: int = Data.MUSIC_RULES["soundtrack"]["max_sections"]
	if names.is_empty() or names.size() > max_sections:
		return {"ok":false,"error":"Invalid original music section count"}
	if limit > 0:
		names.resize(mini(limit, names.size()))
	var compressed := PackedByteArray()
	for name in names:
		var section := bank.sample(name)
		if not section.get("ok", false) or section.get("format", "") != "mpeg":
			return {"ok":false,"error":"Original music section could not be read"}
		var bytes: PackedByteArray = section["payload"]
		if compressed.size() + bytes.size() > int(Data.AUDIO_DECODER["mpeg"]["input_limit_bytes"]):
			return {"ok":false,"error":"Original music exceeds decoder limit"}
		compressed.append_array(bytes)
	var result := MpegAudio.decode(compressed, decoder)
	result["sections"] = names.size()
	return result


func _exit_tree() -> void:
	_player.stop()
	_player.stream = null
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
