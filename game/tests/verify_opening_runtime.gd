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
			if continue_keeper and keeper_seen and script == "ChooseYourCreature" and not task["in_handler"] and task["pc"] >= 38705 and task["pc"] < 39572 and world.story_camera.owner_task == 0:
				keeper_intro_finished = true
			if DisplayServer.get_name() != "headless" and not capture_dir.is_empty() and script in ["TeachRotate", "TeachPitch", "TeachZoom", "GiveFood"] and not captured.has(script):
				captured[script] = true
				capture_frame.call_deferred(script)
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
		print("OPENING t=%.1f interface=%d camera=%d fade=%.2f movie=%s demo=%s text=%d tasks=%s" % [elapsed, world.story_interface_level, world.story_camera.owner_task,
			world.story_fade_rect.color.a if world.story_fade_rect != null else 0.0,
			world.story_intro_movie != null and world.story_intro_movie.active, world.story_hand_demo.playing,
			world.story_bridge.story_text_enum if world.story_bridge != null else -1, str(tasks)])
		if world.story_construction != null:
			print("CONSTRUCTION progress=%.4f stock=%d sitewood=%d consumed=%d builders=%d" % [world.story_citadel.progress, world.story_construction.storage_wood(), world.story_construction.wood, world.story_construction.wood_consumed, world.story_construction.jobs.size()])
			if construction_diagnostics: print("BUILD_JOBS ", JSON.stringify(world.story_construction.diagnostics()))
	if world.story_vm != null and not world.story_vm.error.is_empty():
		printerr("OPENING BLOCKED ", world.story_vm.error)
		quit(1)
	if elapsed >= duration or (continue_keeper and keeper_intro_finished and not continue_key) or (continue_key and first_key_finished):
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
		if automate_input:
			var passed: bool = visited.has("GiveFood") and temple_visited and camera_clearance >= 0.49 and player_camera_clearance >= 2.99 and door_wait_complete and door_stable and world.story_construction != null and world.story_construction.wood_consumed > 0
			for tutorial in ["TeachRotate", "TeachPitch", "TeachZoom"]:
				passed = passed and completed.has(tutorial)
			if continue_keeper:
				passed = passed and keeper_seen and keeper_intro_finished and world.story_journal.has(55)
			if continue_key:
				passed = passed and first_key_finished and world.story_gate_plinth.info_bits() == 2 and visited.has("LostBrother")
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
	if continue_key and keeper_intro_finished and not first_key_finished:
		if world.held != null:
			target = world.story_gate_plinth.landmark
			var point: Vector3 = target.global_transform * target.rig.bounds.get_center()
			var screen: Vector2 = world.cam.unproject_position(point)
			if Vector2(world.focus.x - target.position.x, world.focus.z - target.position.z).length() < 15.0 and not world.cam.is_position_behind(point) and world.get_viewport().get_visible_rect().has_point(screen):
				if world.story_gate_plinth.ray_hit(world.cam.project_ray_origin(screen), world.cam.project_ray_normal(screen)) != null:
					click_at(screen)
					return
		elif world.story_vm.variables.size() > 89:
			target = world.story_bridge._object(world.story_vm.variables[89]) as Node3D
			if target != null and target.story_pickup_allowed:
				var point := target.position + Vector3(0, 1.5, 0)
				var screen: Vector2 = world.cam.unproject_position(point)
				if Vector2(world.focus.x - target.position.x, world.focus.z - target.position.z).length() < 15.0 and not world.cam.is_position_behind(point) and world.get_viewport().get_visible_rect().has_point(screen):
					click_at(screen)
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
		var flat: Vector3 = target.position - world.focus
		flat.y = 0.0
		if flat.length() > 3.0:
			# Real bounded drags on visible ground, including recovery when the
			# guide has left the screen. Offscreen projection can point above the
			# horizon and incorrectly drag toward the ray's far-distance fallback.
			var right: Vector3 = world.cam.global_basis.x
			right.y = 0.0
			var forward: Vector3 = -world.cam.global_basis.z
			forward.y = 0.0
			var direction := Vector2(flat.dot(right.normalized()), -flat.dot(forward.normalized()))
			var pixels := direction.normalized() * minf(70.0, direction.length() * 3.0)
			drag(center + pixels, center)


func click_at(screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = screen
	event.pressed = true
	world._unhandled_input(event)
	event.pressed = false
	world._unhandled_input(event)
