extends RefCounted
## SPEC-HAND-POINTER-DYNAMICS-001 v1
## Pure lagging hand pointer filter and linear pose blend.

const MAX_CURSOR_ABS: float = 1000000.0
const MAX_STEP_SECONDS: float = 0.25
const LAG_LIMIT: float = 80.0
const SPRING_RATE: float = 20.0
const DAMPING_BASE: float = 0.03

var _has_state: bool = false
var _lag_x: float = 0.0
var _lag_y: float = 0.0
var _velocity_x: float = 0.0
var _velocity_y: float = 0.0
var _slider_lr: float = 0.5
var _slider_fb: float = 0.5


static func _is_valid_cursor(cursor: Vector2) -> bool:
	if not is_finite(cursor.x) or not is_finite(cursor.y):
		return false
	return absf(cursor.x) <= MAX_CURSOR_ABS and absf(cursor.y) <= MAX_CURSOR_ABS


func reset(cursor: Vector2) -> bool:
	if not _is_valid_cursor(cursor):
		return false
	_lag_x = cursor.x
	_lag_y = cursor.y
	_velocity_x = 0.0
	_velocity_y = 0.0
	_slider_lr = 0.5
	_slider_fb = 0.5
	_has_state = true
	return true


func step(dt_seconds: float, cursor: Vector2) -> Dictionary:
	if not _has_state:
		return {}
	if not is_finite(dt_seconds) or dt_seconds < 0.0 or dt_seconds > MAX_STEP_SECONDS:
		return {}
	if not _is_valid_cursor(cursor):
		return {}
	var cx: float = cursor.x
	var cy: float = cursor.y
	var damping: float = pow(DAMPING_BASE, dt_seconds)
	var lag_x: float = _lag_x + dt_seconds * _velocity_x
	var lag_y: float = _lag_y + dt_seconds * _velocity_y
	lag_x = clampf(lag_x, cx - LAG_LIMIT, cx + LAG_LIMIT)
	lag_y = clampf(lag_y, cy - LAG_LIMIT, cy + LAG_LIMIT)
	var velocity_x: float = (_velocity_x + (cx - lag_x) * SPRING_RATE * dt_seconds) * damping
	var velocity_y: float = (_velocity_y + (cy - lag_y) * SPRING_RATE * dt_seconds) * damping
	if not is_finite(lag_x) or not is_finite(lag_y) or not is_finite(velocity_x) or not is_finite(velocity_y):
		return {}
	_lag_x = lag_x
	_lag_y = lag_y
	_velocity_x = velocity_x
	_velocity_y = velocity_y
	_slider_lr = (clampf(lag_x - cx, -LAG_LIMIT, LAG_LIMIT) + LAG_LIMIT) / (2.0 * LAG_LIMIT)
	_slider_fb = (clampf(cy - lag_y, -LAG_LIMIT, LAG_LIMIT) + LAG_LIMIT) / (2.0 * LAG_LIMIT)
	return state()


func state() -> Dictionary:
	if not _has_state:
		return {}
	return {
		'lag': Vector2(_lag_x, _lag_y),
		'velocity': Vector2(_velocity_x, _velocity_y),
		'sliders': Vector2(_slider_lr, _slider_fb),
	}


static func blend_pose(previous: Array[Transform3D], current: Array[Transform3D], progress: float) -> Array[Transform3D]:
	var empty: Array[Transform3D] = []
	if not is_finite(progress) or progress < 0.0 or progress > 1.0:
		return empty
	var count: int = previous.size()
	if count != current.size():
		return empty
	for i: int in range(count):
		if not previous[i].is_finite() or not current[i].is_finite():
			return empty
	var inverse: float = 1.0 - progress
	var result: Array[Transform3D] = []
	for i: int in range(count):
		var a: Transform3D = previous[i]
		var b: Transform3D = current[i]
		var x_axis: Vector3 = a.basis.x * inverse + b.basis.x * progress
		var y_axis: Vector3 = a.basis.y * inverse + b.basis.y * progress
		var z_axis: Vector3 = a.basis.z * inverse + b.basis.z * progress
		var origin: Vector3 = a.origin * inverse + b.origin * progress
		var blended: Transform3D = Transform3D(Basis(x_axis, y_axis, z_axis), origin)
		if not blended.is_finite():
			return empty
		result.append(blended)
	return result
