extends SceneTree
## Real scene, audio, physics and input; unlike the off-tree CHL probe.
## This observes play and never marks a player objective complete by itself.

var world: Node
var elapsed := 0.0
var next_report := 0.0
var duration := 660.0
var visited: Dictionary = {}
var automate := false
var automate_input := false
var capture_dir := ""
var captured: Dictionary = {}
var camera_clearance := INF
var player_camera_clearance := INF
var temple_until := 0.0
var temple_visited := false
var stop_at_village := false
var next_action := 0.0
var door_wait_started := -1.0
var door_wait_pose := Transform3D.IDENTITY
var door_stable := true
var door_wait_complete := false
var continue_keeper := false
var keeper_seen := false
var keeper_intro_finished := false
var continue_key := false
var first_key_finished := false
var stop_at_keys := false
var continue_second_key := false
var stop_after_first := false
var second_key_finished := false
var second_key_phase := "waiting for first key"
var second_key_failure := ""
var second_scroll_clicked := false
var second_brother: WeakRef
var second_sister: WeakRef
var second_brother_released := false
var second_key_delivered := false
var second_drop_at := -1.0
var second_drop_point := Vector3.INF
var unexpected_drop_point := Vector3.INF
var unexpected_drop_at := -1.0
var unexpected_drop_search := 0
var unexpected_drops := 0
var input_failure := ""
var construction_diagnostics := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runtime-seconds="):
			duration = maxf(1.0, arg.substr(18).to_float())
		elif arg == "--runtime-automation":
			automate = true
			automate_input = true
		elif arg == "--runtime-input-only":
			automate_input = true
		elif arg == "--runtime-stop-at-village":
			stop_at_village = true
		elif arg == "--runtime-keeper":
			continue_keeper = true
		elif arg == "--runtime-key":
			continue_keeper = true
			continue_key = true
		elif arg == "--runtime-second-key":
			continue_keeper = true
			continue_key = true
			continue_second_key = true
		elif arg == "--runtime-stop-after-first":
			continue_keeper = true
			continue_key = true
			stop_after_first = true
		elif arg == "--runtime-stop-at-keys":
			continue_keeper = true
			stop_at_keys = true
		elif arg == "--construction-diagnostics":
			construction_diagnostics = true
		elif arg.begins_with("--runtime-captures="):
			capture_dir = arg.substr(19)
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
	if automate:
		print("OPENING TEST AUTOMATION: media skipped, camera driven through input handlers")
		Engine.time_scale = 4.0
	call_deferred("start_scene")

func start_scene() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)

