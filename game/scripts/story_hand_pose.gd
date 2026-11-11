extends RefCounted

# Ordinary CHand data lives in hh.HBN, not the packed AllAnims archive.
# Its hndspec5.txt order is the runtime's authoritative animation index.
var error := ""
var animation := MorphReader.new()
var rig: L3dRig
var slots: Array[String] = []
var state := "hover"
var _clock := 0.0
var _transition := 1.0
var _from: Array[Transform3D] = []
var _pose: Array[Transform3D] = []
var _vertices: Array[Dictionary] = []
var _pointer_local := Vector3.ZERO
var _thumb_local := Vector3.ZERO
const INDEX_TIP_BONE := 19 # The only finger kept extended by the original point clip.
const THUMB_TIP_BONE := 21 # Short side branch 2 -> 3 -> 20 -> 21 in the source L3D.


func configure(bw_dir: String, hand_rig: L3dRig) -> bool:
	error = ""
	rig = hand_rig
	var bytes := FileAccess.get_file_as_bytes(bw_dir.path_join("Data/CTR/hh.HBN"))
	if bytes.size() < 560 or bytes.slice(0, 8).get_string_from_ascii() != "LiOnHeAd" or bytes.slice(8, 12).get_string_from_ascii() != "Hand":
		return _fail("Original Hand segment is unavailable")
	animation._data = bytes.slice(44)
	if animation._data.decode_u32(0) != 0 or animation._data.decode_u32(4) != 5:
		return _fail("Unsupported original hand specification")
	var category := ""
	var lines := FileAccess.get_file_as_string(bw_dir.path_join("Data/hndspec5.txt")).split("\n")
	if lines.is_empty() or lines[0].strip_edges() != "5":
		return _fail("Original hand animation specification is unavailable")
	for line_index in range(1, lines.size()):
		var line := lines[line_index].strip_edges()
		if line == "E": break
		if line.begins_with("="):
			category = line.substr(1)
		elif line.length() > 1:
			slots.append(category + "/" + line.substr(1))
	if slots.size() != 69 or 236 + slots.size() * 4 > animation._data.size():
		return _fail("Invalid hand animation index")
	for index in slots.size():
		var offset := animation._data.decode_u32(236 + index * 4)
		if offset == 0: continue
		if not animation._register_clip(slots[index], offset, animation._data.size()):
			return _fail(animation.error)
		if int(animation.clips[slots[index]]["bones"]) != rig.bone_count:
			return _fail("Original hand animation and skeleton differ")
	if not animation.clips.has("standard/wiggle"):
		return _fail("Original idle hand animation is missing")
	animation.clips["move/stand"] = animation.clips["standard/wiggle"]
	_collect_vertices()
	_pose = animation.sample_adviser("standard/wiggle", 0.0, rig)
	return true


func set_state(next: String) -> bool:
	if not _state_clip(next).is_empty() and animation.clips.has(_state_clip(next)):
		if next != state:
			_from = _pose.duplicate()
			_transition = 0.0
			state = next
		return true
	return false


func _state_clip(value: String) -> String:
	match value:
		"hover", "release": return "standard/wiggle"
		"point", "scroll": return "standard/point"
		"pickup", "grab": return "standard/can_pickup"
		"hold", "hold_above": return "standard/hold_above"
		"hold_side": return "standard/hold_side"
		"hold_fingers": return "standard/hold_fingers"
		"drag", "camera_grip": return "camera/grip"
		"rotate": return "camera/rotate"
		"pitch": return "camera/pitch"
		"zoom": return "camera/zoom"
		"knock": return "individual/tap_house"
	return ""


func sample(delta: float, sliders := Vector2(0.5, 0.5)) -> Array[Transform3D]:
	if rig == null or animation.clips.is_empty(): return []
	_clock += maxf(delta, 0.0)
	_transition = minf(1.0, _transition + delta / 0.13)
	var clip := _state_clip(state)
	var result := animation.sample_adviser(clip, _clock, rig)
	# Phases come from the frame-based pointer controller, not event deltas.
	sliders = sliders.clamp(Vector2.ZERO, Vector2.ONE)
	animation.apply_adviser_difference(clip + "_lr", sliders.x, 0.5, result, rig)
	animation.apply_adviser_difference(clip + "_fb", sliders.y, 0.5, result, rig)
	if _from.size() == result.size() and _transition < 1.0:
		result = preload("res://scripts/hand_pointer_dynamics.gd").blend_pose(_from, result, _transition)
	_pose = result
	return result


func animated_bounds(pose: Array[Transform3D] = _pose) -> AABB:
	var globals := _globals(pose)
	var result := AABB()
	var first := true
	for vertex in _vertices:
		var point: Vector3 = globals[vertex["bone"]] * vertex["local"]
		if first:
			result = AABB(point, Vector3.ZERO)
			first = false
		else: result = result.expand(point)
	return result


