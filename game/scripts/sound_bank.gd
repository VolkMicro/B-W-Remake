# Indexed, read-only access to an original Lionhead SAD sound bank.
# Samples are read into memory on demand; nothing is extracted to disk.
class_name SoundBank
extends RefCounted

var error := ""
var entries: Dictionary = {}
var _path := ""
var _wave_start := 0
var _wave_size := 0


func open(path: String) -> bool:
	entries.clear()
	error = ""
	_path = path
	_wave_start = 0
	_wave_size = 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Cannot read original sound bank")
	var table_start := -1
	var table_size := 0
	while f.get_position() + 36 <= f.get_length():
		var raw_name := f.get_buffer(32)
		var end := raw_name.find(0)
		var name := raw_name.slice(0, end if end >= 0 else 32).get_string_from_ascii()
		var size := f.get_32()
		var start := f.get_position()
		if size > f.get_length() - start:
			return _fail("Truncated sound bank block")
		if name == "LHAudioWaveData":
			_wave_start = start
			_wave_size = size
		elif name == "LHAudioBankSampleTable":
			table_start = start
			table_size = size
		f.seek(start + size)
	if table_start < 0 or _wave_start <= 0 or table_size < 4:
		return _fail("Original sound bank index missing")
	f.seek(table_start)
	var count := f.get_32()
	if count > 100000 or 4 + count * 640 != table_size:
		return _fail("Unsupported original sound bank index")
	for i in count:
		var row := f.get_buffer(640)
		if row.size() != 640:
			return _fail("Truncated sound bank entry")
		var e := row.find(0)
		if e < 0 or e > 256:
			return _fail("Invalid sound name")
		var filename := row.slice(0, e).get_string_from_ascii().replace("\\", "/").get_file()
		var id := row.decode_u32(260)
		var size := row.decode_u32(268)
		var offset := row.decode_u32(272)
		if offset > _wave_size or size > _wave_size - offset:
			return _fail("Sound entry outside archive")
		var key := filename.get_basename().to_upper()
		if key != "":
			entries[key] = {"id":id,"name":filename,"size":size,"offset":offset}
	return not entries.is_empty()


func sample(key: String) -> Dictionary:
	key = key.to_upper().get_basename()
	if not entries.has(key):
		return {"ok":false,"error":"Original sound is missing"}
	var entry: Dictionary = entries[key]
	var size: int = entry["size"]
	if size < 4 or size > 33554432:
		return {"ok":false,"error":"Original sound size is invalid"}
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return {"ok":false,"error":"Original sound bank is unavailable"}
	f.seek(_wave_start + int(entry["offset"]))
	var bytes := f.get_buffer(size)
	if bytes.size() != size:
		return {"ok":false,"error":"Original sound is truncated"}
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"ok":true,"format":"mpeg","payload":bytes}
	if bytes.size() < 12 or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"ok":false,"error":"Invalid original WAV"}
	var format := -1
	var payload := PackedByteArray()
	var p := 12
	while p + 8 <= bytes.size():
		var chunk := bytes.slice(p, p + 4).get_string_from_ascii()
		var n := bytes.decode_u32(p + 4)
		var start := p + 8
		if n > bytes.size() - start:
			return {"ok":false,"error":"Truncated original WAV chunk"}
		if chunk == "fmt " and n >= 2:
			format = bytes.decode_u16(start)
		elif chunk == "data":
			payload = bytes.slice(start, start + n)
		p = start + n + (n & 1)
	if format == 1:
		return {"ok":true,"format":"pcm_wav","payload":bytes}
	if format == 0x50 and not payload.is_empty():
		return {"ok":true,"format":"mpeg","payload":payload}
	return {"ok":false,"error":"Unsupported original sound format %d" % format}


func _fail(message: String) -> bool:
	error = message
	entries.clear()
	return false
