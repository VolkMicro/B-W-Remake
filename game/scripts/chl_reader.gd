# Index the original campaign, never confuse indexing with story execution.
class_name ChlReader
extends RefCounted

var error := ""
var scripts: Dictionary = {}
var globals: Array[String] = []
var autostart := PackedInt32Array()
var instruction_count := 0
var native_calls: Dictionary = {}
var scripts_by_id: Dictionary = {}
var code := PackedByteArray()
var constants := PackedByteArray()
var _bytes := PackedByteArray()
var _p := 0


func load_file(path: String) -> bool:
	error = ""
	scripts.clear()
	scripts_by_id.clear()
	globals.clear()
	autostart.clear()
	native_calls.clear()
	code.clear()
	constants.clear()
	_bytes = FileAccess.get_file_as_bytes(path)
	if _bytes.size() < 12 or _bytes.slice(0, 4).get_string_from_ascii() != "LHVM" or _bytes.decode_u32(4) != 7:
		return _fail("Expected original Black & White LHVM v7")
	_p = 8
	globals = _strings()
	instruction_count = _u()
	if instruction_count > 1000000 or _p + instruction_count * 20 > _bytes.size():
		return _fail("Invalid original story instruction table")
	code = _bytes.slice(_p, _p + instruction_count * 20)
	for i in instruction_count:
		var op := _bytes.decode_u32(_p + i * 20)
		if op == 5:
			var id := _bytes.decode_u32(_p + i * 20 + 12)
			native_calls[id] = int(native_calls.get(id, 0)) + 1
	_p += instruction_count * 20
	var na := _u()
	if na > 100000:
		return _fail("Invalid autostart table")
	for i in na:
		autostart.append(_u())
	var ns := _u()
	if ns > 100000:
		return _fail("Invalid script table")
	for i in ns:
		var name := _string()
		var source := _string()
		var type := _u()
		var variable_offset := _u()
		var variables := _strings()
		var address := _u()
		var params := _u()
		var id := _u()
		if error != "" or name == "" or address >= instruction_count:
			return _fail("Invalid campaign script record")
		if scripts.has(name) or scripts_by_id.has(id):
			return _fail("Duplicate campaign script")
		var entry := {"name":name,"id":id,"source":source,"type":type,"variables":variables.size(),"variable_names":variables,"variable_offset":variable_offset,"address":address,"params":params}
		scripts[name] = entry
		scripts_by_id[id] = entry
	var data_size := _u()
	if error != "" or _p + data_size > _bytes.size():
		return _fail("Truncated campaign string data")
	constants = _bytes.slice(_p, _p + data_size)
	_bytes.clear()
	return scripts.has("SetupLand1")


func instruction(address: int) -> Dictionary:
	if address < 0 or address >= instruction_count or address * 20 + 20 > code.size():
		return {}
	var p := address * 20
	return {"opcode":code.decode_u32(p),"mode":code.decode_u32(p + 4),"type":code.decode_u32(p + 8),"bits":code.decode_u32(p + 12),"line":code.decode_u32(p + 16)}


func constant_string(offset: int) -> String:
	if offset < 0 or offset >= constants.size():
		return ""
	var end := constants.find(0, offset)
	if end < 0:
		return ""
	return constants.slice(offset, end).get_string_from_ascii()


func _u() -> int:
	if _p + 4 > _bytes.size():
		error = "Unexpected end of campaign"
		return 0
	var value := _bytes.decode_u32(_p)
	_p += 4
	return value


func _string() -> String:
	var end := _bytes.find(0, _p)
	if end < _p or end - _p > 4096:
		error = "Unterminated campaign string"
		return ""
	var value := _bytes.slice(_p, end).get_string_from_ascii()
	_p = end + 1
	return value


func _strings() -> Array[String]:
	var result: Array[String] = []
	var count := _u()
	if count > 100000:
		error = "Invalid variable table"
		return result
	for i in count:
		result.append(_string())
	return result


func _fail(message: String) -> bool:
	error = message
	scripts.clear()
	scripts_by_id.clear()
	code.clear()
	constants.clear()
	_bytes.clear()
	return false
