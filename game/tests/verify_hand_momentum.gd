extends SceneTree
## Verification script for hand_momentum.gd. Synthetic positions only.
## Run: godot --headless --script res://verify_hand_momentum.gd

const HandMomentum = preload('res://scripts/hand_momentum.gd')

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_test_configuration()
	_test_linear_frame_rates()
	_test_diagonal_direction()
	_test_vertical()
	_test_fast_clamped()
	_test_slow_zero()
	_test_window()
	_test_stale_release()
	_test_duplicate_out_of_order_time_zero()
	_test_invalid_inputs()
	_test_finish_consumed_and_cancel()
	_test_bounded_samples()
	_test_stable_norm()
	print('hand_momentum checks: %d, failures: %d' % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print('PASS ' + label)
	else:
		_failures += 1
		printerr('FAIL ' + label)


func _near(actual: float, expected: float) -> bool:
	var tolerance: float = maxf(1e-4, 1e-5 * absf(expected))
	return absf(actual - expected) <= tolerance


func _near_vec(actual: Vector3, expected: Vector3) -> bool:
	return _near(actual.x, expected.x) and _near(actual.y, expected.y) and _near(actual.z, expected.z)


func _representable_speed(value: float) -> bool:
	var probe: Vector3 = Vector3(value, 0.0, 0.0)
	return is_finite(probe.x) and probe.x > 0.0


func _make(max_speed: float = 180.0, window: float = 0.12, stale: float = 0.1, minimum: float = 2.0) -> HandMomentum:
	var hm: HandMomentum = HandMomentum.new()
	var ok: bool = hm.configure(max_speed, window, stale, minimum)
	_check(ok, 'configure accepted (%s, %s, %s, %s)' % [max_speed, window, stale, minimum])
	return hm


func _drive_linear(hm: HandMomentum, velocity: Vector3, fps: float, frames: int) -> Vector3:
	hm.begin(Vector3.ZERO, 0.0)
	var last_time: float = 0.0
	for i in range(1, frames + 1):
		last_time = float(i) / fps
		hm.sample(velocity * last_time, last_time)
	return hm.finish(last_time)


func _test_configuration() -> void:
	var fresh: HandMomentum = HandMomentum.new()
	_check(not fresh.begin(Vector3.ZERO, 0.0), 'begin rejected before configure')
	fresh.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(fresh.finish(0.1) == Vector3.ZERO, 'finish before configure is zero')

	var bad_values: Array = [
		[-1.0, 0.12, 0.1, 2.0],
		[0.0, 0.12, 0.1, 0.0],
		[NAN, 0.12, 0.1, 2.0],
		[INF, 0.12, 0.1, 2.0],
		[180.0, 0.0, 0.1, 2.0],
		[180.0, -0.1, 0.1, 2.0],
		[180.0, 1.5, 0.1, 2.0],
		[180.0, NAN, 0.1, 2.0],
		[180.0, 0.12, -0.1, 2.0],
		[180.0, 0.12, 1.5, 2.0],
		[180.0, 0.12, INF, 2.0],
		[180.0, 0.12, 0.1, -1.0],
		[180.0, 0.12, 0.1, 200.0],
		[180.0, 0.12, 0.1, NAN],
	]
	for values in bad_values:
		var row: Array = values
		var hm: HandMomentum = HandMomentum.new()
		var accepted: bool = hm.configure(float(row[0]), float(row[1]), float(row[2]), float(row[3]))
		_check(not accepted, 'invalid configure rejected %s' % [str(row)])
		_check(not hm.begin(Vector3.ZERO, 0.0), 'still unconfigured after rejected configure %s' % [str(row)])

	for speed in [1e39, 1e-60]:
		var value: float = float(speed)
		var hm_probe: HandMomentum = HandMomentum.new()
		var expected: bool = _representable_speed(value)
		var got: bool = hm_probe.configure(value, 0.12, 0.1, 0.0)
		_check(got == expected, 'max_speed %s accepted only if Vector3-representable' % [str(value)])

	var recover: HandMomentum = HandMomentum.new()
	_check(not recover.configure(-5.0), 'rejected configure before valid one')
	_check(recover.configure(180.0, 0.12, 0.1, 2.0), 'valid configure after rejection')
	_check(not recover.configure(10.0, 0.12, 0.1, 0.0), 'repeated configure rejected')
	var fast: Vector3 = _drive_linear(recover, Vector3(1000.0, 0.0, 0.0), 60.0, 30)
	_check(_near(fast.length(), 180.0), 'repeated configure left max_speed 180')

	var edge: HandMomentum = HandMomentum.new()
	_check(edge.configure(50.0, 1.0, 0.0, 50.0), 'edge configure window 1, stale 0, minimum == max_speed accepted')
	var edge2: HandMomentum = HandMomentum.new()
	_check(edge2.configure(50.0, 0.5, 1.0, 0.0), 'edge configure stale 1, minimum 0 accepted')
	var defaults: HandMomentum = HandMomentum.new()
	_check(defaults.configure(), 'default configure accepted')


func _test_linear_frame_rates() -> void:
	var v30: Vector3 = _drive_linear(_make(), Vector3(10.0, 0.0, 0.0), 30.0, 15)
	var v60: Vector3 = _drive_linear(_make(), Vector3(10.0, 0.0, 0.0), 60.0, 30)
	_check(_near_vec(v30, Vector3(10.0, 0.0, 0.0)), 'linear 10 u/s at 30 fps: %s' % [str(v30)])
	_check(_near_vec(v60, Vector3(10.0, 0.0, 0.0)), 'linear 10 u/s at 60 fps: %s' % [str(v60)])
	_check(_near_vec(v30, v60), '30 fps and 60 fps agree')


func _test_diagonal_direction() -> void:
	var v: Vector3 = _drive_linear(_make(), Vector3(6.0, 0.0, 8.0), 60.0, 30)
	_check(_near_vec(v, Vector3(6.0, 0.0, 8.0)), 'diagonal velocity: %s' % [str(v)])
	_check(v != Vector3.ZERO and _near_vec(v.normalized(), Vector3(0.6, 0.0, 0.8)), 'diagonal direction preserved')
	var w: Vector3 = _drive_linear(_make(), Vector3(-4.0, 4.0, -7.0), 60.0, 30)
	_check(_near_vec(w, Vector3(-4.0, 4.0, -7.0)), '3D diagonal velocity: %s' % [str(w)])


func _test_vertical() -> void:
	var up: Vector3 = _drive_linear(_make(), Vector3(0.0, 10.0, 0.0), 60.0, 30)
	var down: Vector3 = _drive_linear(_make(), Vector3(0.0, -10.0, 0.0), 60.0, 30)
	_check(_near_vec(up, Vector3(0.0, 10.0, 0.0)), 'vertical up: %s' % [str(up)])
	_check(_near_vec(down, Vector3(0.0, -10.0, 0.0)), 'vertical down: %s' % [str(down)])


func _test_fast_clamped() -> void:
	var v: Vector3 = _drive_linear(_make(), Vector3(1000.0, 0.0, 0.0), 60.0, 30)
	_check(_near_vec(v, Vector3(180.0, 0.0, 0.0)), 'fast clamped to 180: %s' % [str(v)])
	var d: Vector3 = _drive_linear(_make(), Vector3(1000.0, 1000.0, 0.0), 60.0, 30)
	_check(_near(d.length(), 180.0), 'fast diagonal magnitude clamped to 180')
	_check(_near_vec(d, Vector3(127.27922, 127.27922, 0.0)), 'fast diagonal direction preserved: %s' % [str(d)])


func _test_slow_zero() -> void:
	var v: Vector3 = _drive_linear(_make(), Vector3(1.0, 0.0, 0.0), 60.0, 30)
	_check(v == Vector3.ZERO, 'slow 1 u/s below minimum is exactly zero')
	var still: Vector3 = _drive_linear(_make(), Vector3.ZERO, 60.0, 30)
	_check(still == Vector3.ZERO, 'still hand is exactly zero')


func _test_window() -> void:
	var hm: HandMomentum = _make()
	hm.begin(Vector3.ZERO, 0.0)
	var last_time: float = 0.0
	for i in range(1, 26):
		last_time = float(i) * 0.02
		hm.sample(Vector3(10.0 * last_time, 0.0, 0.0), last_time)
	var rest: Vector3 = Vector3(10.0 * last_time, 0.0, 0.0)
	for i in range(26, 51):
		last_time = float(i) * 0.02
		hm.sample(rest, last_time)
	_check(hm.finish(last_time) == Vector3.ZERO, 'window removes old movement after still samples')

	var boundary: HandMomentum = _make(180.0, 0.125, 0.1, 2.0)
	boundary.begin(Vector3.ZERO, 0.0)
	boundary.sample(Vector3(1.25, 0.0, 0.0), 0.125)
	_check(_near_vec(boundary.finish(0.125), Vector3(10.0, 0.0, 0.0)), 'sample exactly at window boundary retained')

	var outside: HandMomentum = _make(180.0, 0.125, 0.1, 2.0)
	outside.begin(Vector3.ZERO, 0.0)
	outside.sample(Vector3(2.5, 0.0, 0.0), 0.25)
	_check(outside.finish(0.25) == Vector3.ZERO, 'sample older than window discarded, newest retained alone gives zero')


func _test_stale_release() -> void:
	var moving: HandMomentum = _make()
	moving.begin(Vector3.ZERO, 0.0)
	moving.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(moving.finish(0.5) == Vector3.ZERO, 'stale release is zero')

	var equal: HandMomentum = _make(180.0, 0.25, 0.125, 2.0)
	equal.begin(Vector3.ZERO, 0.0)
	equal.sample(Vector3(1.25, 0.0, 0.0), 0.125)
	_check(_near_vec(equal.finish(0.25), Vector3(10.0, 0.0, 0.0)), 'release exactly at stale limit is valid')

	var beyond: HandMomentum = _make(180.0, 0.25, 0.125, 2.0)
	beyond.begin(Vector3.ZERO, 0.0)
	beyond.sample(Vector3(1.25, 0.0, 0.0), 0.125)
	_check(beyond.finish(0.2501) == Vector3.ZERO, 'release just beyond stale limit is zero')

	var zero_stale: HandMomentum = _make(180.0, 0.25, 0.0, 2.0)
	zero_stale.begin(Vector3.ZERO, 0.0)
	zero_stale.sample(Vector3(1.25, 0.0, 0.0), 0.125)
	_check(_near_vec(zero_stale.finish(0.125), Vector3(10.0, 0.0, 0.0)), 'stale 0 accepts release at last timestamp')

	var later: HandMomentum = _make()
	later.begin(Vector3.ZERO, 0.0)
	later.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	var no_append: Vector3 = later.finish(0.15)
	_check(_near_vec(no_append, Vector3(10.0, 0.0, 0.0)), 'finish time does not append still sample or rewindow')


func _test_duplicate_out_of_order_time_zero() -> void:
	var hm: HandMomentum = _make()
	_check(hm.begin(Vector3.ZERO, 0.0), 'begin at time 0 accepted')
	hm.sample(Vector3(1.0, 0.0, 0.0), 0.05)
	hm.sample(Vector3(2.0, 0.0, 0.0), 0.05)
	hm.sample(Vector3(100.0, 0.0, 0.0), 0.03)
	var v: Vector3 = hm.finish(0.05)
	_check(_near_vec(v, Vector3(40.0, 0.0, 0.0)), 'duplicate timestamp replaces, out-of-order ignored: %s' % [str(v)])

	var single: HandMomentum = _make()
	single.begin(Vector3(3.0, 0.0, 0.0), 0.0)
	_check(single.finish(0.0) == Vector3.ZERO, 'single sample finish is zero')

	var dup_only: HandMomentum = _make()
	dup_only.begin(Vector3.ZERO, 0.0)
	dup_only.sample(Vector3(5.0, 0.0, 0.0), 0.0)
	_check(dup_only.finish(0.0) == Vector3.ZERO, 'duplicate of only sample leaves one sample, zero')

	var neg: HandMomentum = _make()
	_check(not neg.begin(Vector3.ZERO, -0.01), 'begin with negative time rejected')

	var early: HandMomentum = _make()
	early.begin(Vector3.ZERO, 0.0)
	early.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(early.finish(0.05) == Vector3.ZERO, 'finish earlier than last sample is zero')

	var replace: HandMomentum = _make()
	replace.begin(Vector3(50.0, 50.0, 50.0), 0.0)
	replace.sample(Vector3(60.0, 0.0, 0.0), 0.1)
	_check(replace.begin(Vector3.ZERO, 1.0), 'second begin accepted')
	replace.sample(Vector3(1.0, 0.0, 0.0), 1.1)
	_check(_near_vec(replace.finish(1.1), Vector3(10.0, 0.0, 0.0)), 'valid begin replaces old gesture')


func _test_invalid_inputs() -> void:
	var hm: HandMomentum = _make()
	hm.begin(Vector3.ZERO, 0.0)
	hm.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(not hm.begin(Vector3(NAN, 0.0, 0.0), 0.2), 'begin NaN point rejected')
	_check(not hm.begin(Vector3(0.0, INF, 0.0), 0.2), 'begin Inf point rejected')
	_check(not hm.begin(Vector3(0.0, 0.0, -INF), 0.2), 'begin -Inf point rejected')
	_check(not hm.begin(Vector3.ZERO, NAN), 'begin NaN time rejected')
	_check(not hm.begin(Vector3.ZERO, INF), 'begin Inf time rejected')
	_check(not hm.begin(Vector3.ZERO, -0.5), 'begin negative time rejected')
	hm.sample(Vector3(NAN, 0.0, 0.0), 0.11)
	hm.sample(Vector3(0.0, INF, 0.0), 0.11)
	hm.sample(Vector3(500.0, 0.0, 0.0), NAN)
	hm.sample(Vector3(500.0, 0.0, 0.0), INF)
	hm.sample(Vector3(500.0, 0.0, 0.0), -1.0)
	var v: Vector3 = hm.finish(0.1)
	_check(_near_vec(v, Vector3(10.0, 0.0, 0.0)), 'invalid begin/sample left gesture unchanged: %s' % [str(v)])

	var nan_finish: HandMomentum = _make()
	nan_finish.begin(Vector3.ZERO, 0.0)
	nan_finish.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(nan_finish.finish(NAN) == Vector3.ZERO, 'finish NaN time is zero')

	var inf_finish: HandMomentum = _make()
	inf_finish.begin(Vector3.ZERO, 0.0)
	inf_finish.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(inf_finish.finish(INF) == Vector3.ZERO, 'finish Inf time is zero')

	var inactive: HandMomentum = _make()
	inactive.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(inactive.finish(0.1) == Vector3.ZERO, 'sample without begin ignored, finish zero')


func _test_finish_consumed_and_cancel() -> void:
	var hm: HandMomentum = _make()
	hm.begin(Vector3.ZERO, 0.0)
	hm.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(hm.finish(0.1) != Vector3.ZERO, 'first finish nonzero')
	_check(hm.finish(0.1) == Vector3.ZERO, 'second finish zero (consumed)')
	hm.sample(Vector3(2.0, 0.0, 0.0), 0.2)
	_check(hm.finish(0.2) == Vector3.ZERO, 'sample after finish ignored')
	_check(hm.begin(Vector3.ZERO, 1.0), 'begin after finish accepted')
	hm.sample(Vector3(0.0, 0.0, 1.0), 1.1)
	_check(_near_vec(hm.finish(1.1), Vector3(0.0, 0.0, 10.0)), 'new gesture after finish works')

	var bad: HandMomentum = _make()
	bad.begin(Vector3.ZERO, 0.0)
	bad.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(bad.finish(NAN) == Vector3.ZERO, 'invalid finish returns zero')
	_check(bad.finish(0.1) == Vector3.ZERO, 'invalid finish consumed gesture')

	var early: HandMomentum = _make()
	early.begin(Vector3.ZERO, 0.0)
	early.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(early.finish(0.05) == Vector3.ZERO, 'finish before last returns zero')
	_check(early.finish(0.1) == Vector3.ZERO, 'finish before last consumed gesture')

	var stale: HandMomentum = _make()
	stale.begin(Vector3.ZERO, 0.0)
	stale.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	_check(stale.finish(0.9) == Vector3.ZERO, 'stale finish returns zero')
	_check(stale.finish(0.1) == Vector3.ZERO, 'stale finish consumed gesture')

	var cancelled: HandMomentum = _make()
	cancelled.begin(Vector3.ZERO, 0.0)
	cancelled.sample(Vector3(1.0, 0.0, 0.0), 0.1)
	cancelled.cancel()
	_check(cancelled.finish(0.1) == Vector3.ZERO, 'cancel discards gesture')
	cancelled.cancel()
	cancelled.sample(Vector3(2.0, 0.0, 0.0), 0.2)
	_check(cancelled.finish(0.2) == Vector3.ZERO, 'sample after cancel ignored')


func _test_bounded_samples() -> void:
	var far: Vector3 = Vector3(100.0, 0.0, 0.0)
	var hm: HandMomentum = _make(180.0, 1.0, 0.1, 2.0)
	hm.begin(far, 0.0)
	var last_time: float = 0.0
	for i in range(1, 100):
		last_time = float(i) * 0.001
		if i < 36:
			hm.sample(far, last_time)
		else:
			hm.sample(Vector3(10.0 * last_time, 0.0, 0.0), last_time)
	var v: Vector3 = hm.finish(last_time)
	_check(_near_vec(v, Vector3(10.0, 0.0, 0.0)), 'only 64 newest samples retained: %s' % [str(v)])

	var control: HandMomentum = _make(180.0, 1.0, 0.1, 2.0)
	control.begin(far, 0.0)
	var control_time: float = 0.0
	for i in range(1, 64):
		control_time = float(i) * 0.001
		control.sample(Vector3(10.0 * control_time, 0.0, 0.0), control_time)
	var c: Vector3 = control.finish(control_time)
	_check(_near_vec(c, Vector3(-180.0, 0.0, 0.0)), 'exactly 64 samples keeps first sample: %s' % [str(c)])


func _test_stable_norm() -> void:
	var hm: HandMomentum = _make(180.0, 1.0, 0.1, 2.0)
	hm.begin(Vector3.ZERO, 0.0)
	hm.sample(Vector3(1e30, 1e30, 0.0), 1.0)
	var v: Vector3 = hm.finish(1.0)
	_check(v.is_finite(), 'large finite velocity stays finite')
	_check(v != Vector3.ZERO, 'large finite velocity not zeroed')
	_check(_near_vec(v, Vector3(127.27922, 127.27922, 0.0)), 'large velocity capped to stable direction: %s' % [str(v)])
	_check(_near(v.length(), 180.0), 'large velocity magnitude capped to 180')
