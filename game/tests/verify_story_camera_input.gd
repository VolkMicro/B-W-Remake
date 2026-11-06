extends SceneTree

const CameraInput := preload("res://scripts/story_camera_input.gd")
class TutorialWorld extends Node3D:
	var story_camera_input := CameraInput.new()
	func story_set_widescreen(_enabled: bool) -> void:
		pass

var failures := 0
var passed := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok:
		passed += 1
	else:
		failures += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := TutorialWorld.new()
	var input := world.story_camera_input
	var bridge := StoryNatives.new()
	bridge.configure(world)
	for ignored in 20:
		input.record_rotation(0.02)
		input.advance(0.005)
	check(input.total(25) == 1.0, "many mouse events count once per original 100 ms turn")
	input.advance(2.0)
	check(input.total(25) == 1.0, "idle time does not fabricate camera use")
	input.record_pitch(0.01)
	input.record_zoom(3.0)
	input.advance(0.1)
	check(input.total(28) == 1.0 and input.total(29) == 1.0, "pitch and zoom have independent event totals")
	var result := bridge.invoke(237, [StoryVm.integer(25)], {})
	check(result.get("ok", false) and StoryVm.as_float(result["push"][0]) == 1.0, "GET_TOTAL_EVENTS returns the original FLOAT count")
	result = bridge.invoke(413, [], {})
	check(result.get("ok", false) and result["push"][0]["type"] == StoryVm.INT and StoryVm.as_int(result["push"][0]) == 22, "GET_HAND_STATE returns the actual zoom gesture as an INT")
	check(not bridge.invoke(237, [StoryVm.integer(3)], {}).get("ok", false), "unimplemented non-camera statistics remain explicit")
	bridge.invoke(285, [StoryVm.integer(1, StoryVm.BOOL)], {})
	check(input.angle_sound_axis == 25, "rotation feedback selects original rotation channel")
	bridge.invoke(348, [StoryVm.integer(1, StoryVm.BOOL)], {})
	bridge.invoke(348, [StoryVm.integer(0, StoryVm.BOOL)], {})
	check(input.angle_sound_axis == 0, "pitch feedback is released by its original stop command")
	var owner := {"task": 1}
	check(StoryVm.as_int(bridge.invoke(122, [], owner)["push"][0]) == 1, "dialogue ready queries an unowned dialogue")
	bridge.invoke(120, [], owner)
	check(StoryVm.as_int(bridge.invoke(122, [], {"task": 2})["push"][0]) == 0 and bridge.dialogue_owner == 1, "dialogue ready does not steal another task's dialogue")
	bridge.invoke(121, [], owner)
	result = bridge.invoke(65, [StoryVm.integer(4), StoryVm.integer(4)], {})
	check(result.get("ok", false) and result["push"][0]["type"] == StoryVm.INT and StoryVm.as_int(result["push"][0]) == 4, "lost-family random callouts support an inclusive single-value integer range")
	result = bridge.invoke(29, [], {"tick":1234})
	check(result.get("ok", false) and absf(StoryVm.as_float(result["push"][0]) - 123.4) < 0.0001, "notification clock reads original VM elapsed seconds")
	check(not bridge.invoke(29, [], {}).get("ok", false), "notification clock requires a real VM tick context")
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
	if not source.is_empty():
		verify_original_rotation_tutorial(world, bridge, source)
	bridge.clear_created()
	world.free()
	print("CAMERA INPUT ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)

func verify_original_rotation_tutorial(world: TutorialWorld, bridge: StoryNatives, source: String) -> void:
	var program := ChlReader.new()
	check(program.load_file(source.path_join("Scripts/Quests/challenge.chl")), "load player's original tutorial bytecode")
	var camera := preload("res://scripts/story_camera.gd").new()
	camera.update_player_pose(Vector3(0, 40, 30), Vector3.ZERO)
	bridge.camera = camera
	bridge.game_time = preload("res://scripts/story_time.gd").new()
	var centre := Node3D.new()
	var view := Node3D.new()
	world.add_child(centre)
	world.add_child(view)
	view.position = camera.eye
	# CALL moves arguments from the caller stack into child order by popping.
	var args := [StoryVm.integer(bridge.register_object(view), StoryVm.OBJECT), StoryVm.integer(bridge.register_object(centre), StoryVm.OBJECT)]
	var vm := StoryVm.new()
	vm.configure(program, bridge.invoke)
	var id := vm.start("TeachRotate", args)
	for ignored in 20:
		vm.tick()
	check(vm.error.is_empty() and vm.tasks.has(id), "original TeachRotate waits for actual rotation")
	for ignored in 100:
		world.story_camera_input.record_rotation(0.02)
		world.story_camera_input.advance(0.1)
		if not vm.tick():
			break
	check(vm.error.is_empty() and vm.finished.has(id), "original TeachRotate completes after player input without changing script flags: %s" % vm.error)
