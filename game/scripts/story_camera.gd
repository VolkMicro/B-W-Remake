extends RefCounted
## Camera state shared by LHVM calls and the rendered camera.

const MOVE_EPSILON := 0.001
const MIN_FOLLOW_PITCH := 0.2416609824

var eye := Vector3.ZERO
var focus := Vector3.ZERO
var owner_task := 0
var _zone := PackedVector2Array()
var _eye_motion: Dictionary = {}
var _focus_motion: Dictionary = {}
var _follow_target: WeakRef
var _focus_follow_target: WeakRef
var _focus_follow_height := 0.0
var _follow_height := 0.0
var _follow_distance := 0.0
var _follow_yaw := 0.0
var _follow_pitch := MIN_FOLLOW_PITCH
var _follow_heading := false


func update_player_pose(player_eye: Vector3, player_focus: Vector3) -> void:
	if owner_task == 0:
		eye = player_eye
		focus = player_focus


func above_water_pose(surface: float) -> Dictionary:
	# Presentation correction for the introductory shark shots. Their authored
	# camera goes underwater, which this port does not yet render as underwater.
	# Leave LHVM state intact so camera queries and arrival tests keep working.
	if eye.y >= surface + 16.0:
		return {"eye": eye, "focus": focus}
	var blend := 1.0 - smoothstep(surface + 6.0, surface + 16.0, eye.y)
	var target := Vector3(focus.x, lerpf(focus.y, maxf(focus.y, surface), blend), focus.z)
	var horizontal := Vector2(eye.x - target.x, eye.z - target.z).length()
	var safe_height := maxf(surface + 8.0, target.y + horizontal)
	var origin := Vector3(eye.x, lerpf(eye.y, maxf(eye.y, safe_height), blend), eye.z)
	return {"eye": origin, "focus": target}


static func constrain_player_eye(origin: Vector3, target: Vector3, height: Callable, surface: float) -> Vector3:
	var offset := origin - target
	var raise := 0.0
	# Clearance grows from zero at the ground focus to three units at the eye.
	# Applying full clearance near the focus incorrectly magnifies it eightfold
	# and launches the camera upward when the cinematic hands control to the player.
	for i in range(1, 9):
		var weight := float(i) / 8.0
		var point := target + offset * weight
		var required := maxf(float(height.call(point)), surface) + 3.0 * weight
		raise = maxf(raise, (required - point.y) / weight)
	return origin + Vector3.UP * raise


func load_zone(bytes: PackedByteArray) -> bool:
	const HEADER_SIZE := 76
	const FOOTER_SIZE := 8
	const VERTEX_SIZE := 12
	if bytes.size() < HEADER_SIZE + FOOTER_SIZE or bytes.slice(0, 17).get_string_from_ascii() != "LiOnHeAdcameraexc":
		return false
	if bytes.decode_u32(40) != bytes.size() - 44 or bytes.decode_u32(44) != 1:
		return false
	var count := bytes.decode_u32(72)
	if count < 3 or count > 1024 or bytes.size() != HEADER_SIZE + count * VERTEX_SIZE + FOOTER_SIZE:
		return false
	var polygon := PackedVector2Array()
	for i in count:
		var offset := HEADER_SIZE + i * VERTEX_SIZE
		var vertex := Vector2(bytes.decode_float(offset), -bytes.decode_float(offset + 8))
		if not vertex.is_finite():
			return false
		polygon.append(vertex)
	_zone = polygon
	return true


func constrain_player_focus(point: Vector3) -> Vector3:
	if _zone.is_empty():
		return point
	var xz := Vector2(point.x, point.z)
	if Geometry2D.is_point_in_polygon(xz, _zone):
		return point
	var nearest := _zone[0]
	var nearest_distance := xz.distance_squared_to(nearest)
	for i in _zone.size():
		var edge_point := Geometry2D.get_closest_point_to_segment(xz, _zone[i], _zone[(i + 1) % _zone.size()])
		var distance := xz.distance_squared_to(edge_point)
		if distance < nearest_distance:
			nearest = edge_point
			nearest_distance = distance
	return Vector3(nearest.x, point.y, nearest.y)


func advance(delta: float) -> void:
	if _follow_target != null:
		_update_follow_pose()
	if not _eye_motion.is_empty():
		eye = _advance_motion(_eye_motion, delta)
	if not _focus_motion.is_empty():
		focus = _advance_motion(_focus_motion, delta)
	if _focus_follow_target != null:
		var target := _focus_follow_target.get_ref() as Node3D
		if is_instance_valid(target):
			focus = (target.global_position if target.is_inside_tree() else target.position) + Vector3.UP * _focus_follow_height
		else:
			_focus_follow_target = null


func release() -> void:
	owner_task = 0
	_follow_target = null
	_focus_follow_target = null
	_eye_motion.clear()
	_focus_motion.clear()


func invoke(id: int, stack: Array, context: Dictionary) -> Dictionary:
	var task := int(context.get("task", 0))
	match id:
		1, 2, 3, 4:
			# The native targets the active scripted camera. Nested scripts
			# such as Drag can move it while their caller retains the lock.
			if task <= 0 or owner_task == 0:
				return {"ok": false}
			return _set_target(id, stack)
		5, 6:
			var point := eye if id == 5 else focus
			return _reply(0, [
				StoryVm.number(point.x, StoryVm.VECTOR),
				StoryVm.number(point.y, StoryVm.VECTOR),
				StoryVm.number(-point.z, StoryVm.VECTOR),
			])
		30:
			if task <= 0:
				return {"ok": false}
			var acquired := owner_task == 0
			if acquired:
				owner_task = task
			return _reply(0, [StoryVm.integer(int(acquired), StoryVm.BOOL)])
		31:
			if owner_task == task:
				release()
			return _reply(0)
		35:
			var arrived := _eye_motion.is_empty() and _focus_motion.is_empty()
			return _reply(0, [StoryVm.integer(int(arrived), StoryVm.BOOL)])
		180:
			return _set_follow_properties(stack, task)
	return {"ok": false}


