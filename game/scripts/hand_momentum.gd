extends RefCounted
## Remake release-velocity estimator (SPEC-HAND-MOMENTUM-001 v1).
## Pure computation from caller-supplied world positions and game-time seconds.
## No input, physics, scene, clock, filesystem or network access.

const MAX_SAMPLES: int = 64
const MIN_SPAN: float = 1e-6

var _configured: bool = false
var _max_speed: float = 180.0
var _window: float = 0.12
var _stale: float = 0.1
var _minimum: float = 2.0

var _active: bool = false
var _points: PackedVector3Array = PackedVector3Array()
var _times: PackedFloat64Array = PackedFloat64Array()


func configure(max_speed: float = 180.0, window: float = 0.12, stale: float = 0.1, minimum: float = 2.0) -> bool:
	if _configured:
		return false
	if not (is_finite(max_speed) and is_finite(window) and is_finite(stale) and is_finite(minimum)):
		return false
	if max_speed <= 0.0:
		return false
	var probe: Vector3 = Vector3(max_speed, 0.0, 0.0)
	if not is_finite(probe.x) or probe.x <= 0.0:
		return false
	if window <= 0.0 or window > 1.0:
		return false
	if stale < 0.0 or stale > 1.0:
		return false
	if minimum < 0.0 or minimum > max_speed:
		return false
	_max_speed = max_speed
	_window = window
	_stale = stale
	_minimum = minimum
	_configured = true
	return true


func begin(point: Vector3, time: float) -> bool:
	if not _configured:
		return false
	if not point.is_finite():
		return false
	if not is_finite(time) or time < 0.0:
		return false
	_points.clear()
	_times.clear()
	_points.append(point)
	_times.append(time)
	_active = true
	return true


func sample(point: Vector3, time: float) -> void:
	if not _active:
		return
	if not point.is_finite():
		return
	if not is_finite(time) or time < 0.0:
		return
	var last_index: int = _times.size() - 1
	if last_index < 0:
		return
	var last_time: float = _times[last_index]
	if time < last_time:
		return
	if time == last_time:
		_points[last_index] = point
		return
	_points.append(point)
	_times.append(time)
	while _times.size() > MAX_SAMPLES:
		_points.remove_at(0)
		_times.remove_at(0)
	var cutoff: float = time - _window
	while _times.size() > 1 and _times[0] < cutoff:
		_points.remove_at(0)
		_times.remove_at(0)


func finish(time: float) -> Vector3:
	var result: Vector3 = _evaluate(time)
	cancel()
	return result


func cancel() -> void:
	_active = false
	_points.clear()
	_times.clear()


func _evaluate(time: float) -> Vector3:
	if not _active:
		return Vector3.ZERO
	var count: int = _times.size()
	if count < 2 or _points.size() != count:
		return Vector3.ZERO
	if not is_finite(time) or time < 0.0:
		return Vector3.ZERO
	var first_time: float = _times[0]
	var last_time: float = _times[count - 1]
	if time < last_time:
		return Vector3.ZERO
	if time - last_time > _stale:
		return Vector3.ZERO
	var span: float = last_time - first_time
	if not is_finite(span) or span <= MIN_SPAN:
		return Vector3.ZERO
	var first_point: Vector3 = _points[0]
	var last_point: Vector3 = _points[count - 1]
	# GDScript float arithmetic is 64-bit, so large float32 components do not overflow here.
	var dx: float = last_point.x - first_point.x
	var dy: float = last_point.y - first_point.y
	var dz: float = last_point.z - first_point.z
	if not (is_finite(dx) and is_finite(dy) and is_finite(dz)):
		return Vector3.ZERO
	var vx: float = dx / span
	var vy: float = dy / span
	var vz: float = dz / span
	if not (is_finite(vx) and is_finite(vy) and is_finite(vz)):
		return Vector3.ZERO
	var magnitude: float = _stable_length(vx, vy, vz)
	if not is_finite(magnitude) or magnitude <= 0.0:
		return Vector3.ZERO
	var factor: float = 1.0
	var final_magnitude: float = magnitude
	if magnitude > _max_speed:
		factor = _max_speed / magnitude
		final_magnitude = _max_speed
	if final_magnitude < _minimum:
		return Vector3.ZERO
	var result: Vector3 = Vector3(vx * factor, vy * factor, vz * factor)
	if not result.is_finite():
		return Vector3.ZERO
	if result == Vector3.ZERO:
		return Vector3.ZERO
	return result


func _stable_length(x: float, y: float, z: float) -> float:
	var ax: float = absf(x)
	var ay: float = absf(y)
	var az: float = absf(z)
	var largest: float = maxf(ax, maxf(ay, az))
	if largest == 0.0:
		return 0.0
	if not is_finite(largest):
		return INF
	var sx: float = ax / largest
	var sy: float = ay / largest
	var sz: float = az / largest
	return largest * sqrt(sx * sx + sy * sy + sz * sz)
