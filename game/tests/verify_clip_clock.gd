extends SceneTree

## Standalone tests: godot --headless --script test_clip_clock.gd
## Synthetic data only. Exits 0 when every check passes, 1 otherwise.

const MODULE_FILE: String = "clip_clock.gd"
const DEADLINE_SECONDS: float = 20.0
const SNAPSHOT_KEYS: Array = ["name", "age", "position", "duration", "repeats", "playing", "completed"]

var _module_script: GDScript = null
var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	var deadline: SceneTreeTimer = create_timer(DEADLINE_SECONDS)
	deadline.timeout.connect(_on_deadline)
	call_deferred("_run")


func _on_deadline() -> void:
	if _finished:
		return
	_finished = true
	print("FAIL deadline of %s seconds reached before tests finished" % DEADLINE_SECONDS)
	quit(1)


func _run() -> void:
	var own_script: Script = get_script() as Script
	var module_path: String = "res://scripts/" + MODULE_FILE
	_module_script = load(module_path) as GDScript
	if _module_script == null:
		_check(false, "load module at " + module_path)
		_finish()
		return
	_test_unconfigured()
	_test_configure_rejections()
	_test_configure_limits()
	_test_duplicate_configure_and_input_copy()
	_test_snapshot_isolation()
	_test_start_validation()
	_test_advance_validation()
	_test_example_table()
	_test_finite_single_repeat()
	_test_finite_multiple_repeats_and_clamp()
	_test_terminal_retention()
	_test_restart()
	_test_stop()
	_test_invalid_calls_keep_running_request()
	_test_large_values()
	_test_nonbinary_timing()
	_test_independent_instances()
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------- helpers

func _new_clock() -> Variant:
	return _module_script.new()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS " + label)
	else:
		_failures += 1
		print("FAIL " + label)


func _close(a: float, b: float) -> bool:
	var magnitude: float = maxf(absf(a), absf(b))
	return absf(a - b) <= maxf(1e-9, 1e-12 * magnitude)


func _state(clip_name: String, age: float, pos: float, duration: float, repeats: int, playing: bool, completed: bool) -> Dictionary:
	return {
		"name": clip_name,
		"age": age,
		"position": pos,
		"duration": duration,
		"repeats": repeats,
		"playing": playing,
		"completed": completed,
	}


func _idle() -> Dictionary:
	return _state("", 0.0, 0.0, 0.0, 0, false, false)


func _bad_deltas() -> Array:
	return [NAN, INF, -INF, -0.25, -1.0, 36000.000001, 36001.0]


func _snapshot_matches(actual: Dictionary, expected: Dictionary, approximate: bool) -> bool:
	if actual.size() != SNAPSHOT_KEYS.size():
		return false
	for key: Variant in SNAPSHOT_KEYS:
		if not actual.has(key) or not expected.has(key):
			return false
		var got: Variant = actual[key]
		var want: Variant = expected[key]
		if typeof(got) != typeof(want):
			return false
		if approximate and typeof(want) == TYPE_FLOAT:
			if not _close(got, want):
				return false
		elif got != want:
			return false
	return true


func _expect(clock: Variant, expected: Dictionary, label: String) -> void:
	var actual: Dictionary = clock.snapshot()
	var ok: bool = _snapshot_matches(actual, expected, false)
	if ok:
		_check(true, label)
	else:
		_check(false, "%s got=%s want=%s" % [label, actual, expected])


func _expect_close(clock: Variant, expected: Dictionary, label: String) -> void:
	var actual: Dictionary = clock.snapshot()
	var ok: bool = _snapshot_matches(actual, expected, true)
	if ok:
		_check(true, label)
	else:
		_check(false, "%s got=%s want=%s" % [label, actual, expected])


# ---------------------------------------------------------------- tests

