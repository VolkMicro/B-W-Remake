extends Node3D

var rig: L3dRig
var animations: AnmReader
var clip: String
var age := 0.0
var track: Dictionary = {}
var frame := 0.0
var end_frame := 0.0
var forwards := true


func configure(models: G3dReader, reader: AnmReader) -> bool:
	clip = reader.names_by_index.get(129, "")
	if clip.is_empty():
		return false
	rig = models.rig_index(31)
	if rig == null:
		return false
	if rig.bone_count != int(reader.clips[clip]["bones"]):
		rig.root.free()
		return false
	animations = reader
	add_child(rig.root)
	return true


func walk_track(editor: PackedByteArray, path_id: int, first: float, last: float, reverse_flag: bool) -> bool:
	if not path_id in [20, 21] or not is_finite(first) or not is_finite(last) or first < 0.0 or first >= last or last > 1.0:
		return false
	var path := read_track(editor, path_id)
	if path.is_empty():
		return false
	track = path
	frame = first * float(track["duration"])
	end_frame = last * float(track["duration"])
	forwards = reverse_flag
	return true


func _process(delta: float) -> void:
	age += delta
	var pose := animations.sample(clip, age)
	if pose.size() == rig.bone_count:
		rig.apply_local_pose(pose)
	if track.is_empty() or frame >= end_frame:
		return
	var points: PackedVector3Array = track["points"]
	var times: PackedFloat32Array = track["times"]
	var time := frame if forwards else float(track["duration"]) - frame
	for i in range(1, times.size()):
		if time <= times[i] or i == times.size() - 1:
			var weight := clampf(inverse_lerp(times[i - 1], times[i], time), 0.0, 1.0)
			position = points[i - 1].lerp(points[i], weight)
			# The original mesh's length/forward axis is +X, not Godot's -Z.
			var direction := points[i] - points[i - 1]
			if not forwards:
				direction = -direction
			if Vector2(direction.x, direction.z).length_squared() > 0.000001:
				rotation.y = atan2(-direction.z, direction.x)
			break
	# The original advances 100 path frames per 10 Hz game turn.
	frame = minf(frame + 1000.0 * delta, end_frame)


static func read_track(editor: PackedByteArray, path_id: int) -> Dictionary:
	if editor.slice(0, 14).get_string_from_ascii() != "LiOnHeAdEDITOR":
		return {}
	var name_bytes := ("Track%d" % path_id).to_ascii_buffer()
	for p in range(14, editor.size() - 40):
		if editor[p] != name_bytes[0] or editor[p + name_bytes.size()] != 0 or editor.slice(p, p + name_bytes.size()) != name_bytes:
			continue
		var limit := p + 36 + int(editor.decode_u32(p + 32))
		var eye := p + 40
		if limit > editor.size() or limit < eye + 36:
			return {}
		var focus := eye + int(editor.decode_u16(eye))
		var count := int(editor.decode_u32(eye + 4))
		if count < 2 or count > 100 or focus < eye + 36 + 40 * count or focus + 36 + 12 * count > limit:
			return {}
		if int(editor.decode_u32(focus + 4)) != count:
			return {}
		var duration := int(editor.decode_u32(eye + 16))
		var points := PackedVector3Array()
		var times := PackedFloat32Array()
		for i in count:
			var point := focus + 36 + i * 12
			var position := Vector3(editor.decode_float(point), editor.decode_float(point + 4), -editor.decode_float(point + 8))
			var time := editor.decode_float(eye + 36 + 36 * count + i * 4)
			if not position.is_finite() or not is_finite(time) or (i > 0 and time <= times[i - 1]):
				return {}
			points.append(position)
			times.append(time)
		if duration <= 0 or times[0] != 0.0 or times[-1] < duration:
			return {}
		return {"points": points, "times": times, "duration": duration}
	return {}
