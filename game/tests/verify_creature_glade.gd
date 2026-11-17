extends "res://tests/verify_sculptor.gd"
## Continues actual three-stone source progression; no synthetic quest flags.
var glade_species := "cow"
var glade_ready_only := false

func _initialize() -> void:
	super._initialize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--species="): glade_species = arg.substr(10)
		if arg == "--glade-ready-only": glade_ready_only = true

func source_step(world: Node) -> void:
	await super.source_step(world)
	for actor in world.story_creatures:
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			actor.advance_story(0.1)

func verify_third_stone(world: Node, quarry: Thing) -> void:
	await super.verify_third_stone(world, quarry)
	if failed > 0: return
	world.story_vm.strict_scripts.append_array(PackedStringArray(["CreaturesInGlade", "CreaturesPlayVarietyOfAnims"]))
	if not await until(world, func() -> bool:
		for task in world.story_vm.tasks.values():
			if task["script"] == "CreaturesInGlade" and task["pc"] >= 40344 and world.story_camera.owner_task == 0:
				return true
		return false, "original creature-glade cinema reaches genuine player choice", 8000): return
	check(world.story_creatures.size() == 3 and world.creature == null and not world.story_bridge.profile_has_creature, "seeing the three source-created creatures does not choose one")
	var glade: Dictionary
	for task in world.story_vm.tasks.values():
		if task["script"] == "CreaturesInGlade": glade = task
	for i in 3:
		var actor := world.story_bridge._object(glade["locals"][i]) as IslandCreature
		check(actor != null and actor.species == ["cow", "ape", "tiger"][i] and actor.rig.bone_count == [48,76,51][i], "source creature %s uses its own installed skeleton" % ["cow", "ape", "tiger"][i])
		if actor == null: return
		print("GLADE ACTOR ", actor.species, " position=", actor.position, " ground=", world.ground_y(actor.position))
		check(actor.story_actor and actor.story_script_controlled and not actor.following and actor.story_player_id == -1, "unchosen creature does not run the sandbox or acquire player ownership")
	for i in [13,14]:
		var gate := world.story_bridge._object(glade["locals"][i]) as OriginalLandmark
		check(gate != null and gate.gate_open, "source opens the actual glade landmark %d through its original clip" % i)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		print("GLADE HANDOVER camera=",world.cam.position," focus=",world.focus," source_eye=",world.story_camera.eye," source_focus=",world.story_camera.focus)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-glade.png")
	if glade_ready_only or failed > 0: return
	var slot: int = ["cow", "ape", "tiger"].find(glade_species)
	check(slot in [0,1,2], "requested choice belongs to the original three creatures")
	if slot not in [0,1,2]: return
	var selected := world.story_bridge._object(glade["locals"][slot]) as IslandCreature
	view(world, selected.position + Vector3.UP * 1.5, 15.0)
	print("GLADE VIEW camera=",world.cam.position," focus=",world.focus," selected=",selected.position)
	for click in [1,2]:
		var screen := creature_screen(world, selected)
		check(screen.is_finite(), "actual %s mesh is selectable for Action%d" % [glade_species,click])
		if not screen.is_finite(): return
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		world.loaded = true
		world._unhandled_input(motion)
		world._update_world(0.1)
		world.loaded = false
		mouse_click(world, screen)
		check(world.held == null and world.story_bridge.clicked_thing != null and world.story_bridge.clicked_thing.get_ref() == selected, "Action clicks the actual creature rather than picking up a neighbouring object")
		if not await until(world, func() -> bool: return StoryVm.as_float(glade["locals"][slot+7]) >= float(click), "source acknowledges Action%d for %s" % [click, glade_species], 1000): return
		if click == 1:
			check(world.creature == null and world.story_creatures.size() == 3, "first Action asks for confirmation without changing ownership or deleting alternatives")
			for i in 10: await source_step(world)
	var reached := false
	for i in 8000:
		await source_step(world)
		var problem: Dictionary = world.story_vm.error
		if not problem.is_empty():
			check(false,"source creature choice blocked: "+str(problem))
			return
		if world.creature == selected and world.story_creatures.size() == 1 and not selected.story_script_controlled and world.story_camera.owner_task == 0 and world.story_vm.finished.values().any(func(t:Dictionary):return t["script"]=="CreaturesInGlade"):
			reached = true
			break
	check(reached and world.creature == selected and world.story_creatures.size() == 1 and not selected.story_script_controlled and world.story_camera.owner_task == 0,"source confirms the chosen creature, deletes actual alternatives and restores control")
	if not reached: return
	check(selected.story_player_id == 1 and world.story_bridge.profile_has_creature and selected.story_home.is_finite(), "source-selected actor has actual player ownership and home position")
	check(selected.story_development_phase==0 and selected.story_desires.size()==40 and selected.story_tether_center==selected.story_home and selected.story_tether_radius==12.0,"source development initialization applies the installed desire mask and home tether")
	check(StoryVm.as_float(world.story_vm.variables[2]) == 1.0, "source alone records creature selection")
	print("GLADE RESULT species=",selected.species," source_selected=",StoryVm.as_float(world.story_vm.variables[2])," journal=",world.story_journal.get(55,{}).get("success",-1.0)," pending=",world.story_vm.error)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		view(world, selected.position + Vector3.UP * 1.5, 15.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-chosen-" + glade_species + ".png")


func creature_screen(world: Node, actor: IslandCreature) -> Vector2:
	# A sitting tiger does not fill its standing bind-pose AABB. Search real
	# visible triangles at several body heights, with declared fixture views.
	for angle in 16:
		world.yaw = float(angle) * TAU / 16.0
		world._update_camera()
		for centre in [actor.position+Vector3.UP,actor.position+Vector3.UP*2.0,actor.rig.root.global_transform*actor.rig.bounds.get_center()]:
			if world.cam.is_position_behind(centre): continue
			var screen: Vector2 = world.cam.unproject_position(centre)
			for offset in [Vector2.ZERO,Vector2(10,0),Vector2(-10,0),Vector2(0,-15),Vector2(0,15),Vector2(0,-30),Vector2(0,30)]:
				var point: Vector2 = screen + offset
				if root.get_visible_rect().has_point(point) and world.hand_target(point).get("story_creature") == actor: return point
	return Vector2.INF