func _test_unconfigured() -> void:
	var clock: Variant = _new_clock()
	_expect(clock, _idle(), "unconfigured snapshot is idle")
	_check(not clock.start("a", 1), "unconfigured start rejected")
	_check(not clock.start("a", -1), "unconfigured infinite start rejected")
	_check(not clock.advance(0.0), "unconfigured zero advance rejected")
	_check(not clock.advance(1.0), "unconfigured advance rejected")
	_check(not clock.advance(NAN), "unconfigured NaN advance rejected")
	_check(not clock.stop(), "unconfigured stop rejected")
	_expect(clock, _idle(), "unconfigured state unchanged after rejected calls")


func _test_configure_rejections() -> void:
	var cases: Array = []
	cases.append(["empty map", {}])
	cases.append(["int key", {1: 2.0}])
	cases.append(["empty key", {"": 2.0}])
	var long_ascii: Dictionary = {}
	long_ascii["a".repeat(129)] = 2.0
	cases.append(["129 character key", long_ascii])
	var long_unicode: Dictionary = {}
	long_unicode[char(0xE9).repeat(129)] = 2.0
	cases.append(["129 code point non-ascii key", long_unicode])
	cases.append(["bool value", {"a": true}])
	cases.append(["string value", {"a": "2"}])
	cases.append(["null value", {"a": null}])
	cases.append(["NaN value", {"a": NAN}])
	cases.append(["infinite value", {"a": INF}])
	cases.append(["negative infinite value", {"a": -INF}])
	cases.append(["zero float value", {"a": 0.0}])
	cases.append(["zero int value", {"a": 0}])
	cases.append(["negative value", {"a": -1.0}])
	cases.append(["below minimum value", {"a": 0.0000009}])
	cases.append(["above maximum float value", {"a": 36000.0001}])
	cases.append(["above maximum int value", {"a": 36001}])
	cases.append(["one bad value among good", {"a": 2.0, "b": -1.0}])
	cases.append(["one bad key among good", {"a": 2.0, 7: 1.0}])
	var too_many: Dictionary = {}
	for i: int in range(513):
		too_many["clip_%d" % i] = 1.0
	cases.append(["513 entries", too_many])

	var clock: Variant = _new_clock()
	for entry: Array in cases:
		var label: String = entry[0]
		var durations: Dictionary = entry[1]
		_check(not clock.configure(durations), "configure rejects " + label)
		_check(not clock.start("a", 1), "still unconfigured after " + label)
		_expect(clock, _idle(), "idle snapshot after " + label)

	var string_name_map: Dictionary = {}
	string_name_map[StringName("a")] = 2.0
	if typeof(string_name_map.keys()[0]) == TYPE_STRING_NAME:
		_check(not clock.configure(string_name_map), "configure rejects StringName key")
	else:
		print("NOTE engine did not keep a StringName key; StringName case skipped")

	_check(not clock.advance(0.0), "advance still rejected after failed configures")
	_check(not clock.stop(), "stop still rejected after failed configures")
	_check(clock.configure({"a": 2.0}), "configure succeeds after failures")
	_check(clock.start("a", 1), "start after successful configure")
	_check(not clock.start("b", 1), "rejected map left no residue")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, 1, true, false), "state after failed-then-successful configure")


