# Music is assembled in memory from original, ordered SAD segments.
# This is a provisional alignment-based player, not the original music director.
class_name OriginalMusic
extends Node

const Data := preload("res://scripts/data.gd")
const STORY_CUES := {2: "Audio/Music/align/Neutral.sad", 54: "Audio/Music/Intro/intro.sad", 61: "Audio/Music/script/Epic01.sad", 65: "Audio/Music/script/CreatureChosen.sad", 67: "Audio/Music/script/CreatureGuide.sad"}
# The cinematic recordings are quieter than the voices. Keep the original
# dynamics while making the score audible over the island ambience.
const STORY_VOLUME_DB := -10.0
var error := ""
var _host := ""
var _player := AudioStreamPlayer.new()
var _current := ""
var _requested := ""
var _requested_age := 0.0
var _failed_mode := ""
var _thread: Thread
var _worker_mode := ""
var _alignment_enabled := true
var _story_cue := 0
var _worker_cue := 0


func _init() -> void:
	add_child(_player)


func configure(host_folder: String) -> bool:
	error = ""
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
		if _story_cue == 0:
			_failed_mode = ""


func set_alignment_enabled(enabled: bool) -> void:
	_alignment_enabled = enabled
	if _story_cue == 0:
		_player.stream_paused = not enabled


func start_story_cue(cue: int) -> bool:
	if not STORY_CUES.has(cue):
		error = "Unsupported original music cue %d" % cue
		return false
	if not FileAccess.file_exists(_host.path_join(STORY_CUES[cue])):
		error = "Original music cue %d is missing: %s" % [cue, STORY_CUES[cue]]
		return false
	if _story_cue == cue:
		return true
	_player.stop()
	_current = ""
	_story_cue = cue
	_failed_mode = ""
	error = ""
	return true


func stop_story_cue() -> void:
	if _story_cue != 0:
		_player.stop()
		_story_cue = 0
		_current = ""


func _process(delta: float) -> void:
	_requested_age += delta
	if _thread != null and _thread.is_started() and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		if _worker_cue != 0 and _worker_cue == _story_cue:
			if result.get("ok", false):
				_play_result(result, true)
			else:
				_decode_failed(str(_story_cue), str(result.get("error", "Original story music could not be decoded")))
		elif _worker_cue == 0 and _story_cue == 0 and _worker_mode == _requested:
			if result.get("ok", false):
				_play_result(result)
			else:
				_decode_failed(_worker_mode, str(result.get("error", "Original music could not be decoded")))
	if _thread != null:
		return
	if _story_cue != 0:
		if _current != str(_story_cue) and _failed_mode != str(_story_cue):
			_worker_cue = _story_cue
			_thread = Thread.new()
			if _thread.start(decode_track.bind(_host.path_join(STORY_CUES[_story_cue]), "SECT", MpegAudio.executable_path(), 0)) != OK:
				_thread = null
				_decode_failed(str(_story_cue), "Could not start original story music worker")
	elif _alignment_enabled and _requested != _current and _requested != _failed_mode and _requested_age >= float(Data.MUSIC_RULES["soundtrack"]["debounce_seconds"]):
		_start_decode(_requested)


func _start_decode(mode: String) -> void:
	_worker_cue = 0
	var row: Dictionary = Data.MUSIC_MODES[mode]
	var source: Dictionary = Data.AUDIO_SOURCES[row["source"]]
	_worker_mode = mode
	_thread = Thread.new()
	var rc := _thread.start(decode_track.bind(_host.path_join(source["path"]), row["section_prefix"], MpegAudio.executable_path(), 0))
	if rc != OK:
		_thread = null
		_decode_failed(mode, "Could not start original music worker")


func _decode_failed(track: String, message: String) -> void:
	error = message
	_failed_mode = track
	push_warning("Original music %s: %s" % [track, message])


func _play_result(result: Dictionary, story := false) -> void:
	# Alignment variants can continue the island's score at the same position.
	# Scripted cues are complete musical phrases and must start at their beginning.
	var old_position := _player.get_playback_position() if not story and _player.playing else 0.0
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = int(result["sample_rate"])
	wave.stereo = int(result["channels"]) == 2
	wave.data = result["pcm"]
	if not story and bool(Data.MUSIC_RULES["soundtrack"]["loop"]):
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_begin = 0
		wave.loop_end = wave.data.size() / (2 * int(result["channels"]))
	_player.stop()
	_player.stream = wave
	_player.volume_db = STORY_VOLUME_DB if story else float(Data.MUSIC_MODES[_worker_mode]["volume_db"])
	if story and _worker_cue == 2:
		_player.volume_db = float(Data.MUSIC_MODES[Data.MUSIC_RULES["soundtrack"]["default_mode"]]["volume_db"])
	_current = str(_worker_cue) if story else _worker_mode
	error = ""
	_player.play(fposmod(old_position, maxf(wave.get_length(), 0.1)))
	_player.stream_paused = not story and not _alignment_enabled
	print("[OriginalMusic] playing %s: %d sections, %.3f seconds, %.1f dB" % [_current, int(result.get("sections", 0)), wave.get_length(), _player.volume_db])


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
