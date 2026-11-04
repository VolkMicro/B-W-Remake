# Invokes the bundled CC0 decoder using pipes. Never writes the game's audio
# to files. Call from a worker Thread, since pipe reads are blocking.
class_name MpegAudio
extends RefCounted

const Data := preload("res://scripts/data.gd")


static func executable_path() -> String:
	var file: String = Data.AUDIO_DECODER["mpeg"]["executable"]
	var beside_game := OS.get_executable_path().get_base_dir().path_join(file)
	if FileAccess.file_exists(beside_game):
		return beside_game
	return ProjectSettings.globalize_path("res://bin/" + file)


static func decode(payload: PackedByteArray, executable := "") -> Dictionary:
	var cfg: Dictionary = Data.AUDIO_DECODER["mpeg"]
	if payload.is_empty() or payload.size() > int(cfg["input_limit_bytes"]):
		return {"ok":false,"error":"Invalid compressed audio size"}
	var path := executable if executable != "" else executable_path()
	if not FileAccess.file_exists(path):
		return {"ok":false,"error":"Audio decoder is unavailable"}
	var process := OS.execute_with_pipe(path, PackedStringArray(), true)
	if process.is_empty():
		return {"ok":false,"error":"Could not start audio decoder"}
	var pipe: FileAccess = process["stdio"]
	pipe.store_32(payload.size())
	pipe.store_buffer(payload)
	pipe.flush()
	var header := _read_exact(pipe, 20)
	if header.size() != 20 or header.slice(0, 4).get_string_from_ascii() != "BWAD":
		pipe.close()
		return {"ok":false,"error":"Audio decoder returned no valid header"}
	var status := header.decode_u32(4)
	var hz := header.decode_u32(8)
	var channels := header.decode_u32(12)
	var length := header.decode_u32(16)
	if status != 0 or hz < 8000 or hz > 192000 or channels not in [1,2] or length == 0 or length > int(cfg["output_limit_bytes"]) or length % (2 * channels) != 0:
		pipe.close()
		return {"ok":false,"error":"Original MPEG sound could not be decoded (%d)" % status}
	var pcm := _read_exact(pipe, length)
	pipe.close()
	if pcm.size() != length:
		return {"ok":false,"error":"Decoded audio is truncated"}
	return {"ok":true,"sample_rate":hz,"channels":channels,"pcm":pcm}


static func _read_exact(pipe: FileAccess, wanted: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	while bytes.size() < wanted:
		var chunk := pipe.get_buffer(mini(wanted - bytes.size(), 65536))
		if chunk.is_empty():
			break
		bytes.append_array(chunk)
	return bytes