func _test_configure_limits() -> void:
	var full: Dictionary = {}
	for i: int in range(512):
		full["clip_%d" % i] = 0.5
	var clock: Variant = _new_clock()
	_check(clock.configure(full), "512 entries accepted")
	_check(clock.start("clip_0", 1), "first of 512 known")
	_check(clock.start("clip_511", 1), "last of 512 known")

	var unicode_name: String = char(0xE9).repeat(128)
	var ascii_name: String = "b".repeat(128)
	var limits: Dictionary = {"min": 0.000001, "max": 36000.0, "whole": 3, "whole_max": 36000}
	limits[unicode_name] = 1.0
	limits[ascii_name] = 2.0
	var bounds: Variant = _new_clock()
	_check(bounds.configure(limits), "inclusive duration and name length bounds accepted")
	_check(bounds.start("min", 1), "start minimum duration clip")
	_expect(bounds, _state("min", 0.0, 0.0, 0.000001, 1, true, false), "minimum duration stored")
	_check(bounds.start("max", 1), "start maximum duration clip")
	_expect(bounds, _state("max", 0.0, 0.0, 36000.0, 1, true, false), "maximum duration stored")
	_check(bounds.start("whole", 2), "start int-valued clip")
	_expect(bounds, _state("whole", 0.0, 0.0, 3.0, 2, true, false), "int value stored as float")
	_check(bounds.start("whole_max", 1), "start int maximum clip")
	_expect(bounds, _state("whole_max", 0.0, 0.0, 36000.0, 1, true, false), "int maximum stored as float")
	_check(bounds.start(unicode_name, -1), "128 code point non-ascii name accepted")
	_check(bounds.start(ascii_name, -1), "128 character name accepted")
	_check(not bounds.start("b".repeat(127), 1), "prefix of long name is unknown")


func _test_duplicate_configure_and_input_copy() -> void:
	var source: Dictionary = {"a": 2.0, "b": 0.5}
	var clock: Variant = _new_clock()
	_check(clock.configure(source), "configure from host map")
	source["a"] = 100.0
	source["z"] = 1.0
	source.erase("b")
	_check(not clock.configure({"a": 4.0, "c": 1.0}), "duplicate configure rejected")
	_check(not clock.configure(source), "duplicate configure with same map rejected")
	_check(not clock.start("z", 1), "key added to host map is unknown")
	_check(not clock.start("c", 1), "duplicate configure keys not merged")
	_check(clock.start("b", 1), "key erased from host map still configured")
	_expect(clock, _state("b", 0.0, 0.0, 0.5, 1, true, false), "erased key keeps original duration")
	_check(clock.start("a", -1), "start a after host mutation")
	_check(clock.advance(3.0), "advance a after host mutation")
	_expect(clock, _state("a", 3.0, 1.0, 2.0, -1, true, false), "host value change ignored")


func _test_snapshot_isolation() -> void:
	var idle_clock: Variant = _new_clock()
	var idle_snap: Dictionary = idle_clock.snapshot()
	idle_snap["name"] = "x"
	idle_snap["repeats"] = 9
	_expect(idle_clock, _idle(), "mutating unconfigured snapshot does not leak")

	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for snapshot isolation")
	_check(clock.start("a", 2), "start for snapshot isolation")
	_check(clock.advance(1.0), "advance for snapshot isolation")
	var first: Dictionary = clock.snapshot()
	var second: Dictionary = clock.snapshot()
	first["age"] = 99.0
	first["name"] = "hacked"
	first["extra"] = true
	first.erase("completed")
	_check(_snapshot_matches(second, _state("a", 1.0, 1.0, 2.0, 2, true, false), false), "snapshots are distinct dictionaries")
	_expect(clock, _state("a", 1.0, 1.0, 2.0, 2, true, false), "mutating snapshot does not leak")
	_check(clock.advance(1.0), "advance after snapshot mutation")
	_expect(clock, _state("a", 2.0, 0.0, 2.0, 2, true, false), "module continues normally")


func _test_start_validation() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for start validation")
	_check(not clock.start("b", 1), "unknown clip rejected")
	_check(not clock.start("A", 1), "case-sensitive name rejected")
	_check(not clock.start("", 1), "empty name rejected")
	_check(not clock.start("a ", 1), "name with trailing space rejected")
	_check(not clock.start("a", 0), "zero repeats rejected")
	_check(not clock.start("a", -2), "repeats -2 rejected")
	_check(not clock.start("a", -1000), "large negative repeats rejected")
	_check(not clock.start("a", 1000001), "repeats above limit rejected")
	_expect(clock, _idle(), "rejected starts leave idle state")
	_check(clock.start("a", 1000000), "repeats at limit accepted")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, 1000000, true, false), "repeat limit request active")
	_check(clock.start("a", 1), "single repeat accepted")
	_check(clock.start("a", -1), "infinite repeats accepted")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, -1, true, false), "infinite request active")


