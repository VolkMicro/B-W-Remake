extends SceneTree
## Standalone synthetic tests for orbit_actors.gd (SPEC-ORBIT-ACTORS-001 v3).
## Run: godot --headless --script <absolute path to this file>
## The module is loaded relative to this script directory (no class_name).
## Exits with quit(0) when all checks pass and quit(1) otherwise. A real-time
## deadline guard forces quit(1) if anything waits for too long.

const MODULE_FILE: String = 'orbit_actors.gd'
const DEADLINE_SEC: float = 120.0
const HEADING_TOL: float = 1e-5

const DOMAIN_KINDS: Array[String] = [
    'top_level', 'order_xyz', 'order_zxy', 'mode_quaternion', 'mode_basis',
    'scale_zero', 'scale_negative', 'scale_inf', 'scale_nan',
    'rotation_nan', 'rotation_inf', 'actor_script', 'descendant_script',
    'internal_script',
]
const REQUEST_KINDS: Array[String] = [
    'count0', 'count65', 'duplicate', 'grandchild', 'root_child', 'orphan',
    'freed', 'null', 'int', 'refcounted', 'resource', 'plain_node',
    'mesh_instance', 'marker', 'bad_first',
]

var _module: GDScript = null
var _checks: int = 0
var _failures: int = 0
var _finished: bool = false
var _section: String = ''
var _loose_nodes: Array = []
var _scratch_script: GDScript = null


func _initialize() -> void:
    var guard: SceneTreeTimer = create_timer(DEADLINE_SEC, true, false, true)
    guard.timeout.connect(_on_deadline)
    _begin.call_deferred()


func _on_deadline() -> void:
    if _finished:
        return
    _finished = true
    printerr('FAIL: deadline of %s s exceeded in section [%s]' % [str(DEADLINE_SEC), _section])
    quit(1)


func _begin() -> void:
    _section = 'startup'
    while not root.is_inside_tree():
        await process_frame
    var own_script: Script = get_script() as Script
    var module_path: String = 'res://scripts/' + MODULE_FILE
    _module = load(module_path) as GDScript
    if _module == null:
        _check(false, 'module loads from ' + module_path)
        _finish()
        return
    await _run_all()
    _finish()


func _finish() -> void:
    if _finished:
        return
    _finished = true
    _section = 'teardown'
    for item: Variant in _loose_nodes:
        if is_instance_valid(item):
            var node: Node = item as Node
            if node != null:
                var parent_node: Node = node.get_parent()
                if parent_node != null:
                    parent_node.remove_child(node)
                node.free()
    _loose_nodes.clear()
    if _failures == 0:
        print('PASS: %d checks passed' % _checks)
        quit(0)
    else:
        printerr('FAIL: %d of %d checks failed' % [_failures, _checks])
        quit(1)


func _run_all() -> void:
    _test_module_shape()
    _test_before_configure()
    _test_phases()
    _test_speed_signs()
    _test_quarter_turns()
    _test_delta_zero()
    _test_partitioning()
    _test_large_delta()
    _test_large_age()
    _test_bounds_accepted()
    _test_int_coercion()
    _test_tilt_scale_preservation()
    _test_invalid_scalars()
    _test_invalid_actors()
    _test_repeated_configure()
    _test_tree_exit_reentry()
    _test_remove_reparent_restore()
    _test_domain_changes_in_advance()
    _test_freed_actor_permanence()
    _test_input_and_snapshot_mutation()
    _test_parent_scale()
    _test_failed_advance_preserves_age()
    await _test_no_process_movement()


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr('FAIL [%s]: %s' % [_section, message])


func _new_controller(parent_node: Node) -> Node3D:
    var instance: Object = _module.new()
    var controller: Node3D = instance as Node3D
    if controller != null and parent_node != null:
        parent_node.add_child(controller)
    return controller


func _new_actors(controller: Node3D, amount: int) -> Array:
    var result: Array = []
    for i: int in range(amount):
        var actor: Node3D = Node3D.new()
        actor.name = 'Actor%d' % i
        controller.add_child(actor)
        result.append(actor)
    return result


func _cleanup(node: Node) -> void:
    if not is_instance_valid(node):
        return
    var parent_node: Node = node.get_parent()
    if parent_node != null:
        parent_node.remove_child(node)
    node.free()


func _configure(controller: Node, actors: Array, radius: float, height: float, speed: float) -> bool:
    var result: Variant = controller.call('configure', actors, radius, height, speed)
    return typeof(result) == TYPE_BOOL and bool(result)


func _advance(controller: Node, delta_value: float) -> bool:
    var result: Variant = controller.call('advance', delta_value)
    return typeof(result) == TYPE_BOOL and bool(result)


func _snapshot(controller: Node) -> Dictionary:
    var result: Variant = controller.call('snapshot')
    if typeof(result) != TYPE_DICTIONARY:
        _check(false, 'snapshot returns a Dictionary')
        return {}
    return result


func _exp_angle(age: float, speed: float, index: int, amount: int) -> float:
    var phase: float = (float(index) * TAU) / float(amount)
    return fposmod(age * speed + phase, TAU)


func _exp_yaw(angle: float, speed: float) -> float:
    if speed == 0.0:
        return 0.0
    var direction_sign: float = signf(speed)
    return atan2(-direction_sign * sin(angle), direction_sign * cos(angle))


