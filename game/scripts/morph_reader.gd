# Independent runtime reader for the Creature block of the player's CBN.
class_name MorphReader
extends RefCounted

var error := ""
var clips: Dictionary = {}
var base_mesh := ""
var _data := PackedByteArray()
var adviser_metadata: Dictionary = {}


func load_adviser(path: String) -> bool:
	adviser_metadata.clear()
	adviser_metadata["slots"] = {}
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
			adviser_metadata["slots"][i] = "adviser/" + name
			if i == 0:
				clips["move/stand"] = clips["adviser/" + name]
		p += size
	# HelpDude's final block stores its head/eye indices, UI projection scale
	# and the clinging hold points in HelpDudeSoundInfo, even for silent clips.
	if p + 52 <= _data.size():
		adviser_metadata["head_bone"] = _data.decode_u32(p + 24)
		var emotion_bytes := _data.decode_u32(p + 48)
		var tail := p + 52 + emotion_bytes
		if emotion_bytes <= 8192 and tail + 16 <= _data.size():
			adviser_metadata["depth"] = _data.decode_float(tail)
			adviser_metadata["size"] = _data.decode_float(tail + 4)
			adviser_metadata["tilt"] = _data.decode_float(tail + 8)
			var sounds := _data.decode_u32(tail + 12)
			tail += 16
			var loops: Dictionary = {}
			for i in mini(sounds, 80):
				if tail + 4 > _data.size(): break
				var count_sounds := _data.decode_u32(tail)
				tail += 4 + count_sounds * 12
				if tail + 8 > _data.size(): break
				loops[i] = _data.decode_float(tail + 4)
				tail += 8
			adviser_metadata["loop_ends"] = loops
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
	clips[name] = {"frames":nf,"bones":nb,"rids":rids,"tids":tids,"offset":frames,"duration":maxf(float(_data.decode_u32(p)) / 1000.0, 0.1),"cyclic":_data.decode_u32(p + 4) != 0}
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


func sample(name: String, seconds: float, rest: Array[Transform3D], base_clip := "", base_seconds := 0.0) -> Array[Transform3D]:
	var pose: Array[Transform3D] = rest.duplicate()
	# Base stand defines channels not present in a sparse action clip.
	if clips.has("move/stand"):
		_apply(clips["move/stand"], 0.0, pose, rest, false)
	# Adviser speech contains sparse face channels; keep the original hover
	# underneath so speaking does not freeze the rest of the character.
	if not base_clip.is_empty() and clips.has(base_clip):
		_apply(clips[base_clip], base_seconds, pose, rest, true)
	if clips.has(name):
		_apply(clips[name], seconds, pose, rest, true)
	return pose


# HelpDude uses CAnim::FillBuffer in the original bind coordinate frame. Its
# rotations are not local XYZ Euler offsets. Keep this separate from the
# creature adapter until that format's retargeting is migrated too.
func sample_adviser(name: String, seconds: float, rig: L3dRig) -> Array[Transform3D]:
	var pose: Array[Transform3D] = rig.rests.duplicate()
	if clips.has("move/stand"):
		_apply_adviser(clips["move/stand"], 0.0, pose, rig)
	if clips.has(name):
		_apply_adviser(clips[name], seconds, pose, rig)
	return pose


func _adviser_frame(clip: Dictionary, seconds: float) -> Vector3:
	var count: int = clip["frames"]
	var cyclic: bool = clip.get("cyclic", false)
	var progress: float = fposmod(seconds, float(clip["duration"])) / float(clip["duration"]) if cyclic else clampf(seconds / float(clip["duration"]), 0.0, 1.0)
	var frame := progress * float(count if cyclic else count - 1)
	var a := mini(int(frame), count - 1)
	return Vector3(a, (a + 1) % count if cyclic else mini(a + 1, count - 1), frame - float(a))


static func adviser_rotation(e: Vector3) -> Basis:
	# LHMatrix::SetYXZMatrixOnly(y,x,z), with row vectors converted to Godot
	# columns and the same Z reflection as the original geometry reader.
	var cy := cos(e.y)
	var sy := sin(e.y)
	var cx := cos(e.x)
	var sx := sin(e.x)
	var cz := cos(e.z)
	var sz := sin(e.z)
	var source := Basis(
		Vector3(cz * cy - sz * sx * sy, -sz * cx, sz * sx * cy + cz * sy),
		Vector3(cz * sy * sx + sz * cy, cz * cx, sz * sy - cz * cy * sx),
		Vector3(-cx * sy, sx, cx * cy))
	return L3dRig.reflected(Transform3D(source, Vector3.ZERO)).basis


