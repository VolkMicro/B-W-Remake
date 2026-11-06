# Advisor dialogue audio and captions are read from the owner's installation.
# This plays an authentic selection conversation, not the complete story VM.
class_name OriginalDialogue
extends Node

signal line_started(speaker: String, text: String)
signal line_finished
signal sequence_finished

const Data := preload("res://scripts/data.gd")
var error := ""
var bank := SoundBank.new()
var _villager_bank := SoundBank.new()
var _villager_bank_path := ""
var captions: Dictionary = {}
var _caption_ids: Array[String] = []
var _player := AudioStreamPlayer.new()
var _queue: Array[String] = []
var _thread: Thread
var _generation := 0
var _worker_generation := -1
var _worker_id := ""
var _single_line := false


func _init() -> void:
	add_child(_player)


func configure(host_folder: String) -> bool:
	_villager_bank_path = host_folder.path_join("Audio/Dialogue/villagers.sad")
	if not bank.open(host_folder.path_join(Data.AUDIO_SOURCES["adviser_bank"]["path"])):
		error = bank.error
		return false
	var path: String = host_folder.path_join(Data.AUDIO_SOURCES["dialogue_text"]["path"])
	var raw := FileAccess.get_file_as_bytes(path)
	var text := raw.get_string_from_utf16() if raw.size() >= 2 and raw[0] == 0xff and raw[1] == 0xfe else raw.get_string_from_utf8()
	if text == "":
		error = "Original dialogue text is unavailable"
		return false
	var rx := RegEx.create_from_string('ADD_TEXT\\s*\\(\\s*1\\s*,\\s*([A-Z0-9_]+)\\s*,\\s*"([^"]+)"\\s*,\\s*"([^\"]*)"')
	captions.clear()
	_caption_ids.clear()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("ADD_TEXT("):
			continue
		var found := rx.search(line)
		if found == null:
			_caption_ids.append("")
			continue
		var id := found.get_string(2)
		_caption_ids.append(id)
		captions[id] = {"speaker":found.get_string(1),"text":found.get_string(3)}
	for id in Data.STORY_DIALOGUE:
		if not captions.has(id) or not bank.entries.has(id):
			error = "Original advisor dialogue is missing: " + id
			return false
	_player.name = "OriginalAdviserVoice"
	_player.finished.connect(_on_finished)
	return true


func play_event(event: String) -> bool:
	var rows: Array[Dictionary] = []
	for row in Data.STORY_DIALOGUE.values():
		if row["event"] == event:
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	if rows.is_empty():
		return false
	_generation += 1
	_player.stop()
	_player.stream = null
	line_finished.emit()
	_queue.clear()
	for row in rows:
		_queue.append(row["id"])
	_start_next()
	return true


func has_text_enum(text_enum: int) -> bool:
	return text_enum >= 0 and text_enum < _caption_ids.size() and _bank_for(_caption_ids[text_enum]) != null


func _bank_for(id: String) -> SoundBank:
	if bank.entries.has(id):
		return bank
	if not id.is_empty():
		if _villager_bank.entries.is_empty():
			_villager_bank.open(_villager_bank_path)
		if _villager_bank.entries.has(id):
			return _villager_bank
	return null


func play_text_enum(text_enum: int, single_line := true) -> bool:
	if not has_text_enum(text_enum):
		return false
	# RUN_TEXT appends by default. The original clears the speech queue only
	# when this line or its predecessor explicitly uses single-line mode.
	if single_line or _single_line:
		stop()
	_single_line = single_line
	_queue.append(_caption_ids[text_enum])
	_start_next()
	return true


func is_text_enum_playing(text_enum: int) -> bool:
	if text_enum < 0 or text_enum >= _caption_ids.size():
		return false
	var id := _caption_ids[text_enum]
	return _queue.has(id) or (_worker_id == id and _worker_generation == _generation and (_thread != null or _player.playing))


func stop() -> void:
	_generation += 1
	_queue.clear()
	_player.stop()
	_player.stream = null
	line_finished.emit()


func _process(_delta: float) -> void:
	if _thread != null and _thread.is_started() and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		if _worker_generation != _generation:
			_start_next()
			return
		if not result.get("ok", false):
			error = str(result.get("error", "Audio decode failed"))
			push_error("Original dialogue: " + error)
			_start_next()
			return
		var wave := AudioStreamWAV.new()
		wave.format = AudioStreamWAV.FORMAT_16_BITS
		wave.mix_rate = int(result["sample_rate"])
		wave.stereo = int(result["channels"]) == 2
		wave.data = result["pcm"]
		_player.stream = wave
		var entry: Dictionary = captions[_worker_id]
		line_started.emit(entry["speaker"], entry["text"])
		_player.play()
		print("TEST dialogue playing ", _worker_id, "; duration=", wave.get_length())


func _start_next() -> void:
	if _thread != null or _player.playing:
		return
	if _queue.is_empty():
		sequence_finished.emit()
		return
	_worker_id = _queue.pop_front()
	var source := _bank_for(_worker_id)
	var sample := source.sample(_worker_id) if source != null else {"ok": false}
	if not sample.get("ok", false):
		error = sample.get("error", "Original voice missing")
		_start_next()
		return
	if sample["format"] != "mpeg":
		error = "Unsupported advisor sound"
		_start_next()
		return
	_worker_generation = _generation
	_thread = Thread.new()
	var rc := _thread.start(MpegAudio.decode.bind(sample["payload"], MpegAudio.executable_path()))
	if rc != OK:
		error = "Could not start audio worker"
		_thread = null
		_start_next()


func _on_finished() -> void:
	line_finished.emit()
	_start_next()


func _exit_tree() -> void:
	_player.stop()
	_player.stream = null
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
