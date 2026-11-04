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
var captions: Dictionary = {}
var _player := AudioStreamPlayer.new()
var _queue: Array[String] = []
var _thread: Thread
var _generation := 0
var _worker_generation := -1
var _worker_id := ""


func _init() -> void:
	add_child(_player)


func configure(host_folder: String) -> bool:
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
	for line in text.split("\n"):
		if not line.contains("ADD_TEXT"):
			continue
		var found := rx.search(line)
		if found == null:
			continue
		var id := found.get_string(2)
		if Data.STORY_DIALOGUE.has(id):
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


func _start_next() -> void:
	if _thread != null:
		return
	if _queue.is_empty():
		sequence_finished.emit()
		return
	_worker_id = _queue.pop_front()
	var sample := bank.sample(_worker_id)
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