func _process(delta: float) -> bool:
	elapsed += delta
	if not is_instance_valid(world) or not world.loaded:
		return false
	if stop_at_village and world.story_citadel != null:
		stop_at_village = false
		automate = false
		automate_input = false
		Engine.time_scale = 1.0
		duration = INF
		world.get_window().title = "Black & White — тест деревни"
		print("VILLAGE_TEST_READY original story state; media and player control restored")
	camera_clearance = minf(camera_clearance, world.cam.position.y - maxf(world.ground_y(world.cam.position), world.sea_y))
	if world.story_camera.owner_task == 0 and not world.story_inside_temple():
		player_camera_clearance = minf(player_camera_clearance, world.cam.position.y - maxf(world.ground_y(world.cam.position), world.sea_y))
	if automate:
		if world.story_intro_movie != null and world.story_intro_movie.active:
			world.story_intro_movie.finish()
		if world.dialogue != null:
			world.dialogue.stop()
	if automate_input:
		if world.story_inside_temple():
			if temple_until == 0.0:
				temple_until = elapsed + 8.0
				temple_visited = true
			if elapsed >= temple_until:
				var escape := InputEventKey.new()
				escape.keycode = KEY_ESCAPE
				escape.pressed = true
				world._unhandled_input(escape)
		elif elapsed >= next_action and world.story_camera.owner_task == 0:
			next_action = elapsed + 0.25
			drive_camera_input()
	if world.story_vm != null:
		if continue_key and world.story_journal.get(55, {}).get("success", 0.0) == 0.25 and StoryVm.as_float(world.story_vm.variables[92]) == 1.0 and world.story_camera.owner_task == 0:
			first_key_finished = true
		for actor in world.things:
			if is_instance_valid(actor) and actor.get_meta("story_villager_subtype", -1) == 77:
				keeper_seen = true
		for task in world.story_vm.tasks.values():
			var script: String = task["script"]
			visited[script] = true
			if continue_second_key and script == "LostBrother" and task["locals"].size() >= 6:
				var sister: Object = world.story_bridge._object(task["locals"][4])
				var brother: Object = world.story_bridge._object(task["locals"][5])
				if sister is Node3D: second_sister = weakref(sister)
				if brother is Node3D: second_brother = weakref(brother)
			if continue_keeper and keeper_seen and script == "ChooseYourCreature" and not task["in_handler"] and task["pc"] >= 38705 and task["pc"] < 39572 and world.story_camera.owner_task == 0:
				keeper_intro_finished = true
			if DisplayServer.get_name() != "headless" and not capture_dir.is_empty() and script in ["TeachRotate", "TeachPitch", "TeachZoom", "GiveFood"] and not captured.has(script):
				captured[script] = true
				capture_frame.call_deferred(script)
		if continue_second_key:
			# A later quest may start and immediately suspend on a genuine missing
			# native. Count it as started, while checking this route separately.
			for problem in world.story_vm.suspended.values():
				visited[str(problem.get("script", ""))] = true
				if second_key_required_script(str(problem.get("script", ""))):
					printerr("OPENING SECOND KEY BLOCKED ", problem)
					quit(1)
					return false
			second_key_finished = second_key_delivered and second_scroll_clicked and world.story_gate_plinth.info_bits() == 3 and world.story_gate_plinth.get_child_count() == 2 and world.story_journal.get(55, {}).get("success", 0.0) == 0.5 and StoryVm.as_float(world.story_vm.variables[91]) == 1.0 and StoryVm.as_float(world.story_vm.variables[92]) == 1.0 and world.story_camera.owner_task == 0 and visited.has("TheSculptor")
	if stop_after_first and first_key_finished and not continue_second_key:
		stop_after_first = false
		continue_key = false
		continue_keeper = false
		automate = false
		automate_input = false
		Engine.time_scale = 1.0
		duration = INF
		world.get_window().title = "Black & White — после первого камня"
		print("FIRST_KEY_TEST_READY actual first key delivered; media and manual input restored")
	if stop_at_keys and keeper_intro_finished:
		stop_at_keys = false
		continue_keeper = false
		automate = false
		automate_input = false
		Engine.time_scale = 1.0
		duration = INF
		world.get_window().title = "Black & White — тест первого ключа"
		print("KEY_TEST_READY original keeper state; media and manual input restored; no key collected")
	if elapsed >= next_report:
		next_report = elapsed + 10.0
		var tasks := []
		if world.story_vm != null:
			for task in world.story_vm.tasks.values():
				var script: String = task["script"]
				visited[script] = true
				if script in ["FollowUs", "Drag", "Rotating", "TeachRotate", "TeachPitch", "Zoom", "TeachZoom", "GiveFood", "TunnelOfUltimateDoom", "CitadelGuideCinema"]:
					tasks.append("%s:%d" % [script, task["pc"]])
				elif continue_second_key and second_key_required_script(script):
					tasks.append("%s:%d" % [script, task["pc"]])
		print("OPENING t=%.1f interface=%d camera=%d fade=%.2f movie=%s demo=%s text=%d tasks=%s" % [elapsed, world.story_interface_level, world.story_camera.owner_task,
			world.story_fade_rect.color.a if world.story_fade_rect != null else 0.0,
			world.story_intro_movie != null and world.story_intro_movie.active, world.story_hand_demo.playing,
			world.story_bridge.story_text_enum if world.story_bridge != null else -1, str(tasks)])
		if world.story_construction != null:
			print("CONSTRUCTION progress=%.4f stock=%d sitewood=%d consumed=%d builders=%d" % [world.story_citadel.progress, world.story_construction.storage_wood(), world.story_construction.wood, world.story_construction.wood_consumed, world.story_construction.jobs.size()])
			if construction_diagnostics: print("BUILD_JOBS ", JSON.stringify(world.story_construction.diagnostics()))
		if continue_second_key:
			print("SECOND KEY phase=", second_key_phase, " first=", first_key_finished, " scroll=", second_scroll_clicked, " released=", second_brother_released, " delivered=", second_key_delivered, " bits=", world.story_gate_plinth.info_bits() if world.story_gate_plinth != null else -1)
	if not input_failure.is_empty():
		printerr("OPENING INPUT FAILED ", input_failure)
		quit(1)
		return false
	if not second_key_failure.is_empty():
		printerr("OPENING SECOND KEY FAILED ", second_key_failure)
		quit(1)
		return false
	if world.story_vm != null and not world.story_vm.error.is_empty():
		printerr("OPENING BLOCKED ", world.story_vm.error)
		quit(1)
		return false
	if elapsed >= duration or (continue_keeper and keeper_intro_finished and not continue_key) or (continue_key and first_key_finished and not continue_second_key) or (continue_second_key and second_key_finished):
		print("OPENING OBSERVED ", visited.keys())
		var completed := []
		for task in world.story_vm.finished.values():
			if task["script"] in ["TeachRotate", "TeachPitch", "TeachZoom"]:
				completed.append(task["script"])
		print("OPENING COMPLETED TUTORIALS ", completed)
		print("OPENING MIN CAMERA CLEARANCE ", camera_clearance)
		print("OPENING MIN PLAYER CAMERA CLEARANCE ", player_camera_clearance)
		print("OPENING TEMPLE VISITED ", temple_visited)
		print("OPENING DOOR WAIT STABLE ", door_wait_complete and door_stable)
		if continue_keeper:
			print("OPENING KEEPER INTRO ", keeper_seen and keeper_intro_finished and world.story_journal.has(55))
		if continue_key:
			print("OPENING FIRST KEY ", first_key_finished, " bits=", world.story_gate_plinth.info_bits())
		if continue_second_key:
			print("OPENING SECOND KEY ", second_key_finished, " phase=", second_key_phase, " bits=", world.story_gate_plinth.info_bits(), " journal=", world.story_journal.get(55, {}).get("success", -1.0), " stones=", world.story_gate_plinth.get_child_count(), " sculptor=", visited.has("TheSculptor"), " camera=", world.story_camera.owner_task, " unexpected=", unexpected_drops)
		if automate_input:
			var passed: bool = visited.has("GiveFood") and temple_visited and camera_clearance >= 0.49 and player_camera_clearance >= 2.99 and door_wait_complete and door_stable and world.story_construction != null and world.story_construction.wood_consumed > 0
			for tutorial in ["TeachRotate", "TeachPitch", "TeachZoom"]:
				passed = passed and completed.has(tutorial)
			if continue_keeper:
				passed = passed and keeper_seen and keeper_intro_finished and world.story_journal.has(55)
			if continue_key:
				passed = passed and first_key_finished and visited.has("LostBrother") and (world.story_gate_plinth.info_bits() == 3 if continue_second_key else world.story_gate_plinth.info_bits() == 2)
			if continue_second_key:
				passed = passed and second_key_finished
			print("OPENING RESULT ", "PASS" if passed else "FAIL")
			quit(0 if passed else 1)
		else:
			quit()
	return false