func _pos_tol(radius: float, height: float) -> float:
    return 1e-5 + 1e-6 * maxf(1.0, maxf(radius, height))


func _heading_diff(a: float, b: float) -> float:
    return absf(fposmod(a - b + PI, TAU) - PI)


func _is_negative_zero(value: float) -> bool:
    return value == 0.0 and atan2(0.0, value) > 1.0


func _vec_close(a: Vector3, b: Vector3, tol: float) -> bool:
    return absf(a.x - b.x) <= tol and absf(a.y - b.y) <= tol and absf(a.z - b.z) <= tol


func _check_actor(actor: Node3D, age: float, radius: float, height: float, speed: float, index: int, amount: int, label: String) -> void:
    var angle: float = _exp_angle(age, speed, index, amount)
    var tol: float = _pos_tol(radius, height)
    var p: Vector3 = actor.position
    var ex: float = radius * cos(angle)
    var ez: float = radius * sin(angle)
    var ok_pos: bool = absf(p.x - ex) <= tol and absf(p.y - height) <= tol and absf(p.z - ez) <= tol
    _check(ok_pos, '%s: actor %d position %s expected (%s, %s, %s)' % [label, index, str(p), str(ex), str(height), str(ez)])
    var yaw: float = _exp_yaw(angle, speed)
    var got_yaw: float = actor.rotation.y
    _check(_heading_diff(got_yaw, yaw) <= HEADING_TOL, '%s: actor %d yaw %s expected %s' % [label, index, str(got_yaw), str(yaw)])


func _check_all(actors: Array, age: float, radius: float, height: float, speed: float, label: String) -> void:
    var amount: int = actors.size()
    for i: int in range(amount):
        _check_actor(actors[i] as Node3D, age, radius, height, speed, i, amount, label)


func _check_tangents(actors: Array, age: float, speed: float, label: String) -> void:
    if speed == 0.0:
        return
    var amount: int = actors.size()
    var direction_sign: float = signf(speed)
    for i: int in range(amount):
        var actor: Node3D = actors[i] as Node3D
        var angle: float = _exp_angle(age, speed, i, amount)
        var expected_dir: Vector3 = Vector3(-direction_sign * sin(angle), 0.0, direction_sign * cos(angle))
        var plus_z: Vector3 = actor.basis.z.normalized()
        _check(plus_z.distance_to(expected_dir) <= 1e-5, '%s: actor %d +Z %s follows tangent %s' % [label, i, str(plus_z), str(expected_dir)])


func _check_snapshot(controller: Node, age: float, radius: float, height: float, speed: float, count: int, label: String) -> void:
    var snap: Dictionary = _snapshot(controller)
    _check(snap.size() == 5, '%s: snapshot has exactly five keys %s' % [label, str(snap)])
    for key: Variant in snap.keys():
        _check(typeof(key) == TYPE_STRING, '%s: snapshot key %s is a String' % [label, str(key)])
    var expected: Dictionary = {'age': age, 'radius': radius, 'height': height, 'angular_speed': speed}
    for field: Variant in expected.keys():
        var value: Variant = snap.get(field)
        _check(typeof(value) == TYPE_FLOAT, '%s: snapshot %s is a float' % [label, str(field)])
        if typeof(value) == TYPE_FLOAT:
            var got: float = value
            var want: float = expected[field]
            _check(got == want, '%s: snapshot %s = %s expected %s' % [label, str(field), str(got), str(want)])
            if want == 0.0:
                _check(_is_negative_zero(got) == _is_negative_zero(want), '%s: snapshot %s keeps zero sign' % [label, str(field)])
    var count_value: Variant = snap.get('count')
    _check(typeof(count_value) == TYPE_INT and int(count_value) == count, '%s: snapshot count %s expected %d' % [label, str(count_value), count])


func _snapshot_age(controller: Node) -> float:
    var value: Variant = _snapshot(controller).get('age')
    if typeof(value) != TYPE_FLOAT:
        return NAN
    return value


func _capture(nodes: Array) -> Array:
    var out: Array = []
    for item: Variant in nodes:
        if not is_instance_valid(item):
            out.append(null)
            continue
        var node: Node3D = item as Node3D
        if node == null:
            out.append(null)
            continue
        var parent_node: Node = node.get_parent()
        var index: int = -1
        if parent_node != null:
            index = node.get_index()
        out.append([node.position, node.rotation, node.scale, node.transform, parent_node, index])
    return out


func _runtime_script() -> GDScript:
    if _scratch_script == null:
        _scratch_script = GDScript.new()
        _scratch_script.source_code = 'extends Node\n'
        var err: Error = _scratch_script.reload()
        _check(err == OK, 'runtime rejection script compiles')
    return _scratch_script


