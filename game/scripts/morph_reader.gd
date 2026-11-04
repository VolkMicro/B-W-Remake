# Independent runtime reader for the Creature block of the player's CBN.
class_name MorphReader
extends RefCounted

var error := ""
var clips: Dictionary = {}
var base_mesh := ""
var _data := PackedByteArray()


func load_adviser(path: String) -> bool:
	_data = FileAccess.get_file_as_bytes(path)
	if _data.size() < 10432 or _data.slice(0, 8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Invalid adviser pack")
	# HD contains 81 fixed-width original filenames, then a sized L3D,
	# followed by 80 sized animations using the same channels as CBN.
	var p := 44 + 12 + 81 * 128
	if _data.decode_u32(p) != 1:
		return _fail("Unsupported adviser mesh table")
	p += 4
	var model_size := _data.decode_u32(p)
	p += 4 + model_size
	if p + 4 > _data.size():
		return _fail("Truncated adviser animations")
	var count := _data.decode_u32(p)
	p += 4
	if count != 80:
		return _fail("Unsupported adviser animation count")
	for i in count:
		var name_start := 44 + 12 + (i + 1) * 128
		var name_end := _data.find(0, name_start)
		var name := _data.slice(name_start, mini(name_end, name_start + 128)).get_string_from_ascii().replace("\\", "/").get_file().get_basename()
		if name == "":
			continue # fixed-width empty filename slots have no animation record
		if p + 4 > _data.size():
			return _fail("Truncated adviser animation size")
		var size := _data.decode_u32(p)
		var header := p + 4
		if size < 4 or p + size > _data.size():
			return _fail("Invalid adviser animation size")
		if size > 44:
			if not _register_clip("adviser/" + name, header, p + size):
				return false
			if i == 0:
				clips["move/stand"] = clips["adviser/" + name]
		p += size
	return clips.has("move/stand")


func _register_clip(name: String, p: int, end: int) -> bool:
	if p + 44 > end:
		return _fail("Truncated channel header")
	var nf := _data.decode_u32(p + 28)
	var nb := _data.decode_u32(p + 32)
	var nr := _data.decode_u32(p + 36)
	var nt := _data.decode_u32(p + 40)
	var frames := p + 44 + (nr + nt) * 4
	if nf < 1 or nf > 10000 or nb > 256 or nr > nb or nt > nb or frames + nf * (nr + nt) * 12 > end:
		return _fail("Invalid adviser channel ranges")
	var rids := PackedInt32Array()
	var tids := PackedInt32Array()
	for i in nr:
		var idx := _data.decode_u32(p + 44 + i * 4)
		if idx >= nb:
			return _fail("Adviser rotation outside skeleton")
		rids.append(idx)
	for i in nt:
		var idx := _data.decode_u32(p + 44 + nr * 4 + i * 4)
		if idx >= nb:
			return _fail("Adviser translation outside skeleton")
		tids.append(idx)
	clips[name] = {"frames":nf,"bones":nb,"rids":rids,"tids":tids,"offset":frames,"duration":maxf(float(_data.decode_u32(p)) / 1000.0, 0.1)}
	return true


func load_file(path: String, data_folder: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 + 236 or bytes.slice(0, 8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Missing creature animation pack")
	_data = bytes.slice(44)
	var version := _data.decode_u32(4)
	var spec_path := data_folder.path_join("ctrspec%d.txt" % version)
	if not FileAccess.file_exists(spec_path):
		return _fail("Missing original creature animation specification")
	base_mesh = _data.slice(12, 44).get_string_from_ascii().strip_edges()
	var lines := FileAccess.get_file_as_string(spec_path).split("\n")
	if int(lines[0]) != version:
		return _fail("Animation specification version mismatch")
	var category := ""
	var names: Array[String] = []
	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line == "E":
			break
		if line.begins_with("="):
			category = line.substr(1)
		elif line.length() > 1:
			names.append(category + "/" + line.substr(1))
	if 236 + names.size() * 4 > _data.size():
		return _fail("Truncated animation offset table")
	for i in names.size():
		var p := _data.decode_u32(236 + i * 4)
		if p == 0:
			continue
		if p + 44 > _data.size():
			return _fail("Invalid animation header")
		var nf := _data.decode_u32(p + 28)
		var nb := _data.decode_u32(p + 32)
		var nr := _data.decode_u32(p + 36)
		var nt := _data.decode_u32(p + 40)
		var frames := p + 44 + (nr + nt) * 4
		if nf < 1 or nf > 10000 or nb > 256 or nr > nb or nt > nb or frames + nf * (nr + nt) * 12 > _data.size():
			return _fail("Invalid animation channel range")
		var rids := PackedInt32Array()
		var tids := PackedInt32Array()
		for j in nr:
			var idx := _data.decode_u32(p + 44 + j * 4)
			if idx >= nb:
				return _fail("Rotation bone outside skeleton")
			rids.append(idx)
		for j in nt:
			var idx := _data.decode_u32(p + 44 + nr * 4 + j * 4)
			if idx >= nb:
				return _fail("Translation bone outside skeleton")
			tids.append(idx)
		clips[names[i]] = {"frames":nf,"bones":nb,"rids":rids,"tids":tids,"offset":frames,"duration":maxf(float(_data.decode_u32(p)) / 1000.0, 0.1)}
	return clips.has("move/stand") and clips.has("move/walk")


func sample(name: String, seconds: float, rest: Array[Transform3D]) -> Array[Transform3D]:
	var pose: Array[Transform3D] = rest.duplicate()
	# Base stand defines channels not present in a sparse action clip.
	if clips.has("move/stand"):
		_apply(clips["move/stand"], 0.0, pose, false)
	if clips.has(name):
		_apply(clips[name], seconds, pose, true)
	return pose


func _apply(clip: Dictionary, seconds: float, pose: Array[Transform3D], lock_root: bool) -> void:
	var nf: int = clip["frames"]
	var frame: float = fposmod(seconds, float(clip["duration"])) / float(clip["duration"]) * float(nf - 1)
	var a := int(frame)
	var b := mini(a + 1, nf - 1)
	var weight := frame - float(a)
	var rids: PackedInt32Array = clip["rids"]
	var tids: PackedInt32Array = clip["tids"]
	var stride := (rids.size() + tids.size()) * 12
	var base: int = clip["offset"]
	for i in rids.size():
		var idx := rids[i]
		if idx >= pose.size():
			continue
		var ea := _vec(base + a * stride + i * 12)
		var eb := _vec(base + b * stride + i * 12)
		# The original data stores XYZ Euler radians in the left-handed frame.
		var qa := Basis.from_euler(ea, EULER_ORDER_XYZ).get_rotation_quaternion()
		var qb := Basis.from_euler(eb, EULER_ORDER_XYZ).get_rotation_quaternion()
		pose[idx].basis = L3dRig.reflected(Transform3D(Basis(qa.slerp(qb, weight)), Vector3.ZERO)).basis
	for i in tids.size():
		var idx := tids[i]
		if idx >= pose.size():
			continue
		var off := base + rids.size() * 12 + i * 12
		var p := _vec(off + a * stride).lerp(_vec(off + b * stride), weight)
		if lock_root and idx == 0:
			# Locomotion is world movement; suppress animation's accumulated XZ.
			var first := _vec(off)
			p.x = first.x
			p.z = first.z
		pose[idx].origin = Vector3(p.x, p.y, -p.z)


func _vec(p: int) -> Vector3:
	return Vector3(_data.decode_float(p), _data.decode_float(p + 4), _data.decode_float(p + 8))


func _fail(message: String) -> bool:
	error = message
	clips.clear()
	return false