func bone_position(bone: int, pose: Array[Transform3D] = _pose) -> Vector3:
	var globals := _globals(pose)
	return globals[bone].origin if bone >= 0 and bone < globals.size() else Vector3.INF


func pointer_position(pose: Array[Transform3D] = _pose) -> Vector3:
	var globals := _globals(pose)
	return globals[INDEX_TIP_BONE] * _pointer_local if globals.size() > INDEX_TIP_BONE else Vector3.INF


func grip_position(pose: Array[Transform3D] = _pose) -> Vector3:
	# A mesh-derived pinch point between the actual thumb and index pads.
	# The caller chooses the held object's surface/attachment separately.
	var globals := _globals(pose)
	if globals.size() <= THUMB_TIP_BONE: return Vector3.INF
	var thumb: Vector3 = globals[THUMB_TIP_BONE] * _thumb_local
	return (thumb + pointer_position(pose)) * 0.5


func anchor(pose: Array[Transform3D] = _pose) -> Vector3:
	return grip_position(pose) if state in ["hold", "hold_above", "hold_side", "hold_fingers", "grab"] else pointer_position(pose)


func geometry(root_basis: Basis, pose: Array[Transform3D] = _pose) -> Dictionary:
	# root_basis can include the caller's world scale and handedness. Exact
	# skinned vertices, rather than rest bounds, define collision clearance.
	var globals := _globals(pose)
	var bounds := AABB()
	var first := true
	for vertex in _vertices:
		var point: Vector3 = root_basis * (globals[vertex["bone"]] * vertex["local"])
		if first:
			bounds = AABB(point, Vector3.ZERO)
			first = false
		else: bounds = bounds.expand(point)
	return {"bounds":bounds,"pointer":root_basis * pointer_position(pose),"grip":root_basis * grip_position(pose),"anchor":root_basis * anchor(pose),"wrist":root_basis * bone_position(2, pose)}


static func source_orientation(heading: float, facing_normal := Vector3.UP, right_hand := true) -> Basis:
	# CHand's original matrix builder (0x46e160) uses heading+PI and a facing
	# vector. CHand::LoadBinary toggles flag0x484c once; 0x46d080 then negates
	# local X. This is the game's documented default-hand mirror, not a guess.
	var normal := Vector3(facing_normal.x, facing_normal.y, -facing_normal.z).normalized()
	var theta := heading + PI
	var tangent := Vector3(cos(theta) * normal.y, -cos(theta) * normal.x - sin(theta) * normal.z, sin(theta) * normal.y)
	if tangent.length_squared() < 0.00001:
		tangent = normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.UP)
	tangent = tangent.normalized()
	var source := Basis(tangent, tangent.cross(normal), -normal)
	var result := L3dRig.reflected(Transform3D(source, Vector3.ZERO)).basis
	return result.scaled_local(Vector3(-1, 1, 1)) if right_hand else result


static func surface_orientation(camera_yaw: float, surface_normal := Vector3.UP, right_hand := true) -> Basis:
	# Adapter for main.gd's yaw convention (eye offset points toward +Z at0).
	return source_orientation(PI + camera_yaw, surface_normal, right_hand)


func _globals(pose: Array[Transform3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if rig == null or pose.size() != rig.bone_count: return result
	for bone in pose.size():
		var parent := rig.parents[bone]
		result.append(result[parent] * pose[bone] if parent >= 0 else pose[bone])
	return result


func _collect_vertices() -> void:
	_vertices.clear()
	for child in rig.root.get_children():
		if not child is MeshInstance3D: continue
		for surface in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for index in points.size():
				var bone := bones[index * 4]
				_vertices.append({"bone":bone,"local":rig.global_rests[bone].affine_inverse() * points[index]})
	# The source L3D stores each finger segment along its local +Z axis;
	# after our geometry reflection its distal end is local -Z. Average the
	# distal cap vertices so the cursor follows the pad rather than a corner.
	_pointer_local = _distal_cap(INDEX_TIP_BONE)
	_thumb_local = _distal_cap(THUMB_TIP_BONE)


func _distal_cap(bone: int) -> Vector3:
	var minimum := INF
	var maximum := -INF
	for vertex in _vertices:
		if vertex["bone"] == bone:
			minimum = minf(minimum, vertex["local"].z)
			maximum = maxf(maximum, vertex["local"].z)
	var count := 0
	var result := Vector3.ZERO
	for vertex in _vertices:
		if vertex["bone"] == bone and vertex["local"].z <= minimum + (maximum - minimum) * 0.05:
			result += vertex["local"]
			count += 1
	return result / float(count) if count > 0 else Vector3.ZERO


func _fail(message: String) -> bool:
	error = message
	return false
