# Isolated compatibility engine for the player's LHVM v7 campaign records.
# World bindings are deliberately opt-in: an unknown native operation blocks
# execution with its script and instruction address, without consuming input.
class_name StoryVm
extends RefCounted

const Data := preload("res://scripts/data.gd")
const INT := 1
const FLOAT := 2
const VECTOR := 3
const OBJECT := 4
const BOOL := 6

var program: ChlReader
var variables: Array[Dictionary] = []
var tasks: Dictionary = {}
var finished: Dictionary = {}
var error: Dictionary = {}
var isolate_unbound_tasks := false
var strict_scripts := PackedStringArray()
var suspended: Dictionary = {}
var native_handler := Callable()
var ticks := 0
var executed := 0
var opcode_counts: Dictionary = {}
var _next_id := 1
var _remaining := 0
var _cfg: Dictionary = Data.STORY_VM["core"]


func configure(source: ChlReader, handler := Callable()) -> bool:
	if source == null or source.code.size() != source.instruction_count * 20:
		return false
	program = source
	native_handler = handler
	variables.clear()
	for ignored in source.globals:
		variables.append(number(0.0))
	tasks.clear()
	finished.clear()
	error.clear()
	suspended.clear()
	ticks = 0
	executed = 0
	opcode_counts.clear()
	_next_id = 1
	return true


static func integer(n: int, type := INT) -> Dictionary:
	return {"type":type,"bits":n & 0xffffffff}


static func number(n: float, type := FLOAT) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, n)
	return {"type":type,"bits":bytes.decode_u32(0)}


static func as_float(value: Dictionary) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, int(value["bits"]))
	return bytes.decode_float(0)


static func as_int(value: Dictionary) -> int:
	var bits: int = int(value["bits"]) & 0xffffffff
	return bits - 0x100000000 if bits >= 0x80000000 else bits


func start(name: String, args: Array = []) -> int:
	if program == null or not program.scripts.has(name):
		error = {"kind":"script_not_found","script":name}
		return 0
	return _start_entry(program.scripts[name], args)


func _start_entry(entry: Dictionary, args: Array) -> int:
	if tasks.size() >= int(_cfg["maximum_tasks"]):
		error = {"kind":"task_limit","script":entry["name"]}
		return 0
	if args.size() != int(entry["params"]):
		error = {"kind":"parameter_count","script":entry["name"],"expected":entry["params"],"actual":args.size()}
		return 0
	if args.size() > int(_cfg["stack_limit"]):
		error = {"kind":"stack_overflow","script":entry["name"]}
		return 0
	for value in args:
		if not value is Dictionary or not value.has("type") or not value.has("bits"):
			error = {"kind":"invalid_parameter","script":entry["name"]}
			return 0
	var locals: Array[Dictionary] = []
	for ignored in int(entry["variables"]):
		locals.append(number(0.0))
	var id := _next_id
	_next_id += 1
	tasks[id] = {"id":id,"script":entry["name"],"script_id":entry["id"],"pc":entry["address"],"var_offset":entry["variable_offset"],"locals":locals,"stack":args.duplicate(true),"handlers":[],"handler_index":0,"in_handler":false,"saved_pc":0,"waiting":0,"age":0,"state":"running"}
	return id


func tick() -> bool:
	if program == null or not error.is_empty():
		return false
	_remaining = int(_cfg["instructions_per_tick"])
	# Original scripts can register handlers that are evaluated once per tick.
	for id in tasks.keys():
		var t: Dictionary = tasks[id]
		if t["state"] != "running" or int(t["waiting"]) != 0:
			continue
		if t["in_handler"]:
			_run(t)
		elif not t["handlers"].is_empty():
			t["saved_pc"] = t["pc"]
			t["handler_index"] = 0
			t["pc"] = t["handlers"].back()
			t["in_handler"] = true
			_run(t)
		if not error.is_empty():
			return false
	for id in tasks.keys():
		var t: Dictionary = tasks[id]
		if t["state"] == "running" and not t["in_handler"] and int(t["waiting"]) == 0:
			_run(t)
		if not error.is_empty():
			return false
	for id in tasks.keys():
		var t: Dictionary = tasks[id]
		if t["state"] == "done":
			finished[id] = t.duplicate(true)
			tasks.erase(id)
	for t in tasks.values():
		t["age"] = int(t["age"]) + 1
		if int(t["waiting"]) != 0 and not tasks.has(t["waiting"]):
			t["waiting"] = 0
	ticks += 1
	return true


func resume_unbound(handler: Callable) -> bool:
	if error.get("kind", "") != "unbound_native" or not tasks.has(error.get("task", -1)):
		return false
	native_handler = handler
	tasks[error["task"]]["state"] = "running"
	error.clear()
	return true


