extends SceneTree
## Verification for SPEC-HAND-SURFACE-MOTION-001 v1. Nonzero exit on failure.

const HandSurfaceMotionScript := preload('res://scripts/hand_surface_motion.gd')
const TOLERANCE: float = 1e-5

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
    _test_scale_fixtures()
    _test_defensive_configure_and_reset()
    _test_depth_response_fixture()
    _test_cap_without_teleport()
    _test_facing_fixture()
    _test_previous_scale_fixture()
    _test_slow_outward()
    _test_invalid_steps()
    _test_huge_and_zero_steps()
    _test_separate_deltas()
    _test_fresh_snapshots()
    _test_large_normal_components()
    _test_base_scale_effect()
    print('hand_surface_motion checks: %d, failures: %d' % [_checks, _failures])
    quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        push_error('FAIL: ' + label)
        print('FAIL: ' + label)


func _near(a: float, b: float, tolerance: float = TOLERANCE) -> bool:
    return absf(a - b) <= tolerance


func _vec_near(a: Vector3, b: Vector3, tolerance: float = TOLERANCE) -> bool:
    return _near(a.x, b.x, tolerance) and _near(a.y, b.y, tolerance) and _near(a.z, b.z, tolerance)


func _make(maximum_distance: float = 1800.0, base_scale: float = 1.0) -> RefCounted:
    var motion := HandSurfaceMotionScript.new()
    _check('configure succeeds', motion.configure(maximum_distance, base_scale))
    return motion


func _scale_at(depth: float) -> float:
    var motion := HandSurfaceMotionScript.new()
    motion.configure(1800.0, 1.0)
    motion.reset(depth)
    return float(motion.state()['scale'])


func _test_scale_fixtures() -> void:
    _check('scale 2', _near(_scale_at(2.0), 0.2759459323))
    _check('scale 5', _near(_scale_at(5.0), 0.5743491775))
    _check('scale 10', _near(_scale_at(10.0), 1.0))
    _check('scale 100', _near(_scale_at(100.0), 1.0))
    _check('scale 150', _near(_scale_at(150.0), 1.0))
    _check('scale 300', _near(_scale_at(300.0), 1.9454545455))
    _check('scale 1000', _near(_scale_at(1000.0), 5.6363636364))
    _check('scale 1800', _near(_scale_at(1800.0), 8.4))


func _test_defensive_configure_and_reset() -> void:
    var motion := HandSurfaceMotionScript.new()
    _check('state empty before configure', motion.state().is_empty())
    _check('reset before configure fails', not motion.reset(20.0))
    _check('step before configure empty', motion.step(0.1, 0.1, 50.0, Vector3.UP).is_empty())
    _check('configure max below 2 fails', not motion.configure(1.0, 1.0))
    _check('configure max above 1800 fails', not motion.configure(1801.0, 1.0))
    _check('configure base zero fails', not motion.configure(100.0, 0.0))
    _check('configure base above 10 fails', not motion.configure(100.0, 10.5))
    _check('configure nan fails', not motion.configure(NAN, 1.0))
    _check('configure inf base fails', not motion.configure(100.0, INF))
    _check('state still empty after invalid configure', motion.state().is_empty())
    _check('configure valid', motion.configure(1800.0, 1.0))
    _check('repeated configure fails', not motion.configure(100.0, 2.0))
    _check('state empty before reset', motion.state().is_empty())
    _check('step before reset empty', motion.step(0.1, 0.1, 50.0, Vector3.UP).is_empty())
    _check('reset nan fails', not motion.reset(NAN))
    _check('reset inf fails', not motion.reset(INF))
    _check('reset zero normal fails', not motion.reset(20.0, Vector3.ZERO))
    _check('reset nonfinite normal fails', not motion.reset(20.0, Vector3(NAN, 0.0, 0.0)))
    _check('state empty after invalid resets', motion.state().is_empty())
    _check('reset 5000 clamps to max', motion.reset(5000.0))
    var s: Dictionary = motion.state()
    _check('clamped depth 1800', _near(float(s['internal_depth']), 1800.0))
    _check('limit equals clamped reset depth', _near(float(s['limit']), 1800.0))
    _check('render equals clamped reset depth', _near(float(s['render_depth']), 1800.0))
    _check('reset scale 1800', _near(float(s['scale']), 8.4))
    _check('reset normal UP', _vec_near(s['normal'], Vector3.UP))
    _check('reset velocity zero', _near(float(s['depth_velocity']), 0.0))
    _check('reset normal velocity zero', _vec_near(s['normal_velocity'], Vector3.ZERO))
    _check('reset 1 clamps to 2', motion.reset(1.0, Vector3(0.0, 0.0, 5.0)))
    s = motion.state()
    _check('clamped depth 2', _near(float(s['internal_depth']), 2.0))
    _check('reset normal normalized', _vec_near(s['normal'], Vector3(0.0, 0.0, 1.0)))
    _check('invalid reset after valid leaves state', not motion.reset(NAN))
    s = motion.state()
    _check('state unchanged after invalid reset', _near(float(s['internal_depth']), 2.0) and _vec_near(s['normal'], Vector3(0.0, 0.0, 1.0)))


