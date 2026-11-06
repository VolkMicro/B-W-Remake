extends CanvasLayer

signal playback_finished

var player := VideoStreamPlayer.new()
var status := Label.new()
var active := false
var error := ""
var _worker: Thread
var _output := ""


func start(source: String) -> bool:
	if not FileAccess.file_exists(source):
		return false
	layer = 100
	var background := ColorRect.new()
	background.color = Color.BLACK
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(player)
	player.expand = true
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.finished.connect(finish)
	add_child(status)
	status.text = "Подготовка оригинального ролика…"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cache := ProjectSettings.globalize_path("user://movie-cache")
	if DirAccess.make_dir_recursive_absolute(cache) != OK:
		return false
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false
	_output = cache.path_join("intro-%d-%d.ogv" % [FileAccess.get_modified_time(source), input.get_length()])
	active = true
	if FileAccess.file_exists(_output):
		_play()
	else:
		_worker = Thread.new()
		if _worker.start(_convert.bind(source, _output)) != OK:
			_worker = null
			active = false
			return false
	return active


func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive():
		return
	var converted: bool = _worker.wait_to_finish()
	_worker = null
	if not active:
		return
	if converted:
		_play()
	else:
		error = "Не удалось декодировать оригинальный ролик. Для Bink требуется FFmpeg в PATH."
		finish()


func _play() -> void:
	var stream := VideoStreamTheora.new()
	stream.file = _output
	player.stream = stream
	status.hide()
	player.play()
	print("TEST intro_movie playing; duration=", player.get_stream_length())
	if not player.is_playing():
		error = "Не удалось воспроизвести оригинальный ролик."
		finish()


func finish() -> void:
	if not active:
		return
	active = false
	player.stop()
	hide()
	print("TEST intro_movie finished", "" if error.is_empty() else "; error=" + error)
	playback_finished.emit()


static func _convert(source: String, destination: String) -> bool:
	var temporary := destination + ".%d.ogv" % OS.get_process_id()
	var args := PackedStringArray(["-nostdin", "-loglevel", "error", "-y", "-i", source,
		"-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libtheora", "-q:v", "8", "-c:a", "libvorbis", "-q:a", "5", temporary])
	if OS.execute("ffmpeg", args) != 0:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, destination) == OK:
		return true
	DirAccess.remove_absolute(temporary)
	return FileAccess.file_exists(destination)


func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
