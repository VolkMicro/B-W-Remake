extends SceneTree
## Source VM storage, rather than the host catalogue, owns script references.

class QueryWorld extends Node:
	var story_vm := StoryVm.new()
	func story_add_influence() -> void: pass # Host capability; never invoked here.
	func ground_y(_point: Vector3) -> float: return 10.0

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failed += 1

func source() -> ChlReader:
	var program := ChlReader.new()
	program.globals.assign(["zero", "claimed"])
	var code := [[3,1,2,3], [2,0,2,int(StoryVm.number(0.2)["bits"])], [21,0,2,0], [1,0,1,1], [0,0,0,0], [3,1,2,3], [5,0,0,999], [0,0,0,0]]
	program.instruction_count = code.size()
	program.code.resize(code.size() * 20)
	for i in code.size():
		for part in 4: program.code.encode_u32(i * 20 + part * 4, int(code[i][part]) & 0xffffffff)
	program.scripts = {
		"owner":{"name":"owner","id":1,"address":0,"params":1,"variables":1,"variable_offset":2},
		"blocked":{"name":"blocked","id":2,"address":5,"params":1,"variables":1,"variable_offset":2}}
	program.scripts_by_id = {1:program.scripts["owner"], 2:program.scripts["blocked"]}
	return program

func query(bridge: StoryNatives, exclude: bool) -> Dictionary:
	return bridge.invoke(51, [StoryVm.integer(33),StoryVm.integer(5000),StoryVm.number(0,StoryVm.VECTOR),StoryVm.number(0,StoryVm.VECTOR),StoryVm.number(5,StoryVm.VECTOR),StoryVm.number(20),StoryVm.integer(int(exclude),StoryVm.BOOL)], {})

func selected(result: Dictionary) -> int:
	return StoryVm.as_int(result["push"][0]) if result.get("ok", false) else -1

func run() -> void:
	var world := QueryWorld.new()
	root.add_child(world)
	var bridge := StoryNatives.new()
	bridge.configure(world)
	check(world.story_vm.configure(source(), bridge.invoke), "configure real VM with bounded source reference fixture")
	var first := Thing.new()
	first.kind = "rock"
	first.position = Vector3(5,0,-5)
	first.set_meta("story_mobile_subtype", 2)
	world.add_child(first)
	var second := Thing.new()
	second.kind = "rock"
	second.position = Vector3(6,0,-5)
	second.set_meta("story_mobile_subtype", 2)
	world.add_child(second)
	var a := bridge.register_object(first, 8)
	var b := bridge.register_object(second, 8)
	check(a != 0 and b != a and bridge.register_object(first,8) == a, "one live object has one stable script handle")
	check(world.story_vm.active_object_handles().is_empty() and selected(query(bridge,true)) == a, "catalogue membership alone does not exclude a free nearby rock")
	world.story_vm.variables[1] = StoryVm.integer(a,StoryVm.OBJECT)
	check(selected(query(bridge,true)) == b and selected(query(bridge,false)) == a, "a global OBJECT reference excludes its rock only when requested")
	world.story_vm.variables[1] = StoryVm.integer(a,StoryVm.FLOAT)
	check(selected(query(bridge,true)) == a, "equal bits in a numeric cell do not acquire an object reference")
	world.story_vm.variables[1] = StoryVm.number(0)
	var task := world.story_vm.start("owner",[StoryVm.integer(a,StoryVm.OBJECT)])
	check(task != 0 and selected(query(bridge,true)) == b, "a pending script parameter stack retains the object before its first instruction")
	world.story_vm.tick()
	check(world.story_vm.tasks.has(task) and world.story_vm.tasks[task]["stack"].is_empty() and selected(query(bridge,true)) == b, "popping a parameter into a live local retains ownership")
	for i in 8: world.story_vm.tick()
	check(world.story_vm.finished.has(task) and world.story_vm.active_object_handles().is_empty() and selected(query(bridge,true)) == a, "finishing source releases its local despite retained diagnostic history")
	world.story_vm.isolate_unbound_tasks = true
	var blocked := world.story_vm.start("blocked",[StoryVm.integer(a,StoryVm.OBJECT)])
	world.story_vm.tick()
	check(world.story_vm.suspended.has(blocked) and world.story_vm.tasks[blocked]["pc"] == 6 and selected(query(bridge,true)) == b, "unsupported pending bytecode preserves the local and its script ownership")
	check(bridge.register_object(first,33) == a and selected(query(bridge,true)) == b, "registering an alias cannot make an owned rock appear free")
	first.set_meta("story_deleted",true)
	check(bridge.register_object(first,8) == 0 and selected(query(bridge,false)) == b, "logical deletion cannot recreate a handle or return a fading object")
	var unsupported := bridge.invoke(51,[StoryVm.integer(99),StoryVm.integer(5000),StoryVm.number(0),StoryVm.number(0),StoryVm.number(0),StoryVm.number(20),StoryVm.integer(1)],{})
	check(not unsupported.get("ok",false), "unimplemented object-search types remain unsupported")
	var actor := Thing.new()
	actor.kind = "villager"
	actor.set_meta("story_villager_subtype",81)
	actor.set_process(false)
	actor.set_physics_process(false)
	world.add_child(actor)
	var actor_handle := StoryVm.integer(bridge.register_object(actor,4),StoryVm.OBJECT)
	check(bridge.invoke(321,[StoryVm.integer(0),actor_handle],{}).get("ok",false) and not actor.story_hurt_by_fire,"source fire-vulnerability flag disables the physical actor's fire gate")
	check(bridge.invoke(321,[StoryVm.integer(1),actor_handle],{}).get("ok",false) and actor.story_hurt_by_fire,"source restores the fire gate after the sculptor cinema")
	bridge.invoke(168,[StoryVm.integer(0),actor_handle],{})
	bridge.invoke(169,[StoryVm.integer(0),actor_handle],{})
	check(not actor.story_move_allowed and not actor.story_pickup_allowed,"script move/pick restrictions also apply to villagers")
	bridge.invoke(22,[StoryVm.integer(2),actor_handle,StoryVm.number(90)],{})
	check(is_equal_approx(actor.rotation.y,-PI/2.0),"script degree heading reaches the mirrored actor transform")
	var heading := bridge.invoke(21,[StoryVm.integer(2),actor_handle],{})
	check(heading.get("ok",false) and is_equal_approx(StoryVm.as_float(heading["push"][0]),90.0),"heading property reads source degrees rather than engine radians")
	var before_angle := actor.rotation
	check(not bridge.invoke(22,[StoryVm.integer(3),actor_handle,StoryVm.number(NAN)],{}).get("ok",false) and actor.rotation==before_angle,"nonfinite angle leaves the actor's actual transform unchanged")
	bridge.invoke(349,[StoryVm.integer(1),StoryVm.integer(16),actor_handle],{})
	check(is_equal_approx(actor.rotation.y,-PI) and not actor.story_smooth_heading,"scripted quarter-turn applies immediately in mirrored coordinates")
	bridge.invoke(349,[StoryVm.integer(1),StoryVm.integer(8),actor_handle],{})
	check(actor.story_smooth_heading,"source command8 restores heading interpolation")
	world.free()
	await process_frame
	print("OWNERSHIP ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