func _apply_bad_state(kind: String, target: Node3D) -> void:
    match kind:
        'top_level':
            target.top_level = true
        'order_xyz':
            target.rotation_order = EULER_ORDER_XYZ
        'order_zxy':
            target.rotation_order = EULER_ORDER_ZXY
        'mode_quaternion':
            target.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_QUATERNION
        'mode_basis':
            target.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_BASIS
        'scale_zero':
            target.scale = Vector3(1.0, 0.0, 1.0)
        'scale_negative':
            target.scale = Vector3(1.0, 1.0, -2.0)
        'scale_inf':
            target.scale = Vector3(INF, 1.0, 1.0)
        'scale_nan':
            target.scale = Vector3(1.0, NAN, 1.0)
        'rotation_nan':
            target.rotation = Vector3(NAN, 0.0, 0.0)
        'rotation_inf':
            target.rotation = Vector3(0.0, 0.0, INF)
        'actor_script':
            target.set_script(_runtime_script())
        'descendant_script':
            var middle: Node3D = Node3D.new()
            middle.name = 'Middle'
            target.add_child(middle)
            var leaf: Node = Node.new()
            leaf.name = 'ScriptedLeaf'
            middle.add_child(leaf)
            leaf.set_script(_runtime_script())
        'internal_script':
            var hidden: Node = Node.new()
            hidden.name = 'ScriptedInternal'
            target.add_child(hidden, false, Node.INTERNAL_MODE_BACK)
            hidden.set_script(_runtime_script())
        _:
            _check(false, 'unknown bad state kind ' + kind)


func _clear_scripts(top: Node) -> void:
    var pending: Array[Node] = [top]
    while not pending.is_empty():
        var current: Node = pending.pop_back()
        if current.get_script() != null:
            current.set_script(null)
        for child: Node in current.get_children(true):
            pending.append(child)


func _restore_state(target: Node3D, saved_rotation: Vector3, saved_scale: Vector3) -> void:
    _clear_scripts(target)
    target.top_level = false
    target.rotation_order = EULER_ORDER_YXZ
    target.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_EULER
    target.scale = saved_scale
    target.rotation = saved_rotation


func _build_request(kind: String, controller: Node3D, good: Array) -> Array:
    var request: Array = good.duplicate()
    match kind:
        'valid':
            pass
        'count0':
            request = []
        'count65':
            for i: int in range(65 - good.size()):
                var extra: Node3D = Node3D.new()
                controller.add_child(extra)
                request.append(extra)
        'duplicate':
            request.append(good[0])
        'grandchild':
            var nested: Node3D = Node3D.new()
            (good[1] as Node3D).add_child(nested)
            request.append(nested)
        'root_child':
            var stranger: Node3D = Node3D.new()
            root.add_child(stranger)
            _loose_nodes.append(stranger)
            request.append(stranger)
        'orphan':
            var orphan: Node3D = Node3D.new()
            _loose_nodes.append(orphan)
            request.append(orphan)
        'freed':
            var doomed: Node3D = Node3D.new()
            controller.add_child(doomed)
            doomed.free()
            request.append(doomed)
        'null':
            request.append(null)
        'int':
            request.append(42)
        'refcounted':
            request.append(RefCounted.new())
        'resource':
            request.append(Resource.new())
        'plain_node':
            var plain: Node = Node.new()
            controller.add_child(plain)
            request.append(plain)
        'mesh_instance':
            var mesh_node: MeshInstance3D = MeshInstance3D.new()
            controller.add_child(mesh_node)
            request.append(mesh_node)
        'marker':
            var marker: Marker3D = Marker3D.new()
            controller.add_child(marker)
            request.append(marker)
        'bad_first':
            var first: Node3D = Node3D.new()
            controller.add_child(first)
            _apply_bad_state('actor_script', first)
            request.push_front(first)
        _:
            var bad: Node3D = Node3D.new()
            controller.add_child(bad)
            _apply_bad_state(kind, bad)
            request.append(bad)
    return request


func _expect_configure_reject(label: String, kind: String, radius: float, height: float, speed: float) -> void:
    _section = 'configure reject: ' + label
    var controller: Node3D = _new_controller(root)
    var good: Array = _new_actors(controller, 2)
    (good[0] as Node3D).position = Vector3(0.25, -0.5, 0.75)
    (good[1] as Node3D).rotation = Vector3(0.0, 0.4, 0.0)
    var request: Array = _build_request(kind, controller, good)
    var before: Array = _capture(good)
    var children_before: Array = controller.get_children(true)
    _check(not _configure(controller, request, radius, height, speed), 'configure must return false')
    _check(_snapshot(controller).is_empty(), 'snapshot stays empty after rejected configure')
    _check(_capture(good) == before, 'earlier valid actors were not mutated')
    _check(controller.get_children(true) == children_before, 'hierarchy was not mutated')
    _check(not _advance(controller, 1.0), 'advance still fails after rejected configure')
    _check(_configure(controller, good, 2.0, 1.0, 0.5), 'controller still accepts a valid first configure')
    _check_all(good, 0.0, 2.0, 1.0, 0.5, 'post-reject configure')
    _cleanup(controller)


# ---------------------------------------------------------------- tests

func _test_module_shape() -> void:
    _section = 'module shape'
    _check(str(_module.get_global_name()).is_empty(), 'module declares no class_name')
    var method_names: Array = []
    for info: Dictionary in _module.get_script_method_list():
        method_names.append(str(info.get('name', '')))
    for required: String in ['configure', 'advance', 'snapshot']:
        _check(method_names.has(required), 'module defines ' + required)
    for forbidden: String in ['_process', '_physics_process', '_input', '_unhandled_input', '_notification']:
        _check(not method_names.has(forbidden), 'module does not define ' + forbidden)
    var controller: Node3D = _new_controller(root)
    _check(controller != null, 'module instantiates as a Node3D')
    if controller == null:
        return
    _check(not controller.is_processing(), 'controller does not process')
    _check(not controller.is_physics_processing(), 'controller does not physics-process')
    _check(not controller.is_processing_input(), 'controller does not process input')
    _cleanup(controller)


