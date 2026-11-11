extends SceneTree

class ScrollWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var host := "C:/Games/Black and White Complete Collection"
var failed := 0
var capture := ""
var deliver_key := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
		if arg == "--deliver-key": deliver_key = true
	Engine.time_scale = 6.0
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failed += 1

func run() -> void:
	var world := ScrollWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	world._build_hud()
	var opened := world.lnd.load_file(host.path_join(world.Data.SOURCES["landscape"]))
	opened = opened and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	opened = opened and world.island.load_file(host.path_join("Scripts/Land1.txt")) and world._load_landmark_animations()
	check(opened, "load actual first-island terrain, meshes and source actor/scroll registries")
	if not opened:
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	if not capture.is_empty():
		world._build_environment()
		world._build_terrain()
	world._spawn_objects()
	world._build_hand()
	world._build_advisers()
	world._setup_original_dialogue()
	world._setup_original_music()
	for control in world.hud.get_children():
		if control is Control and control != world.dialogue_caption: control.hide()
	world.campaign.load_file(host.path_join("Scripts/Quests/challenge.chl"))
	check(world.host_info.highlights.size() == 4 and world.host_info.villagers.size() == 84, "read all four original highlight types and 84 original villager records")
	check(world.host_info.highlight(2)["mesh_id"] == 319 and world.host_info.highlight(3)["active_mesh_id"] == 318, "silver and gold inactive/active meshes come from info.dat")
	check(world.host_info.villager(77)["mesh_id"] == 420, "the creature keeper uses the actual Animal Trainer mesh")
	if deliver_key:
		world._start_story("SetupLand1")
		for i in 100:
			if not world.story_vm.tick(): break
		world.story_vm.start("ChooseYourCreature")
	else:
		world._start_story("ChooseYourCreature")
	world.story_vm.isolate_unbound_tasks = false
	# This focused fixture starts after SetupLand1. Link its actual existing
	# second gate-key object, without moving it or setting any completed quest.
	for key in world.story_mobile_statics:
		if key.get_meta("story_mobile_subtype", -1) == 52:
			world.story_vm.variables[89] = StoryVm.integer(world.story_bridge.register_object(key, 8), StoryVm.OBJECT)
			break
	if deliver_key:
		# start() takes the VM's popped call stack, matching CALL_SCRIPT reversal.
		world.story_vm.start("ProtectGateKey2", [world.story_vm.variables[84], world.story_vm.variables[85]])
	for i in 4: world.story_vm.tick()
	var gold: Node3D
	for highlight in world.story_highlights:
		if highlight.get_meta("challenge", -1) == 55:
			gold = highlight
	check(gold != null and gold.visual.mesh != null and gold.visible, "original ChooseYourCreature creates its visible golden scroll")
	if gold == null:
		quit(1)
		return
	check(is_equal_approx(gold.position.y, world.ground_y(gold.position) + 14.0), "source YPOS property places the golden scroll fourteen metres above its ground anchor")
	world.cam.position = gold.position + Vector3(0, 6, 25)
	world.cam.look_at(gold.position)
	gold.advance(0.0, world.cam)
	world.story_camera.update_player_pose(world.cam.position, gold.position)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-scroll.png")
	var handle := StoryVm.integer(world.story_bridge.register_object(gold, 37), StoryVm.OBJECT)
	check(StoryVm.as_int(world.story_bridge.invoke(16, [handle], {})["push"][0]) == 0, "a visible scroll is not considered clicked merely by entering its trigger")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = world.cam.unproject_position(gold.visual.global_transform * gold.visual.mesh.get_aabb().get_center())
	world.loaded = true
	click.pressed = true
	world._unhandled_input(click)
	click.pressed = false
	world._unhandled_input(click)
	world.loaded = false
	check(StoryVm.as_int(world.story_bridge.invoke(16, [handle], {})["push"][0]) == 1 and world.held == null, "real mouse press/release selects the scroll without putting it in the Hand")
	check(gold.active and gold.visual.mesh == gold._active_mesh, "clicked scroll displays its original active mesh")
	world.story_bridge.invoke(255, [StoryVm.integer(0, StoryVm.BOOL), handle], {})
	check(StoryVm.as_int(world.story_bridge.invoke(361, [handle], {})["push"][0]) == 0, "original SET_ACTIVE and IS_ACTIVE use the actual scroll state")
	var reached_keeper_end := false
	var captured_keeper := false
	var keeper: Thing
	for tick in 3000:
		world.story_camera.advance(0.1)
		world.animation_clock += 0.1
		for actor in world.things:
			actor.set_process(false)
			actor.set_physics_process(false)
			if actor.get_meta("story_villager_subtype", -1) == 77:
				keeper = actor
				actor._physics_process(0.1)
				actor._process(0.1)
		world.dialogue.stop() # Explicit media-skipping fixture, never a player completion flag.
		if not world.story_vm.tick(): break
		world._update_camera()
		if not capture.is_empty(): world._update_world(0.1)
		for task in world.story_vm.tasks.values():
			if not capture.is_empty() and not captured_keeper and task["script"] == "ChooseYourCreature" and task["pc"] > 38400 and task["pc"] < 38575:
				captured_keeper = true
				# Skipping the voice removes the seven-second interval in which the
				# authored focus settles. Render its final shot before skipping on.
				for settling_frame in 80:
					world.story_camera.advance(0.1)
					world.animation_clock += 0.1
					if is_instance_valid(keeper): keeper._process(0.1)
					world._update_camera()
					world._update_world(0.1)
					await process_frame
				await RenderingServer.frame_post_draw
				check(world.cam.position.is_equal_approx(world.story_camera.eye), "keeper close-up preserves its original above-ground camera height")
				check(keeper._ordinary_rig != null, "keeper close-up uses the original separate sable.l3d model")
				root.get_texture().get_image().save_png(capture.get_basename() + "-keeper.png")
			if task["script"] == "ChooseYourCreature" and not task["in_handler"] and task["pc"] >= 38705 and task["pc"] < 39572:
				reached_keeper_end = true
		if reached_keeper_end: break
		await process_frame
	check(world.story_vm.error.is_empty(), "keeper cinema executes original CHL without an unimplemented native: " + str(world.story_vm.error))
	check(is_instance_valid(keeper) and keeper.rig.bone_count > 0, "original Keeper actor has a real animated skeleton")
	check(world.story_journal.has(55) and world.story_journal[55]["source_cells"].size() == 14, "original counted SNAPSHOT creates the keeper's actual story-book entry")
	check(reached_keeper_end and world.story_camera.owner_task == 0, "original keeper introduction finishes and returns camera control before the gate-key phase")
	if deliver_key: await verify_key_delivery(world)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	for property in ["hand_ring", "hand_pivot", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	print("SCROLLS failures=", failed)
	quit(0 if failed == 0 else 1)


func source_step(world: Node) -> void:
	world.story_camera.advance(0.1)
	world.animation_clock += 0.1
	for actor in world.things:
		if not is_instance_valid(actor): continue
		actor.set_process(false)
		actor.set_physics_process(false)
		if actor.has_meta("story_villager_subtype"):
			actor._physics_process(0.1)
			actor._process(0.1)
	world.dialogue.stop()
	world.story_vm.tick()
	world._update_camera()
	await process_frame


func mouse_click(world: Node, screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.button_index = MOUSE_BUTTON_RIGHT
	world.loaded = true
	event.pressed = true
	world._unhandled_input(event)
	event.pressed = false
	world._unhandled_input(event)
	world.loaded = false


func verify_key_delivery(world: Node) -> void:
	world.story_vm.isolate_unbound_tasks = true
	world.story_vm.strict_scripts = PackedStringArray(["ChooseYourCreature", "ProtectGateKey2", "AdvisorSpotsGateKey2"])
	for i in 80: await source_step(world)
	check(world.story_vm.error.is_empty(), "original keeper cleanup and waiting key loop execute without a missing native")
	var key := world.story_bridge._object(world.story_vm.variables[89]) as Thing
	check(key != null and key.story_pickup_allowed and key.story_move_allowed, "original keeper unlocks the actual tiger key")
	if key == null: return
	check(not key.get_children().filter(func(n:Node): return n.get_script() == preload("res://scripts/story_object_highlight.gd")).is_empty(), "original key protection attaches its requested persistent object highlight")
	check(world.story_gate_plinth.info_bits() == 0 and StoryVm.as_float(world.story_vm.variables[92]) == 0.0, "waiting and seeing the key do not complete the first key objective")
	# Trees are real cursor occluders now. Choose a view of the real key rather
	# than relying on the old terrain-only picking ray through a nearby tree.
	var key_point := key.position + Vector3(0, 1.5, 0)
	var visible_key := false
	for angle in 16:
		var heading := float(angle) * TAU / 16.0
		world.cam.position = key_point + Vector3(sin(heading) * 15, 20, cos(heading) * 15)
		world.cam.look_at(key_point)
		if world.hand_target(world.cam.unproject_position(key_point)).get("pickup") == key:
			visible_key = true
			break
	check(visible_key, "actual first key can be targeted from a view unobstructed by trees")
	if not visible_key: return
	mouse_click(world, world.cam.unproject_position(key_point))
	check(world.held == key and key.state == Thing.State.HELD, "real mouse input picks up the original tiger key within its source influence")
	if world.held != key: return
	var plinth: OriginalLandmark = world.story_gate_plinth.landmark
	var centre: Vector3 = plinth.global_transform * plinth.rig.bounds.get_center()
	world.cam.position = centre + Vector3(12, 20, 30)
	world.cam.look_at(centre)
	var target: Vector2 = world.cam.unproject_position(centre)
	check(world.story_gate_plinth.ray_hit(world.cam.project_ray_origin(target), world.cam.project_ray_normal(target)) != null, "drop targets actual plinth triangles")
	mouse_click(world, target)
	check(world.held == null and not is_instance_valid(key) and world.story_gate_plinth.info_bits() == 2, "actual hand delivery consumes the carried key and installs its tiger mesh on the plinth")
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-key.png")
	for i in 150:
		await source_step(world)
		if world.story_journal.get(55, {}).get("success", 0.0) == 0.25 and world.story_camera.owner_task == 0: break
	check(world.story_vm.error.is_empty(), "first key reward cinema executes original source functions: " + str(world.story_vm.error))
	check(StoryVm.as_float(world.story_vm.variables[92]) == 1.0 and StoryVm.as_float(world.story_vm.variables[91]) == 0.0 and StoryVm.as_float(world.story_vm.variables[93]) == 0.0, "original CHL acknowledges only the physically delivered tiger key")
	check(world.story_journal.get(55, {}).get("success", 0.0) == 0.25, "original counted UPDATE_SNAPSHOT records first-key progress")
	check(world.story_vm.tasks.values().any(func(t:Dictionary): return t["script"] == "LostBrother") or world.story_vm.suspended.values().any(func(t:Dictionary): return t["script"] == "LostBrother"), "original first-key reaction starts LostBrother without pretending that later quest is complete")
	check(world.story_gate_plinth.info_bits() == 2 and world.story_gate_plinth.get_child_count() == 1, "reward preserves one visible installed stone and keeps the other slots empty")