func _adviser_channel(clip: Dictionary, channel: int, frame: Vector3, rotation: bool) -> Variant:
	var rids: PackedInt32Array = clip["rids"]
	var tids: PackedInt32Array = clip["tids"]
	var stride := (rids.size() + tids.size()) * 12
	var offset: int = clip["offset"] + channel * 12 + (0 if rotation else rids.size() * 12)
	var a := _vec(offset + int(frame.x) * stride)
	var b := _vec(offset + int(frame.y) * stride)
	if rotation:
		return Basis(adviser_rotation(a).get_rotation_quaternion().slerp(adviser_rotation(b).get_rotation_quaternion(), frame.z))
	var position := a.lerp(b, frame.z)
	return Vector3(position.x, position.y, -position.z)


func _apply_adviser(clip: Dictionary, seconds: float, pose: Array[Transform3D], rig: L3dRig) -> void:
	var frame := _adviser_frame(clip, seconds)
	var rids: PackedInt32Array = clip["rids"]
	var tids: PackedInt32Array = clip["tids"]
	for channel in rids.size():
		var bone := rids[channel]
		var parent := rig.parents[bone]
		var parent_base := rig.global_rests[parent].basis if parent >= 0 else Basis.IDENTITY
		var rotation: Basis = _adviser_channel(clip, channel, frame, true)
		pose[bone].basis = parent_base.inverse() * rotation * rig.global_rests[bone].basis
	for channel in tids.size():
		pose[tids[channel]].origin = _adviser_channel(clip, channel, frame, false)


# Original speech, pointing and head controls are additive differences from a
# neutral frame. A zero vowel weight must leave the hovering body untouched.
func apply_adviser_difference(name: String, position: float, reference: float, pose: Array[Transform3D], rig: L3dRig) -> void:
	if not clips.has(name):
		return
	var clip: Dictionary = clips[name]
	var end := float(clip["frames"] - 1)
	var current_frame := clampf(position, 0.0, 1.0) * end
	var reference_frame := clampf(reference, 0.0, 1.0) * end
	var current := Vector3(int(current_frame), mini(int(current_frame) + 1, int(end)), fposmod(current_frame, 1.0))
	var neutral := Vector3(int(reference_frame), mini(int(reference_frame) + 1, int(end)), fposmod(reference_frame, 1.0))
	var rids: PackedInt32Array = clip["rids"]
	var tids: PackedInt32Array = clip["tids"]
	for channel in rids.size():
		var bone := rids[channel]
		var parent := rig.parents[bone]
		var parent_base := rig.global_rests[parent].basis if parent >= 0 else Basis.IDENTITY
		var rotation: Basis = _adviser_channel(clip, channel, current, true)
		var base_rotation: Basis = _adviser_channel(clip, channel, neutral, true)
		pose[bone].basis = parent_base.inverse() * rotation * base_rotation.inverse() * parent_base * pose[bone].basis
	for channel in tids.size():
		var position_now: Vector3 = _adviser_channel(clip, channel, current, false)
		var position_base: Vector3 = _adviser_channel(clip, channel, neutral, false)
		pose[tids[channel]].origin += position_now - position_base


func adviser_root_motion(name: String, position: float) -> Vector3:
	if not clips.has(name): return Vector3.ZERO
	var clip: Dictionary = clips[name]
	var tids: PackedInt32Array = clip["tids"]
	var channel := tids.find(0)
	if channel < 0: return Vector3.ZERO
	var end := float(clip["frames"] - 1)
	var f := clampf(position, 0.0, 1.0) * end
	var frame := Vector3(int(f), mini(int(f) + 1, int(end)), fposmod(f, 1.0))
	var current: Vector3 = _adviser_channel(clip, channel, frame, false)
	var first: Vector3 = _adviser_channel(clip, channel, Vector3.ZERO, false)
	return current - first


func _apply(clip: Dictionary, seconds: float, pose: Array[Transform3D], rest: Array[Transform3D], lock_root: bool) -> void:
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
		# The original data stores XYZ Euler radians in the left-handed frame,
		# relative to the model's rest orientation (zero = the bone's bind pose).
		var qa := Basis.from_euler(ea, EULER_ORDER_XYZ).get_rotation_quaternion()
		var qb := Basis.from_euler(eb, EULER_ORDER_XYZ).get_rotation_quaternion()
		pose[idx].basis = rest[idx].basis * L3dRig.reflected(Transform3D(Basis(qa.slerp(qb, weight)), Vector3.ZERO)).basis
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
