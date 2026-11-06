extends SceneTree

const CameraController := preload("res://scripts/story_camera.gd")

var failures := 0


func _initialize() -> void:
	var controller := CameraController.new()
	var owner := {"task": 7}
	var other := {"task": 11}
	controller.update_player_pose(Vector3(8, 6, -4), Vector3(1, 2, -3))
	check(read_vector(controller.invoke(5, [], owner)) == Vector3(8, 6, 4), "read player eye in original coordinates")
	check(read_vector(controller.invoke(6, [], owner)) == Vector3(1, 2, 3), "read player focus in original coordinates")
	check(read_bool(controller.invoke(30, [], owner)), "first task acquires control")
	check(not read_bool(controller.invoke(30, [], other)), "other task cannot acquire while camera is owned")
	controller.invoke(31, [], other)
	check(controller.owner_task == 7, "other task cannot release the camera")
	check(controller.invoke(3, vector_args(Vector3(4, 9, 12)) + [StoryVm.number(2.0)], {"task":8}).get("ok", false), "a nested task can move the active script camera without releasing its owner")
	controller.update_player_pose(Vector3.ZERO, Vector3.ZERO)
	check(controller.eye == Vector3(8, 6, -4), "player updates do not replace the scripted eye")
	var reply := controller.invoke(1, vector_args(Vector3(3, 9, 12)), owner)
	check(reply.get("pop") == 3 and controller.eye == Vector3(3, 9, -12), "set eye maps the coordinates immediately")
	var movement := vector_args(Vector3(3, 13, 20))
	movement.append(StoryVm.number(2.0))
	controller.invoke(3, movement, owner)
	movement = vector_args(Vector3(1, 4, 7))
	movement.append(StoryVm.number(4.0))
	controller.invoke(4, movement, owner)
	check(not read_bool(controller.invoke(35, [], owner)), "camera reports movement")
	controller.advance(1.0)
	check(controller.eye == Vector3(3, 11.75, -17.5), "half-time pose matches the original quartic move")
	controller.advance(1.0)
	check(controller.eye == Vector3(3, 13, -20) and not read_bool(controller.invoke(35, [], owner)), "arriving eye leaves independent focus motion active")
	controller.advance(2.0)
	check(controller.focus == Vector3(1, 4, -7) and read_bool(controller.invoke(35, [], owner)), "camera arrives when both targets settle")
	controller.invoke(4, movement, owner)
	controller.invoke(31, [], owner)
	check(controller.owner_task == 0 and read_bool(controller.invoke(35, [], owner)), "owner release cancels scripted movement")
	controller.update_player_pose(Vector3.ONE, Vector3.ZERO)
	check(controller.eye == Vector3.ONE, "player can update the eye after release")
	verify_retarget(controller, owner)
	verify_follow(controller, owner)
	verify_focus_follow(controller, owner)
	verify_above_water_view()
	verify_player_clearance()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			verify_original_zone(controller, arg.substr(5))
	quit(0 if failures == 0 else 1)


func verify_player_clearance() -> void:
	var flat := func(_point: Vector3) -> float: return 5.0
	var focus := Vector3(0, 5, 0)
	var eye := Vector3(0, 13, 16)
	check(CameraController.constrain_player_eye(eye, focus, flat, 0.0) == eye, "near tutorial camera stays at authored height over flat terrain")
	var low_eye := Vector3(0, 6, 16)
	var raised := CameraController.constrain_player_eye(low_eye, focus, flat, 0.0)
	check(is_equal_approx(raised.y, 8.0), "low eye clears flat terrain by three units without magnifying clearance")
	var hill := func(point: Vector3) -> float: return 20.0 if point.z >= 7.0 and point.z <= 9.0 else 5.0
	raised = CameraController.constrain_player_eye(eye, focus, hill, 0.0)
	check(focus.lerp(raised, 0.5).y >= 21.499, "camera line of sight clears a hill between eye and focus")


func verify_above_water_view() -> void:
	var controller := CameraController.new()
	controller.eye = Vector3(1336.965, -2.176293, -2033.183)
	controller.focus = Vector3(1328.965, -2.524593, -2023.183)
	var authored_eye: Vector3 = controller.eye
	var authored_focus: Vector3 = controller.focus
	var pose := controller.above_water_pose(1.742)
	var direction: Vector3 = pose["eye"] - pose["focus"]
	check(pose["eye"].y >= 9.7419 and pose["focus"].y >= 1.7419, "shark shot is viewed from above the sea surface")
	check(atan2(direction.y, Vector2(direction.x, direction.z).length()) >= PI / 4.0 - 0.0001, "shark shot looks down at least forty-five degrees")
	check(controller.eye == authored_eye and controller.focus == authored_focus, "water view correction preserves original script camera state")
	controller.eye.y = 100.0
	check(controller.above_water_pose(1.742)["eye"] == controller.eye, "high introductory camera shots keep their authored position")