func _test_advance_validation() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for advance validation")
	for bad: Variant in _bad_deltas():
		_check(not clock.advance(bad), "idle rejects delta %s" % [bad])
		_expect(clock, _idle(), "idle unchanged after delta %s" % [bad])
	_check(clock.advance(0.0), "idle accepts zero delta")
	_check(clock.advance(-0.0), "idle accepts negative zero delta")
	_check(clock.advance(36000.0), "idle accepts maximum delta")
	_check(clock.advance(1), "idle accepts int delta")
	_expect(clock, _idle(), "idle unchanged by valid deltas")

	_check(clock.start("a", -1), "start for active delta checks")
	_check(clock.advance(0.0), "active zero delta accepted")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, -1, true, false), "zero delta at start changes nothing")
	_check(clock.advance(0.5), "active advance 0.5")
	_check(clock.advance(0.0), "active zero delta mid clip")
	_check(clock.advance(-0.0), "active negative zero delta mid clip")
	_expect(clock, _state("a", 0.5, 0.5, 2.0, -1, true, false), "zero deltas change nothing mid clip")
	for bad: Variant in _bad_deltas():
		_check(not clock.advance(bad), "active rejects delta %s" % [bad])
	_expect(clock, _state("a", 0.5, 0.5, 2.0, -1, true, false), "active state unchanged by invalid deltas")
	_check(clock.advance(1), "active accepts int delta")
	_expect(clock, _state("a", 1.5, 1.5, 2.0, -1, true, false), "int delta converted")
	_check(clock.advance(36000.0), "active accepts maximum delta")
	_expect(clock, _state("a", 36001.5, 1.5, 2.0, -1, true, false), "maximum delta applied")


func _test_example_table() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for table")
	_check(clock.start("a", 2), "table start a 2")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, 2, true, false), "table row start")
	_check(clock.advance(2.0), "table advance 2")
	_expect(clock, _state("a", 2.0, 0.0, 2.0, 2, true, false), "table row repeat boundary position 0")
	_check(clock.advance(1.0), "table advance 1")
	_expect(clock, _state("a", 3.0, 1.0, 2.0, 2, true, false), "table row mid second repeat")
	_check(clock.advance(9.0), "table advance 9")
	_expect(clock, _state("a", 4.0, 2.0, 2.0, 2, false, true), "table row clamped completion")
	_check(clock.advance(0.5), "table advance 0.5 after completion")
	_expect(clock, _state("a", 4.0, 2.0, 2.0, 2, false, true), "table row completion retained")
	_check(clock.start("a", -1), "table start a infinite")
	_check(clock.advance(5.0), "table advance 5")
	_expect(clock, _state("a", 5.0, 1.0, 2.0, -1, true, false), "table row infinite loop")
	_check(clock.stop(), "table stop")
	_expect(clock, _idle(), "table row stop")


func _test_finite_single_repeat() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for single repeat")
	_check(clock.start("a", 1), "start single repeat")
	_check(clock.advance(1.5), "advance 1.5 of single repeat")
	_expect(clock, _state("a", 1.5, 1.5, 2.0, 1, true, false), "single repeat mid clip")
	_check(clock.advance(0.5), "advance exactly to end")
	_expect(clock, _state("a", 2.0, 2.0, 2.0, 1, false, true), "exact end completes with position duration")
	_check(clock.start("a", 1), "restart single repeat")
	_check(clock.advance(2.0), "single step exactly to end")
	_expect(clock, _state("a", 2.0, 2.0, 2.0, 1, false, true), "single exact step completes")