func _test_depth_response_fixture() -> void:
    var motion := _make()
    _check('reset 20', motion.reset(20.0))
    var dt: float = 1.0 / 60.0
    var r: Dictionary = motion.step(dt, 0.0, 103.2, Vector3.UP)
    _check('step returns fields', r.has('internal_depth') and r.has('depth_velocity') and r.has('limit') and r.has('render_depth') and r.has('scale') and r.has('normal') and r.has('normal_velocity'))
    _check('limit 100', _near(float(r['limit']), 100.0))
    _check('frame 1 depth', _near(float(r['internal_depth']), 21.56871847))
    _check('frame 1 velocity', _near(float(r['depth_velocity']), 180.50927854))
    _check('frame 1 render', _near(float(r['render_depth']), 21.56871847))
    _check('frame 1 scale', _near(float(r['scale']), 1.0))
    for i: int in range(5):
        r = motion.step(dt, 0.0, 103.2, Vector3.UP)
    _check('frame 6 depth', _near(float(r['internal_depth']), 51.30883736))
    for i: int in range(6):
        r = motion.step(dt, 0.0, 103.2, Vector3.UP)
    _check('frame 12 depth', _near(float(r['internal_depth']), 82.86689845))
    _check('state matches step output', _near(float(motion.state()['internal_depth']), 82.86689845))


func _test_cap_without_teleport() -> void:
    var motion := _make()
    _check('reset 100', motion.reset(100.0))
    var r: Dictionary = motion.step(0.0, 0.0, 23.2, Vector3.UP)
    _check('cap limit 20', _near(float(r['limit']), 20.0))
    _check('cap render 20', _near(float(r['render_depth']), 20.0))
    _check('cap internal 100 preserved', _near(float(r['internal_depth']), 100.0))
    _check('cap velocity preserved zero', _near(float(r['depth_velocity']), 0.0))
    _check('cap scale at render depth', _near(float(r['scale']), 1.0))
    r = motion.step(0.1, 0.0, 23.2, Vector3.UP)
    _check('inward settle internal 20', _near(float(r['internal_depth']), 20.0))
    _check('inward settle velocity 0', _near(float(r['depth_velocity']), 0.0))
    _check('inward settle render 20', _near(float(r['render_depth']), 20.0))