func resume_suspended(id: int, handler: Callable) -> bool:
	if not suspended.has(id) or not tasks.has(id) or tasks[id]["state"] != "blocked":
		return false
	native_handler = handler
	tasks[id]["state"] = "running"
	suspended.erase(id)
	return true


func _run(t: Dictionary) -> void:
	var handler_mode: bool = t["in_handler"]
	while t["state"] == "running" and int(t["waiting"]) == 0 and bool(t["in_handler"]) == handler_mode:
		if _remaining <= 0:
			_fail(t, "instruction_budget", {})
			return
		var at: int = t["pc"]
		var ins := program.instruction(at)
		if ins.is_empty():
			_fail(t, "instruction_address", {"address":at})
			return
		var op: int = ins["opcode"]
		var mode: int = ins["mode"]
		var type: int = ins["type"]
		var bits: int = ins["bits"]
		if not Data.STORY_OPCODES.has(str(op)):
			_fail(t, "unsupported_opcode", {"opcode":op})
			return
		_remaining -= 1
		executed += 1
		opcode_counts[op] = int(opcode_counts.get(op, 0)) + 1
		t["pc"] = at + 1
		var stack: Array = t["stack"]
		match op:
			0:
				t["state"] = "done"
			1:
				if mode != 0 and mode != 1:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
				if not _need(t, 1): return
				var condition: Dictionary = stack.pop_back()
				if int(condition["bits"]) == 0:
					if not _jump(t, bits): return
					if mode == 0: return
				else:
					t["age"] = 1
			2:
				if mode == 0:
					if not _push(t, {"type":type,"bits":bits}): return
				elif mode == 1:
					var value := _get_var(t, bits)
					if not error.is_empty() or not _push(t, value): return
				else:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
			3:
				if not _need(t, 1): return
				if mode == 1 and not _set_var(t, bits, stack.back()): return
				if mode != 0 and mode != 1:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
				stack.pop_back()
			4, 6, 7, 8, 9, 10:
				if not _arithmetic(t, op, type): return
			5:
				if not _native(t, bits, at): return
			11:
				if not _need(t, 1): return
				var v: Dictionary = stack.pop_back()
				if not _push(t, integer(1 if int(v["bits"]) == 0 else 0, BOOL)): return
			12, 13:
				if not _need(t, 2): return
				var a: Dictionary = stack.pop_back()
				var b: Dictionary = stack.pop_back()
				var av := int(a["bits"]) != 0
				var bv := int(b["bits"]) != 0
				if not _push(t, integer(int((av and bv) if op == 12 else (av or bv)), BOOL)): return
			14, 15, 16, 17, 18, 19:
				if not _compare(t, op, type): return
			20:
				if mode != 0 and mode != 1:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
				if not _jump(t, bits): return
				if mode == 0: return
			21:
				if not _need(t, 1): return
				var seconds := as_float(stack.pop_back())
				if not is_finite(seconds) or seconds < 0:
					_fail(t, "invalid_timer", {}); return
				if not _push(t, integer(int(seconds * float(_cfg["tick_rate"]) < float(t["age"])), BOOL)): return
			22:
				if bits >= program.instruction_count:
					_fail(t, "handler_address", {"address":bits}); return
				t["handlers"].append(bits)
			23:
				if mode == 1:
					if type != FLOAT:
						_fail(t, "unsupported_mode", {"opcode":op,"type":type}); return
					if not _set_var(t, bits, number(0.0)): return
				elif mode == 0:
					if not _need(t, 1): return
					var value: Dictionary = stack.pop_back().duplicate()
					# ScriptLibraryR.dll dispatches CAST by the destination type.
					if type == INT:
						var converted := as_float(value)
						if not is_finite(converted) or converted < -2147483648.0 or converted >= 2147483648.0:
							_fail(t, "invalid_integer_cast", {}); return
						value = integer(int(converted))
					elif type == FLOAT:
						value = number(float(int(value["bits"]) & 0xffffffff))
					else:
						value["type"] = type
					if not _push(t, value): return
				else:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
			24:
				if mode != 0 and mode != 1:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
				if not program.scripts_by_id.has(bits):
					_fail(t, "script_id_not_found", {"script_id":bits}); return
				var child: Dictionary = program.scripts_by_id[bits]
				var n: int = child["params"]
				if not _need(t, n): return
				var args: Array = []
				for ignored in n:
					args.append(stack.pop_back())
				var child_id := _start_entry(child, args)
				if child_id == 0: return
				if mode == 0:
					t["waiting"] = child_id
					return
			25:
				if mode == 0:
					if not t["handlers"].is_empty(): t["handlers"].pop_back()
				elif mode == 1:
					return
				else:
					_fail(t, "unsupported_mode", {"opcode":op,"mode":mode}); return
			26:
				if not t["in_handler"]:
					_fail(t, "not_in_handler", {}); return
				t["pc"] = t["saved_pc"]
				t["in_handler"] = false
			27:
				if not t["in_handler"]:
					_fail(t, "not_in_handler", {}); return
				t["handler_index"] = int(t["handler_index"]) + 1
				var index: int = t["handlers"].size() - int(t["handler_index"]) - 1
				if index >= 0:
					t["pc"] = t["handlers"][index]
				else:
					t["pc"] = t["saved_pc"]
					t["in_handler"] = false
			28:
				if not t["in_handler"]:
					_fail(t, "not_in_handler", {}); return
				t["handlers"].clear()
				t["in_handler"] = false
			29:
				if not _swap(t, mode, type, bits): return
			30:
				pass