func _test_finite_multiple_repeats_and_clamp() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"h": 0.5}), "configure for multiple repeats")
	_check(clock.start("h", 3), "start h 3")
	_check(clock.advance(0.5), "advance one repeat")
	_expect(clock, _state("h", 0.5, 0.0, 0.5, 3, true, false), "first internal boundary position 0")
	_check(clock.advance(0.25), "advance quarter")
	_expect(clock, _state("h", 0.75, 0.25, 0.5, 3, true, false), "second repeat mid clip")
	_check(clock.advance(0.25), "advance to second boundary")
	_expect(clock, _state("h", 1.0, 0.0, 0.5, 3, true, false), "second internal boundary position 0")
	_check(clock.advance(0.5), "advance to final end")
	_expect(clock, _state("h", 1.5, 0.5, 0.5, 3, false, true), "multiple repeats complete exactly")
	_check(clock.start("h", 3), "restart for large clamp")
	_check(clock.advance(36000.0), "large step accepted")
	_expect(clock, _state("h", 1.5, 0.5, 0.5, 3, false, true), "large step clamps to total")
	_check(clock.start("h", 3), "restart for overshoot")
	_check(clock.advance(1.25), "advance near end")
	_check(clock.advance(1.0), "overshoot from near end")
	_expect(clock, _state("h", 1.5, 0.5, 0.5, 3, false, true), "overshoot clamps to total")


func _test_terminal_retention() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for terminal retention")
	_check(clock.start("a", 2), "start for terminal retention")
	_check(clock.advance(4.0), "advance to terminal")
	var terminal: Dictionary = _state("a", 4.0, 2.0, 2.0, 2, false, true)
	_expect(clock, terminal, "terminal reached")
	for valid: Variant in [0.0, -0.0, 10.0, 36000.0, 1]:
		_check(clock.advance(valid), "terminal accepts delta %s" % [valid])
		_expect(clock, terminal, "terminal retained after delta %s" % [valid])
	for bad: Variant in _bad_deltas():
		_check(not clock.advance(bad), "terminal rejects delta %s" % [bad])
		_expect(clock, terminal, "terminal retained after invalid delta %s" % [bad])
	_check(not clock.start("missing", 1), "terminal rejects unknown start")
	_check(not clock.start("a", 0), "terminal rejects zero repeats start")
	_check(not clock.start("a", 1000001), "terminal rejects oversize repeats start")
	_expect(clock, terminal, "terminal retained after invalid starts")


func _test_restart() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0, "b": 0.5}), "configure for restart")
	_check(clock.start("a", 3), "start a 3")
	_check(clock.advance(1.5), "advance before restart")
	_check(clock.start("a", 3), "restart same request while playing")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, 3, true, false), "same request restart resets")
	_check(clock.advance(6.0), "advance to completion")
	_expect(clock, _state("a", 6.0, 2.0, 2.0, 3, false, true), "completed before restart")
	_check(clock.start("a", 3), "restart same request after completion")
	_expect(clock, _state("a", 0.0, 0.0, 2.0, 3, true, false), "restart after completion resets")
	_check(clock.advance(1.0), "advance before switching clip")
	_check(clock.start("b", -1), "switch clip while playing")
	_expect(clock, _state("b", 0.0, 0.0, 0.5, -1, true, false), "switched clip reset")
	_check(clock.advance(0.75), "advance switched clip")
	_expect(clock, _state("b", 0.75, 0.25, 0.5, -1, true, false), "switched clip loops")
	_check(clock.start("a", 1), "switch back to finite")
	_check(clock.advance(2.0), "complete finite")
	_check(clock.start("b", 2), "start other clip after completion")
	_expect(clock, _state("b", 0.0, 0.0, 0.5, 2, true, false), "other clip after completion")


