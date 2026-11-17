extends Node3D
## Visual orbit controller (SPEC-ORBIT-ACTORS-001 v3).
##
## Places host-owned plain Node3D actor containers on a horizontal circle in
## this controller's local space. This is presentation policy only. The
## controller never creates, reparents or frees nodes. It never connects
## signals and never processes automatically. The host drives it explicitly
## through advance().

const MAX_ACTORS: int = 64
const MAX_RADIUS: float = 1000.0
const MAX_HEIGHT: float = 1000.0
const MAX_ANGULAR_SPEED: float = 5.0
const MAX_DELTA: float = 36000.0
const MAX_AGE: float = 1.0e9
const ACTOR_CLASS: String = 'Node3D'

var _configured: bool = false
var _actors: Array = []
var _count: int = 0
var _radius: float = 0.0
var _height: float = 0.0
var _angular_speed: float = 0.0
var _age: float = 0.0


## Validates the whole request first, then commits it and places every actor
## at age 0. Succeeds at most once, and only while this controller is inside
## the SceneTree. Any failure returns false without mutating anything.
func configure(actors: Array, radius: float, height: float, angular_speed: float) -> bool:
    if _configured:
        return false
    if not is_inside_tree():
        return false
    if not _is_radius_valid(radius):
        return false
    if not _is_height_valid(height):
        return false
    if not _is_speed_valid(angular_speed):
        return false
    var actor_count: int = actors.size()
    if actor_count < 1 or actor_count > MAX_ACTORS:
        return false
    var seen_ids: Dictionary = {}
    var staged: Array = []
    for i: int in range(actor_count):
        var candidate: Variant = actors[i]
        if not _is_actor_valid(candidate):
            return false
        var actor: Node3D = candidate as Node3D
        var actor_id: int = actor.get_instance_id()
        if seen_ids.has(actor_id):
            return false
        seen_ids[actor_id] = true
        staged.append(actor)
    # Commit: everything has been validated, nothing below can fail.
    _actors = staged
    _count = actor_count
    _radius = radius
    _height = height
    _angular_speed = angular_speed
    _age = 0.0
    _configured = true
    _apply_placement(0.0)
    return true


## Advances the float64 age by delta and reapplies placement. Every retained
## actor and the controller are validated before anything is changed.
func advance(delta: float) -> bool:
    if not _configured:
        return false
    if not is_inside_tree():
        return false
    if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA:
        return false
    var next_age: float = _age + delta
    if not is_finite(next_age) or next_age > MAX_AGE:
        return false
    for i: int in range(_count):
        # A freed actor stays invalid forever, so advancement fails permanently.
        if not _is_actor_valid(_actors[i]):
            return false
    _age = next_age
    _apply_placement(next_age)
    return true


## Returns {} before configure, otherwise a fresh Dictionary with exactly the
## String keys age, radius, height, angular_speed (float) and count (int).
func snapshot() -> Dictionary:
    if not _configured:
        return {}
    var result: Dictionary = {}
    result['age'] = _age
    result['radius'] = _radius
    result['height'] = _height
    result['angular_speed'] = _angular_speed
    result['count'] = _count
    return result


func _is_radius_valid(value: float) -> bool:
    return is_finite(value) and value > 0.0 and value <= MAX_RADIUS


func _is_height_valid(value: float) -> bool:
    return is_finite(value) and value >= 0.0 and value <= MAX_HEIGHT


func _is_speed_valid(value: float) -> bool:
    return is_finite(value) and value >= -MAX_ANGULAR_SPEED and value <= MAX_ANGULAR_SPEED


func _is_actor_valid(candidate: Variant) -> bool:
    # Validity is checked before any type check or member access.
    if not is_instance_valid(candidate):
        return false
    if not (candidate is Node3D):
        return false
    var actor: Node3D = candidate as Node3D
    if actor.get_class() != ACTOR_CLASS:
        return false
    if actor.get_parent() != self:
        return false
    if not actor.is_inside_tree():
        return false
    if actor.top_level:
        return false
    if actor.rotation_order != EULER_ORDER_YXZ:
        return false
    if actor.rotation_edit_mode != Node3D.ROTATION_EDIT_MODE_EULER:
        return false
    var current_rotation: Vector3 = actor.rotation
    if not current_rotation.is_finite():
        return false
    var current_scale: Vector3 = actor.scale
    if not current_scale.is_finite():
        return false
    if current_scale.x <= 0.0 or current_scale.y <= 0.0 or current_scale.z <= 0.0:
        return false
    if _subtree_has_script(actor):
        return false
    return true


func _subtree_has_script(top: Node) -> bool:
    var pending: Array[Node] = [top]
    while not pending.is_empty():
        var current: Node = pending.pop_back()
        if current.get_script() != null:
            return true
        for child: Node in current.get_children(true):
            pending.append(child)
    return false


func _apply_placement(next_age: float) -> void:
    var count_float: float = float(_count)
    for i: int in range(_count):
        var actor: Node3D = _actors[i] as Node3D
        var phase: float = (float(i) * TAU) / count_float
        var angle: float = fposmod(next_age * _angular_speed + phase, TAU)
        var target: Vector3 = Vector3(_radius * cos(angle), _height, _radius * sin(angle))
        var yaw: float = 0.0
        if _angular_speed != 0.0:
            var direction_sign: float = signf(_angular_speed)
            yaw = atan2(-direction_sign * sin(angle), direction_sign * cos(angle))
        actor.position = target
        var current: Vector3 = actor.rotation
        actor.rotation = Vector3(current.x, yaw, current.z)