func _native(t: Dictionary, id: int, address: int) -> bool:
	if not native_handler.is_valid():
		t["pc"] = address
		_fail(t, "unbound_native", {"native_id":id})
		return false
	var stack: Array = t["stack"]
	var reply = native_handler.call(id, stack.duplicate(true), {"task":t["id"],"script":t["script"],"address":address,"tick":ticks})
	if not reply is Dictionary or not reply.get("ok", false):
		t["pc"] = address
		_fail(t, "unbound_native", {"native_id":id})
		return false
	var count := int(reply.get("pop", -1))
	var output = reply.get("push", null)
	if count < 0 or count > stack.size() or not output is Array or stack.size() - count + output.size() > int(_cfg["stack_limit"]):
		t["pc"] = address
		_fail(t, "invalid_native_result", {"native_id":id})
		return false
	for value in output:
		if not value is Dictionary or not value.has("type") or not value.has("bits"):
			t["pc"] = address
			_fail(t, "invalid_native_result", {"native_id":id})
			return false
	stack.resize(stack.size() - count)
	for value in output:
		stack.append(value.duplicate())
	return not reply.get("yield_task", false)


func _jump(t: Dictionary, address: int) -> bool:
	if address < 0 or address >= program.instruction_count:
		_fail(t, "jump_address", {"address":address})
		return false
	t["pc"] = address
	return true


func _get_var(t: Dictionary, id: int) -> Dictionary:
	var local_index := id - int(t["var_offset"]) - 1
	if id > int(t["var_offset"]):
		if local_index >= 0 and local_index < t["locals"].size(): return t["locals"][local_index].duplicate()
	elif id >= 0 and id < variables.size():
		return variables[id].duplicate()
	_fail(t, "variable_address", {"variable":id})
	return {}


func _set_var(t: Dictionary, id: int, value: Dictionary) -> bool:
	var local_index := id - int(t["var_offset"]) - 1
	if id > int(t["var_offset"]):
		if local_index >= 0 and local_index < t["locals"].size():
			t["locals"][local_index] = value.duplicate()
			return true
	elif id >= 0 and id < variables.size():
		variables[id] = value.duplicate()
		return true
	_fail(t, "variable_address", {"variable":id})
	return false


func _need(t: Dictionary, count: int) -> bool:
	if count < 0 or t["stack"].size() < count:
		_fail(t, "stack_underflow", {"required":count,"available":t["stack"].size()})
		return false
	return true


func _push(t: Dictionary, value: Dictionary) -> bool:
	if t["stack"].size() >= int(_cfg["stack_limit"]):
		_fail(t, "stack_overflow", {})
		return false
	t["stack"].append(value.duplicate())
	return true


func _fail(t: Dictionary, kind: String, detail: Dictionary) -> void:
	var address: int = t["pc"] if kind == "unbound_native" or kind == "invalid_native_result" else maxi(int(t["pc"]) - 1, 0)
	var ins := program.instruction(address)
	error = {"kind":kind,"task":t["id"],"script":t["script"],"address":address,"opcode":ins.get("opcode", -1),"line":ins.get("line", -1),"detail":detail}
	t["state"] = "blocked" if kind == "unbound_native" else "failed"
	# Development preview: keep unsupported later quests suspended at their
	# exact call/stack without treating them as completed. Original synchronous
	# parents still wait for them. Intro scripts retain the strict failure path.
	if kind == "unbound_native" and isolate_unbound_tasks and not strict_scripts.has(t["script"]):
		suspended[t["id"]] = error.duplicate(true)
		error.clear()


