extends "res://tests/verify_story_scrolls.gd"
## Focused post-keeper integration fixture. Camera placement is a test setup;
## actors, reward/completion and both deliveries are driven by real source/input.
## Full input-only camera traversal belongs to verify_opening_runtime.

func _initialize() -> void:
	super._initialize()
	deliver_key = true


func source_step(world: Node) -> void:
	await super.source_step(world)
	# The off-main-loop fixture must advance the real recorded reminder and
	# the caller-clocked weather, just as the live scene does each frame.
	world.story_advance_hand_demo(0.1)
	world._advance_story_weather(0.1)


func verify_key_delivery(world: Node) -> void:
	verify_actor_contract(world)
	# This fixture starts after SetupLand1 rather than FollowUs. Bind the
	# existing house key as a declared precondition, just as the parent does
	# for the existing tiger key. Do not change any quest/progress flags.
	var reward: Thing
	for key in world.story_mobile_statics:
		if key.get_meta("story_mobile_subtype", -1) == 49:
			reward = key
			world.story_vm.variables[88] = StoryVm.integer(world.story_bridge.register_object(key, 8), StoryVm.OBJECT)
	check(reward != null, "second stone already exists in the installed island")
	world.story_vm.start("ProtectGateKey1", [world.story_vm.variables[84]])
	await super.verify_key_delivery(world)
	if failed > 0: return
	world.story_vm.strict_scripts.append_array(PackedStringArray(["LostBrother", "GiveReward", "HeadingHome", "ProtectGateKey1"]))
	check(not reward.story_pickup_allowed and world.story_gate_plinth.info_bits() == 2, "waiting for rescue leaves the reward locked and only the first stone installed")
	var scroll: Node3D
	for highlight in world.story_highlights:
		if highlight.get_meta("challenge", -1) == 19: scroll = highlight
	check(scroll != null, "original LostBrother creates its own golden scroll")
	if scroll == null: return
	view(world, scroll.position)
	scroll.advance(0.0, world.cam)
	var scroll_point: Vector3 = scroll.visual.global_transform * scroll.visual.mesh.get_aabb().get_center()
	mouse_click(world, world.cam.unproject_position(scroll_point))
	check(scroll.active, "mouse Action activates the actual lost-brother scroll")
	var siblings := {}
	if not await until(world, func() -> bool:
		for task in world.story_vm.tasks.values():
			if task["script"] != "LostBrother": continue
			var sister: Node3D = world.story_bridge._object(task["locals"][4])
			var brother: Node3D = world.story_bridge._object(task["locals"][5])
			if sister != null and brother != null and task["pc"] >= 33915 and world.story_camera.owner_task == 0:
				siblings["sister"] = sister
				siblings["brother"] = brother
				return true
		return false, "source introduction creates and animates both siblings, then returns control"): return
	var sister: Thing = siblings["sister"]
	var brother: Thing = siblings["brother"]
	check(brother.story_health > 0.0 and brother.story_health < 1.0 and brother.state != Thing.State.DEAD, "original brother begins injured and alive")
	check(not reward.story_pickup_allowed and world.story_journal[55]["success"] == 0.25, "seeing the brother does not manufacture the second reward")
	view(world, brother.position)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-storm.png")
	var pickup := visible_pickup(world, brother)
	check(pickup.is_finite(), "actual sick brother can be selected without clicking an occluding tree")
	if not pickup.is_finite(): return
	mouse_click(world, pickup)
	check(world.held == brother and brother.state == Thing.State.HELD, "Action picks up the living brother")
	if world.held != brother: return
	view(world, sister.position)
	var drop: Vector3 = sister.position + Vector3(2.5, 0, 0)
	drop.y = world.ground_y(drop)
	var drop_screen: Vector2 = world.cam.unproject_position(drop)
	var move := InputEventMouseMotion.new()
	move.position = drop_screen
	world.loaded = true
	world._unhandled_input(move)
	world._update_world(0.1)
	world.loaded = false
	mouse_click(world, drop_screen)
	check(world.held == null and brother.state == Thing.State.FLYING and not brother.thrown, "slow Action release drops the brother through physical flight")
	if not await until(world, func() -> bool: return brother.state != Thing.State.FLYING, "brother settles on the real island"): return
	check(brother.state != Thing.State.DEAD and brother.story_health > 0.0 and Vector2(brother.position.x - sister.position.x, brother.position.z - sister.position.z).length() < 10.0, "living brother lands within reunion distance of his sister")
	if not await until(world, func() -> bool: return reward.story_pickup_allowed and reward.story_move_allowed and StoryVm.as_float(world.story_vm.variables[129]) == 1.0 and world.story_camera.owner_task == 0 and world.story_interface_level == 0 and not world.story_hand_demo.playing, "source reunion and GiveReward unlock the existing second stone"): return
	check(world.story_gate_plinth.info_bits() == 2 and world.story_journal[55]["success"] == 0.25, "receiving a reward does not count as delivering it")
	view(world, reward.position)
	pickup = visible_pickup(world, reward)
	check(pickup.is_finite(), "rewarded original stone is visible and selectable")
	if not pickup.is_finite(): return
	check(world.has_influence(reward.position), "original key protection supplies influence at the reunion reward")
	mouse_click(world, pickup)
	check(world.held == reward, "Action picks up the real reunion reward")
	if world.held != reward: return
	var plinth: OriginalLandmark = world.story_gate_plinth.landmark
	var centre: Vector3 = plinth.global_transform * plinth.rig.bounds.get_center()
	view(world, centre, 38.0)
	mouse_click(world, world.cam.unproject_position(centre))
	check(world.held == null and not is_instance_valid(reward) and world.story_gate_plinth.info_bits() == 3 and world.story_gate_plinth.get_child_count() == 2, "physical hand delivery installs exactly two original stones")
	if not await until(world, func() -> bool: return world.story_journal[55]["success"] == 0.5 and world.story_camera.owner_task == 0, "original keeper cinema acknowledges the second delivered stone"): return
	check(StoryVm.as_float(world.story_vm.variables[91]) == 1.0 and StoryVm.as_float(world.story_vm.variables[92]) == 1.0 and StoryVm.as_float(world.story_vm.variables[93]) == 0.0, "only the two genuinely delivered source objectives are acknowledged")
	check(world.story_vm.tasks.values().any(func(t:Dictionary): return t["script"] == "TheSculptor") or world.story_vm.finished.values().any(func(t:Dictionary): return t["script"] == "TheSculptor"), "source starts the next quest without completing the third stone or creature choice")