func _test_before_configure() -> void:
    _section = 'before configure'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 2)
    var before: Array = _capture(actors)
    _check(_snapshot(controller).is_empty(), 'snapshot is empty before configure')
    _check(not _advance(controller, 1.0), 'advance fails before configure')
    _check(not _advance(controller, 0.0), 'advance(0) fails before configure')
    _check(_capture(actors) == before, 'actors untouched before configure')
    _check(_snapshot(controller).is_empty(), 'snapshot still empty')
    _cleanup(controller)


func _test_phases() -> void:
    for amount: int in [1, 3, 20]:
        _section = 'phases N=%d' % amount
        var controller: Node3D = _new_controller(root)
        var actors: Array = _new_actors(controller, amount)
        var r: float = 2.5
        var h: float = 1.25
        var w: float = 0.75
        _check(_configure(controller, actors, r, h, w), 'configure succeeds')
        _check_snapshot(controller, 0.0, r, h, w, amount, 'initial')
        _check_all(actors, 0.0, r, h, w, 'initial')
        _check_tangents(actors, 0.0, w, 'initial')
        for i: int in range(amount):
            var expected_phase: float = (float(i) * TAU) / float(amount)
            var p: Vector3 = (actors[i] as Node3D).position
            _check(_heading_diff(atan2(p.z, p.x), expected_phase) <= 1e-5, 'actor %d sits at its configure phase' % i)
        _check(_advance(controller, 0.4), 'advance 0.4')
        _check_snapshot(controller, 0.4, r, h, w, amount, 'after 0.4')
        _check_all(actors, 0.4, r, h, w, 'after 0.4')
        _check_tangents(actors, 0.4, w, 'after 0.4')
        _cleanup(controller)


func _test_speed_signs() -> void:
    var speeds: Array = [-1.3, 0.0, -0.0, 1e-310, -1e-310, 5.0, -5.0]
    for speed_value: Variant in speeds:
        var w: float = speed_value
        _section = 'speed ' + str(w)
        var controller: Node3D = _new_controller(root)
        var actors: Array = _new_actors(controller, 3)
        var r: float = 3.0
        var h: float = 0.5
        _check(_configure(controller, actors, r, h, w), 'configure succeeds')
        _check_snapshot(controller, 0.0, r, h, w, 3, 'initial')
        _check_all(actors, 0.0, r, h, w, 'initial')
        _check_tangents(actors, 0.0, w, 'initial')
        var initial_positions: Array = []
        for actor_value: Variant in actors:
            initial_positions.append((actor_value as Node3D).position)
        _check(_advance(controller, 0.75), 'advance 0.75')
        _check_snapshot(controller, 0.75, r, h, w, 3, 'after 0.75')
        _check_all(actors, 0.75, r, h, w, 'after 0.75')
        _check_tangents(actors, 0.75, w, 'after 0.75')
        if w == 0.0:
            for i: int in range(3):
                var actor: Node3D = actors[i] as Node3D
                _check(_vec_close(actor.position, initial_positions[i], _pos_tol(r, h)), 'zero speed keeps actor %d still' % i)
                _check(actor.rotation.y == 0.0, 'zero speed yaw is 0 for actor %d' % i)
        _cleanup(controller)


func _test_quarter_turns() -> void:
    _section = 'quarter turns'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 4)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = TAU / 4.0
    var tol: float = _pos_tol(r, h)
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    var table: Array[Vector3] = [Vector3(r, h, 0.0), Vector3(0.0, h, r), Vector3(-r, h, 0.0), Vector3(0.0, h, -r)]
    var yaw_table: Array[float] = [0.0, -PI / 2.0, PI, PI / 2.0]
    for i: int in range(4):
        var actor_at_start: Node3D = actors[i] as Node3D
        _check(_vec_close(actor_at_start.position, table[i], tol), 'actor %d starts at quarter %d' % [i, i])
    for k: int in range(1, 9):
        _check(_advance(controller, 1.0), 'advance quarter %d' % k)
        _check_all(actors, float(k), r, h, w, 'quarter %d' % k)
        var first: Node3D = actors[0] as Node3D
        _check(_vec_close(first.position, table[k % 4], tol), 'actor 0 at quarter %d position %s' % [k, str(first.position)])
        _check(_heading_diff(first.rotation.y, yaw_table[k % 4]) <= HEADING_TOL, 'actor 0 yaw at quarter %d is %s' % [k, str(first.rotation.y)])
    _check_snapshot(controller, 8.0, r, h, w, 4, 'after eight quarters')
    _cleanup(controller)


func _test_delta_zero() -> void:
    _section = 'delta zero'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 1.5
    var h: float = 0.25
    var w: float = 0.9
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 0.7), 'advance 0.7')
    for actor_value: Variant in actors:
        var actor: Node3D = actor_value as Node3D
        actor.position = Vector3(99.0, -99.0, 99.0)
        actor.rotation = Vector3(actor.rotation.x, 2.0, actor.rotation.z)
    _check(_advance(controller, 0.0), 'advance(0) succeeds')
    _check_snapshot(controller, 0.7, r, h, w, 3, 'after delta 0')
    _check_all(actors, 0.7, r, h, w, 'delta 0 reapplies placement')
    _cleanup(controller)


