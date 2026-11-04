extends SceneTree

var passed := 0
var failed: Array[String] = []
var natives_seen: Array = []
var host := ""
var tested_vms: Array[StoryVm] = []
var bridge := StoryNatives.new()
var bridge_seen: Array[int] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	call_deferred("run_tests")


func check(ok: bool, name: String) -> void:
	if ok:
		passed += 1
		print("PASS ", name)
	else:
		failed.append(name)
		printerr("FAIL ", name)


func inst(op: int, mode := 0, type := 1, bits := 0) -> Array:
	return [op, mode, type, bits, 1]


func input_float(value: float) -> int:
	return int(StoryVm.number(value)["bits"])


func fixture(instructions: Array, definitions := {}) -> ChlReader:
	var source := ChlReader.new()
	source.globals.assign(["zero", "a", "b", "c", "d", "e"])
	source.instruction_count = instructions.size()
	source.code.resize(instructions.size() * 20)
	for i in instructions.size():
		for part in 5:
			source.code.encode_u32(i * 20 + part * 4, int(instructions[i][part]) & 0xffffffff)
	if definitions.is_empty():
		definitions = {"main":{"id":1,"address":0,"params":0,"variables":0,"variable_offset":5}}
	for name in definitions:
		var entry: Dictionary = definitions[name].duplicate(true)
		entry["name"] = name
		source.scripts[name] = entry
		source.scripts_by_id[entry["id"]] = entry
	return source


func execute_all(vm: StoryVm, limit := 100) -> bool:
	for ignored in limit:
		if not vm.tick():
			return false
		if vm.tasks.is_empty():
			return true
	return false


func prepare(vm: StoryVm, source: ChlReader) -> bool:
	tested_vms.append(vm)
	return vm.configure(source)


