extends SceneTree
## Verification script for SPEC-HAND-POINTER-DYNAMICS-001 v1.

const HandPointerDynamics = preload('res://scripts/hand_pointer_dynamics.gd')
const TOLERANCE: float = 0.0001

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_before_reset()
	_test_fixture_steps()
	_test_zero_dt_clamp()
	_test_convergence_and_signs()
	_test_invalid_and_reset()
	_test_detached()
	_test_blend()
	if _failures > 0:
		print('FAILED: %d of %d checks failed' % [_failures, _checks])
		quit(1)
	else:
		print('OK: %d checks passed' % _checks)
		quit(0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print('FAIL: ' + message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOLERANCE


func _near2(a: Vector2, b: Vector2) -> bool:
	return _near(a.x, b.x) and _near(a.y, b.y)


func _near3(a: Vector3, b: Vector3) -> bool:
	return _near(a.x, b.x) and _near(a.y, b.y) and _near(a.z, b.z)


func _vec(d: Dictionary, key: String) -> Vector2:
	if d.has(key) and d[key] is Vector2:
		var v: Vector2 = d[key]
		return v
	_check(false, 'missing Vector2 key ' + key)
	return Vector2(NAN, NAN)


func _same_state(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != 3 or b.size() != 3:
		return false
	return _vec(a, 'lag') == _vec(b, 'lag') and _vec(a, 'velocity') == _vec(b, 'velocity') and _vec(a, 'sliders') == _vec(b, 'sliders')


func _test_before_reset() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	var s: Dictionary = h.state()
	_check(s.is_empty(), 'state before reset is empty')
	var r: Dictionary = h.step(0.02, Vector2(1.0, 2.0))
	_check(r.is_empty(), 'step before reset is empty')
	var ok: bool = h.reset(Vector2(NAN, 0.0))
	_check(not ok, 'invalid first reset returns false')
	s = h.state()
	_check(s.is_empty(), 'state still empty after invalid first reset')


func _test_fixture_steps() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	var ok: bool = h.reset(Vector2(400.0, 300.0))
	_check(ok, 'valid reset returns true')
	var s: Dictionary = h.state()
	_check(s.size() == 3, 'state has three keys')
	_check(_vec(s, 'lag') == Vector2(400.0, 300.0), 'reset lag equals cursor')
	_check(_vec(s, 'velocity') == Vector2.ZERO, 'reset velocity zero')
	_check(_vec(s, 'sliders') == Vector2(0.5, 0.5), 'reset sliders centred')
	var r: Dictionary = h.step(0.02, Vector2(500.0, 340.0))
	_check(_near2(_vec(r, 'lag'), Vector2(420.0, 300.0)), 'step1 lag')
	_check(_near2(_vec(r, 'velocity'), Vector2(29.83268919, 14.91634459)), 'step1 velocity')
	_check(_near2(_vec(r, 'sliders'), Vector2(0.0, 0.75)), 'step1 sliders')
	r = h.step(0.02, Vector2(500.0, 340.0))
	_check(_near2(_vec(r, 'lag'), Vector2(420.59665378, 300.29832689)), 'step2 lag')
	_check(_near2(_vec(r, 'velocity'), Vector2(57.42235885, 28.71117943)), 'step2 velocity')
	_check(_near2(_vec(r, 'sliders'), Vector2(0.00372908615, 0.74813545693)), 'step2 sliders')
	s = h.state()
	_check(_same_state(s, r), 'state matches last step result')


func _test_zero_dt_clamp() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	h.reset(Vector2(0.0, 0.0))
	var r: Dictionary = h.step(0.0, Vector2(1000.0, -1000.0))
	_check(_near2(_vec(r, 'lag'), Vector2(920.0, -920.0)), 'dt0 lag clamped')
	_check(_near2(_vec(r, 'velocity'), Vector2.ZERO), 'dt0 velocity zero')
	_check(_near2(_vec(r, 'sliders'), Vector2(0.0, 0.0)), 'dt0 sliders')
	r = h.step(0.25, Vector2(1000.0, -1000.0))
	_check(r.size() == 3, 'dt 0.25 boundary accepted')


func _test_convergence_and_signs() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	h.reset(Vector2(0.0, 0.0))
	# Move right and down: LR below centre, FB above centre.
	var r: Dictionary = h.step(0.016, Vector2(30.0, 20.0))
	var sl: Vector2 = _vec(r, 'sliders')
	_check(_near2(sl, Vector2(50.0 / 160.0, 100.0 / 160.0)), 'right/down slider values')
	_check(sl.x < 0.5 and sl.y > 0.5, 'right/down slider signs')
	# Reversal: jump left and up past the lag point.
	r = h.step(0.016, Vector2(-40.0, -30.0))
	sl = _vec(r, 'sliders')
	_check(sl.x > 0.5 and sl.y < 0.5, 'reversal slider signs')
	_check(sl.x >= 0.0 and sl.x <= 1.0 and sl.y >= 0.0 and sl.y <= 1.0, 'sliders within phase range')
	# Static cursor converges back to centre.
	var target: Vector2 = Vector2(-40.0, -30.0)
	var early: Dictionary = h.step(0.01, target)
	var early_dist: float = (_vec(early, 'sliders') - Vector2(0.5, 0.5)).length()
	for i: int in range(3000):
		r = h.step(0.01, target)
	var late_sl: Vector2 = _vec(r, 'sliders')
	_check((late_sl - Vector2(0.5, 0.5)).length() < early_dist, 'static cursor moves toward centre')
	_check(_near2(late_sl, Vector2(0.5, 0.5)), 'static cursor sliders converge to centre')
	_check(_near2(_vec(r, 'lag'), target), 'static cursor lag converges')
	_check(_near2(_vec(r, 'velocity'), Vector2.ZERO), 'static cursor velocity decays')


func _test_invalid_and_reset() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	h.reset(Vector2(10.0, 20.0))
	h.step(0.02, Vector2(40.0, -5.0))
	var before: Dictionary = h.state()
	var r: Dictionary = h.step(-0.001, Vector2(50.0, 50.0))
	_check(r.is_empty(), 'negative dt rejected')
	r = h.step(0.2501, Vector2(50.0, 50.0))
	_check(r.is_empty(), 'dt above 0.25 rejected')
	r = h.step(NAN, Vector2(50.0, 50.0))
	_check(r.is_empty(), 'NaN dt rejected')
	r = h.step(INF, Vector2(50.0, 50.0))
	_check(r.is_empty(), 'INF dt rejected')
	r = h.step(0.02, Vector2(NAN, 50.0))
	_check(r.is_empty(), 'NaN cursor rejected')
	r = h.step(0.02, Vector2(50.0, -INF))
	_check(r.is_empty(), 'INF cursor rejected')
	r = h.step(0.02, Vector2(1000001.0, 0.0))
	_check(r.is_empty(), 'out of range cursor rejected')
	r = h.step(0.02, Vector2(0.0, -1000001.0))
	_check(r.is_empty(), 'out of range negative cursor rejected')
	_check(_same_state(h.state(), before), 'invalid steps preserve state')
	var ok: bool = h.reset(Vector2(INF, 0.0))
	_check(not ok, 'INF reset rejected')
	ok = h.reset(Vector2(0.0, 1000000.5))
	_check(not ok, 'out of range reset rejected')
	_check(_same_state(h.state(), before), 'invalid resets preserve state')
	ok = h.reset(Vector2(-1000000.0, 1000000.0))
	_check(ok, 'boundary reset accepted')
	var s: Dictionary = h.state()
	_check(_vec(s, 'lag') == Vector2(-1000000.0, 1000000.0), 'reset replaces lag')
	_check(_vec(s, 'velocity') == Vector2.ZERO, 'reset replaces velocity')
	_check(_vec(s, 'sliders') == Vector2(0.5, 0.5), 'reset replaces sliders')


func _test_detached() -> void:
	var h: RefCounted = HandPointerDynamics.new()
	h.reset(Vector2(1.0, 2.0))
	var r: Dictionary = h.step(0.02, Vector2(5.0, 9.0))
	var expected: Dictionary = h.state()
	r['lag'] = Vector2(999.0, 999.0)
	r.erase('velocity')
	r['extra'] = 1
	var s: Dictionary = h.state()
	_check(_same_state(s, expected), 'mutating step result does not affect state')
	s['sliders'] = Vector2(9.0, 9.0)
	s.clear()
	_check(_same_state(h.state(), expected), 'mutating state snapshot does not affect state')


func _test_blend() -> void:
	var rot_y: Basis = Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var prev: Array[Transform3D] = [Transform3D.IDENTITY]
	var cur: Array[Transform3D] = [Transform3D(rot_y, Vector3(4.0, 8.0, 12.0))]
	var out: Array[Transform3D] = HandPointerDynamics.blend_pose(prev, cur, 0.25)
	_check(out.size() == 1, 'blend size')
	if out.size() == 1:
		var t: Transform3D = out[0]
		_check(_near3(t.basis.x, Vector3(0.75, 0.0, -0.25)), 'blend x column')
		_check(_near3(t.basis.y, Vector3(0.0, 1.0, 0.0)), 'blend y column')
		_check(_near3(t.basis.z, Vector3(0.25, 0.0, 0.75)), 'blend z column')
		_check(_near3(t.origin, Vector3(1.0, 2.0, 3.0)), 'blend origin')
		_check(_near(t.basis.determinant(), 0.625), 'blend determinant not normalized')
		_check(absf(t.basis.x.x - cos(PI / 8.0)) > 0.01, 'differs from quaternion slerp')
		_check(absf(t.basis.x.x - 0.84375) > 0.01, 'differs from smoothstep')
		out[0] = Transform3D(Basis.IDENTITY, Vector3(7.0, 7.0, 7.0))
	_check(prev.size() == 1 and prev[0] == Transform3D.IDENTITY, 'previous input unmodified')
	_check(cur.size() == 1 and cur[0] == Transform3D(rot_y, Vector3(4.0, 8.0, 12.0)), 'current input unmodified')
	# Endpoints.
	out = HandPointerDynamics.blend_pose(prev, cur, 0.0)
	_check(out.size() == 1 and out[0] == prev[0], 'progress 0 gives previous')
	out = HandPointerDynamics.blend_pose(prev, cur, 1.0)
	_check(out.size() == 1 and out[0] == cur[0], 'progress 1 gives current')
	# Mirrored and scaled bases, no normalization.
	var mirrored: Basis = Basis(Vector3(-2.0, 0.0, 0.0), Vector3(0.0, 3.0, 0.0), Vector3(0.0, 0.5, 1.0))
	var scaled: Basis = Basis(Vector3(2.0, 0.0, 0.0), Vector3(0.0, 3.0, 0.0), Vector3(0.0, 0.0, 5.0))
	var a: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(mirrored, Vector3(-1.0, 0.0, 2.0))]
	var b: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(scaled, Vector3(1.0, 4.0, 2.0))]
	out = HandPointerDynamics.blend_pose(a, b, 0.5)
	_check(out.size() == 2, 'two element blend size')
	if out.size() == 2:
		_check(out[0] == Transform3D.IDENTITY, 'identity pair stays identity')
		var m: Transform3D = out[1]
		_check(_near3(m.basis.x, Vector3(0.0, 0.0, 0.0)), 'mirrored x column collapses linearly')
		_check(_near3(m.basis.y, Vector3(0.0, 3.0, 0.0)), 'scaled y column kept')
		_check(_near3(m.basis.z, Vector3(0.0, 0.25, 3.0)), 'sheared z column linear')
		_check(_near3(m.origin, Vector3(0.0, 2.0, 2.0)), 'mirrored origin linear')
	out = HandPointerDynamics.blend_pose(a, b, 0.0)
	_check(out.size() == 2 and out[1] == a[1], 'mirrored endpoint 0 preserved')
	out = HandPointerDynamics.blend_pose(a, b, 1.0)
	_check(out.size() == 2 and out[1] == b[1], 'scaled endpoint 1 preserved')
	# Empty and invalid.
	var e1: Array[Transform3D] = []
	var e2: Array[Transform3D] = []
	out = HandPointerDynamics.blend_pose(e1, e2, 0.5)
	_check(out.is_empty(), 'empty arrays give empty result')
	out = HandPointerDynamics.blend_pose(prev, a, 0.5)
	_check(out.is_empty(), 'mismatched arrays rejected')
	out = HandPointerDynamics.blend_pose(prev, cur, -0.01)
	_check(out.is_empty(), 'negative progress rejected')
	out = HandPointerDynamics.blend_pose(prev, cur, 1.01)
	_check(out.is_empty(), 'progress above 1 rejected')
	out = HandPointerDynamics.blend_pose(prev, cur, NAN)
	_check(out.is_empty(), 'NaN progress rejected')
	out = HandPointerDynamics.blend_pose(prev, cur, INF)
	_check(out.is_empty(), 'INF progress rejected')
	var bad_origin: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(NAN, 0.0, 0.0))]
	out = HandPointerDynamics.blend_pose(a, bad_origin, 0.5)
	_check(out.is_empty(), 'NaN origin in current rejected atomically')
	var bad_basis: Array[Transform3D] = [Transform3D(Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, INF, 0.0), Vector3(0.0, 0.0, 1.0)), Vector3.ZERO), Transform3D.IDENTITY]
	out = HandPointerDynamics.blend_pose(bad_basis, b, 0.0)
	_check(out.is_empty(), 'INF basis in previous rejected atomically')
