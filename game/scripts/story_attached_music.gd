extends AudioStreamPlayer3D

var _thread: Thread


func start(path: String) -> bool:
	_thread = Thread.new()
	if _thread.start(OriginalMusic.decode_track.bind(path, "SECT", MpegAudio.executable_path(), 0)) != OK:
		_thread = null
		return false
	return true


func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var decoded: Dictionary = _thread.wait_to_finish()
	_thread = null
	if not decoded.get("ok", false):
		push_warning(str(decoded.get("error", "Original chant decode failed")))
		queue_free()
		return
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = int(decoded["sample_rate"])
	wave.stereo = int(decoded["channels"]) == 2
	wave.data = decoded["pcm"]
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = wave.data.size() / (2 * int(decoded["channels"]))
	stream = wave
	play()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
