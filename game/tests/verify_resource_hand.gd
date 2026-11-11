extends SceneTree
## Headless verification for SPEC-RESOURCE-HAND-001 v1 remake components.
## Usage: godot --headless --script res://verify_resource_hand.gd
## Exits with code 1 if any assertion fails. Uses only synthetic data.

const ResourceHandScript: GDScript = preload('res://scripts/resource_hand.gd')
const ResourceStreamScript: GDScript = preload('res://scripts/resource_stream.gd')

var _failures: int = 0
var _checks: int = 0


class Source extends RefCounted:
	var stock: int = 0
	var calls: int = 0
	var last_request: int = -1

	func _init(initial_stock: int) -> void:
		stock = initial_stock

	func take(requested: int) -> int:
		calls += 1
		last_request = requested
		var got: int = clampi(requested, 0, stock)
		stock -= got
		return got


class FreeableSource extends Object:
	var stock: int = 1000
	var calls: int = 0

	func take(requested: int) -> int:
		calls += 1
		var got: int = clampi(requested, 0, stock)
		stock -= got
		return got


class BadSource extends RefCounted:
	var calls: int = 0
	var reply: Variant = null

	func _init(value: Variant) -> void:
		reply = value

	func take(_requested: int) -> Variant:
		calls += 1
		return reply


class Receiver extends RefCounted:
	var limit: int = 0
	var received: int = 0
	var calls: int = 0

	func _init(capacity: int) -> void:
		limit = capacity

	func accept(offered: int) -> int:
		calls += 1
		var got: int = clampi(offered, 0, limit - received)
		received += got
		return got


class BadReceiver extends RefCounted:
	var calls: int = 0
	var reply: Variant = null

	func _init(value: Variant) -> void:
		reply = value

	func accept(_offered: int) -> Variant:
		calls += 1
		return reply


class ReentrantSource extends RefCounted:
	var hand: Variant = null
	var other: Source = null
	var receiver: Receiver = null
	var stock: int = 100000
	var calls: int = 0
	var begin_results: Array = []
	var give_results: Array = []

	func take(requested: int) -> int:
		calls += 1
		if hand != null:
			begin_results.append(hand.begin(1, other.take))
			give_results.append(hand.give(receiver.accept))
			hand.stop()
		var got: int = clampi(requested, 0, stock)
		stock -= got
		return got


class Target extends RefCounted:
	var pos: Vector3 = Vector3.ZERO
	var valid: bool = true
	var calls: int = 0

	func _init(start: Vector3) -> void:
		pos = start

	func get_pos() -> Variant:
		calls += 1
		if valid:
			return pos
		return 'gone'


class FreeableTarget extends Object:
	var pos: Vector3 = Vector3.ZERO

	func get_pos() -> Vector3:
		return pos