func _test_partitioning() -> void:
    _section = 'partitioning'
    var r: float = 3.0
    var h: float = 0.75
    var w: float = -1.1
    var tol: float = _pos_tol(r, h)
    var tenths: Array = []
    for k: int in range(30):
        tenths.append(0.1)
    var partitions: Array = [[3.0], tenths, [1.5, 0.75, 0.5, 0.25], [0.0, 2.9, 0.0, 0.1]]
    var reference: Array = []
    for p_index: int in range(partitions.size()):
        var deltas: Array = partitions[p_index]
        var controller: Node3D = _new_controller(root)
        var actors: Array = _new_actors(controller, 3)
        _check(_configure(controller, actors, r, h, w), 'configure partition %d' % p_index)
        var expected_age: float = 0.0
        for d: Variant in deltas:
            var delta_value: float = d
            expected_age += delta_value
            _check(_advance(controller, delta_value), 'advance partition %d by %s' % [p_index, str(delta_value)])
        _check_snapshot(controller, expected_age, r, h, w, 3, 'partition %d' % p_index)
        _check_all(actors, expected_age, r, h, w, 'partition %d' % p_index)
        var positions: Array = []
        for actor_value: Variant in actors:
            positions.append((actor_value as Node3D).position)
        if p_index == 0:
            reference = positions
        else:
            for i: int in range(3):
                _check(_vec_close(positions[i], reference[i], tol), 'partition %d actor %d matches single step' % [p_index, i])
        _cleanup(controller)


func _test_large_delta() -> void:
    _section = 'large delta'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 2)
    var r: float = 10.0
    var h: float = 2.0
    var w: float = -0.37
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 36000.0), 'advance 36000 accepted')
    _check_snapshot(controller, 36000.0, r, h, w, 2, 'after 36000')
    _check_all(actors, 36000.0, r, h, w, 'after 36000')
    _check(not _advance(controller, 36000.000001), 'delta above 36000 rejected')
    _check_snapshot(controller, 36000.0, r, h, w, 2, 'after rejected large delta')
    _cleanup(controller)


func _test_large_age() -> void:
    _section = 'large age'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 7.0
    var h: float = 1.0
    var w: float = 1.7
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    var age: float = 0.0
    for k: int in range(28):
        _check(_advance(controller, 36000.0), 'advance step %d' % k)
        age += 36000.0
    _check(age >= 1.0e6, 'reference age reached 1e6')
    _check_snapshot(controller, age, r, h, w, 3, 'age ' + str(age))
    _check_all(actors, age, r, h, w, 'age ' + str(age))
    var all_ok: bool = true
    for k: int in range(28, 27777):
        if not _advance(controller, 36000.0):
            all_ok = false
            break
        age += 36000.0
    _check(all_ok, 'all 36000 steps up to 999972000 accepted')
    _check_snapshot(controller, age, r, h, w, 3, 'age ' + str(age))
    _check(_advance(controller, 28000.0), 'advance to exactly 1e9 accepted')
    age += 28000.0
    _check(age == 1.0e9, 'reference age is exactly 1e9')
    _check_snapshot(controller, 1.0e9, r, h, w, 3, 'age 1e9')
    _check_all(actors, 1.0e9, r, h, w, 'age 1e9')
    _check(not _advance(controller, 1.0), 'advance beyond 1e9 rejected')
    _check_snapshot(controller, 1.0e9, r, h, w, 3, 'age 1e9 after rejection')
    _check(_advance(controller, 0.0), 'advance(0) at 1e9 accepted')
    _check_all(actors, 1.0e9, r, h, w, 'age 1e9 after delta 0')
    _cleanup(controller)


func _test_bounds_accepted() -> void:
    var cases: Array = [
        [1000.0, 1000.0, 5.0],
        [1000.0, 0.0, -5.0],
        [1e-300, -0.0, 2.0],
        [0.5, 1000.0, 0.0],
    ]
    for case_index: int in range(cases.size()):
        var values: Array = cases[case_index]
        var r: float = values[0]
        var h: float = values[1]
        var w: float = values[2]
        _section = 'bounds case %d' % case_index
        var controller: Node3D = _new_controller(root)
        var actors: Array = _new_actors(controller, 2)
        _check(_configure(controller, actors, r, h, w), 'boundary configure accepted')
        _check_snapshot(controller, 0.0, r, h, w, 2, 'initial')
        _check_all(actors, 0.0, r, h, w, 'initial')
        _check(_advance(controller, 36000.0), 'advance 36000')
        _check_snapshot(controller, 36000.0, r, h, w, 2, 'after 36000')
        _check_all(actors, 36000.0, r, h, w, 'after 36000')
        _cleanup(controller)