func _test_facing_fixture() -> void:
    var motion := _make()
    _check('reset 100 facing', motion.reset(100.0))
    var r: Dictionary = motion.step(0.0, 0.2, 103.2, Vector3.RIGHT)
    _check('facing depth unchanged', _near(float(r['internal_depth']), 100.0))
    var expected_first: Vector3 = Vector3(0.6875, 0.3125, 0.0).normalized()
    _check('facing first normal', _vec_near(r['normal'], expected_first))
    _check('facing first velocity', _vec_near(r['normal_velocity'], Vector3(3.75, -3.75, 0.0)))
    _check('facing output unit length', _near(Vector3(r['normal']).length(), 1.0))
    r = motion.step(0.0, 0.2, 103.2, Vector3.RIGHT)
    var expected_second: Vector3 = Vector3(0.99609375, 0.00390625, 0.0).normalized()
    _check('facing second normal', _vec_near(r['normal'], expected_second))
    _check('facing second differs from exact RIGHT', not _vec_near(r['normal'], Vector3.RIGHT, 1e-7))
    var settled: Dictionary = motion.step(0.0, 0.4, 103.2, Vector3.RIGHT)
    _check('facing settles exactly at duration', _vec_near(settled['normal'], Vector3.RIGHT))
    _check('facing settle velocity zero', _vec_near(settled['normal_velocity'], Vector3.ZERO))


func _test_previous_scale_fixture() -> void:
    var motion := _make()
    _check('reset 300', motion.reset(300.0))
    _check('reset 300 scale', _near(float(motion.state()['scale']), 1.9454545))
    var r: Dictionary = motion.step(0.28, 0.0, 400.0, Vector3.UP)
    _check('previous scale limit', _near(float(r['limit']), 393.7745454545))
    _check('settled internal at limit', _near(float(r['internal_depth']), 393.7745454545))
    _check('new output scale', _near(float(r['scale']), 2.5088094414))
    r = motion.step(0.28, 0.0, 400.0, Vector3.UP)
    _check('next limit uses cached scale', _near(float(r['limit']), 391.9718097875))


func _test_slow_outward() -> void:
    var motion := _make()
    _check('reset 20 slow', motion.reset(20.0))
    var r: Dictionary = motion.step(1.0, 0.0, 103.2, Vector3.UP, true)
    _check('slow outward half way', _near(float(r['internal_depth']), 75.0))
    r = motion.step(1.0, 0.0, 103.2, Vector3.UP, true)
    _check('slow outward rebuild from current', not _near(float(r['internal_depth']), 100.0))
    var fast := _make()
    fast.reset(20.0)
    var f: Dictionary = fast.step(1.0, 0.0, 103.2, Vector3.UP, false)
    _check('normal outward settles at 1s', _near(float(f['internal_depth']), 100.0))
    var inward := _make()
    inward.reset(100.0)
    var i: Dictionary = inward.step(0.1, 0.0, 23.2, Vector3.UP, true)
    _check('inward ignores slow_outward', _near(float(i['internal_depth']), 20.0))


func _test_invalid_steps() -> void:
    var motion := _make()
    motion.reset(20.0)
    var before: Dictionary = motion.state()
    _check('negative delta rejected', motion.step(-0.1, 0.0, 103.2, Vector3.UP).is_empty())
    _check('negative facing delta rejected', motion.step(0.1, -0.1, 103.2, Vector3.UP).is_empty())
    _check('nan delta rejected', motion.step(NAN, 0.0, 103.2, Vector3.UP).is_empty())
    _check('inf facing rejected', motion.step(0.1, INF, 103.2, Vector3.UP).is_empty())
    _check('zero distance rejected', motion.step(0.1, 0.0, 0.0, Vector3.UP).is_empty())
    _check('negative distance rejected', motion.step(0.1, 0.0, -5.0, Vector3.UP).is_empty())
    _check('inf distance rejected', motion.step(0.1, 0.0, INF, Vector3.UP).is_empty())
    _check('zero normal rejected', motion.step(0.1, 0.0, 103.2, Vector3.ZERO).is_empty())
    _check('nan normal rejected', motion.step(0.1, 0.0, 103.2, Vector3(0.0, NAN, 0.0)).is_empty())
    var after: Dictionary = motion.state()
    _check('invalid steps do not mutate', _near(float(after['internal_depth']), float(before['internal_depth'])) and _near(float(after['limit']), float(before['limit'])) and _vec_near(after['normal'], before['normal']))


