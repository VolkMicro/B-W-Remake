extends SceneTree

const Hand := preload("res://scripts/story_hand_pose.gd")
var failures := 0
var passed := 0
var host := "C:/Games/Black and White Complete Collection"
var capture := ""
var facing := Vector3.UP

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bw="): host = argument.substr(5)
		if argument.begins_with("--capture="): capture = argument.substr(10)
		if argument == "--palm-up": facing = Vector3.DOWN
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
	else: passed += 1

func difference(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var result := 0.0
	for bone in a.size():
		result = maxf(result, a[bone].origin.distance_to(b[bone].origin))
		for axis in 3:
			result = maxf(result, a[bone].basis[axis].distance_to(b[bone].basis[axis]))
	return result

func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 18, 22)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	root.add_child(environment)
	var poses: Dictionary = {}
	for state_index in 6:
		var state: String = ["hover", "point", "pickup", "hold", "drag", "rotate"][state_index]
		var rig := L3dRig.new()
		var visual := rig.load_file(host.path_join("Data/CreatureMesh/Hand_Boned_Base2.l3d"))
		root.add_child(visual)
		var controller := Hand.new()
		check(controller.configure(host, rig), state + " original HBN and hndspec5 load")
		if not controller.error.is_empty():
			printerr(controller.error)
			continue
		check(rig.bone_count == 22 and controller.slots.size() == 69, state + " preserves original skeleton and animation index")
		check(controller.set_state(state), state + " selects an existing source clip")
		var pose := controller.sample(0.5)
		poses[state] = pose
		rig.apply_local_pose(pose)
		var s := 7.0 / rig.bounds.get_longest_axis_size()
		visual.basis = Hand.source_orientation(PI, facing).scaled_local(Vector3.ONE * s)
		var geometry := controller.geometry(visual.basis, pose)
		var bounds: AABB = geometry["bounds"]
		visual.position = -bounds.get_center() + Vector3(float(state_index % 3 - 1) * 8.0, 0, float(state_index / 3) * 9.0 - 4.5)
		check((geometry["pointer"] as Vector3).is_finite() and bounds.has_point(geometry["pointer"]), state + " fingertip anchor is a vertex-derived point inside the animated mesh bounds")
		if state == "hold":
			check(bounds.has_point(geometry["grip"]) and (geometry["grip"] as Vector3).distance_to(geometry["pointer"]) > 0.1, "holding uses a distinct pinch point between the actual thumb and index pads")
		if state == "hover":
			var tilted := controller.sample(0.0, Vector2(0.0625, 0.875))
			check(difference(pose, tilted) > 0.01, "original mouse-lag LR/FB sliders animate hovering fingers and wrist")
		if state == "point":
			check(controller.bone_position(Hand.INDEX_TIP_BONE, pose).y > controller.bone_position(16, pose).y + 100.0, "source pointing clip leaves index finger extended while middle finger bends")
			check(rig.skeleton.get_bone_global_pose(Hand.INDEX_TIP_BONE).origin.distance_to(controller.bone_position(Hand.INDEX_TIP_BONE, pose)) < 0.01, "Godot skeleton receives the same posed fingertip used for cursor attachment")
		var label := Label3D.new()
		label.text = state
		label.position = visual.position + Vector3(0, 5.0, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		root.add_child(label)
	check(difference(poses["hover"], poses["pickup"]) > 1.0 and difference(poses["pickup"], poses["hold"]) > 1.0, "actual pickup and holding source poses differ from the idle hand")
	check(Hand.source_orientation(0.0).determinant() < 0.0 and Hand.source_orientation(0.0, Vector3.DOWN, false).determinant() > 0.0, "default right hand uses the original CHand negative-X toggle")
	if not capture.is_empty():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(capture)
	print("HAND_POSE passed=", passed, " failures=", failures)
	quit(1 if failures else 0)