func _test_int_coercion() -> void:
    _section = 'int coercion'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 2)
    var result: Variant = controller.call('configure', actors, 3, 2, 1)
    _check(typeof(result) == TYPE_BOOL and bool(result), 'configure accepts int scalars')
    _check_snapshot(controller, 0.0, 3.0, 2.0, 1.0, 2, 'int configure')
    var advanced: Variant = controller.call('advance', 2)
    _check(typeof(advanced) == TYPE_BOOL and bool(advanced), 'advance accepts int delta')
    _check_snapshot(controller, 2.0, 3.0, 2.0, 1.0, 2, 'int advance')
    _check_all(actors, 2.0, 3.0, 2.0, 1.0, 'int advance')
    _cleanup(controller)


func _capture_tilt(actors: Array) -> Array:
    var out: Array = []
    for actor_value: Variant in actors:
        var actor: Node3D = actor_value as Node3D
        out.append([actor.rotation.x, actor.rotation.z, actor.scale])
    return out


func _check_tilt(actors: Array, before: Array, label: String) -> void:
    for i: int in range(actors.size()):
        var actor: Node3D = actors[i] as Node3D
        var saved: Array = before[i]
        var saved_x: float = saved[0]
        var saved_z: float = saved[1]
        var saved_scale: Vector3 = saved[2]
        _check(is_equal_approx(actor.rotation.x, saved_x), '%s: actor %d tilt x preserved' % [label, i])
        _check(is_equal_approx(actor.rotation.z, saved_z), '%s: actor %d tilt z preserved' % [label, i])
        _check(actor.scale.is_equal_approx(saved_scale), '%s: actor %d scale preserved' % [label, i])


func _test_tilt_scale_preservation() -> void:
    _section = 'tilt and scale preservation'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 1.0
    var w: float = 0.6
    for i: int in range(3):
        var actor: Node3D = actors[i] as Node3D
        actor.rotation = Vector3(0.3 + 0.1 * float(i), 1.0, -0.2)
        actor.scale = Vector3(2.0, 0.5, 3.0 + float(i))
    var mesh_node: MeshInstance3D = MeshInstance3D.new()
    mesh_node.mesh = BoxMesh.new()
    mesh_node.position = Vector3(1.0, 2.0, 3.0)
    mesh_node.rotation = Vector3(0.1, 0.2, 0.3)
    (actors[0] as Node3D).add_child(mesh_node)
    var skeleton: Skeleton3D = Skeleton3D.new()
    skeleton.add_bone('root')
    mesh_node.add_child(skeleton)
    var mesh_transform: Transform3D = mesh_node.transform
    var skeleton_transform: Transform3D = skeleton.transform
    var before: Array = _capture_tilt(actors)
    _check(_configure(controller, actors, r, h, w), 'configure with tilted scaled actors')
    _check_tilt(actors, before, 'configure')
    _check_all(actors, 0.0, r, h, w, 'configure')
    _check(mesh_node.transform == mesh_transform, 'descendant mesh transform untouched')
    _check(skeleton.transform == skeleton_transform, 'descendant skeleton transform untouched')
    for i: int in range(3):
        var actor: Node3D = actors[i] as Node3D
        actor.rotation = Vector3(-0.6, actor.rotation.y + 0.5, 0.4 - 0.05 * float(i))
        actor.scale = Vector3(0.25, 4.0, 1.0 + 0.5 * float(i))
    before = _capture_tilt(actors)
    _check(_advance(controller, 0.3), 'advance after host edit')
    _check_tilt(actors, before, 'first host edit')
    _check_all(actors, 0.3, r, h, w, 'first host edit')
    for i: int in range(3):
        var actor: Node3D = actors[i] as Node3D
        actor.rotation = Vector3(0.05, actor.rotation.y, -0.7 + 0.1 * float(i))
        actor.scale = Vector3(1.5, 1.5, 0.75)
    before = _capture_tilt(actors)
    _check(_advance(controller, 0.0), 'advance(0) after second host edit')
    _check_tilt(actors, before, 'second host edit')
    _check_all(actors, 0.3, r, h, w, 'second host edit')
    _check(mesh_node.transform == mesh_transform, 'descendant mesh transform still untouched')
    _check(skeleton.transform == skeleton_transform, 'descendant skeleton transform still untouched')
    _cleanup(controller)


func _test_invalid_scalars() -> void:
    for bad_radius: float in [0.0, -0.0, -1.0, 1000.0001, NAN, INF, -INF]:
        _expect_configure_reject('radius ' + str(bad_radius), 'valid', bad_radius, 1.0, 0.5)
    for bad_height: float in [-0.001, -1.0, 1000.0001, NAN, INF, -INF]:
        _expect_configure_reject('height ' + str(bad_height), 'valid', 2.0, bad_height, 0.5)
    for bad_speed: float in [5.000001, -5.000001, 100.0, NAN, INF, -INF]:
        _expect_configure_reject('speed ' + str(bad_speed), 'valid', 2.0, 1.0, bad_speed)


func _test_invalid_actors() -> void:
    for kind: String in REQUEST_KINDS:
        _expect_configure_reject('request ' + kind, kind, 2.0, 1.0, 0.5)
    for kind: String in DOMAIN_KINDS:
        _expect_configure_reject('later actor ' + kind, kind, 2.0, 1.0, 0.5)


