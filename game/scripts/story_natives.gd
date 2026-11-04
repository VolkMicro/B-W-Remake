# Small, explicit bridge for original LHVM calls whose behaviour is understood.
# Unlisted calls return ok=false and therefore suspend the story VM safely.
class_name StoryNatives
extends RefCounted

const Data := preload("res://scripts/data.gd")
var terrain: WeakRef
var _objects: Dictionary = {}
var _object_types: Dictionary = {}
var _created_markers: Array[Node3D] = []
var _next_object := 1
var _random := RandomNumberGenerator.new()
var keep_old_creature := false
var profile_has_creature := false


func configure(world: Object) -> void:
	terrain = weakref(world) if is_instance_valid(world) else null


func register_object(object: Object, story_type := -1) -> int:
	if not is_instance_valid(object):
		return 0
	var id := _next_object
	_next_object += 1
	_objects[id] = weakref(object)
	_object_types[id] = story_type
	return id


func register_landmarks(landmarks: Array[Node3D]) -> int:
	var supported := {}
	for rule in Data.STORY_SEARCH_RULES.values():
		supported[int(rule["object_type"])] = true
	var registered := 0
	for landmark in landmarks:
		if not is_instance_valid(landmark):
			continue
		var story_type := int(landmark.get_meta("story_type", -1))
		if supported.has(story_type) and register_object(landmark, story_type) != 0:
			registered += 1
	return registered


func clear_created() -> void:
	for marker in _created_markers:
		if is_instance_valid(marker):
			marker.free()
	_created_markers.clear()


func invoke(id: int, stack: Array, _context: Dictionary) -> Dictionary:
	if not Data.STORY_NATIVES.has(str(id)):
		return {"ok":false}
	var row: Dictionary = Data.STORY_NATIVES[str(id)]
	var count: int = row["arguments"]
	if stack.size() < count:
		return {"ok":false}
	var result: Array[Dictionary] = []
	match str(row["handler"]):
		"get_position":
			var object_id: int = int(stack.back()["bits"])
			var object: Object = _objects[object_id].get_ref() if _objects.has(object_id) else null
			var position := Vector3.ZERO
			if is_instance_valid(object) and object is Node3D:
				position = object.global_position if object.is_inside_tree() else object.position
			# The island is mirrored on Z in the Godot scene.
			result.append(StoryVm.number(position.x, StoryVm.VECTOR))
			result.append(StoryVm.number(position.y, StoryVm.VECTOR))
			result.append(StoryVm.number(-position.z, StoryVm.VECTOR))
		"distance":
			var p := stack.size() - count
			var a := Vector3(StoryVm.as_float(stack[p]), StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2]))
			var b := Vector3(StoryVm.as_float(stack[p + 3]), StoryVm.as_float(stack[p + 4]), StoryVm.as_float(stack[p + 5]))
			if not a.is_finite() or not b.is_finite():
				return {"ok":false}
			result.append(StoryVm.number(a.distance_to(b)))
		"exact_landmark":
			# Only the observed, unambiguous first-island use is supported.
			# Every other search blocks instead of guessing original behaviour.
			var p := stack.size() - count
			var rule: Dictionary = {}
			for candidate in Data.STORY_SEARCH_RULES.values():
				if int(candidate["object_type"]) == StoryVm.as_int(stack[p]):
					rule = candidate
					break
			if rule.is_empty():
				return {"ok":false}
			if StoryVm.as_int(stack[p]) != int(rule["object_type"]) or StoryVm.as_int(stack[p + 1]) != int(rule["any_subtype"]) or StoryVm.as_int(stack[p + 5]) != 0:
				return {"ok":false}
			var point := Vector2(StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 4]))
			if not point.is_finite() or not is_finite(StoryVm.as_float(stack[p + 3])):
				return {"ok":false}
			var matches: Array[int] = []
			for object_id in _object_types:
				if _object_types[object_id] != int(rule["object_type"]):
					continue
				var object: Object = _objects[object_id].get_ref()
				if not is_instance_valid(object) or not object is Node3D:
					continue
				var position: Vector3 = object.global_position if object.is_inside_tree() else object.position
				if Vector2(position.x, -position.z).distance_to(point) <= float(rule["position_tolerance"]):
					matches.append(object_id)
			if matches.size() != 1:
				return {"ok":false}
			result.append(StoryVm.integer(matches[0], StoryVm.OBJECT))
		"create_marker":
			var rule: Dictionary = Data.STORY_CREATE_RULES["create_marker"]
			var p := stack.size() - count
			if StoryVm.as_int(stack[p]) != int(rule["object_type"]) or StoryVm.as_int(stack[p + 1]) != int(rule["subtype"]) or _created_markers.size() >= int(rule["maximum_created"]):
				return {"ok":false}
			var position := Vector3(StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 3]), -StoryVm.as_float(stack[p + 4]))
			if not position.is_finite():
				return {"ok":false}
			var marker := Node3D.new()
			marker.position = position
			_created_markers.append(marker)
			result.append(StoryVm.integer(register_object(marker, int(rule["object_type"])), StoryVm.OBJECT))
		"random_range":
			var lo := StoryVm.as_float(stack[stack.size() - 2])
			var hi := StoryVm.as_float(stack.back())
			if not is_finite(lo) or not is_finite(hi):
				return {"ok":false}
			result.append(StoryVm.number(lo + (hi - lo) * _random.randf()))
		"land_height":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("ground_y"):
				return {"ok":false}
			var x := StoryVm.as_float(stack[stack.size() - 3])
			var z := StoryVm.as_float(stack[stack.size() - 1])
			if not is_finite(x) or not is_finite(z):
				return {"ok":false}
			# Original island coordinates use +Y across the map; Godot uses -Z.
			var height: float = world.ground_y(Vector3(x, 0, -z))
			if not is_finite(height):
				return {"ok":false}
			result.append(StoryVm.number(height))
		"thing_valid":
			var object_id: int = int(stack.back()["bits"])
			var valid := object_id != 0 and _objects.has(object_id) and is_instance_valid(_objects[object_id].get_ref())
			result.append(StoryVm.integer(int(valid), StoryVm.BOOL))
		"square_root":
			var value := StoryVm.as_float(stack.back())
			if not is_finite(value):
				return {"ok":false}
			result.append(StoryVm.number(sqrt(value) if value > 0.0 else 0.0))
		"skip_tutorial", "skip_creature_training":
			# This preservation build always starts with original training enabled.
			result.append(StoryVm.integer(0, StoryVm.BOOL))
		"keep_old_creature":
			result.append(StoryVm.integer(int(keep_old_creature), StoryVm.BOOL))
		"profile_has_creature":
			result.append(StoryVm.integer(int(profile_has_creature), StoryVm.BOOL))
		_:
			return {"ok":false}
	if result.size() != int(row["returns"]):
		return {"ok":false}
	return {"ok":true,"pop":count,"push":result}
