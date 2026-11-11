extends RefCounted
## SPEC-HAND-SURFACE-MOTION-001 v1
## Bounded ordinary-terrain hand following law. Pure RefCounted component:
## no geometry, parsing, input, animation, filesystem or network access.
## Special object/camera predicates and raw mesh unit conversion are caller scope.

const MIN_DEPTH: float = 2.0
const MIN_MAXIMUM_DISTANCE: float = 2.0
const MAX_MAXIMUM_DISTANCE: float = 1800.0
const MAX_BASE_SCALE: float = 10.0
const HAND_OFFSET_FACTOR: float = 3.2
const DURATION_OUTWARD: float = 0.28
const DURATION_INWARD: float = 0.1
const DURATION_SLOW_OUTWARD: float = 2.0
const DURATION_FACING: float = 0.4
const INTERNAL_DEPTH_FLOOR: float = 1.0

const SCALE_SMALL_LIMIT: float = 10.0
const SCALE_UNIT_LIMIT: float = 150.0
const SCALE_SMALL_EXPONENT: float = 0.8
const SCALE_FAR_SLOPE: float = 0.3
const SCALE_FAR_RANGE: float = 1650.0

var _configured: bool = false
var _has_state: bool = false
var _maximum_distance: float = 0.0
var _base_scale: float = 1.0

var _internal_depth: float = 0.0
var _depth_velocity: float = 0.0
var _limit: float = 0.0
var _render_depth: float = 0.0
var _scale: float = 1.0
## Unnormalized facing controller components kept as 64-bit floats.
var _normal_position: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.0])
var _normal_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])


func configure(maximum_distance: float, base_scale: float = 1.0) -> bool:
    if _configured:
        return false
    if not is_finite(maximum_distance) or not is_finite(base_scale):
        return false
    if maximum_distance < MIN_MAXIMUM_DISTANCE or maximum_distance > MAX_MAXIMUM_DISTANCE:
        return false
    if base_scale <= 0.0 or base_scale > MAX_BASE_SCALE:
        return false
    _maximum_distance = maximum_distance
    _base_scale = base_scale
    _configured = true
    return true


func reset(depth: float, normal: Vector3 = Vector3.UP) -> bool:
    if not _configured:
        return false
    if not is_finite(depth):
        return false
    var unit: PackedFloat64Array = _normalize_triplet(float(normal.x), float(normal.y), float(normal.z))
    if unit.is_empty():
        return false
    var clamped_depth: float = clampf(depth, MIN_DEPTH, _maximum_distance)
    _internal_depth = clamped_depth
    _depth_velocity = 0.0
    _limit = clamped_depth
    _render_depth = clamped_depth
    _scale = _scale_for_depth(clamped_depth)
    _normal_position = unit
    _normal_velocity = PackedFloat64Array([0.0, 0.0, 0.0])
    _has_state = true
    return true


func step(delta: float, facing_delta: float, surface_distance: float, target_normal: Vector3, slow_outward: bool = false) -> Dictionary:
    if not _configured or not _has_state:
        return {}
    if not is_finite(delta) or delta < 0.0:
        return {}
    if not is_finite(facing_delta) or facing_delta < 0.0:
        return {}
    if not is_finite(surface_distance) or surface_distance <= 0.0:
        return {}
    var target_unit: PackedFloat64Array = _normalize_triplet(float(target_normal.x), float(target_normal.y), float(target_normal.z))
    if target_unit.is_empty():
        return {}

    # Limit uses the scale cached from the previous valid output/reset.
    var limit: float = clampf(surface_distance - HAND_OFFSET_FACTOR * _scale * _base_scale, MIN_DEPTH, _maximum_distance)

    # Depth response is rebuilt every step, preserving current position/velocity.
    var duration: float = DURATION_INWARD
    if limit >= _internal_depth:
        duration = DURATION_SLOW_OUTWARD if slow_outward else DURATION_OUTWARD
    var depth_result: PackedFloat64Array = _advance_scalar(_internal_depth, _depth_velocity, limit, delta, duration)
    _internal_depth = maxf(depth_result[0], INTERNAL_DEPTH_FLOOR)
    _depth_velocity = depth_result[1]
    _limit = limit
    _render_depth = clampf(minf(_internal_depth, limit), MIN_DEPTH, _maximum_distance)

    # Facing components are retargeted independently every step.
    var new_position: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
    var new_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
    for axis: int in range(3):
        var component: PackedFloat64Array = _advance_scalar(_normal_position[axis], _normal_velocity[axis], target_unit[axis], facing_delta, DURATION_FACING)
        new_position[axis] = component[0]
        new_velocity[axis] = component[1]
    _normal_position = new_position
    _normal_velocity = new_velocity

    # Scale is evaluated at rendered depth and cached for the next limit.
    _scale = _scale_for_depth(_render_depth)
    return _snapshot()


