extends SceneTree

const Pose := preload("res://scripts/story_adviser_pose.gd")
const Data := preload("res://scripts/data.gd")
var failures := 0
var host := "C:/Games/Black and White Complete Collection"
var capture := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func pose_error(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var error := 0.0
	for bone in a.size():
		error = maxf(error, a[bone].origin.distance_to(b[bone].origin))
		for axis in 3:
			error = maxf(error, a[bone].basis[axis].distance_to(b[bone].basis[axis]))
	return error

func run() -> void:
	check((MorphReader.adviser_rotation(Vector3(PI / 2.0, 0, 0)) * Vector3.UP).distance_to(Vector3.BACK) < 0.00001, "original X rotation and handedness match LHMatrix")
	check((MorphReader.adviser_rotation(Vector3(0, PI / 2.0, 0)) * Vector3.BACK).distance_to(Vector3.RIGHT) < 0.00001, "original Y rotation and handedness match LHMatrix")
	check((MorphReader.adviser_rotation(Vector3(0, 0, PI / 2.0)) * Vector3.RIGHT).distance_to(Vector3.DOWN) < 0.00001, "original Z rotation matches LHMatrix rather than Godot XYZ")
	check(Pose.facing_yaw(Vector2(0.8, 0.8)) < 0.0 and Pose.facing_yaw(Vector2(0.2, 0.8)) > 0.0, "hover turns advisers toward the centre of the camera")
	check(Pose.facing_yaw(Vector2(0.8, 1.0), true) == 0.0, "original bottom-edge clinging disables hover yaw")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color(0.12, 0.18, 0.25)
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color = Color.WHITE
	world_environment.environment.ambient_light_energy = 1.0
	root.add_child(world_environment)
	for id in ["good", "evil"]:
		var rig := L3dRig.new()
		var animation := MorphReader.new()
		var visual := rig.load_file(host.path_join(Data.ADVISERS[id]["file"]))
		check(visual != null and animation.load_adviser(host.path_join(Data.ADVISERS[id]["file"])), id + " original model and clips load")
		if visual == null: continue
		root.add_child(visual)
		var prefix := "adviser/Yogi_" if id == "good" else "adviser/Demon_"
		var hover := animation.sample_adviser(prefix + "Hover", 0.3, rig)
		var additive := hover.duplicate()
		animation.apply_adviser_difference(prefix + "Speak_AAA", 0.0, 0.0, additive, rig)
		check(pose_error(hover, additive) < 0.00001, id + " closed mouth leaves original hover unchanged")
		animation.apply_adviser_difference(prefix + "Speak_AAA", 1.0, 0.0, additive, rig)
		check(pose_error(hover, additive) > 0.001, id + " vowel layers a real facial movement")
		var introduction := prefix + ("Point_L_In" if id == "good" else "Point_Left_In")
		check(not animation.clips[introduction]["cyclic"], id + " pointing intro is non-cyclic in original data")
		check(pose_error(animation.sample_adviser(introduction, 0.7, rig), animation.sample_adviser(introduction, 7.0, rig)) < 0.00001, id + " pointing intro holds its end instead of restarting")
		var controller := Pose.new()
		var anchor := Vector2(0.8, 0.85) if id == "good" else Vector2(0.2, 0.85)
		var result: Array[Transform3D]
		var worst_rotation := 0.0
		var worst_translation := 0.0
		var previous: Array[Transform3D] = []
		for step in 360:
			var point := Vector2(0.5, 0.4) if step >= 120 and step < 240 else Vector2.INF
			result = controller.sample(animation, rig, id, 1.0 / 60.0, anchor, point)
			if not previous.is_empty():
				for bone in result.size():
					worst_translation = maxf(worst_translation, previous[bone].origin.distance_to(result[bone].origin) * 3.4 / rig.bounds.size.y)
					worst_rotation = maxf(worst_rotation, previous[bone].basis.orthonormalized().get_rotation_quaternion().angle_to(result[bone].basis.orthonormalized().get_rotation_quaternion()))
			previous = result
		check(worst_translation < 0.12 and worst_rotation < deg_to_rad(20.0), id + " idle/point/idle transitions remain continuous; translation=" + str(worst_translation) + " angle=" + str(rad_to_deg(worst_rotation)))
		var voiced := controller.sample(animation, rig, id, 0.0, anchor)
		check(pose_error(result, voiced) < 0.00001, id + " speech event cannot reset body animation time")
		var waveform := AudioStreamWAV.new()
		waveform.format = AudioStreamWAV.FORMAT_16_BITS
		waveform.mix_rate = 22050
		waveform.loop_mode = AudioStreamWAV.LOOP_FORWARD
		waveform.loop_end = 22050
		var samples := PackedByteArray()
		samples.resize(22050 * 2)
		for sample_index in 22050:
			samples.encode_s16(sample_index * 2, int(8000.0 * sin(float(sample_index) * TAU * 220.0 / 22050.0)))
		waveform.data = samples
		var voice := AudioStreamPlayer.new()
		voice.stream = waveform
		voice.volume_db = -80.0
		root.add_child(voice)
		voice.play()
		controller.sample(animation, rig, id, 1.0 / 60.0, anchor, Vector2.INF, Vector2.INF, voice)
		check(controller._mouth > 0.1, id + " real 16-bit PCM amplitude opens the mouth")
		voice.stop()
		for step in 60:
			controller.sample(animation, rig, id, 1.0 / 60.0, anchor, Vector2.INF, Vector2.INF, voice)
		check(controller._mouth < 0.00001, id + " silence closes the mouth without restarting the body")
		voice.free()
		rig.apply_local_pose(animation.sample_adviser(prefix + "Hover", 0.4, rig))
		var s := 3.4 / rig.bounds.size.y
		visual.scale = Vector3.ONE * s
		visual.position = Vector3(2.5 if id == "good" else -2.5, -1.8 - rig.bounds.position.y * s, -9.0)
		var camera_anchor := Node3D.new()
		camera.add_child(camera_anchor)
		visual.reparent(camera_anchor)
		visual.scale = Vector3.ONE * (2.7 / rig.bounds.size.y)
		visual.position = Vector3(0.0, -rig.bounds.position.y * visual.scale.y, 0.0)
		anchor = Vector2(0.8 if id == "good" else 0.2, 1.0)
		camera_anchor.position = camera.project_position(anchor * root.get_visible_rect().size, 10.0)
		var cling_controller := Pose.new()
		cling_controller.camera = camera
		for step in 240:
			result = cling_controller.sample(animation, rig, id, 1.0 / 60.0, anchor, Vector2.INF, Vector2.INF, null, true)
			rig.apply_local_pose(result)
		var globals: Array[Transform3D] = []
		for bone in result.size():
			globals.append(globals[rig.parents[bone]] * result[bone] if rig.parents[bone] >= 0 else result[bone])
		var head := visual.global_transform * globals[animation.adviser_metadata["head_bone"]]
		var toward_camera := (camera.global_position - head.origin).normalized()
		var facing := head.basis.y.normalized().dot(toward_camera)
		var head_screen := camera.unproject_position(head.origin) / root.get_visible_rect().size
		check(facing > 0.5, id + " clinging head faces the perspective camera; dot=" + str(facing))
		check(head_screen.y > 0.7 and head_screen.y < 0.97, id + " clinging head pivot remains above the bottom edge; y=" + str(head_screen.y))
	if not capture.is_empty():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(capture)
	print("ADVISER_POSE failures=", failures)
	quit(1 if failures else 0)