func _test_stop() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for stop")
	_check(clock.stop(), "stop while idle after configure")
	_check(clock.start("a", 2), "start for stop")
	_check(clock.advance(1.0), "advance before stop")
	_check(clock.stop(), "stop while playing")
	_expect(clock, _idle(), "stop while playing returns to idle")
	_check(clock.stop(), "repeated stop succeeds")
	_expect(clock, _idle(), "repeated stop stays idle")
	_check(clock.advance(1.0), "advance while idle after stop")
	_check(not clock.advance(NAN), "NaN still rejected after stop")
	_expect(clock, _idle(), "idle unchanged after stop and advances")
	_check(clock.start("a", 1), "start after stop")
	_check(clock.advance(2.0), "complete after stop")
	_expect(clock, _state("a", 2.0, 2.0, 2.0, 1, false, true), "completed before stop")
	_check(clock.stop(), "stop after completion")
	_expect(clock, _idle(), "stop after completion returns to idle")
	_check(clock.start("a", -1), "durations preserved after stop")
	_check(clock.advance(3.0), "advance after stops")
	_expect(clock, _state("a", 3.0, 1.0, 2.0, -1, true, false), "configured duration retained after stop")


func _test_invalid_calls_keep_running_request() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"a": 2.0}), "configure for running retention")
	_check(clock.start("a", -1), "start infinite for retention")
	_check(clock.advance(1.5), "advance infinite for retention")
	var running: Dictionary = _state("a", 1.5, 1.5, 2.0, -1, true, false)
	var bad_starts: Array = [["missing", 1], ["A", 1], ["a", 0], ["a", -2], ["a", 1000001]]
	for request: Array in bad_starts:
		_check(not clock.start(request[0], request[1]), "running rejects start %s" % [request])
		_expect(clock, running, "running retained after start %s" % [request])
	for bad: Variant in _bad_deltas():
		_check(not clock.advance(bad), "running rejects delta %s" % [bad])
		_expect(clock, running, "running retained after delta %s" % [bad])
	_check(clock.advance(1.0), "running continues after invalid calls")
	_expect(clock, _state("a", 2.5, 0.5, 2.0, -1, true, false), "infinite request continued")

	_check(clock.start("a", 3), "start finite for retention")
	_check(clock.advance(1.0), "advance finite for retention")
	var finite_running: Dictionary = _state("a", 1.0, 1.0, 2.0, 3, true, false)
	_check(not clock.start("missing", 3), "finite running rejects unknown")
	_check(not clock.advance(INF), "finite running rejects infinite delta")
	_check(not clock.advance(-0.5), "finite running rejects negative delta")
	_expect(clock, finite_running, "finite running retained")
	_check(clock.advance(1.0), "finite running continues")
	_expect(clock, _state("a", 2.0, 0.0, 2.0, 3, true, false), "finite request continued")


func _test_large_values() -> void:
	var clock: Variant = _new_clock()
	_check(clock.configure({"long": 36000.0, "tiny": 0.000001, "two": 2.0}), "configure for large values")
	_check(clock.start("long", 1000000), "start maximum total request")
	var all_ok: bool = true
	for i: int in range(3):
		all_ok = bool(clock.advance(36000.0)) and all_ok
	_check(all_ok, "maximum deltas accepted on maximum total")
	_expect(clock, _state("long", 108000.0, 0.0, 36000.0, 1000000, true, false), "maximum total still playing")

	_check(clock.start("long", 2), "start long 2")
	_check(clock.advance(36000.0), "long first boundary")
	_expect(clock, _state("long", 36000.0, 0.0, 36000.0, 2, true, false), "long internal boundary")
	_check(clock.advance(35999.5), "long near end")
	_expect(clock, _state("long", 71999.5, 35999.5, 36000.0, 2, true, false), "long just before end")
	_check(clock.advance(0.5), "long exact end")
	_expect(clock, _state("long", 72000.0, 36000.0, 36000.0, 2, false, true), "long completes exactly")

	_check(clock.start("tiny", 1000000), "start tiny maximum repeats")
	_check(clock.advance(36000.0), "tiny large step")
	var tiny_total: float = 0.000001 * 1000000.0
	_expect(clock, _state("tiny", tiny_total, 0.000001, 0.000001, 1000000, false, true), "tiny clamps to computed total")

	_check(clock.start("tiny", -1), "start tiny infinite")
	_check(clock.advance(36000.0), "tiny infinite large step")
	var tiny_snap: Dictionary = clock.snapshot()
	var tiny_pos: float = tiny_snap["position"]
	_check(tiny_snap["age"] == 36000.0 and tiny_pos >= 0.0 and tiny_pos < 0.000001 and tiny_snap["playing"], "tiny infinite position within one duration")

	_check(clock.start("two", -1), "start infinite for cumulative age")
	all_ok = true
	for i: int in range(20):
		all_ok = bool(clock.advance(36000.0)) and all_ok
	_check(all_ok, "twenty maximum deltas accepted on infinite request")
	_expect(clock, _state("two", 720000.0, 0.0, 2.0, -1, true, false), "infinite age cumulative far below 1e12 cap")