func capture_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))


func drag(from: Vector2, to: Vector2, right := false) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE if right else MOUSE_BUTTON_LEFT
	press.position = from
	press.pressed = true
	world._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	world._unhandled_input(motion)
	if right:
		return # Hold through real VM turns so GET_HAND_STATE observes rotation.
	press.position = to
	press.pressed = false
	world._unhandled_input(press)


func drive_camera_input() -> void:
	if world.story_vm == null:
		return
	var scripts := []
	for task in world.story_vm.tasks.values():
		scripts.append(task["script"])
	var center: Vector2 = world.get_viewport().get_visible_rect().size * 0.5
	if scripts.has("TeachRotate"):
		drag(center, center + Vector2(35, 0), true)
		return
	if scripts.has("TeachPitch"):
		var sign := -1.0 if world.pitch > PI / 3.0 else 1.0
		drag(center, center + Vector2(0, sign * 30), true)
		return
	if world._middle_down:
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_MIDDLE
		release.pressed = false
		release.position = center
		world._unhandled_input(release)
	if scripts.has("TeachZoom"):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN if world.dist < 30.0 else MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = center
		world._unhandled_input(wheel)
		return
	if scripts.has("CitadelGuideCinema") and world.story_citadel_interface and not temple_visited:
		if door_wait_started < 0.0:
			door_wait_started = elapsed
			door_wait_pose = world.cam.transform
			if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
				capture_frame.call_deferred("TempleDoor")
			print("DOOR WAIT begin: thirty seconds without player input")
		if elapsed - door_wait_started < 30.0:
			door_stable = door_stable and world.cam.position.distance_to(door_wait_pose.origin) < 0.01 and world.cam.basis.is_equal_approx(door_wait_pose.basis)
			return
		door_wait_complete = true
		var doorway: Vector3 = world.story_citadel.entrance_position()
		if not world.cam.is_position_behind(doorway):
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = true
			click.double_click = true
			click.position = world.cam.unproject_position(doorway)
			world._unhandled_input(click)
			return
	var target: Node3D
	if continue_second_key and first_key_finished:
		drive_second_key_input()
		return
	elif continue_key and keeper_intro_finished and not first_key_finished:
		var first_key: Node3D = world.story_bridge._object(world.story_vm.variables[89]) as Node3D if world.story_vm.variables.size() > 89 else null
		if world.held != null and world.held != first_key:
			release_unexpected_held(first_key.position if is_instance_valid(first_key) else world.focus)
			return
		if world.held != null:
			target = world.story_gate_plinth.landmark
			var point: Vector3 = target.global_transform * target.rig.bounds.get_center()
			var screen: Vector2 = world.cam.unproject_position(point)
			if Vector2(world.focus.x - target.position.x, world.focus.z - target.position.z).length() < 15.0 and not world.cam.is_position_behind(point) and world.get_viewport().get_visible_rect().has_point(screen):
				if world.hand_target(screen).get("target") == target and world.story_gate_plinth.ray_hit(world.cam.project_ray_origin(screen), world.cam.project_ray_normal(screen)) != null:
					click_at(screen)
					return
			if drive_to_position(target.position): orbit_for_visible_pickup()
			return
		elif is_instance_valid(first_key) and first_key.story_pickup_allowed:
			# Only press Action where the hand really selects the stone itself;
			# a blind click beside it can pick up a neighbouring tree instead.
			var screen := visible_pickup_screen(first_key)
			if screen.is_finite() and Vector2(world.focus.x - first_key.position.x, world.focus.z - first_key.position.z).length() < 15.0:
				click_at(screen)
				if world.held == first_key: print("FIRST KEY actual stone picked up through mouse Action")
				return
			if drive_to_position(first_key.position): orbit_for_visible_pickup()
			return
	elif continue_keeper and temple_visited and scripts.has("ChooseYourCreature") and not keeper_seen:
		for highlight in world.story_highlights:
			if is_instance_valid(highlight) and highlight.get_meta("challenge", -1) == 55:
				target = highlight
				break
		if target != null:
			if world.dist < 80.0:
				var wheel := InputEventMouseButton.new()
				wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
				wheel.pressed = true
				wheel.position = center
				world._unhandled_input(wheel)
				return
			var source_point: Vector3 = target.visual.global_transform * target.visual.mesh.get_aabb().get_center()
			var screen: Vector2 = world.cam.unproject_position(source_point)
			if world.focus.distance_to(target.position) < 45.0 and not world.cam.is_position_behind(source_point) and world.get_viewport().get_visible_rect().has_point(screen):
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_RIGHT
				click.position = screen
				click.pressed = true
				world._unhandled_input(click)
				click.pressed = false
				world._unhandled_input(click)
				return
	elif scripts.has("TunnelOfUltimateDoom") or scripts.has("CheckCitadel"):
		target = world.story_citadel
	else:
		for thing in world.things:
			# The mother leads the original route; the father can lag behind.
			if thing.get_meta("story_villager_subtype", -1) == 49:
				target = thing
				break
	if scripts.has("LostTheMother"):
		for task in world.story_vm.tasks.values():
			if task["script"] == "LostTheMother" and not task["locals"].is_empty():
				var mother = world.story_bridge._object(task["locals"][0])
				if mother is Node3D:
					target = mother
	if is_instance_valid(target):
		drive_to_position(target.position)