func _arithmetic(t: Dictionary, op: int, type: int) -> bool:
	var stack: Array = t["stack"]
	if type not in [INT, FLOAT, VECTOR]:
		_fail(t, "arithmetic_type", {"type":type}); return false
	if type == VECTOR:
		var count := 3 if op == 7 else (6 if op in [4,6] else 4)
		if not _need(t, count): return false
		var result: Array[Dictionary] = []
		if op == 7:
			for i in 3: result.push_front(number(-as_float(stack.pop_back()), VECTOR))
		elif op == 4 or op == 6:
			var rhs: Array[float] = []
			for i in 3: rhs.push_front(as_float(stack.pop_back()))
			var lhs: Array[float] = []
			for i in 3: lhs.push_front(as_float(stack.pop_back()))
			for i in 3: result.append(number(lhs[i] + rhs[i] if op == 4 else lhs[i] - rhs[i], VECTOR))
		elif op == 8:
			var vec: Array[float] = []
			for i in 3: vec.push_front(as_float(stack.pop_back()))
			var scalar := as_float(stack.pop_back())
			for v in vec: result.append(number(v * scalar, VECTOR))
		else:
			var scalar := as_float(stack.pop_back())
			if scalar == 0.0: _fail(t, "divide_by_zero", {}); return false
			var vec: Array[float] = []
			for i in 3: vec.push_front(as_float(stack.pop_back()))
			for v in vec: result.append(number(v / scalar if op == 9 else _remainder(v, scalar), VECTOR))
		for v in result:
			if not _push(t, v): return false
		return true
	var count := 1 if op == 7 else 2
	if not _need(t, count): return false
	var right: Dictionary = stack.pop_back()
	if type == INT:
		var r := as_int(right)
		var l := 0
		if op != 7:
			l = as_int(stack.pop_back())
		if op in [9,10] and r == 0:
			_fail(t, "divide_by_zero", {}); return false
		var int_result := 0
		match op:
			4: int_result = l + r
			6: int_result = l - r
			7: int_result = -r
			8: int_result = l * r
			9: int_result = int(float(l) / float(r))
			10: int_result = l - int(float(l) / float(r)) * r
		return _push(t, integer(int_result))
	var rv: float = float(as_int(right)) if type == INT else as_float(right)
	var lv := 0.0
	if op != 7:
		var left: Dictionary = stack.pop_back()
		lv = float(as_int(left)) if type == INT else as_float(left)
	if op in [9,10] and rv == 0.0:
		_fail(t, "divide_by_zero", {}); return false
	var result := 0.0
	match op:
		4: result = lv + rv
		6: result = lv - rv
		7: result = -rv
		8: result = lv * rv
		9: result = lv / rv
		10: result = _remainder(lv, rv)
	if not is_finite(result):
		_fail(t, "invalid_number", {}); return false
	return _push(t, integer(int(result)) if type == INT else number(result))


static func _remainder(a: float, b: float) -> float:
	return a - b * float(int(a / b))


func _compare(t: Dictionary, op: int, type: int) -> bool:
	var stack: Array = t["stack"]
	if type == VECTOR and op in [14,15]:
		if not _need(t, 6): return false
		var rhs: Array[float] = []
		var lhs: Array[float] = []
		for i in 3: rhs.push_front(as_float(stack.pop_back()))
		for i in 3: lhs.push_front(as_float(stack.pop_back()))
		var equal := lhs == rhs
		return _push(t, integer(int(equal if op == 14 else not equal), BOOL))
	if type not in [INT,FLOAT,BOOL,OBJECT] or (type in [BOOL,OBJECT] and op not in [14,15]):
		_fail(t, "comparison_type", {"type":type}); return false
	if not _need(t, 2): return false
	var r: Dictionary = stack.pop_back()
	var l: Dictionary = stack.pop_back()
	var right: float = as_float(r) if type == FLOAT else float(as_int(r))
	var left: float = as_float(l) if type == FLOAT else float(as_int(l))
	var result := false
	match op:
		14: result = left == right
		15: result = left != right
		16: result = left >= right
		17: result = left <= right
		18: result = left > right
		19: result = left < right
	return _push(t, integer(int(result), BOOL))


func _swap(t: Dictionary, mode: int, type: int, offset: int) -> bool:
	var stack: Array = t["stack"]
	if type == INT:
		if not _need(t, 2): return false
		var last = stack.pop_back()
		var previous = stack.pop_back()
		stack.append(last)
		stack.append(previous)
		return true
	if offset < 1 or offset >= int(_cfg["stack_limit"]) - 1 or mode not in [0,1]:
		_fail(t, "invalid_stack_offset", {"offset":offset,"mode":mode}); return false
	if not _need(t, offset): return false
	if stack.size() >= int(_cfg["stack_limit"]):
		_fail(t, "stack_overflow", {}); return false
	if mode == 1:
		stack.append(stack[stack.size() - offset].duplicate())
	else:
		stack.insert(stack.size() - offset, stack.back().duplicate())
	return true