func _test_nonbinary_timing() -> void:
	var stepped: Variant = _new_clock()
	var single: Variant = _new_clock()
	_check(stepped.configure({"n": 0.3}), "configure stepped nonbinary")
	_check(single.configure({"n": 0.3}), "configure single nonbinary")
	_check(stepped.start("n", -1), "start stepped nonbinary")
	_check(single.start("n", -1), "start single nonbinary")
	var all_ok: bool = true
	for i: int in range(10):
		all_ok = bool(stepped.advance(0.1)) and all_ok
	_check(all_ok, "ten nonbinary steps accepted")
	_check(single.advance(1.0), "single nonbinary step accepted")
	var expected: Dictionary = _state("n", 1.0, 0.1, 0.3, -1, true, false)
	_expect_close(stepped, expected, "stepped nonbinary within tolerance")
	_expect_close(single, expected, "single nonbinary within tolerance")
	var a: Dictionary = stepped.snapshot()
	var b: Dictionary = single.snapshot()
	_check(_close(a["position"], b["position"]) and _close(a["age"], b["age"]), "partitions agree away from boundaries")

	var finite: Variant = _new_clock()
	_check(finite.configure({"t": 0.1}), "configure finite nonbinary")
	_check(finite.start("t", 3), "start finite nonbinary")
	_check(finite.advance(0.25), "finite nonbinary advance 0.25")
	_expect_close(finite, _state("t", 0.25, 0.05, 0.1, 3, true, false), "finite nonbinary mid clip")
	_check(finite.advance(0.04), "finite nonbinary advance 0.04")
	_expect_close(finite, _state("t", 0.29, 0.09, 0.1, 3, true, false), "finite nonbinary near end")
	_check(finite.advance(1.0), "finite nonbinary overshoot")
	_expect(finite, _state("t", 0.1 * 3.0, 0.1, 0.1, 3, false, true), "finite nonbinary completes exactly at computed total")


func _test_independent_instances() -> void:
	var first: Variant = _new_clock()
	var second: Variant = _new_clock()
	var third: Variant = _new_clock()
	_check(first.configure({"a": 2.0}), "configure first instance")
	_check(second.configure({"a": 0.5, "b": 1.0}), "configure second instance")
	_check(not first.start("b", 1), "first does not see second keys")
	_check(first.start("a", -1), "start first")
	_check(second.start("b", 1), "start second")
	_check(first.advance(3.0), "advance first")
	_expect(first, _state("a", 3.0, 1.0, 2.0, -1, true, false), "first advanced")
	_expect(second, _state("b", 0.0, 0.0, 1.0, 1, true, false), "second unaffected")
	_check(second.advance(5.0), "advance second")
	_expect(second, _state("b", 1.0, 1.0, 1.0, 1, false, true), "second completed")
	_expect(first, _state("a", 3.0, 1.0, 2.0, -1, true, false), "first unaffected by second")
	_expect(third, _idle(), "third remains unconfigured idle")
	_check(not third.start("a", 1), "third start rejected")
	_check(not third.stop(), "third stop rejected")
	_check(first.stop(), "stop first")
	_expect(second, _state("b", 1.0, 1.0, 1.0, 1, false, true), "second unaffected by first stop")