func _test_repeated_configure() -> void:
    _section = 'repeated configure'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    _check(_configure(controller, actors, r, h, w), 'first configure succeeds')
    _check(_advance(controller, 0.5), 'advance 0.5')
    var extra: Array = _new_actors(controller, 2)
    var before: Array = _capture(actors + extra)
    _check(not _configure(controller, actors, 5.0, 2.0, 1.0), 'second configure with same actors fails')
    _check(not _configure(controller, extra, 5.0, 2.0, 1.0), 'second configure with new actors fails')
    _check(_capture(actors + extra) == before, 'repeated configure mutates nothing')
    _check_snapshot(controller, 0.5, r, h, w, 3, 'after repeated configure')
    _cleanup(controller)


func _test_tree_exit_reentry() -> void:
    _section = 'out of tree and re-entry'
    var controller: Node3D = _new_controller(null)
    var actors: Array = _new_actors(controller, 2)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    var before: Array = _capture(actors)
    _check(not _configure(controller, actors, r, h, w), 'configure fails out of tree')
    _check(_snapshot(controller).is_empty(), 'snapshot empty after out-of-tree configure')
    _check(_capture(actors) == before, 'out-of-tree configure mutates nothing')
    root.add_child(controller)
    _check(_configure(controller, actors, r, h, w), 'configure succeeds in tree')
    _check(_advance(controller, 0.5), 'advance 0.5')
    root.remove_child(controller)
    _check(not _advance(controller, 0.25), 'advance fails out of tree')
    _check(not _advance(controller, 0.0), 'advance(0) fails out of tree')
    _check_snapshot(controller, 0.5, r, h, w, 2, 'snapshot readable out of tree')
    root.add_child(controller)
    _check(_advance(controller, 0.25), 'advance resumes after re-entry')
    _check_snapshot(controller, 0.75, r, h, w, 2, 'after re-entry')
    _check_all(actors, 0.75, r, h, w, 'after re-entry')
    _cleanup(controller)


func _test_remove_reparent_restore() -> void:
    _section = 'remove reparent restore'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 1.0), 'advance 1.0')
    var a0: Node3D = actors[0] as Node3D
    var a1: Node3D = actors[1] as Node3D
    var a2: Node3D = actors[2] as Node3D
    a0.position = Vector3(42.0, 42.0, 42.0)
    var sentinel: Vector3 = a0.position
    controller.remove_child(a1)
    _check(not _advance(controller, 0.5), 'removed actor rejects advance')
    _check(a0.position == sentinel, 'failed advance did not move earlier actor')
    _check_snapshot(controller, 1.0, r, h, w, 3, 'after removal')
    var stranger: Node3D = Node3D.new()
    root.add_child(stranger)
    _loose_nodes.append(stranger)
    stranger.add_child(a1)
    _check(not _advance(controller, 0.5), 'actor under foreign parent rejects advance')
    stranger.remove_child(a1)
    a2.add_child(a1)
    _check(not _advance(controller, 0.5), 'actor nested under sibling rejects advance')
    a2.remove_child(a1)
    controller.add_child(a1)
    controller.move_child(a1, 0)
    controller.move_child(a2, 1)
    _check(a0.position == sentinel, 'earlier actor untouched by all failed advances')
    _check_snapshot(controller, 1.0, r, h, w, 3, 'before restore advance')
    _check(_advance(controller, 0.5), 'restored parenting permits advance')
    _check_snapshot(controller, 1.5, r, h, w, 3, 'after restore')
    _check_all(actors, 1.5, r, h, w, 'configure-time indices after child reorder')
    _cleanup(controller)


func _test_domain_changes_in_advance() -> void:
    for kind: String in DOMAIN_KINDS:
        _section = 'advance domain change: ' + kind
        var controller: Node3D = _new_controller(root)
        var actors: Array = _new_actors(controller, 3)
        var r: float = 2.0
        var h: float = 0.5
        var w: float = 0.8
        _check(_configure(controller, actors, r, h, w), 'configure succeeds')
        _check(_advance(controller, 0.5), 'advance 0.5')
        var target: Node3D = actors[2] as Node3D
        var saved_rotation: Vector3 = target.rotation
        var saved_scale: Vector3 = target.scale
        var first: Node3D = actors[0] as Node3D
        first.position = Vector3(42.0, 42.0, 42.0)
        var sentinel_position: Vector3 = first.position
        var sentinel_rotation: Vector3 = first.rotation
        _apply_bad_state(kind, target)
        _check(not _advance(controller, 0.25), 'advance rejected')
        _check(not _advance(controller, 0.0), 'advance(0) rejected')
        _check(first.position == sentinel_position and first.rotation == sentinel_rotation, 'earlier actor untouched by failed advance')
        _check_snapshot(controller, 0.5, r, h, w, 3, 'age preserved')
        _restore_state(target, saved_rotation, saved_scale)
        _check(_advance(controller, 0.0), 'advance(0) resumes after restore')
        _check_snapshot(controller, 0.5, r, h, w, 3, 'age kept after restore')
        _check_all(actors, 0.5, r, h, w, 'restored')
        _check(_advance(controller, 0.25), 'advance 0.25 after restore')
        _check_all(actors, 0.75, r, h, w, 'advanced after restore')
        _cleanup(controller)