func verify_retarget(controller: RefCounted, owner: Dictionary) -> void:
	controller.update_player_pose(Vector3.ZERO, Vector3.ZERO)
	controller.invoke(30, [], owner)
	var movement := vector_args(Vector3(100, 0, 0))
	movement.append(StoryVm.number(2.0))
	controller.invoke(3, movement, owner)
	controller.advance(1.0)
	movement = vector_args(Vector3(120, 0, 0))
	movement.append(StoryVm.number(2.0))
	controller.invoke(3, movement, owner)
	controller.advance(1.0)
	check(is_equal_approx(controller.eye.x, 113.359375), "retargeting carries the old camera velocity into the new move")
	controller.release()


func verify_follow(controller: RefCounted, owner: Dictionary) -> void:
	var target := Node3D.new()
	target.position = Vector3(100, 20, 35)
	controller.update_player_pose(Vector3(100, 22, 32), target.position)
	controller.invoke(30, [], owner)
	check(controller.follow(target, 3.0, 1.0, owner["task"]), "owner starts following a moving object")
	var properties := [StoryVm.number(3.0), StoryVm.number(0.0), StoryVm.number(22.5), StoryVm.integer(1, StoryVm.BOOL)]
	check(controller.invoke(180, properties, owner).get("ok", false), "tutorial follow properties are accepted")
	check(controller.focus == Vector3(100, 21, 35) and is_equal_approx(controller.eye.distance_to(controller.focus), 3.0), "follow keeps the prescribed distance from the model centre")
	target.position.x += 10.0
	target.rotation.y = PI / 2.0
	controller.advance(0.1)
	check(controller.focus == Vector3(110, 21, 35) and controller.eye.x < 110, "camera follows target motion and heading")
	controller.invoke(1, vector_args(Vector3(111, 25, -40)), owner)
	target.position.x += 10.0
	controller.advance(0.1)
	check(controller.eye == Vector3(111, 25, 40), "explicit eye command replaces following")
	controller.release()
	target.free()


func verify_focus_follow(controller: RefCounted, owner: Dictionary) -> void:
	var target := Node3D.new()
	target.position = Vector3(10, 5, -20)
	controller.update_player_pose(Vector3(8, 6, -15), Vector3.ZERO)
	check(not controller.follow_focus(target, owner["task"], 0.75), "focus following requires an acquired script camera")
	controller.invoke(30, [], owner)
	controller.invoke(3, vector_args(Vector3(8, 7, 16)) + [StoryVm.number(2.0)], owner)
	check(controller.follow_focus(target, owner["task"], 0.75), "script camera starts tracking the actual actor's centre")
	controller.advance(1.0)
	check(controller.focus == target.position + Vector3(0, 0.75, 0) and controller.eye == Vector3(8, 6.6875, -15.6875), "actor focus and authored eye movement advance independently")
	target.position.x += 2.0
	controller.invoke(1, vector_args(Vector3(7, 6, 16)), owner)
	controller.advance(0.1)
	check(controller.focus.x == 12.0, "an explicit eye position keeps actor focus following")
	controller.invoke(2, vector_args(Vector3(1, 2, 3)), owner)
	target.position.x += 2.0
	controller.advance(0.1)
	check(controller.focus == Vector3(1, 2, -3), "an explicit focus replaces actor focus following")
	controller.release()
	target.free()


func verify_original_zone(controller: RefCounted, host: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(host.path_join("Data/Zones/land1begin.exc"))
	check(controller.load_zone(bytes), "original first tutorial camera zone loads")
	var inside := Vector3(1578, 4, -2220)
	var outside := Vector3(1000, 4, -2250)
	check(controller.constrain_player_focus(inside) == inside, "camera can focus inside the tutorial zone")
	var clamped: Vector3 = controller.constrain_player_focus(outside)
	check(clamped.x > 1438 and clamped.x < 1480 and clamped.y == outside.y, "camera focus outside the tutorial zone moves to its edge")
	check(not controller.load_zone(bytes.slice(0, bytes.size() - 1)), "truncated zone is rejected")
	check(controller.constrain_player_focus(outside) == clamped, "a rejected zone preserves the previous boundary")


func vector_args(point: Vector3) -> Array:
	return [
		StoryVm.number(point.x, StoryVm.VECTOR),
		StoryVm.number(point.y, StoryVm.VECTOR),
		StoryVm.number(point.z, StoryVm.VECTOR),
	]


func read_vector(reply: Dictionary) -> Vector3:
	var values: Array = reply["push"]
	return Vector3(StoryVm.as_float(values[0]), StoryVm.as_float(values[1]), StoryVm.as_float(values[2]))


func read_bool(reply: Dictionary) -> bool:
	return reply.get("ok", false) and StoryVm.as_int(reply["push"][0]) != 0


func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS ", description)
	else:
		failures += 1
		printerr("FAIL ", description)