func _test_huge_and_zero_steps() -> void:
    var motion := _make()
    motion.reset(20.0)
    var r: Dictionary = motion.step(0.0, 0.0, 103.2, Vector3.UP)
    _check('zero step keeps depth', _near(float(r['internal_depth']), 20.0))
    _check('zero step updates limit', _near(float(r['limit']), 100.0))
    r = motion.step(1.0e6, 0.0, 103.2, Vector3.UP)
    _check('huge step settles exactly', _near(float(r['internal_depth']), 100.0))
    _check('huge step zero velocity', _near(float(r['depth_velocity']), 0.0))
    r = motion.step(0.0, 1.0e6, 103.2, Vector3.FORWARD)
    _check('huge facing step settles', _vec_near(r['normal'], Vector3.FORWARD))
    r = motion.step(0.5, 0.0, 2.0, Vector3.FORWARD)
    _check('internal depth never below floor', float(r['internal_depth']) >= 1.0)
    _check('render depth bounded below by 2', float(r['render_depth']) >= 2.0)


func _test_separate_deltas() -> void:
    var motion := _make()
    motion.reset(20.0)
    var r: Dictionary = motion.step(1.0 / 60.0, 0.4, 103.2, Vector3.RIGHT)
    _check('depth uses delta', _near(float(r['internal_depth']), 21.56871847))
    _check('facing uses facing_delta', _vec_near(r['normal'], Vector3.RIGHT))
    var other := _make()
    other.reset(20.0)
    var o: Dictionary = other.step(0.4, 1.0 / 60.0, 103.2, Vector3.RIGHT)
    _check('swapped deltas settle depth', _near(float(o['internal_depth']), 100.0))
    _check('swapped deltas partial facing', not _vec_near(o['normal'], Vector3.RIGHT, 1e-3))


func _test_fresh_snapshots() -> void:
    var motion := _make()
    motion.reset(50.0)
    var s1: Dictionary = motion.state()
    s1['internal_depth'] = -5.0
    s1['normal'] = Vector3.ZERO
    s1.erase('scale')
    var s2: Dictionary = motion.state()
    _check('state not mutated by snapshot edits', _near(float(s2['internal_depth']), 50.0) and s2.has('scale') and _vec_near(s2['normal'], Vector3.UP))
    var r: Dictionary = motion.step(0.0, 0.0, 103.2, Vector3.UP)
    r['limit'] = 1.0
    _check('step snapshot detached', _near(float(motion.state()['limit']), 100.0))
    _check('snapshots are distinct objects', not is_same(motion.state(), motion.state()))


func _test_large_normal_components() -> void:
    var motion := _make()
    _check('reset with large normal', motion.reset(20.0, Vector3(1.0e30, 0.0, 0.0)))
    _check('large normal normalized', _vec_near(motion.state()['normal'], Vector3.RIGHT))
    var r: Dictionary = motion.step(0.0, 0.4, 103.2, Vector3(0.0, 3.0e30, 4.0e30))
    _check('large target normalized', _vec_near(r['normal'], Vector3(0.0, 0.6, 0.8)))


func _test_base_scale_effect() -> void:
    var motion := _make(1800.0, 2.0)
    motion.reset(20.0)
    var r: Dictionary = motion.step(0.0, 0.0, 103.2, Vector3.UP)
    _check('base scale widens offset', _near(float(r['limit']), 96.8))
    var small := _make(50.0, 1.0)
    small.reset(20.0)
    var s: Dictionary = small.step(1.0, 0.0, 500.0, Vector3.UP)
    _check('limit clamped to maximum', _near(float(s['limit']), 50.0))
    _check('render clamped to maximum', _near(float(s['render_depth']), 50.0))
