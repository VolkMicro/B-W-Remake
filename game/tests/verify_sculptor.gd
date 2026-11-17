extends "res://tests/verify_lost_brother.gd"
## Focused post-keeper sculptor fixture. Camera placement is a test setup;
## the sculptor, quarry rock, crafting timer, third stone and its delivery are
## driven by real source/input. Creature choice is deliberately not exercised.

# Source script coordinates of the SetupLand1 quarry and sculptor markers.
const QUARRY_MARKER := [1410.94396972656, 61.4570007324219, 2349.5048828125]
const SCULPTOR_MARKER := [1768.98803710938, 28.8099994659424, 2690.7060546875]

func source_step(world: Node) -> void:
	await super.source_step(world)
	# The parent freezes ordinary bodies in this off-main-loop fixture. Drive
	# real flight explicitly so a released quarry rock can physically settle.
	for actor in world.things:
		if is_instance_valid(actor) and not actor.has_meta("story_villager_subtype") and actor.state == Thing.State.FLYING:
			actor._physics_process(0.1)

func until(world: Node, predicate: Callable, label: String, turns := 2000) -> bool:
	for i in turns:
		await source_step(world)
		if not world.story_vm.error.is_empty():
			check(false, label + ": " + str(world.story_vm.error))
			return false
		for problem in world.story_vm.suspended.values():
			if str(problem.get("script", "")) in ["TheSculptor", "SetupSculptor", "KeepRockScripted", "SculptorSculptingOutside", "SculptorSculpting", "AdvisorSpotsRock", "CreatureRetrieveRockReturned", "ProtectQuarryRock", "ProtectGateKey3"]:
				check(false, label + ": original source blocked: " + str(problem))
				return false
		if predicate.call():
			check(true, label)
			return true
	check(false, label + ": timeout; pending=" + str(world.story_vm.tasks.values().map(func(t:Dictionary): return [t["script"], t["pc"]])))
	return false


func verify_key_delivery(world: Node) -> void:
	# The fixture starts after SetupLand1 rather than ProtectGateKeys. Bind the
	# existing quarry rock through the source CALL_NEAR query and start the
	# source ProtectQuarryRock, just as the parent binds the existing tiger key.
	# Do not change any quest/progress flags.
	var bridge: StoryNatives = world.story_bridge
	var vars: Array = world.story_vm.variables
	for marker in [[97, QUARRY_MARKER], [98, SCULPTOR_MARKER]]:
		if bridge._object(vars[marker[0]]) is Node3D: continue
		var created := bridge.invoke(27, [StoryVm.integer(1), StoryVm.integer(0)] + marker[1].map(func(v): return StoryVm.number(v)), {})
		check(created.get("ok", false) and created.get("push", []).size() == 1, "source marker %d is created with SetupLand1 parameters" % marker[0])
		if failed > 0: return
		vars[marker[0]] = created["push"][0]
		print("SCULPTOR precondition: created missing SetupLand1 marker ", marker[0])
	var quarry: Thing
	for rock in world.story_mobile_statics:
		if rock.get_meta("story_mobile_subtype", -1) == 50:
			check(quarry == null, "installed island has exactly one original quarry rock")
			quarry = rock
	check(quarry != null, "original quarry rock already exists in the installed island")
	if quarry == null: return
	var quarry_id := bridge.register_object(quarry, 8)
	var near := bridge.invoke(51, [StoryVm.integer(8), StoryVm.integer(50)] + QUARRY_MARKER.map(func(v): return StoryVm.number(v)) + [StoryVm.number(30.0), StoryVm.integer(0)], {})
	check(near.get("ok", false) and near.get("push", []).size() == 1 and StoryVm.as_int(near["push"][0]) == quarry_id, "source CALL_NEAR(8, 50, quarry marker, 30) resolves the installed quarry rock")
	if failed > 0: return
	vars[95] = near["push"][0]
	world.story_vm.start("ProtectQuarryRock", [vars[98], vars[97]])
	check(world.story_vm.error.is_empty(), "source ProtectQuarryRock accepts the quarry and sculptor markers: " + str(world.story_vm.error))
	if failed > 0: return
	await super.verify_key_delivery(world)
	if failed > 0: return
	await verify_third_stone(world, quarry)