func second_key_required_script(script: String) -> bool:
	return script.begins_with("LostBrother") or script in ["GiveReward", "HeadingHome", "ProtectGateKey1", "ProtectGateKey2", "ProtectGateKeys", "ChooseYourCreature"]


func drive_to_position(point: Vector3, stopping_distance := 3.0) -> bool:
	var flat: Vector3 = point - world.focus
	flat.y = 0.0
	if flat.length() <= stopping_distance: return true
	# All movement goes through bounded drags on visible ground. No scene,
	# actor or focus assignment is used to reach the next objective.
	var center: Vector2 = world.get_viewport().get_visible_rect().size * 0.5
	var right: Vector3 = world.cam.global_basis.x
	right.y = 0.0
	var forward: Vector3 = -world.cam.global_basis.z
	forward.y = 0.0
	var direction := Vector2(flat.dot(right.normalized()), -flat.dot(forward.normalized()))
	var pixels := direction.normalized() * minf(70.0, direction.length() * 3.0)
	drag(center + pixels, center)
	return false


func mouse_move_to(screen: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.relative = Vector2.ZERO
	world._unhandled_input(event)


func orbit_for_visible_pickup() -> void:
	var center: Vector2 = world.get_viewport().get_visible_rect().size * 0.5
	drag(center, center + Vector2(24, 0), true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.position = center + Vector2(24, 0)
	release.pressed = false
	world._unhandled_input(release)


func visible_pickup_screen(target: Node3D) -> Vector2:
	var points: Array[Vector3] = [target.global_position + Vector3.UP * 1.5]
	if target is Thing and target.rig != null:
		points.append(target.rig.root.global_transform * target.rig.bounds.get_center())
	for point in points:
		if world.cam.is_position_behind(point): continue
		var screen: Vector2 = world.cam.unproject_position(point)
		for offset in [Vector2.ZERO, Vector2(10, 0), Vector2(-10, 0), Vector2(0, -10), Vector2(0, 10)]:
			var candidate: Vector2 = screen + offset
			if world.get_viewport().get_visible_rect().has_point(candidate) and world.hand_target(candidate).get("pickup") == target:
				return candidate
	return Vector2.INF


func release_unexpected_held(anchor: Vector3) -> void:
	# Put a wrongly selected object back through the same Action press/release
	# a player would use: on visible land inside influence, away from the
	# objective. It is never moved, deleted or written by the test itself.
	if unexpected_drop_point.is_finite():
		var armed: Vector2 = world.cam.unproject_position(unexpected_drop_point)
		var point := unexpected_drop_candidate(armed, anchor)
		if not point.is_finite() or point.distance_to(unexpected_drop_point) > 2.0:
			unexpected_drop_point = Vector3.INF
			return
		mouse_move_to(armed)
		if elapsed < unexpected_drop_at: return
		var item: Node3D = world.held
		click_at(armed)
		unexpected_drop_point = Vector3.INF
		if world.held == null:
			unexpected_drops += 1
			unexpected_drop_search = 0
			print("UNEXPECTED PICKUP released through mouse Action: ", item.get("kind"), " drops=", unexpected_drops)
			if unexpected_drops > 6: input_failure = "automation repeatedly picked up an object other than its objective"
		return
	var size: Vector2 = world.get_viewport().get_visible_rect().size
	for offset in [Vector2(0.22, 0.12), Vector2(-0.22, 0.12), Vector2(0.3, 0.0), Vector2(-0.3, 0.0), Vector2(0.15, 0.28), Vector2(-0.15, 0.28), Vector2(0.0, 0.32), Vector2(0.3, -0.15), Vector2(-0.3, -0.15)]:
		var screen: Vector2 = size * (Vector2(0.5, 0.5) + offset)
		var point := unexpected_drop_candidate(screen, anchor)
		if not point.is_finite(): continue
		unexpected_drop_point = point
		unexpected_drop_at = elapsed + 0.75
		mouse_move_to(screen)
		return
	if not drive_to_position(anchor, 8.0): return
	unexpected_drop_search += 1
	if unexpected_drop_search > 240:
		input_failure = "no visible land inside influence to put down unexpected %s" % str(world.held.get("kind"))
		return
	orbit_for_visible_pickup()


func unexpected_drop_candidate(screen: Vector2, anchor: Vector3) -> Vector3:
	if not world.get_viewport().get_visible_rect().has_point(screen): return Vector3.INF
	var selection: Dictionary = world.hand_target(screen)
	var hit: Vector3 = selection["point"]
	if selection.get("target") != null and selection.get("target") != world.held: return Vector3.INF
	if selection.has("resource") or not world.has_influence(hit) or hit.y <= world.sea_y + 0.05: return Vector3.INF
	var away := Vector2(hit.x - anchor.x, hit.z - anchor.z).length()
	return hit if away >= 6.0 and away <= 60.0 else Vector3.INF


func drive_second_key_input() -> void:
	if second_key_delivered:
		second_key_phase = "waiting for original second-key keeper reaction"
		return
	var sister: Node3D = second_sister.get_ref() as Node3D if second_sister != null else null
	var brother: Thing = second_brother.get_ref() as Thing if second_brother != null else null
	var key: Thing = world.story_bridge._object(world.story_vm.variables[88]) as Thing
	if world.held != null and world.held == key:
		second_key_phase = "carrying rewarded stone to plinth"
		var plinth: OriginalLandmark = world.story_gate_plinth.landmark
		if not drive_to_position(plinth.position): return
		var centre: Vector3 = plinth.global_transform * plinth.rig.bounds.get_center()
		if world.cam.is_position_behind(centre): return
		var screen: Vector2 = world.cam.unproject_position(centre)
		if world.get_viewport().get_visible_rect().has_point(screen) and world.hand_target(screen).get("target") == plinth:
			click_at(screen)
			second_key_delivered = world.held == null and not is_instance_valid(key) and world.story_gate_plinth.info_bits() == 3
			if second_key_delivered:
				print("SECOND KEY actual rewarded stone installed through mouse Action")
				if not capture_dir.is_empty() and DisplayServer.get_name() != "headless": capture_frame.call_deferred("SecondKeyInstalled")
		else:
			orbit_for_visible_pickup()
		return
	if world.held != null and world.held != brother:
		second_key_phase = "putting down unexpected carried object"
		release_unexpected_held(brother.position if is_instance_valid(brother) else (key.position if is_instance_valid(key) else world.focus))
		return
	if world.held == null and is_instance_valid(key) and key.story_pickup_allowed and StoryVm.as_float(world.story_vm.variables[129]) == 1.0:
		second_key_phase = "picking up original reunion reward"
		if not drive_to_position(key.position): return
		var screen := visible_pickup_screen(key)
		if screen.is_finite(): click_at(screen)
		else: orbit_for_visible_pickup()
		return
	if not second_scroll_clicked:
		for highlight in world.story_highlights:
			if not is_instance_valid(highlight) or highlight.get_meta("challenge", -1) != 19: continue
			second_key_phase = "clicking original lost-brother scroll"
			if not drive_to_position(highlight.position, 12.0): return
			var point: Vector3 = highlight.visual.global_transform * highlight.visual.mesh.get_aabb().get_center()
			if world.cam.is_position_behind(point): return
			var screen: Vector2 = world.cam.unproject_position(point)
			if world.get_viewport().get_visible_rect().has_point(screen) and world.hand_target(screen).get("scroll") == highlight:
				click_at(screen)
				second_scroll_clicked = highlight.active
				if second_scroll_clicked: print("SECOND KEY lost-brother scroll activated through mouse Action")
			else:
				orbit_for_visible_pickup()
			return
		second_key_phase = "waiting for original lost-brother scroll"
		return
	if not is_instance_valid(sister) or not is_instance_valid(brother):
		second_key_phase = "waiting for source-created siblings"
		return
	if brother.state == Thing.State.DEAD:
		second_key_failure = "brother died before reunion; source quest was not completed"
		return
	if world.held == brother:
		second_key_phase = "carrying brother to sister"
		if not drive_to_position(sister.position): return
		if second_drop_at < 0.0:
			for offset in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3.ZERO]:
				var point: Vector3 = sister.position + offset
				point.y = world.ground_y(point)
				if world.cam.is_position_behind(point): continue
				var screen: Vector2 = world.cam.unproject_position(point)
				if not world.get_viewport().get_visible_rect().has_point(screen): continue
				var selection: Dictionary = world.hand_target(screen)
				var hit: Vector3 = selection["point"]
				if hit.distance_to(point) > 2.0 or not world.has_influence(hit) or hit.y <= world.sea_y + 0.05: continue
				second_drop_point = point
				second_drop_at = elapsed + 0.75
				mouse_move_to(screen)
				return
			orbit_for_visible_pickup()
			return
		var screen: Vector2 = world.cam.unproject_position(second_drop_point)
		mouse_move_to(screen)
		if elapsed >= second_drop_at:
			# Press and release at rest: actual physics starts at the visible grip.
			click_at(screen)
			if world.held == null:
				second_brother_released = true
				second_drop_at = -1.0
				print("SECOND KEY brother released through mouse Action; waiting for physics and source reunion")
		return
	if brother.state == Thing.State.FLYING:
		second_key_phase = "waiting for brother to settle physically"
		return
	if second_brother_released and Vector2(brother.position.x - sister.position.x, brother.position.z - sister.position.z).length() < 10.0:
		second_key_phase = "waiting for source reunion and reward"
		return
	second_key_phase = "finding and picking up living brother"
	if not drive_to_position(brother.position): return
	var screen := visible_pickup_screen(brother)
	if screen.is_finite():
		click_at(screen)
		if world.held == brother: print("SECOND KEY living brother picked up through mouse Action")
	else:
		orbit_for_visible_pickup()


func click_at(screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = screen
	event.pressed = true
	world._unhandled_input(event)
	event.pressed = false
	world._unhandled_input(event)