func _initialize() -> void:
	_test_reference_timeline()
	_test_wood_and_snapshot()
	_test_subdivisions()
	_test_small_sources()
	_test_bad_source_returns()
	_test_capacity()
	_test_stop_and_restart()
	_test_receivers()
	_test_freed_source()
	_test_deltas()
	_test_signals()
	_test_reentrancy()
	_test_configuration()
	_test_ramp_boundaries()
	_test_stream_path()
	_test_stream_arcs_and_independence()
	_test_stream_cap()
	_test_stream_invalid_inputs()
	_test_stream_cleanup()
	print('verify_resource_hand: checks=%d failures=%d' % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr('FAIL: ' + message)


func _near(a: Vector3, b: Vector3, tolerance: float = 0.0001) -> bool:
	return a.distance_to(b) <= tolerance


func _profile(initial: int, rate_start: int, rate_end: int, ramp_seconds: Variant, maximum: int) -> Dictionary:
	return {'initial': initial, 'rate_start': rate_start, 'rate_end': rate_end, 'ramp_seconds': ramp_seconds, 'maximum': maximum}


func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	copy[key] = value
	return copy


func _without(base: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	copy.erase(key)
	return copy


func _profiles(maximum: int = 20000, initial: int = 25) -> Array[Dictionary]:
	var result: Array[Dictionary] = [_profile(initial, 8, 70, 6.0, maximum), _profile(initial, 8, 70, 6.0, maximum)]
	return result


func _new_hand(maximum: int = 20000, initial: int = 25) -> Variant:
	var hand: Variant = ResourceHandScript.new()
	var ok: bool = hand.configure(_profiles(maximum, initial), 0.1)
	_check(ok, 'valid configuration accepted')
	return hand


func _test_reference_timeline() -> void:
	var source: Source = Source.new(1000)
	var hand: Variant = _new_hand()
	_check(hand.begin(0, source.take) == true, 'begin food returns true')
	_check(hand.amount == 25, 'initial pickup credits 25')
	_check(source.stock == 975, 'source1000 debited to 975')
	_check(source.last_request == 25, 'initial request is 25')
	_check(hand.resource == 0 and hand.collecting == true, 'collecting food after begin')
	hand.stop()
	var big: Source = Source.new(1000000)
	var timed: Variant = _new_hand()
	_check(timed.begin(0, big.take) == true, 'timeline begin')
	timed.advance(1.0)
	_check(timed.amount == 108, 'amount at 1s is 108, got ' + str(timed.amount))
	timed.advance(2.0)
	_check(timed.amount == 413, 'amount at 3s is 413, got ' + str(timed.amount))
	timed.advance(3.0)
	_check(timed.amount == 1746, 'amount at 6s is 1746, got ' + str(timed.amount))
	timed.advance(4.0)
	_check(timed.amount == 4546, 'amount at 10s is 4546, got ' + str(timed.amount))
	_check(big.stock + int(timed.amount) == 1000000, 'timeline stock conservation')
	_check(big.calls == 101, 'one initial call plus 100 turn calls, got ' + str(big.calls))
	_check(big.last_request == 70, 'rate saturates at 70')
	timed.stop()


func _test_wood_and_snapshot() -> void:
	var source: Source = Source.new(1000)
	var hand: Variant = _new_hand()
	_check(hand.begin(1, source.take) == true, 'begin wood')
	var snap: Dictionary = hand.snapshot()
	_check(snap.get('resource') == 1 and snap.get('amount') == 25 and snap.get('collecting') == true, 'snapshot wood fields')
	snap['amount'] = 999
	snap['resource'] = 0
	snap['collecting'] = false
	_check(hand.amount == 25 and hand.resource == 1 and hand.collecting == true, 'snapshot mutation does not alter live state')
	var fresh_snap: Dictionary = hand.snapshot()
	_check(fresh_snap.get('amount') == 25, 'snapshot is fresh')
	var other: Source = Source.new(1000)
	_check(hand.begin(0, other.take) == false, 'begin other resource while holding rejected')
	_check(hand.begin(1, other.take) == false, 'begin same resource while holding rejected')
	_check(other.calls == 0, 'rejected begin did not debit')
	_check(hand.amount == 25 and hand.resource == 1, 'rejected begin left state unchanged')
	hand.stop()
	var fresh: Variant = _new_hand()
	_check(fresh.begin(2, other.take) == false, 'resource 2 rejected')
	_check(fresh.begin(-1, other.take) == false, 'resource -1 rejected')
	_check(other.calls == 0 and fresh.resource == -1, 'invalid resource did not debit')
	var unconfigured: Variant = ResourceHandScript.new()
	_check(unconfigured.begin(0, other.take) == false and other.calls == 0, 'unconfigured begin rejected')


func _amount_after_steps(step: float, count: int) -> int:
	var source: Source = Source.new(1000000)
	var hand: Variant = _new_hand()
	hand.begin(0, source.take)
	for i: int in range(count):
		hand.advance(step)
	hand.advance(0.0)
	var result: int = hand.amount
	_check(source.stock + result == 1000000, 'subdivision stock conservation')
	hand.stop()
	return result


func _test_subdivisions() -> void:
	var cases: Array = [[10.0, 1], [0.1, 100], [0.25, 40], [0.05, 200], [0.5, 20], [0.03, 334], [2.5, 4]]
	for entry: Array in cases:
		var step: float = entry[0]
		var count: int = entry[1]
		var got: int = _amount_after_steps(step, count)
		_check(got == 4546, 'subdivision %s x %d yields 4546, got %d' % [str(step), count, got])


func _test_small_sources() -> void:
	var seven: Source = Source.new(7)
	var hand: Variant = _new_hand()
	_check(hand.begin(0, seven.take) == true, 'source7 begin true')
	_check(hand.amount == 7 and seven.stock == 0, 'source7 credits 7')
	_check(hand.collecting == true, 'positive partial initial does not prove exhaustion')
	hand.advance(0.1)
	_check(hand.collecting == false and hand.amount == 7, 'zero return stops collection and retains 7')
	_check(seven.calls == 2, 'source7 called twice')
	hand.advance(1.0)
	_check(seven.calls == 2, 'no debit after exhaustion')
	var thirty: Source = Source.new(30)
	var second: Variant = _new_hand()
	_check(second.begin(0, thirty.take) == true, 'source30 begin')
	second.advance(0.1)
	_check(second.amount == 30 and second.collecting == true, 'partial turn return keeps collecting')
	_check(thirty.last_request == 8, 'first turn requests 8')
	second.advance(0.1)
	_check(second.collecting == false and second.amount == 30 and thirty.calls == 3, 'next zero return stops')
	var empty: Source = Source.new(0)
	var third: Variant = _new_hand()
	_check(third.begin(0, empty.take) == false, 'empty source begin false')
	_check(third.resource == -1 and third.amount == 0 and third.collecting == false, 'empty begin resets state')
	_check(empty.calls == 1, 'empty source asked once')


func _test_bad_source_returns() -> void:
	var replies: Array = ['10', -3, 26, 2.5, null, true]
	for reply: Variant in replies:
		var bad: BadSource = BadSource.new(reply)
		var hand: Variant = _new_hand()
		_check(hand.begin(0, bad.take) == false, 'invalid source return treated as 0: ' + str(reply))
		_check(hand.resource == -1 and hand.amount == 0 and hand.collecting == false, 'invalid source return leaves empty hand: ' + str(reply))
	var flaky: BadSource = BadSource.new(25)
	var collector: Variant = _new_hand()
	_check(collector.begin(0, flaky.take) == true and collector.amount == 25, 'valid int reply credited')
	flaky.reply = 'x'
	collector.advance(0.1)
	_check(collector.collecting == false and collector.amount == 25, 'invalid turn return stops and retains')


func _test_capacity() -> void:
	var source: Source = Source.new(1000)
	var hand: Variant = _new_hand(30, 25)
	_check(hand.begin(0, source.take) == true and hand.collecting == true, 'capacity30 begin')
	hand.advance(0.1)
	_check(hand.amount == 30, 'capped turn fills to 30')
	_check(source.last_request == 5, 'request capped by free capacity')
	_check(hand.collecting == false, 'full hand stops collecting')
	_check(source.stock == 970, 'stock debited only accepted amount')
	hand.advance(5.0)
	_check(source.calls == 2, 'no debit after full')
	var exact: Source = Source.new(1000)
	var filled: Variant = _new_hand(25, 25)
	_check(filled.begin(0, exact.take) == true, 'begin that fills capacity returns true')
	_check(filled.collecting == false and filled.amount == 25, 'begin filling capacity is not collecting')
	filled.advance(1.0)
	_check(exact.calls == 1 and exact.stock == 975, 'released source not debited later')


func _test_stop_and_restart() -> void:
	var source: Source = Source.new(100000)
	var receiver: Receiver = Receiver.new(100000)
	var hand: Variant = _new_hand()
	hand.begin(0, source.take)
	hand.advance(0.05)
	_check(source.calls == 1 and hand.amount == 25, 'half turn does not debit')
	hand.stop()
	_check(hand.collecting == false and hand.amount == 25 and hand.resource == 0, 'stop retains quantity')
	hand.advance(10.0)
	_check(source.calls == 1, 'no debit after stop')
	hand.stop()
	_check(hand.begin(0, source.take) == false and source.calls == 1, 'begin while holding rejected')
	_check(hand.give(receiver.accept) == 25, 'give after stop transfers 25')
	_check(hand.begin(0, source.take) == true and source.calls == 2, 'new begin after empty')
	hand.advance(0.05)
	_check(source.calls == 2, 'stop discarded backlog')
	hand.advance(0.05)
	_check(source.calls == 3 and source.last_request == 8 and hand.amount == 33, 'turn after full turn time')
	hand.advance(0.9)
	_check(source.calls == 12 and source.last_request == 9, 'turn 10 requests 9')
	_check(hand.give(receiver.accept) == 108, 'give returns 108')
	_check(hand.begin(0, source.take) == true, 'third begin')
	hand.advance(0.1)
	_check(source.last_request == 8, 'elapsed turns restart at 0 on new begin')
	_check(source.stock + int(hand.amount) + receiver.received == 100000, 'stop/restart conservation')
	hand.stop()


func _test_receivers() -> void:
	var source: Source = Source.new(1000)
	var hand: Variant = _new_hand()
	hand.begin(0, source.take)
	_check(hand.collecting == true, 'collecting before give')
	var partial: Receiver = Receiver.new(10)
	_check(hand.give(partial.accept) == 10, 'partial receiver accepts 10')
	_check(hand.collecting == false, 'give stops collection')
	_check(hand.amount == 15 and hand.resource == 0, 'partial give retains remainder and resource')
	hand.advance(1.0)
	_check(source.calls == 1, 'no debit after give stopped collection')
	var replies: Array = [0, -5, 999, 'x', 3.0, null]
	for reply: Variant in replies:
		var bad: BadReceiver = BadReceiver.new(reply)
		_check(hand.give(bad.accept) == 0, 'zero/invalid receiver returns 0: ' + str(reply))
		_check(bad.calls == 1, 'receiver called once: ' + str(reply))
		_check(hand.amount == 15 and hand.resource == 0, 'invalid receiver retains quantity: ' + str(reply))
	_check(hand.give(Callable()) == 0 and hand.amount == 15, 'invalid callable give returns 0')
	var full: Receiver = Receiver.new(1000)
	_check(hand.give(full.accept) == 15, 'full receiver takes remainder')
	_check(hand.amount == 0 and hand.resource == -1, 'empty hand clears resource')
	_check(hand.give(full.accept) == 0 and full.calls == 1, 'duplicate give does not call receiver')
	_check(source.stock + partial.received + full.received == 1000, 'receiver conservation')
	var second_source: Source = Source.new(1000)
	var second: Variant = _new_hand()
	second.begin(0, second_source.take)
	_check(second.give(Callable()) == 0, 'invalid give returns 0')
	_check(second.collecting == false and second.amount == 25, 'invalid give still stops collection')
	second.advance(1.0)
	_check(second_source.calls == 1, 'no debit after invalid give')


func _test_freed_source() -> void:
	var freeable: FreeableSource = FreeableSource.new()
	var hand: Variant = _new_hand()
	_check(hand.begin(0, freeable.take) == true and hand.amount == 25, 'begin from freeable source')
	freeable.free()
	hand.advance(0.1)
	_check(hand.collecting == false and hand.amount == 25, 'freed source stops collection and retains')
	hand.advance(1.0)
	_check(hand.amount == 25, 'no change after freed source')
	var gone: FreeableSource = FreeableSource.new()
	var gone_take: Callable = gone.take
	gone.free()
	var second: Variant = _new_hand()
	_check(second.begin(0, gone_take) == false and second.resource == -1, 'freed callable begin rejected')
	_check(second.begin(0, Callable()) == false, 'empty callable begin rejected')
	hand.stop()


func _test_deltas() -> void:
	var source: Source = Source.new(100000)
	var hand: Variant = _new_hand()
	hand.begin(0, source.take)
	var bad_deltas: Array = [-1.0, -0.0001, NAN, INF, -INF]
	for bad_delta: float in bad_deltas:
		hand.advance(bad_delta)
	_check(source.calls == 1 and hand.amount == 25 and hand.collecting == true, 'negative/nonfinite delta ignored')
	hand.advance(1.0e308)
	_check(source.calls == 257, 'huge delta processes at most 256 turns, calls ' + str(source.calls))
	_check(hand.amount == 15466, 'amount after 256 turns is 15466, got ' + str(hand.amount))
	_check(hand.collecting == true, 'still collecting with backlog')
	hand.advance(0.0)
	_check(hand.amount == 20000 and hand.collecting == false, 'advance(0) drains backlog to capacity')
	_check(source.last_request == 54 and source.calls == 322, 'last turn capped by capacity')
	_check(source.stock + int(hand.amount) == 100000, 'huge delta conservation')
	hand.advance(1.0e308)
	_check(source.calls == 322, 'no calls after capacity')
	var second_source: Source = Source.new(100000)
	var second: Variant = _new_hand()
	second.begin(1, second_source.take)
	second.advance(1.7976931348623157e308)
	second.advance(1.7976931348623157e308)
	_check(int(second.amount) <= 20000 and second_source.stock + int(second.amount) == 100000, 'largest finite delta saturates safely')
	second.stop()


func _test_signals() -> void:
	var source: Source = Source.new(1000)
	var hand: Variant = _new_hand()
	var events: Array = []
	var observer: Callable = func(direction: String, res: int, qty: int) -> void:
		events.append([direction, res, qty, hand.amount, hand.resource, hand.collecting])
	hand.moved.connect(observer)
	hand.begin(0, source.take)
	_check(events.size() == 1 and events[0] == ['pickup', 0, 25, 25, 0, true], 'begin pickup signal sees final state: ' + str(events))
	hand.advance(0.1)
	_check(events.size() == 2 and events[1] == ['pickup', 0, 8, 33, 0, true], 'turn pickup signal')
	hand.advance(-1.0)
	hand.advance(0.05)
	_check(events.size() == 2, 'no signal for no-op advance')
	var r1: Receiver = Receiver.new(10)
	hand.give(r1.accept)
	_check(events.size() == 3 and events[2] == ['putdown', 0, 10, 23, 0, false], 'partial putdown signal')
	var r0: BadReceiver = BadReceiver.new(0)
	hand.give(r0.accept)
	_check(events.size() == 3, 'no signal for zero acceptance')
	var r2: Receiver = Receiver.new(100)
	hand.give(r2.accept)
	_check(events.size() == 4 and events[3] == ['putdown', 0, 23, 0, -1, false], 'emptying putdown reports transferred resource')
	hand.give(r2.accept)
	hand.stop()
	_check(events.size() == 4, 'no signal for empty give or stop')
	hand.moved.disconnect(observer)
	var full_source: Source = Source.new(1000)
	var full_hand: Variant = _new_hand(25, 25)
	var full_events: Array = []
	var full_observer: Callable = func(direction: String, res: int, qty: int) -> void:
		full_events.append([direction, res, qty, full_hand.amount, full_hand.resource, full_hand.collecting])
	full_hand.moved.connect(full_observer)
	full_hand.begin(1, full_source.take)
	_check(full_events.size() == 1 and full_events[0] == ['pickup', 1, 25, 25, 1, false], 'filling begin signal sees not collecting')
	full_hand.moved.disconnect(full_observer)


func _test_reentrancy() -> void:
	var hand: Variant = _new_hand()
	var reentrant: ReentrantSource = ReentrantSource.new()
	reentrant.hand = hand
	reentrant.other = Source.new(1000)
	reentrant.receiver = Receiver.new(1000)
	_check(hand.begin(0, reentrant.take) == true, 'reentrant source begin')
	_check(hand.amount == 25 and hand.resource == 0 and hand.collecting == true, 'reentrant calls did not mutate begin')
	_check(reentrant.begin_results == [false] and reentrant.give_results == [0], 'reentrant begin/give rejected')
	_check(reentrant.other.calls == 0 and reentrant.receiver.calls == 0, 'reentrant calls made no transfers')
	hand.advance(0.1)
	_check(hand.collecting == true and hand.amount == 33, 'reentrant stop during turn ignored')
	_check(reentrant.begin_results == [false, false] and reentrant.give_results == [0, 0], 'reentrant calls rejected during turn')
	_check(reentrant.stock + int(hand.amount) == 100000, 'reentrant conservation')
	reentrant.hand = null
	hand.stop()
	var observed_hand: Variant = _new_hand()
	var src: Source = Source.new(1000)
	var rcv: Receiver = Receiver.new(1000)
	var observed: Array = []
	var observer: Callable = func(_direction: String, _res: int, _qty: int) -> void:
		observed.append(observed_hand.give(rcv.accept))
		observed.append(observed_hand.begin(1, src.take))
		observed_hand.stop()
		var snap: Dictionary = observed_hand.snapshot()
		observed.append(snap['amount'])
	observed_hand.moved.connect(observer)
	_check(observed_hand.begin(0, src.take) == true, 'observer test begin')
	_check(observed == [0, false, 25], 'observer mutations rejected, snapshot allowed: ' + str(observed))
	_check(rcv.calls == 0 and src.calls == 1 and observed_hand.collecting == true, 'observer caused no transfer')
	observed_hand.advance(0.1)
	_check(observed.size() == 6 and observed_hand.collecting == true and observed_hand.amount == 33, 'observer during turn rejected')
	_check(observed_hand.give(rcv.accept) == 33, 'outside give works')
	_check(rcv.calls == 1 and src.calls == 2, 'no double debit or double credit')
	_check(observed.size() == 9 and observed[8] == 0, 'observer sees emptied hand')
	_check(src.stock + rcv.received == 1000, 'observer conservation')
	observed_hand.moved.disconnect(observer)


func _test_configuration() -> void:
	var base: Dictionary = _profile(25, 8, 70, 6.0, 20000)
	var bad_profiles: Array[Dictionary] = [
		_with(base, 'initial', true),
		_with(base, 'initial', 25.0),
		_with(base, 'initial', 0),
		_with(base, 'initial', -1),
		_with(base, 'maximum', 20001),
		_with(base, 'maximum', 20000.0),
		_with(_with(base, 'initial', 30), 'maximum', 20),
		_with(base, 'rate_start', 0),
		_with(base, 'rate_start', 71),
		_with(base, 'rate_start', false),
		_with(base, 'rate_end', 20001),
		_with(base, 'rate_end', 70.0),
		_with(base, 'ramp_seconds', NAN),
		_with(base, 'ramp_seconds', INF),
		_with(base, 'ramp_seconds', true),
		_with(base, 'ramp_seconds', 0),
		_with(base, 'ramp_seconds', -6.0),
		_with(base, 'ramp_seconds', '6'),
		_with(base, 'ramp_seconds', 100000.5),
		_without(base, 'initial'),
		_without(base, 'ramp_seconds'),
	]
	var index: int = 0
	for bad: Dictionary in bad_profiles:
		var hand: Variant = ResourceHandScript.new()
		var first: Array[Dictionary] = [base, bad]
		var second: Array[Dictionary] = [bad, base]
		_check(hand.configure(first, 0.1) == false, 'bad profile %d rejected in second slot' % index)
		_check(hand.configure(second, 0.1) == false, 'bad profile %d rejected in first slot' % index)
		var probe: Source = Source.new(100)
		_check(hand.begin(0, probe.take) == false and probe.calls == 0, 'hand unconfigured after failure %d' % index)
		index += 1
	var zero_list: Array[Dictionary] = []
	var one_list: Array[Dictionary] = [base]
	var three_list: Array[Dictionary] = [base, base, base]
	for wrong_size: Array[Dictionary] in [zero_list, one_list, three_list]:
		var sized: Variant = ResourceHandScript.new()
		_check(sized.configure(wrong_size, 0.1) == false, 'profile count %d rejected' % wrong_size.size())
	var pair: Array[Dictionary] = [base, base]
	var bad_turns: Array = [0.0005, 1.5, NAN, INF, 0.0, -0.1]
	for bad_turn: float in bad_turns:
		var turned: Variant = ResourceHandScript.new()
		_check(turned.configure(pair, bad_turn) == false, 'turn_seconds rejected: ' + str(bad_turn))
	var low: Variant = ResourceHandScript.new()
	_check(low.configure(pair, 0.001) == true, 'turn_seconds 0.001 accepted')
	var high: Variant = ResourceHandScript.new()
	_check(high.configure(pair, 1.0) == true, 'turn_seconds 1.0 accepted')
	var int_ramp: Dictionary = _with(base, 'ramp_seconds', 6)
	var mutable: Dictionary = int_ramp.duplicate(true)
	var mutable_pair: Array[Dictionary] = [mutable, mutable]
	var hand_ok: Variant = ResourceHandScript.new()
	_check(hand_ok.configure(mutable_pair, 0.1) == true, 'integer ramp_seconds accepted')
	mutable['initial'] = 3
	var src: Source = Source.new(1000)
	_check(hand_ok.begin(0, src.take) == true and hand_ok.amount == 25, 'profile fields copied at configure')
	var changed: Array[Dictionary] = [_with(base, 'initial', 5), _with(base, 'initial', 5)]
	_check(hand_ok.configure(changed, 0.1) == false, 'reconfigure rejected')
	_check(hand_ok.amount == 25 and hand_ok.collecting == true and hand_ok.resource == 0, 'reconfigure leaves state unchanged')
	var sink: Receiver = Receiver.new(1000)
	hand_ok.give(sink.accept)
	_check(hand_ok.begin(0, src.take) == true and hand_ok.amount == 25, 'original profile still in effect')
	hand_ok.stop()


func _test_ramp_boundaries() -> void:
	var base: Dictionary = _profile(25, 8, 70, 0.3, 20000)
	var pair: Array[Dictionary] = [base, base]
	var hand: Variant = ResourceHandScript.new()
	_check(hand.configure(pair, 0.1) == true, 'ramp 0.3 accepted')
	var source: Source = Source.new(100000)
	hand.begin(0, source.take)
	hand.advance(0.1)
	_check(source.last_request == 14, 'ramp 0.3/0.1 is 3 turns: turn1 requests 14, got ' + str(source.last_request))
	hand.advance(0.1)
	_check(source.last_request == 35, 'turn2 requests 35')
	hand.advance(0.1)
	_check(source.last_request == 70, 'turn3 requests 70')
	hand.stop()
	var short: Dictionary = _profile(25, 8, 70, 0.05, 20000)
	var short_pair: Array[Dictionary] = [short, short]
	var quick: Variant = ResourceHandScript.new()
	_check(quick.configure(short_pair, 0.1) == true, 'sub-turn ramp accepted')
	var quick_source: Source = Source.new(100000)
	quick.begin(1, quick_source.take)
	quick.advance(0.1)
	_check(quick_source.last_request == 70, 'ramp turns at least 1')
	quick.stop()


func _make_box() -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.0, 2.0, 1.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.5, 0.1, 1.0)
	mesh.material = material
	return mesh


func _test_stream_path() -> void:
	var mesh: BoxMesh = _make_box()
	var material: Material = mesh.material
	var stream: Variant = ResourceStreamScript.new()
	_check(stream.active_count() == 0, 'stream starts empty')
	var target: Target = Target.new(Vector3(10.0, 0.0, 0.0))
	_check(stream.burst(mesh, Vector3.ZERO, target.get_pos, 1.5, 1.0) == true, 'burst accepted')
	_check(target.calls == 1, 'destination sampled once at creation')
	_check(stream.active_count() == 1 and stream.get_child_count() == 1, 'one child per burst')
	var child: MeshInstance3D = stream.get_child(0) as MeshInstance3D
	_check(child != null, 'child is MeshInstance3D')
	if child == null:
		stream.free()
		return
	_check(child.mesh == mesh, 'mesh shared unmodified')
	_check(child.material_override == null, 'no material fabricated')
	_check(_near(child.scale, Vector3(1.5, 1.5, 1.5)), 'uniform scale applied')
	_check(_near(child.position, Vector3.ZERO), 'starts at origin')
	stream.advance(0.5)
	_check(_near(child.position, Vector3(5.0, 1.2, 0.0)), 'midpoint with arc lift: ' + str(child.position))
	_check(target.calls == 2, 'destination sampled on advance')
	target.pos = Vector3(20.0, 0.0, 0.0)
	stream.advance(0.25)
	_check(_near(child.position, Vector3(15.0, 0.9, 0.0)), 'follows moving endpoint with fixed arc: ' + str(child.position))
	target.valid = false
	stream.advance(0.0)
	_check(_near(child.position, Vector3(15.0, 0.9, 0.0)), 'invalid endpoint retains last valid')
	target.valid = true
	target.pos = Vector3(INF, 0.0, 0.0)
	stream.advance(0.0)
	_check(_near(child.position, Vector3(15.0, 0.9, 0.0)), 'nonfinite endpoint retains last valid')
	target.pos = Vector3(20.0, 0.0, 0.0)
	var calls_before: int = target.calls
	stream.advance(-1.0)
	stream.advance(NAN)
	stream.advance(INF)
	_check(target.calls == calls_before, 'invalid dt ignored without sampling')
	_check(stream.active_count() == 1 and _near(child.position, Vector3(15.0, 0.9, 0.0)), 'invalid dt does not move')
	stream.advance(0.25)
	_check(stream.active_count() == 0 and stream.get_child_count() == 0, 'particle freed at t=1')
	_check(not is_instance_valid(child), 'finished instance freed immediately')
	_check(mesh.material == material, 'mesh material unchanged')
	var standard: StandardMaterial3D = material as StandardMaterial3D
	_check(standard != null and standard.albedo_color.is_equal_approx(Color(0.2, 0.5, 0.1, 1.0)), 'material color unmodified')
	stream.free()


func _test_stream_arcs_and_independence() -> void:
	var mesh: BoxMesh = _make_box()
	var stream: Variant = ResourceStreamScript.new()
	var near: Target = Target.new(Vector3(1.0, 0.0, 0.0))
	var far: Target = Target.new(Vector3(100.0, 0.0, 0.0))
	var slow: Target = Target.new(Vector3(0.0, 0.0, 10.0))
	_check(stream.burst(mesh, Vector3.ZERO, near.get_pos, 1.0, 1.0) == true, 'near burst')
	_check(stream.burst(mesh, Vector3.ZERO, far.get_pos, 1.0, 1.0) == true, 'far burst')
	_check(stream.burst(mesh, Vector3.ZERO, slow.get_pos, 1.0, 2.0) == true, 'slow burst')
	_check(stream.active_count() == 3, 'three independent bursts')
	var near_node: MeshInstance3D = stream.get_child(0) as MeshInstance3D
	var far_node: MeshInstance3D = stream.get_child(1) as MeshInstance3D
	var slow_node: MeshInstance3D = stream.get_child(2) as MeshInstance3D
	stream.advance(0.5)
	_check(_near(near_node.position, Vector3(0.5, 0.4, 0.0)), 'arc minimum 0.4: ' + str(near_node.position))
	_check(_near(far_node.position, Vector3(50.0, 4.0, 0.0)), 'arc maximum 4: ' + str(far_node.position))
	_check(_near(slow_node.position, Vector3(0.0, 0.9, 2.5)), 'slow quarter path: ' + str(slow_node.position))
	stream.advance(0.5)
	_check(stream.active_count() == 1, 'fast bursts finished independently')
	_check(not is_instance_valid(near_node) and not is_instance_valid(far_node), 'finished nodes freed')
	stream.advance(0.5)
	_check(_near(slow_node.position, Vector3(0.0, 0.9, 7.5)), 'slow three-quarter path')
	var freeable: FreeableTarget = FreeableTarget.new()
	freeable.pos = Vector3(10.0, 0.0, 0.0)
	_check(stream.burst(mesh, Vector3.ZERO, freeable.get_pos, 1.0, 1.0) == true, 'freeable target burst')
	freeable.free()
	stream.advance(0.5)
	_check(stream.active_count() == 1 and stream.get_child_count() == 1, 'slow finished, freed-target particle remains')
	var remaining: MeshInstance3D = stream.get_child(0) as MeshInstance3D
	_check(remaining != null and _near(remaining.position, Vector3(5.0, 1.2, 0.0)), 'freed destination keeps last endpoint')
	stream.free()


func _test_stream_cap() -> void:
	var mesh: BoxMesh = _make_box()
	var stream: Variant = ResourceStreamScript.new()
	var target: Target = Target.new(Vector3(3.0, 0.0, 0.0))
	var accepted: int = 0
	for i: int in range(64):
		if stream.burst(mesh, Vector3(float(i), 0.0, 0.0), target.get_pos, 1.0, 1.0):
			accepted += 1
	_check(accepted == 64, '64 bursts accepted')
	_check(stream.active_count() == 64 and stream.get_child_count() == 64, '64 live particles')
	var calls_before: int = target.calls
	_check(stream.burst(mesh, Vector3.ZERO, target.get_pos, 1.0, 1.0) == false, '65th burst rejected')
	_check(target.calls == calls_before, 'full rejection does not sample destination')
	_check(stream.active_count() == 64 and stream.get_child_count() == 64, 'full rejection does not mutate')
	stream.advance(1.0e308)
	_check(stream.active_count() == 0 and stream.get_child_count() == 0, 'huge dt finishes all particles')
	_check(stream.burst(mesh, Vector3.ZERO, target.get_pos, 1.0, 1.0) == true, 'capacity available after cleanup')
	stream.free()


func _test_stream_invalid_inputs() -> void:
	var mesh: BoxMesh = _make_box()
	var stream: Variant = ResourceStreamScript.new()
	var good: Target = Target.new(Vector3(5.0, 0.0, 0.0))
	var bad_value: Target = Target.new(Vector3.ZERO)
	bad_value.valid = false
	var inf_target: Target = Target.new(Vector3(INF, 0.0, 0.0))
	var far_target: Target = Target.new(Vector3(1.0e308, 0.0, 0.0))
	var plane: PlaneMesh = PlaneMesh.new()
	var empty_mesh: ArrayMesh = ArrayMesh.new()
	var cases: Array = [
		[null, Vector3.ZERO, good.get_pos, 1.0, 1.0, 'null mesh'],
		[empty_mesh, Vector3.ZERO, good.get_pos, 1.0, 1.0, 'mesh without surfaces'],
		[plane, Vector3.ZERO, good.get_pos, 1.0, 1.0, 'zero height mesh'],
		[mesh, Vector3(NAN, 0.0, 0.0), good.get_pos, 1.0, 1.0, 'nan origin'],
		[mesh, Vector3(0.0, INF, 0.0), good.get_pos, 1.0, 1.0, 'inf origin'],
		[mesh, Vector3.ZERO, good.get_pos, 0.0, 1.0, 'zero scale'],
		[mesh, Vector3.ZERO, good.get_pos, -1.0, 1.0, 'negative scale'],
		[mesh, Vector3.ZERO, good.get_pos, NAN, 1.0, 'nan scale'],
		[mesh, Vector3.ZERO, good.get_pos, INF, 1.0, 'inf scale'],
		[mesh, Vector3.ZERO, good.get_pos, 1.0, 0.0, 'zero seconds'],
		[mesh, Vector3.ZERO, good.get_pos, 1.0, -1.0, 'negative seconds'],
		[mesh, Vector3.ZERO, good.get_pos, 1.0, NAN, 'nan seconds'],
		[mesh, Vector3.ZERO, good.get_pos, 1.0, INF, 'inf seconds'],
		[mesh, Vector3.ZERO, Callable(), 1.0, 1.0, 'invalid callable'],
		[mesh, Vector3.ZERO, bad_value.get_pos, 1.0, 1.0, 'non-vector destination'],
		[mesh, Vector3.ZERO, inf_target.get_pos, 1.0, 1.0, 'nonfinite destination'],
		[mesh, Vector3(-1.0e308, 0.0, 0.0), far_target.get_pos, 1.0, 1.0, 'nonfinite distance'],
	]
	for entry: Array in cases:
		var ok: bool = stream.burst(entry[0], entry[1], entry[2], entry[3], entry[4])
		_check(not ok, 'rejected: ' + str(entry[5]))
		_check(stream.active_count() == 0 and stream.get_child_count() == 0, 'no child after: ' + str(entry[5]))
	_check(stream.burst(mesh, Vector3.ZERO, good.get_pos, 1.0, 1.0) == true, 'valid burst after rejections')
	_check(stream.active_count() == 1, 'one particle after valid burst')
	stream.free()


func _test_stream_cleanup() -> void:
	var mesh: BoxMesh = _make_box()
	var stream: Variant = ResourceStreamScript.new()
	var target: Target = Target.new(Vector3(2.0, 0.0, 0.0))
	for i: int in range(3):
		stream.burst(mesh, Vector3(0.0, float(i), 0.0), target.get_pos, 1.0, 1.0)
	var kids: Array = []
	for kid: Variant in stream.get_children():
		kids.append(kid)
	_check(kids.size() == 3 and stream.active_count() == 3, 'three particles before cleanup')
	stream.free()
	var leaked: int = 0
	for kid: Variant in kids:
		if is_instance_valid(kid):
			leaked += 1
	_check(leaked == 0, 'deleting stream deletes all particles')