func verify_actor_contract(world: Node) -> void:
	var bridge: StoryNatives = world.story_bridge
	var none := StoryVm.integer(0, StoryVm.OBJECT)
	var probe := Thing.new()
	probe.kind = "villager"
	probe.world = world
	var handle := StoryVm.integer(bridge.register_object(probe, 4), StoryVm.OBJECT)
	var life := [StoryVm.integer(1), handle]
	check(bridge.invoke(22, life + [StoryVm.number(0.4)], {}).get("ok", false) and is_equal_approx(probe.story_health, 0.4), "health writes preserve a living injured actor")
	check(not bridge.invoke(22, life + [StoryVm.number(NAN)], {}).get("ok", false) and not bridge.invoke(22, life + [StoryVm.number(-1)], {}).get("ok", false) and is_equal_approx(probe.story_health, 0.4), "invalid health writes are rejected without mutation")
	bridge.invoke(298, [StoryVm.integer(1), handle], {})
	bridge.invoke(22, life + [StoryVm.number(0)], {})
	bridge.invoke(22, life + [StoryVm.number(0.01)], {})
	check(is_equal_approx(probe.story_health, 0.4) and probe.state != Thing.State.DEAD, "indestructible ignores lethal health writes without healing the actor")
	bridge.invoke(22, life + [StoryVm.number(0.2)], {})
	check(is_equal_approx(probe.story_health, 0.2), "indestructible still permits nonlethal injury")
	bridge.invoke(298, [StoryVm.integer(0), handle], {})
	bridge.invoke(22, life + [StoryVm.number(0)], {})
	check(probe.state == Thing.State.DEAD and probe.story_health == 0.0 and not bridge.invoke(22, life + [StoryVm.number(1)], {}).get("ok", false), "unprotected zero health kills and health writes cannot revive the actor")
	var missing := bridge.invoke(21, [StoryVm.integer(9999), none], {})
	check(missing.get("ok", false) and missing.get("push", []) == [StoryVm.number(0)], "GET_PROPERTY on NULL returns numeric zero before property dispatch")
	probe.set_meta("story_deleted", true)
	var deleted := bridge.invoke(21, life, {})
	check(deleted.get("ok", false) and deleted.get("push", []) == [StoryVm.number(0)] and bridge._object(handle) == null, "a visibly fading actor is already absent from script handles")
	var attach := bridge.invoke(37, [none, handle, StoryVm.integer(0)], {})
	check(attach.get("ok", false) and attach.get("push", []) == [none], "ATTACH with a missing actor or container returns a NULL object")
	check(bridge.invoke(159, [none], {}).get("ok", false) and bridge.invoke(48, [none, StoryVm.integer(1)], {}).get("ok", false), "release and supported deletion tolerate source cleanup of an absent actor")
	check(not bridge.invoke(48, [none, StoryVm.integer(2)], {}).get("ok", false), "unimplemented deletion modes remain unsupported")
	probe.free()
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-second-stone.png")


func until(world: Node, predicate: Callable, label: String, turns := 2000) -> bool:
	for i in turns:
		await source_step(world)
		if not world.story_vm.error.is_empty():
			check(false, label + ": " + str(world.story_vm.error))
			return false
		if predicate.call():
			check(true, label)
			return true
	check(false, label + ": timeout; pending=" + str(world.story_vm.tasks.values().map(func(t:Dictionary): return [t["script"], t["pc"]])))
	return false


func view(world: Node, point: Vector3, distance := 45.0) -> void:
	world.focus = point
	world.dist = distance
	world.yaw = 0.0
	world.pitch = PI / 3.0
	world._update_camera()
	world.story_camera.update_player_pose(world.cam.position, point)


func visible_pickup(world: Node, actor: Thing) -> Vector2:
	var point: Vector3 = actor.position + Vector3.UP * 1.5
	for angle in 16:
		world.yaw = float(angle) * TAU / 16.0
		world._update_camera()
		for offset in [Vector2.ZERO, Vector2(10, 0), Vector2(-10, 0), Vector2(0, -10)]:
			var screen: Vector2 = world.cam.unproject_position(point) + offset
			if world.hand_target(screen).get("pickup") == actor: return screen
	return Vector2.INF