func run_tests() -> void:
	var world := TestTerrain.new()
	bridge.configure(world)
	var args := [StoryVm.number(11, StoryVm.VECTOR),StoryVm.number(200, StoryVm.VECTOR),StoryVm.number(13, StoryVm.VECTOR)]
	var native := bridge.invoke(151, args, {})
	check(native.get("ok", false) and is_equal_approx(StoryVm.as_float(native["push"][0]), 24.0), "land-height native reads original map axes through game terrain")
	var object := Node.new()
	var handle := bridge.register_object(object)
	native = bridge.invoke(256, [StoryVm.integer(handle, StoryVm.OBJECT)], {})
	check(native.get("ok", false) and StoryVm.as_int(native["push"][0]) == 1, "registered game object is valid")
	object.free()
	native = bridge.invoke(256, [StoryVm.integer(handle, StoryVm.OBJECT)], {})
	check(native.get("ok", false) and StoryVm.as_int(native["push"][0]) == 0, "freed game object is invalid")
	native = bridge.invoke(397, [StoryVm.number(9.0)], {})
	check(native.get("ok", false) and is_equal_approx(StoryVm.as_float(native["push"][0]), 3.0), "square-root native returns real root")
	native = bridge.invoke(397, [StoryVm.number(-9.0)], {})
	check(native.get("ok", false) and is_equal_approx(StoryVm.as_float(native["push"][0]), 0.0), "square-root native matches original negative-input behaviour")
	check(StoryVm.as_int(bridge.invoke(460, [], {})["push"][0]) == 0 and StoryVm.as_int(bridge.invoke(461, [], {})["push"][0]) == 0, "original tutorial and creature training are enabled")
	check(StoryVm.as_int(bridge.invoke(462, [], {})["push"][0]) == 0 and StoryVm.as_int(bridge.invoke(463, [], {})["push"][0]) == 0, "new profile does not fabricate a previous creature")
	bridge.keep_old_creature = true
	bridge.profile_has_creature = true
	check(StoryVm.as_int(bridge.invoke(462, [], {})["push"][0]) == 1 and StoryVm.as_int(bridge.invoke(463, [], {})["push"][0]) == 1, "existing profile flags are reflected accurately")
	bridge.keep_old_creature = false
	bridge.profile_has_creature = false
	var marker := Node3D.new()
	marker.position = Vector3(5, 2, -7)
	var marker_id := bridge.register_object(marker)
	native = bridge.invoke(23, [StoryVm.integer(marker_id, StoryVm.OBJECT)], {})
	check(native.get("ok", false) and native["push"].size() == 3 and StoryVm.as_float(native["push"][0]) == 5.0 and StoryVm.as_float(native["push"][1]) == 2.0 and StoryVm.as_float(native["push"][2]) == 7.0, "object position uses original X, height, and island Z")
	var parent := Node3D.new()
	parent.position = Vector3(100, 0, -10)
	root.add_child(parent)
	parent.add_child(marker)
	native = bridge.invoke(23, [StoryVm.integer(marker_id, StoryVm.OBJECT)], {})
	check(native.get("ok", false) and StoryVm.as_float(native["push"][0]) == 105.0 and StoryVm.as_float(native["push"][2]) == 17.0, "object position includes parent world transform")
	parent.free()
	native = bridge.invoke(23, [StoryVm.integer(marker_id, StoryVm.OBJECT)], {})
	check(native.get("ok", false) and StoryVm.as_float(native["push"][0]) == 0.0 and StoryVm.as_float(native["push"][1]) == 0.0 and StoryVm.as_float(native["push"][2]) == 0.0, "invalid object position returns original zero vector")
	native = bridge.invoke(25, [StoryVm.number(1, StoryVm.VECTOR), StoryVm.number(2, StoryVm.VECTOR), StoryVm.number(3, StoryVm.VECTOR), StoryVm.number(4, StoryVm.VECTOR), StoryVm.number(6, StoryVm.VECTOR), StoryVm.number(3, StoryVm.VECTOR)], {})
	check(native.get("ok", false) and is_equal_approx(StoryVm.as_float(native["push"][0]), 5.0), "distance calculates between complete original coordinate vectors")
	native = bridge.invoke(28, [StoryVm.number(3.5), StoryVm.number(3.5)], {})
	check(native.get("ok", false) and is_equal_approx(StoryVm.as_float(native["push"][0]), 3.5), "random range with equal bounds is exact")
	var in_range := true
	for ignored in 50:
		native = bridge.invoke(28, [StoryVm.number(2), StoryVm.number(5)], {})
		var sample: float = StoryVm.as_float(native["push"][0])
		in_range = in_range and sample >= 2.0 and sample <= 5.0
	check(in_range, "random values remain within the original argument bounds")
	var feature := Node3D.new()
	feature.position = Vector3(10.0, 4.0, -20.0)
	var feature_id := bridge.register_object(feature, 3)
	var search := [StoryVm.integer(3), StoryVm.integer(5000), StoryVm.number(10, StoryVm.VECTOR), StoryVm.number(4, StoryVm.VECTOR), StoryVm.number(20, StoryVm.VECTOR), StoryVm.integer(0, StoryVm.BOOL)]
	native = bridge.invoke(26, search, {})
	check(native.get("ok", false) and StoryVm.as_int(native["push"][0]) == feature_id, "exact original feature lookup returns the registered landmark")
	var synthetic_home := Node3D.new()
	synthetic_home.position = feature.position
	var synthetic_home_id := bridge.register_object(synthetic_home, 2)
	var home_search := search.duplicate(true)
	home_search[0] = StoryVm.integer(2)
	check(StoryVm.as_int(bridge.invoke(26, home_search, {})["push"][0]) == synthetic_home_id and StoryVm.as_int(bridge.invoke(26, search, {})["push"][0]) == feature_id, "abode and feature at the same position stay distinct")
	synthetic_home.free()
	var duplicate := Node3D.new()
	duplicate.position = feature.position
	bridge.register_object(duplicate, 3)
	check(not bridge.invoke(26, search, {}).get("ok", false), "ambiguous feature lookup blocks instead of guessing")
	duplicate.free()
	var excluding := search.duplicate(true)
	excluding[5] = StoryVm.integer(1, StoryVm.BOOL)
	check(not bridge.invoke(26, excluding, {}).get("ok", false), "unsupported excluding-scripted lookup blocks")
	feature.free()
	check(not bridge.invoke(26, search, {}).get("ok", false), "missing feature lookup blocks instead of fabricating an object")
	var create := [StoryVm.integer(1), StoryVm.integer(0), StoryVm.number(8, StoryVm.VECTOR), StoryVm.number(9, StoryVm.VECTOR), StoryVm.number(10, StoryVm.VECTOR)]
	native = bridge.invoke(27, create, {})
	var created_id: int = StoryVm.as_int(native["push"][0]) if native.get("ok", false) else 0
	var created_position := bridge.invoke(23, [StoryVm.integer(created_id, StoryVm.OBJECT)], {})
	check(created_id > 0 and StoryVm.as_float(created_position["push"][0]) == 8.0 and StoryVm.as_float(created_position["push"][1]) == 9.0 and StoryVm.as_float(created_position["push"][2]) == 10.0, "created original story marker preserves its three coordinates")
	var wrong_create := create.duplicate(true)
	wrong_create[0] = StoryVm.integer(3)
	check(not bridge.invoke(27, wrong_create, {}).get("ok", false), "unknown original object creation blocks")
	bridge.clear_created()
	check(StoryVm.as_int(bridge.invoke(256, [StoryVm.integer(created_id, StoryVm.OBJECT)], {})["push"][0]) == 0, "created markers release their handles during cleanup")
	check(not bridge.invoke(254, [StoryVm.integer(1),StoryVm.number(0)], {}).get("ok", false), "unknown influence semantics remain blocked")
	world = null
	var vm := StoryVm.new()
	var source := fixture([
		inst(2,0,1,10),inst(2,0,1,3),inst(6,0,1),
		inst(2,0,1,2),inst(8,0,1),inst(2,0,1,3),inst(9,0,1),
		inst(2,0,1,3),inst(10,0,1),inst(3,1,1,1),inst(0)])
	check(prepare(vm, source), "configure synthetic story program")
	var id := vm.start("main")
	check(id > 0 and execute_all(vm), "arithmetic script completes")
	check(StoryVm.as_int(vm.variables[1]) == 1, "integer operations preserve left/right operand order")

	vm = StoryVm.new()
	source = fixture([inst(2,0,1,-7),inst(2,0,1,3),inst(10,0,1),inst(3,1,1,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == -1, "signed remainder follows truncation toward zero")
	vm = StoryVm.new()
	source = fixture([inst(2,0,1,2147483647),inst(2,0,1,2147483647),inst(8,0,1),inst(3,1,1,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 1, "integer multiplication preserves 32-bit wraparound")

	vm = StoryVm.new()
	source = fixture([
		inst(2,0,2,input_float(1.5)),inst(2,0,2,input_float(2.0)),inst(8,0,2),inst(3,1,2,1),
		inst(2,0,2,input_float(1)),inst(2,0,2,input_float(2)),inst(2,0,2,input_float(3)),
		inst(2,0,2,input_float(4)),inst(2,0,2,input_float(5)),inst(2,0,2,input_float(6)),inst(4,0,3),
		inst(3,1,3,4),inst(3,1,3,3),inst(3,1,3,2),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and is_equal_approx(StoryVm.as_float(vm.variables[1]), 3.0), "floating point multiplication")
	check(is_equal_approx(StoryVm.as_float(vm.variables[2]),5.0) and is_equal_approx(StoryVm.as_float(vm.variables[3]),7.0) and is_equal_approx(StoryVm.as_float(vm.variables[4]),9.0), "vector components add in their original order")

	vm = StoryVm.new()
	source = fixture([
		inst(2,0,2,input_float(2)),inst(2,0,3,input_float(3)),inst(2,0,3,input_float(4)),inst(2,0,3,input_float(5)),inst(8,0,3),
		inst(7,0,3),inst(2,0,2,input_float(2)),inst(9,0,3),inst(3,1,3,3),inst(3,1,3,2),inst(3,1,3,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_float(vm.variables[1]) == -3 and StoryVm.as_float(vm.variables[2]) == -4 and StoryVm.as_float(vm.variables[3]) == -5, "vector scale, negate and division preserve component order")

	vm = StoryVm.new()
	source = fixture([inst(2,0,2,input_float(1.0)),inst(23,0,1),inst(3,1,1,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 1065353216, "cast reinterprets original bits instead of numeric conversion")

	vm = StoryVm.new()
	source = fixture([
		inst(2,0,1,0),inst(11),inst(2,0,6,1),inst(12),inst(2,0,6,0),inst(13),inst(3,1,6,1),
		inst(2,0,1,5),inst(2,0,1,3),inst(18,0,1),inst(3,1,6,2),
		inst(2,0,1,5),inst(2,0,1,3),inst(19,0,1),inst(3,1,6,3),
		inst(2,0,4,44),inst(2,0,4,44),inst(14,0,4),inst(3,1,6,4),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 1, "logical NOT, AND, OR")
	check(StoryVm.as_int(vm.variables[2]) == 1 and StoryVm.as_int(vm.variables[3]) == 0 and StoryVm.as_int(vm.variables[4]) == 1, "comparison order and object equality")
	vm = StoryVm.new()
	source = fixture([
		inst(30),inst(2,0,1,5),inst(2,0,1,3),inst(15,0,1),inst(3,1,6,1),
		inst(2,0,1,3),inst(2,0,1,3),inst(16,0,1),inst(3,1,6,2),
		inst(2,0,1,2),inst(2,0,1,3),inst(17,0,1),inst(3,1,6,3),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 1 and StoryVm.as_int(vm.variables[2]) == 1 and StoryVm.as_int(vm.variables[3]) == 1, "not-equal and inclusive comparisons")

	vm = StoryVm.new()
	source = fixture([
		inst(2,0,3,input_float(1)),inst(2,0,3,input_float(2)),inst(2,0,3,input_float(3)),
		inst(2,0,3,input_float(1)),inst(2,0,3,input_float(2)),inst(2,0,3,input_float(3)),inst(14,0,3),inst(3,1,6,1),
		inst(2,0,1,13),inst(3,1,1,6),inst(2,1,1,6),inst(3,1,1,2),inst(23,1,1,6),inst(2,1,2,6),inst(3,1,2,3),inst(0)],
		{"main":{"id":1,"address":0,"params":0,"variables":1,"variable_offset":5}})
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 1, "vector equality consumes two whole vectors")
	check(StoryVm.as_int(vm.variables[2]) == 13 and StoryVm.as_float(vm.variables[3]) == 0.0, "local variables and clear preserve global address mapping")

	vm = StoryVm.new()
	source = fixture([inst(2,0,1,10),inst(2,0,1,20),inst(29,1,2,2),inst(3,1,1,1),inst(29,0,1),inst(3,1,1,2),inst(3,1,1,3),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 10 and StoryVm.as_int(vm.variables[2]) == 10 and StoryVm.as_int(vm.variables[3]) == 20, "copy-from and swap preserve stack order")
	vm = StoryVm.new()
	source = fixture([inst(2,0,1,4),inst(2,0,1,5),inst(29,0,2,2),inst(3,1,1,1),inst(3,1,1,2),inst(3,1,1,3),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 5 and StoryVm.as_int(vm.variables[2]) == 4 and StoryVm.as_int(vm.variables[3]) == 5, "copy-to inserts an independent stack value")

	vm = StoryVm.new()
	source = fixture([inst(2,0,6,0),inst(1,1,1,4),inst(2,0,1,99),inst(3,1,1,1),inst(2,0,1,8),inst(3,1,1,2),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_float(vm.variables[1]) == 0 and StoryVm.as_int(vm.variables[2]) == 8, "false condition takes forward jump")

	vm = StoryVm.new()
	source = fixture([inst(20,0,1,2),inst(0),inst(2,0,1,7),inst(3,1,1,1),inst(0)])
	prepare(vm, source)
	id = vm.start("main")
	check(vm.tick() and vm.tasks.has(id) and int(vm.tasks[id]["pc"]) == 2, "backward-mode jump yields until next tick")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 7, "yielded task resumes at jump target")

	vm = StoryVm.new()
	source = fixture([
		inst(22,0,1,7),inst(25,1),inst(2,0,1,42),inst(3,1,1,1),inst(25,0),inst(0),inst(30),
		inst(2,0,6,0),inst(1,1,1,10),inst(28),inst(27)])
	prepare(vm, source)
	id = vm.start("main")
	check(vm.tick() and vm.tasks.has(id) and vm.tasks[id]["handlers"].size() == 1, "story task registers and yields with handler")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 42, "inactive exception resumes original story")
	vm = StoryVm.new()
	source = fixture([inst(22,0,1,6),inst(25,1),inst(2,0,1,12),inst(3,1,1,1),inst(25,0),inst(0),inst(26)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 12, "handler return resumes original instruction")

	vm = StoryVm.new()
	source = fixture([
		inst(22,0,1,7),inst(25,1),inst(0),inst(30),inst(30),inst(30),inst(30),
		inst(2,0,6,1),inst(1,1,1,12),inst(2,0,1,99),inst(3,1,1,1),inst(28),
		inst(2,0,1,8),inst(3,1,1,2),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 99 and StoryVm.as_int(vm.variables[2]) == 8, "triggered handler breaks into continuation")

	vm = StoryVm.new()
	source = fixture([inst(2,0,2,input_float(0.2)),inst(21),inst(1,0,1,0),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and vm.ticks >= 4, "script timer waits across ticks")

	vm = StoryVm.new()
	source = fixture([
		inst(24,0,1,2),inst(2,0,1,9),inst(3,1,1,1),inst(0),
		inst(2,0,1,8),inst(3,1,1,2),inst(0)],
		{"main":{"id":1,"address":0,"params":0,"variables":0,"variable_offset":5},"child":{"id":2,"address":4,"params":0,"variables":0,"variable_offset":5}})
	prepare(vm, source)
	id = vm.start("main")
	check(vm.tick() and int(vm.tasks[id]["waiting"]) != 0 and StoryVm.as_float(vm.variables[1]) == 0.0, "synchronous script waits for child")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 9 and StoryVm.as_int(vm.variables[2]) == 8, "parent resumes after child completes")

	vm = StoryVm.new()
	source = fixture([
		inst(2,0,1,10),inst(2,0,1,20),inst(24,0,1,2),inst(0),inst(3,1,1,1),inst(3,1,1,2),inst(0)],
		{"main":{"id":1,"address":0,"params":0,"variables":0,"variable_offset":5},"child":{"id":2,"address":4,"params":2,"variables":0,"variable_offset":5}})
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 10 and StoryVm.as_int(vm.variables[2]) == 20, "script call passes arguments in original order")
	vm = StoryVm.new()
	source = fixture([
		inst(24,1,1,2),inst(2,0,1,3),inst(3,1,1,1),inst(0),
		inst(2,0,1,4),inst(3,1,1,2),inst(0)],
		{"main":{"id":1,"address":0,"params":0,"variables":0,"variable_offset":5},"child":{"id":2,"address":4,"params":0,"variables":0,"variable_offset":5}})
	prepare(vm, source)
	vm.start("main")
	check(execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 3 and StoryVm.as_int(vm.variables[2]) == 4, "asynchronous child runs alongside parent")

	vm = StoryVm.new()
	source = fixture([inst(2,0,1,7),inst(5,0,0,99),inst(3,1,1,1),inst(0)])
	prepare(vm, source)
	id = vm.start("main")
	check(not vm.tick() and vm.error.get("kind") == "unbound_native" and vm.error["detail"]["native_id"] == 99, "unbound world function blocks explicitly")
	check(vm.tasks[id]["pc"] == 1 and vm.tasks[id]["stack"].size() == 1 and StoryVm.as_int(vm.tasks[id]["stack"][0]) == 7, "blocked native leaves instruction and inputs intact")
	check(vm.resume_unbound(_fixture_native) and execute_all(vm) and StoryVm.as_int(vm.variables[1]) == 11, "bound native resumes safely")

	vm = StoryVm.new()
	source = fixture([inst(3,0,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(not vm.tick() and vm.error.get("kind") == "stack_underflow", "stack underflow is reported")
	vm = StoryVm.new()
	source = fixture([inst(2,0,1,1),inst(2,0,1,0),inst(9,0,1),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(not vm.tick() and vm.error.get("kind") == "divide_by_zero", "division by zero is reported")
	vm = StoryVm.new()
	source = fixture([inst(99),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(not vm.tick() and vm.error.get("kind") == "unsupported_opcode", "unknown instructions do not silently succeed")
	vm = StoryVm.new()
	source = fixture([inst(2,0,6,0),inst(1,2,1,0),inst(0)])
	prepare(vm, source)
	vm.start("main")
	check(not vm.tick() and vm.error.get("kind") == "unsupported_mode", "invalid branch mode is rejected")

	if host == "":
		check(false, "original installation supplied")
	else:
		var original := ChlReader.new()
		check(original.load_file(host.path_join("Scripts/Quests/challenge.chl")), "load original campaign bytecode")
		check(original.code.size() == 20 * original.instruction_count and original.scripts_by_id.has(113), "retain original instructions and script identifiers in memory")
		vm = StoryVm.new()
		check(prepare(vm, original), "configure VM for original campaign")
		id = vm.start("SetupLand1")
		var reached_native := false
		for ignored in 10:
			if not vm.tick():
				reached_native = true
				break
		check(reached_native and vm.error.get("kind") == "unbound_native" and vm.error.get("detail",{}).get("native_id") == 254, "original first-island setup executes until unbound influence operation")
		if reached_native and vm.error.get("kind") == "unbound_native":
			var stack_before: Array = vm.tasks[id]["stack"].duplicate(true)
			check(stack_before.size() == 2, "original influence operation receives two operands")
			check(vm.resume_unbound(_observe_first_native), "resume original setup with test-only observation")
			for ignored in 10:
				if not vm.tick(): break
			check(vm.error.get("kind") == "unbound_native" and vm.error.get("detail",{}).get("native_id") == 460, "original setup continues to tutorial decision and blocks")
			check(natives_seen == [254,460], "original setup native sequence is recorded without game side effects")
			check(vm.resume_unbound(_bridge_after_observed_influence), "resume tutorial query through verified bridge")
			for ignored in 50:
				if not vm.tick(): break
			check(vm.error.get("kind") == "unbound_native" and bridge_seen.has(460), "original setup proceeds beyond tutorial query until next unbound operation")
			print("ORIGINAL NEXT NATIVE ", vm.error.get("detail",{}).get("native_id",-1), " after ", vm.executed, " instructions")
			if vm.tasks.has(id):
				print("ORIGINAL NATIVE STACK ", vm.tasks[id]["stack"])
			if vm.error.get("detail",{}).get("native_id") == 26:
				var island := IslandScript.new()
				var read_island := island.load_file(host.path_join("Scripts/Land1.txt"))
				var cave := Node3D.new()
				var home := Node3D.new()
				var cave_found := false
				var home_found := false
				for command in island.all("CREATE_ANIMATED_STATIC"):
					var a: PackedStringArray = command["args"]
					var pos := IslandScript.pos(a[0])
					if a[1] == "Piper Cave Entrance" and pos.distance_to(Vector2(1970.8, 2812.12)) < 0.01:
						cave.position = Vector3(pos.x, 0, -pos.y)
						cave_found = true
						break
				for command in island.all("CREATE_ABODE"):
					var a: PackedStringArray = command["args"]
					var pos := IslandScript.pos(a[1])
					if pos.distance_to(Vector2(1713.83, 2592.59)) < 0.01:
						home.position = Vector3(pos.x, 0, -pos.y)
						home_found = true
						break
				var cave_id := bridge.register_object(cave, 3)
				var home_id := bridge.register_object(home, 2)
				var lookup_pc: int = vm.tasks[id]["pc"]
				var count_before := vm.executed
				check(read_island and cave_found and home_found and cave_id > 0 and home_id > 0 and vm.resume_unbound(_bridge_after_observed_influence), "bind real island cave and home in isolated story test")
				for ignored in 50:
					if not vm.tick(): break
				check(vm.executed > count_before and (not vm.tasks.has(id) or int(vm.tasks[id]["pc"]) != lookup_pc), "original setup passes exact original cave lookup")
				check(not bridge._created_markers.is_empty(), "original setup creates its first marker")
				print("ORIGINAL AFTER CAVE ", vm.error)
				if vm.tasks.has(id):
					print("ORIGINAL AFTER CAVE STACK ", vm.tasks[id]["stack"])
				if vm.error.get("detail",{}).get("native_id") == 27:
					var create_pc: int = vm.tasks[id]["pc"]
					check(vm.resume_unbound(_bridge_after_observed_influence), "bind original marker creation in isolated story test")
					for ignored in 50:
						if not vm.tick(): break
					check(not vm.tasks.has(id) or int(vm.tasks[id]["pc"]) != create_pc, "original setup creates its first marker")
					print("ORIGINAL AFTER MARKER ", vm.error)
					if vm.tasks.has(id):
						print("ORIGINAL AFTER MARKER STACK ", vm.tasks[id]["stack"])
				cave.free()
				home.free()
	var covered := {}
	for tested in tested_vms:
		for opcode in tested.opcode_counts:
			covered[opcode] = true
	var missing: Array[int] = []
	for opcode in 31:
		if not covered.has(opcode): missing.append(opcode)
	check(missing.is_empty(), "every original opcode executed in a focused test; missing=" + str(missing))
	bridge.clear_created()
	print("RESULT ", passed, " passed; ", failed.size(), " failed")
	quit(0 if failed.is_empty() else 1)


func _fixture_native(id: int, stack: Array, _context: Dictionary) -> Dictionary:
	if id == 99 and stack.size() == 1 and StoryVm.as_int(stack.back()) == 7:
		return {"ok":true,"pop":1,"push":[StoryVm.integer(11)]}
	return {"ok":false}


func _observe_first_native(id: int, stack: Array, _context: Dictionary) -> Dictionary:
	natives_seen.append(id)
	if id == 254 and stack.size() >= 2:
		return {"ok":true,"pop":2,"push":[]}
	return {"ok":false}


func _bridge_after_observed_influence(id: int, stack: Array, context: Dictionary) -> Dictionary:
	bridge_seen.append(id)
	return bridge.invoke(id, stack, context)


class TestTerrain extends RefCounted:
	func ground_y(position: Vector3) -> float:
		return position.x - position.z