func verify_third_stone(world: Node, quarry: Thing) -> void:
	var vars: Array = world.story_vm.variables
	world.story_vm.strict_scripts.append_array(PackedStringArray(["TheSculptor", "SetupSculptor", "KeepRockScripted", "SculptorSculptingOutside", "SculptorSculpting", "AdvisorSpotsRock", "CreatureRetrieveRockReturned", "ProtectQuarryRock", "ProtectGateKey3"]))
	var found := {}
	if not await until(world, func() -> bool:
		for highlight in world.story_highlights:
			if highlight.get_meta("challenge", -1) == 20: found["scroll"] = highlight
		return found.has("scroll"), "original TheSculptor creates its own golden scroll"): return
	var scroll: Node3D = found["scroll"]
	check(world.story_gate_plinth.info_bits() == 3 and StoryVm.as_float(vars[93]) == 0.0 and StoryVm.as_float(vars[135]) == 0.0, "the sculptor scroll alone neither crafts nor delivers the third stone")
	check(is_instance_valid(quarry) and not world.story_mobile_statics.any(func(m): return is_instance_valid(m) and m.get_meta("story_mobile_subtype", -1) == 51), "no third stone exists before the sculptor has crafted it")
	view(world, scroll.position)
	scroll.advance(0.0, world.cam)
	var scroll_point: Vector3 = scroll.visual.global_transform * scroll.visual.mesh.get_aabb().get_center()
	mouse_click(world, world.cam.unproject_position(scroll_point))
	check(scroll.active, "mouse Action activates the actual sculptor scroll")
	var actors := {}
	if not await until(world, func() -> bool:
		for task in world.story_vm.tasks.values():
			if task["script"] != "TheSculptor": continue
			var sculptor: Node3D = world.story_bridge._object(task["locals"][1])
			if sculptor != null and task["pc"] >= 35953 and world.story_camera.owner_task == 0:
				actors["task"] = task
				actors["sculptor"] = sculptor
				return true
		return false, "source sculptor introduction plays and returns camera control", 4000): return
	var sculptor: Thing = actors["sculptor"]
	check(sculptor.state != Thing.State.DEAD and sculptor.story_health > 0.0 and sculptor.story_pickup_allowed, "original sculptor survives the cinema and is released to the player")
	check(is_instance_valid(quarry) and world.story_bridge._object(vars[95]) == quarry, "source keeps the original quarry rock bound after the introduction")
	if not is_instance_valid(quarry): return
	view(world, quarry.position)
	var pickup := visible_pickup(world, quarry)
	check(pickup.is_finite(), "actual quarry rock is visible and selectable")
	if not pickup.is_finite(): return
	mouse_click(world, pickup)
	check(world.held == quarry and quarry.state == Thing.State.HELD, "Action picks up the original quarry rock")
	if world.held != quarry: return
	view(world, sculptor.position)
	var drop: Vector3 = sculptor.position + Vector3(5.0, 0, 0)
	drop.y = world.ground_y(drop)
	check(world.has_influence(drop), "release point beside the sculptor lies within player influence")
	var drop_screen: Vector2 = world.cam.unproject_position(drop)
	var move := InputEventMouseMotion.new()
	move.position = drop_screen
	world.loaded = true
	world._unhandled_input(move)
	world._update_world(0.1)
	world.loaded = false
	mouse_click(world, drop_screen)
	check(world.held == null and quarry.state == Thing.State.FLYING and not quarry.thrown, "slow Action release drops the quarry rock through physical flight")
	if not await until(world, func() -> bool: return not is_instance_valid(quarry) or quarry.state != Thing.State.FLYING, "quarry rock settles on the real island"): return
	check(is_instance_valid(quarry) and Vector2(quarry.position.x - sculptor.position.x, quarry.position.z - sculptor.position.z).length() < 15.0 and sculptor.state != Thing.State.DEAD, "quarry rock lands within the source delivery range of the living sculptor")
	if not await until(world, func() -> bool: return StoryVm.as_float(vars[136]) == 1.0 and StoryVm.as_float(vars[137]) == 1.0 and world.story_camera.owner_task == 0 and not world.story_vm.tasks.values().any(func(t:Dictionary): return t["script"] == "CreatureRetrieveRockReturned"), "source sculptor accepts the rock and starts carving", 4000): return
	check(is_instance_valid(quarry) and not quarry.story_pickup_allowed, "accepted rock is locked while the sculptor carves it")
	check(sculptor.state != Thing.State.DEAD and sculptor.story_health > 0.0, "sculptor survives walking to the delivered rock")
	found["steps"] = 0
	if not await until(world, func() -> bool:
		found["steps"] += 1
		var key: Object = world.story_bridge._object(vars[90])
		if key is Thing and key.get_meta("story_mobile_subtype", -1) == 51 and StoryVm.as_float(vars[135]) == 1.0 and world.story_camera.owner_task == 0:
			found["key"] = key
			return true
		return false, "original crafting timer completes and source creates the third stone", 8000): return
	var reward: Thing = found["key"]
	print("SCULPTOR crafting source steps: ", found["steps"])
	# The source carving timer is 60 s; each fixture source step advances 0.1 s.
	check(found["steps"] >= 600, "third stone is not produced before the source sixty-second crafting timer advances")
	check((not is_instance_valid(quarry) or quarry.get_meta("story_deleted", false)) and StoryVm.as_float(vars[96]) == 1.0, "source consumes the original quarry rock when the third stone is created")
	check(world.story_gate_plinth.info_bits() == 3 and StoryVm.as_float(vars[93]) == 0.0, "creating the third stone does not count as delivering it")
	check(world.story_vm.tasks.values().any(func(t:Dictionary): return t["script"] == "ProtectGateKey3"), "source protects the crafted third stone")
	view(world, reward.position)
	pickup = visible_pickup(world, reward)
	check(pickup.is_finite(), "crafted original stone is visible and selectable")
	if not pickup.is_finite(): return
	check(world.has_influence(reward.position), "player influence reaches the crafted stone")
	mouse_click(world, pickup)
	check(world.held == reward, "Action picks up the real crafted third stone")
	if world.held != reward: return
	var plinth: OriginalLandmark = world.story_gate_plinth.landmark
	var centre: Vector3 = plinth.global_transform * plinth.rig.bounds.get_center()
	view(world, centre, 38.0)
	mouse_click(world, world.cam.unproject_position(centre))
	check(world.held == null and not is_instance_valid(reward) and world.story_gate_plinth.info_bits() == 7 and world.story_gate_plinth.get_child_count() == 3, "physical hand delivery installs exactly three original stones")
	if not await until(world, func() -> bool: return StoryVm.as_float(vars[93]) == 1.0 and (world.story_vm.tasks.values().any(func(t:Dictionary): return t["script"] == "CreaturesInGlade") or world.story_vm.finished.values().any(func(t:Dictionary): return t["script"] == "CreaturesInGlade")), "original source acknowledges the third stone and starts CreaturesInGlade", 4000): return
	check(StoryVm.as_float(vars[91]) == 1.0 and StoryVm.as_float(vars[92]) == 1.0, "all three genuinely delivered source objectives are acknowledged")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-third-stone.png")