func _test_freed_actor_permanence() -> void:
    _section = 'freed actor permanence'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 1.0), 'advance 1.0')
    var first: Node3D = actors[0] as Node3D
    first.position = Vector3(42.0, 42.0, 42.0)
    var sentinel: Vector3 = first.position
    (actors[1] as Node3D).free()
    _check(not _advance(controller, 0.5), 'advance fails after actor freed')
    _check(not _advance(controller, 0.0), 'advance(0) fails after actor freed')
    _check_snapshot(controller, 1.0, r, h, w, 3, 'snapshot after free')
    var replacement: Node3D = Node3D.new()
    replacement.name = 'Actor1'
    controller.add_child(replacement)
    _check(not _advance(controller, 0.5), 'replacement child does not restore')
    root.remove_child(controller)
    root.add_child(controller)
    _check(not _advance(controller, 0.5), 'tree re-entry does not restore')
    _check(first.position == sentinel, 'remaining actor never moved by failed advances')
    _check_snapshot(controller, 1.0, r, h, w, 3, 'snapshot still readable')
    _cleanup(controller)


func _test_input_and_snapshot_mutation() -> void:
    _section = 'input array and snapshot mutation'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    var request: Array = actors.duplicate()
    _check(_configure(controller, request, r, h, w), 'configure succeeds')
    request.reverse()
    _check(_advance(controller, 0.25), 'advance after input reverse')
    _check_all(actors, 0.25, r, h, w, 'input reversed')
    request.append(7)
    request.clear()
    _check(_advance(controller, 0.25), 'advance after input clear')
    _check_all(actors, 0.5, r, h, w, 'input cleared')
    _check_snapshot(controller, 0.5, r, h, w, 3, 'membership retained')
    var snap: Dictionary = _snapshot(controller)
    snap['age'] = 999.0
    snap['count'] = 0
    snap['extra'] = 1
    snap.erase('radius')
    _check_snapshot(controller, 0.5, r, h, w, 3, 'after snapshot mutation')
    _check(_advance(controller, 0.0), 'advance(0) after snapshot mutation')
    _check_all(actors, 0.5, r, h, w, 'after snapshot mutation')
    var first_snap: Dictionary = _snapshot(controller)
    var second_snap: Dictionary = _snapshot(controller)
    first_snap['age'] = -1.0
    _check(second_snap.get('age') == 0.5, 'snapshots are independent copies')
    _cleanup(controller)


func _test_parent_scale() -> void:
    _section = 'parent scale'
    var holder: Node3D = Node3D.new()
    root.add_child(holder)
    holder.position = Vector3(1.0, 2.0, 3.0)
    holder.rotation = Vector3(0.2, 0.7, -0.1)
    holder.scale = Vector3(2.0, 3.0, 0.5)
    var controller: Node3D = _new_controller(holder)
    controller.position = Vector3(0.5, 0.0, -1.0)
    controller.rotation = Vector3(0.0, 0.3, 0.0)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 4.0
    var h: float = 1.5
    var w: float = 0.9
    _check(_configure(controller, actors, r, h, w), 'configure under scaled parent')
    _check(_advance(controller, 0.9), 'advance 0.9')
    _check_all(actors, 0.9, r, h, w, 'local placement under scaled parent')
    var tol: float = _pos_tol(r, h) * 3.0
    for i: int in range(3):
        var angle: float = _exp_angle(0.9, w, i, 3)
        var local_point: Vector3 = Vector3(r * cos(angle), h, r * sin(angle))
        var expected_global: Vector3 = controller.global_transform * local_point
        var actor: Node3D = actors[i] as Node3D
        _check(_vec_close(actor.global_position, expected_global, tol), 'actor %d global position %s expected %s' % [i, str(actor.global_position), str(expected_global)])
    _cleanup(holder)


func _test_failed_advance_preserves_age() -> void:
    _section = 'failed advance preserves age'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 2)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 0.8
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 2.5), 'advance 2.5')
    var first: Node3D = actors[0] as Node3D
    first.position = Vector3(42.0, 42.0, 42.0)
    var sentinel: Vector3 = first.position
    for bad_delta: float in [-1.0, -1e-300, NAN, INF, -INF, 36000.0001, 1e12]:
        _check(not _advance(controller, bad_delta), 'delta %s rejected' % str(bad_delta))
        _check(_snapshot_age(controller) == 2.5, 'age preserved after delta %s' % str(bad_delta))
        _check(first.position == sentinel, 'actor untouched after delta %s' % str(bad_delta))
    _check(_advance(controller, -0.0), 'negative zero delta accepted')
    _check_snapshot(controller, 2.5, r, h, w, 2, 'after negative zero delta')
    _check_all(actors, 2.5, r, h, w, 'after negative zero delta')
    _cleanup(controller)


func _test_no_process_movement() -> void:
    _section = 'no process-driven movement'
    var controller: Node3D = _new_controller(root)
    var actors: Array = _new_actors(controller, 3)
    var r: float = 2.0
    var h: float = 0.5
    var w: float = 3.0
    _check(_configure(controller, actors, r, h, w), 'configure succeeds')
    _check(_advance(controller, 0.5), 'advance 0.5')
    var before: Array = _capture(actors)
    for k: int in range(5):
        await process_frame
    for k: int in range(2):
        await physics_frame
    _check(_capture(actors) == before, 'actors did not move while frames passed')
    _check_snapshot(controller, 0.5, r, h, w, 3, 'age unchanged by frames')
    _check(not controller.is_processing() and not controller.is_physics_processing(), 'controller is not processing')
    _cleanup(controller)