func follow(target: Node3D, distance: float, height: float, task: int) -> bool:
	if task <= 0 or owner_task != task or not is_finite(distance) or not is_finite(height):
		return false
	var offset := eye - focus
	_follow_target = weakref(target)
	_follow_height = height
	_follow_distance = clampf(distance, 2.0, 1500.0)
	_follow_yaw = atan2(offset.x, -offset.z)
	_follow_pitch = maxf(MIN_FOLLOW_PITCH, atan2(offset.y, Vector2(offset.x, offset.z).length()))
	_follow_heading = false
	_eye_motion.clear()
	_focus_motion.clear()
	_update_follow_pose()
	return true


func follow_focus(target: Node3D, task: int, half_height := 0.0) -> bool:
	if task <= 0 or owner_task == 0 or not is_instance_valid(target) or not is_finite(half_height):
		return false
	_follow_target = null
	_focus_follow_target = weakref(target)
	_focus_follow_height = half_height
	_focus_motion.clear()
	return true


func _set_follow_properties(stack: Array, task: int) -> Dictionary:
	if task <= 0 or owner_task != task or _follow_target == null or stack.size() < 4:
		return {"ok": false}
	var p := stack.size() - 4
	var distance := StoryVm.as_float(stack[p])
	var speed := StoryVm.as_float(stack[p + 1])
	var yaw_degrees := StoryVm.as_float(stack[p + 2])
	# The tutorial uses a fixed angle, with no automatic angular motion.
	if not is_finite(distance) or speed != 0.0 or not is_finite(yaw_degrees):
		return {"ok": false}
	_follow_distance = clampf(distance, 2.0, 1500.0)
	_follow_yaw = deg_to_rad(yaw_degrees)
	_follow_heading = StoryVm.as_int(stack.back()) != 0
	_update_follow_pose()
	return _reply(4)


func _update_follow_pose() -> void:
	var target := _follow_target.get_ref() as Node3D
	if not is_instance_valid(target):
		_follow_target = null
		return
	focus = (target.global_position if target.is_inside_tree() else target.position) + Vector3.UP * _follow_height
	var bearing := Vector3(sin(_follow_yaw), 0.0, -cos(_follow_yaw))
	if _follow_heading:
		var basis_to_world := target.global_basis if target.is_inside_tree() else target.basis
		var back := Vector3(-basis_to_world.z.x, 0.0, -basis_to_world.z.z).normalized()
		if not back.is_zero_approx():
			bearing = back.rotated(Vector3.UP, -_follow_yaw)
	eye = focus + _follow_distance * (bearing * cos(_follow_pitch) + Vector3.UP * sin(_follow_pitch))


func _set_target(id: int, stack: Array) -> Dictionary:
	var moving := id == 3 or id == 4
	var count := 4 if moving else 3
	if stack.size() < count:
		return {"ok": false}
	var p := stack.size() - count
	var target := Vector3(
		StoryVm.as_float(stack[p]),
		StoryVm.as_float(stack[p + 1]),
		-StoryVm.as_float(stack[p + 2]),
	)
	var seconds := StoryVm.as_float(stack.back()) if moving else 0.0
	if not target.is_finite() or not is_finite(seconds):
		return {"ok": false}
	_follow_target = null
	if id in [2, 4]:
		_focus_follow_target = null
	var sets_eye := id == 1 or id == 3
	var motion := _eye_motion if sets_eye else _focus_motion
	var velocity := _motion_velocity(motion)
	motion.clear()
	if seconds < MOVE_EPSILON:
		if sets_eye:
			eye = target
		else:
			focus = target
	else:
		var start := eye if sets_eye else focus
		var displacement := target - start
		var travel := velocity * seconds
		# Original 1.2 scalar solver at 0x407D60: position and velocity
		# carry over on retarget. End velocity and acceleration are zero.
		motion["from"] = start
		motion["to"] = target
		motion["linear"] = travel
		motion["quadratic"] = 6.0 * displacement - 3.0 * travel
		motion["cubic"] = -8.0 * displacement + 3.0 * travel
		motion["quartic"] = 3.0 * displacement - travel
		motion["elapsed"] = 0.0
		motion["duration"] = seconds
	return _reply(count)


func _advance_motion(motion: Dictionary, delta: float) -> Vector3:
	motion["elapsed"] += delta
	var t := clampf(float(motion["elapsed"]) / float(motion["duration"]), 0.0, 1.0)
	if t >= 1.0:
		var destination: Vector3 = motion["to"]
		motion.clear()
		return destination
	return motion["from"] + t * (motion["linear"] + t * (motion["quadratic"] + t * (motion["cubic"] + t * motion["quartic"])))


func _motion_velocity(motion: Dictionary) -> Vector3:
	if motion.is_empty():
		return Vector3.ZERO
	var duration := float(motion["duration"])
	var t := float(motion["elapsed"]) / duration
	return (motion["linear"] + t * (2.0 * motion["quadratic"] + t * (3.0 * motion["cubic"] + t * 4.0 * motion["quartic"]))) / duration


func _reply(count: int, values: Array = []) -> Dictionary:
	return {"ok": true, "pop": count, "push": values}