func state() -> Dictionary:
    if not _has_state:
        return {}
    return _snapshot()


func _snapshot() -> Dictionary:
    return {
        'internal_depth': _internal_depth,
        'depth_velocity': _depth_velocity,
        'limit': _limit,
        'render_depth': _render_depth,
        'scale': _scale,
        'normal': _output_normal(),
        'normal_velocity': Vector3(_normal_velocity[0], _normal_velocity[1], _normal_velocity[2]),
    }


func _output_normal() -> Vector3:
    var unit: PackedFloat64Array = _normalize_triplet(_normal_position[0], _normal_position[1], _normal_position[2])
    if unit.is_empty():
        return Vector3.UP
    return Vector3(unit[0], unit[1], unit[2])


## Scalar response from p0/v0 toward target with zero terminal velocity and acceleration.
## Returns [position, velocity].
static func _advance_scalar(p0: float, v0: float, target: float, dt: float, duration: float) -> PackedFloat64Array:
    if dt <= 0.0:
        return PackedFloat64Array([p0, v0])
    if dt >= duration:
        return PackedFloat64Array([target, 0.0])
    var t: float = minf(dt / duration, 1.0)
    var one_minus: float = 1.0 - t
    var t2: float = t * t
    var t3: float = t2 * t
    var t4: float = t3 * t
    var f: float = 6.0 * t2 - 8.0 * t3 + 3.0 * t4
    var g: float = t * one_minus * one_minus * one_minus
    var offset: float = target - p0
    var p: float = p0 + offset * f + v0 * duration * g
    var v: float = offset * 12.0 * t * one_minus * one_minus / duration + v0 * one_minus * one_minus * (1.0 - 4.0 * t)
    return PackedFloat64Array([p, v])


## Dimensionless hand scale evaluated at rendered depth.
static func _scale_for_depth(d: float) -> float:
    if d < SCALE_SMALL_LIMIT:
        return pow(d / SCALE_SMALL_LIMIT, SCALE_SMALL_EXPONENT)
    if d <= SCALE_UNIT_LIMIT:
        return 1.0
    return (1.0 - SCALE_FAR_SLOPE * (d - SCALE_UNIT_LIMIT) / SCALE_FAR_RANGE) * (d / SCALE_UNIT_LIMIT)


## Normalizes a finite nonzero direction without overflowing the length computation.
## Returns an empty array when the input is not finite or numerically zero.
static func _normalize_triplet(x: float, y: float, z: float) -> PackedFloat64Array:
    if not is_finite(x) or not is_finite(y) or not is_finite(z):
        return PackedFloat64Array()
    var magnitude: float = maxf(absf(x), maxf(absf(y), absf(z)))
    if magnitude == 0.0 or not is_finite(magnitude):
        return PackedFloat64Array()
    var sx: float = x / magnitude
    var sy: float = y / magnitude
    var sz: float = z / magnitude
    var scaled_length: float = sqrt(sx * sx + sy * sy + sz * sz)
    if scaled_length == 0.0 or not is_finite(scaled_length):
        return PackedFloat64Array()
    return PackedFloat64Array([sx / scaled_length, sy / scaled_length, sz / scaled_length])
