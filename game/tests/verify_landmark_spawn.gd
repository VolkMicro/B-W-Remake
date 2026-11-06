# Construct the island objects without entering the scene tree or running a game.
extends SceneTree

var source := ""
var failures: Array[String] = []
var passed := 0
var probe_script := ""
var probe_simulate := false
var probe_follow_family := false
var probe_ticks := 300


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
		elif arg.begins_with("--probe="):
			probe_script = arg.substr(8)
		elif arg == "--simulate":
			probe_simulate = true
		elif arg == "--follow-family":
			probe_follow_family = true
		elif arg.begins_with("--ticks="):
			probe_ticks = clampi(arg.substr(8).to_int(), 1, 10000)
	call_deferred("run_test")


func check(ok: bool, name: String) -> void:
	if ok:
		passed += 1
		print("PASS ", name)
	else:
		failures.append(name)
		printerr("FAIL ", name)


func run_test() -> void:
	var world = load("res://scripts/main.gd").new()
	var data = preload("res://scripts/data.gd")
	world.bw_dir = source
	var opened: bool = source != "" and world.lnd.load_file(source.path_join(data.SOURCES["landscape"]))
	opened = opened and world.g3d.open(source.path_join(data.SOURCES["meshes"]), source.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(source.path_join(data.SOURCES["object_info"]), world.g3d.mesh_offsets.size())
	opened = opened and world.island.load_file(source.path_join(data.SOURCES["island_script"]))
	opened = opened and world._load_landmark_animations()
	check(opened, "open original island, model and object information")
	if opened:
		world.sea_y = world.lnd.sea_level
		world._spawn_objects()
		var expected: int = world.island.all("CREATE_ABODE").size() + world.island.all("CREATE_TOWN_CENTRE").size() + world.island.all("CREATE_NEW_FEATURE").size() + world.island.all("CREATE_ANIMATED_STATIC").size()
		check(world.story_landmarks.size() == expected, "all original abode, feature, gate and cave objects are instantiated")
		var centres := 0
		var source_angles := true
		for landmark in world.story_landmarks:
			if str(landmark.get_meta("original_type", "")).ends_with("ABODE_TOWN_CENTRE"):
				centres += 1
				for command in world.island.all("CREATE_TOWN_CENTRE"):
					var a: PackedStringArray = command["args"]
					if a[2] == landmark.get_meta("original_type"):
						var original := float(a[3]) / 1000.0
						source_angles = source_angles and landmark.basis.x.distance_to(Vector3(cos(original), 0, -sin(original)) * (float(a[4]) / 1000.0)) < 0.001
		check(centres == 2 and source_angles, "both original village centres load at their source rotation and scale")
		var bridge := StoryNatives.new()
		bridge.configure(world)
		check(bridge.register_landmarks(world.story_landmarks) == expected, "story bridge registers the actual island landmark instances")
		var cave_search := [StoryVm.integer(3), StoryVm.integer(5000), StoryVm.number(1970.8, StoryVm.VECTOR), StoryVm.number(64.4613, StoryVm.VECTOR), StoryVm.number(2812.12, StoryVm.VECTOR), StoryVm.integer(0, StoryVm.BOOL)]
		var home_search := [StoryVm.integer(2), StoryVm.integer(5000), StoryVm.number(1713.83, StoryVm.VECTOR), StoryVm.number(18.09, StoryVm.VECTOR), StoryVm.number(2592.59, StoryVm.VECTOR), StoryVm.integer(0, StoryVm.BOOL)]
		var cave_result := bridge.invoke(26, cave_search, {})
		var home_result := bridge.invoke(26, home_search, {})
		check(cave_result.get("ok", false) and home_result.get("ok", false) and StoryVm.as_int(cave_result["push"][0]) != StoryVm.as_int(home_result["push"][0]), "story queries resolve to the actual original cave and house")
		var original_ready: bool = world.campaign.load_file(source.path_join("Scripts/Quests/challenge.chl"))
		if original_ready:
			if probe_script.is_empty() or probe_script == "FollowUs":
				world._start_story()
			else:
				world._start_story(probe_script)
			if probe_script == "FollowUs":
				for ignored in 300:
					if not world.story_vm.tick() or world.story_vm.finished.has(1): break
				if world.story_vm.error.is_empty() and world.story_vm.finished.has(1):
					world.story_vm.start(probe_script)
			for ignored in probe_ticks:
				if not world.story_vm.tick(): break
				if probe_simulate:
					for step in 6:
						for thing in world.things:
							if thing.has_meta("story_villager_subtype"):
								thing._physics_process(1.0 / 60.0)
					for thing in world.things:
						if thing.has_meta("story_villager_subtype"):
							thing._process(0.1)
							if probe_follow_family and thing.get_meta("story_villager_subtype") == 53 and not world.story_hand_demo.frames.is_empty():
								world.story_camera.update_player_pose(thing.position + Vector3(5.0, 30.0, 0.0), thing.position)
					world.story_camera.advance(0.1)
					world.story_advance_hand_demo(0.1)
					for shark in world.story_sharks:
						if is_instance_valid(shark):
							shark._process(0.1)
		if not probe_script.is_empty():
			var probe_vm: StoryVm = world.story_vm
			if probe_script in ["LandControl1", "FollowUs"]:
				var family := {}
				for thing in world.things:
					if thing.has_meta("story_villager_subtype"):
						var subtype: int = thing.get_meta("story_villager_subtype")
						if not family.has(subtype):
							family[subtype] = thing.get_meta("story_spawn_position")
				var positions := {49: Vector3(1578.433, 12.727, -2220.541), 53: Vector3(1577.822, 12.513, -2221.067), 52: Vector3(1579.006, 11.458, -2220.133)}
				for subtype in positions:
					check(family.has(subtype) and family[subtype].distance_to(positions[subtype]) < 0.002, "FollowUs spawns villager subtype %d at the original position" % subtype)
			check(probe_vm != null and probe_vm.error.is_empty(), "%s for up to %d ticks (error: %s)" % [probe_script, probe_ticks, probe_vm.error if probe_vm else "CHL unavailable"])
			if probe_vm != null and not probe_vm.error.is_empty():
				var blocked: Dictionary = probe_vm.tasks.get(probe_vm.error.get("task", -1), {})
				print("BLOCKED STACK ", blocked.get("stack", []))
			elif probe_vm != null:
				for task in probe_vm.tasks.values():
					print("ACTIVE ", task["script"], " pc=", task["pc"], " state=", task["state"])
				if probe_simulate:
					for thing in world.things:
						if thing.has_meta("story_villager_subtype"):
							print("ACTOR ", thing.get_meta("story_villager_subtype"), " ", thing.position, " anim=", thing._script_clip, " ", thing._script_clip_age, "/", thing._script_clip_end,
								" move=", thing._script_move_active, " target=", thing._script_move_target)
			finish(world)
			return
		var vm: StoryVm = world.story_vm
		check(original_ready and vm != null and vm.error.is_empty(), "the real first-island setup runs with no unported function (error: %s)" % (vm.error if vm else "none"))
		if vm != null:
			var camera_points := {81: Vector3(4484.2822, 2045.168, 6380.063), 82: Vector3(1634.6915, 5.5111, 2118.2815)}
			for native in camera_points:
				var reply: Dictionary = world.story_bridge.invoke(native, [StoryVm.integer(199)], {})
				var point := Vector3.INF
				if reply.get("ok", false):
					var coords: Array = reply["push"]
					point = Vector3(StoryVm.as_float(coords[0]), StoryVm.as_float(coords[1]), StoryVm.as_float(coords[2]))
				check(point.distance_to(camera_points[native]) < 0.001, "native %d reads the original Cam199 point in LHVM coordinates" % native)
			check(not world.story_bridge.invoke(82, [StoryVm.integer(-1)], {}).get("ok", false), "missing camera records block the native")
		check(vm != null and vm.finished.size() > 0, "SetupLand1 itself completes")
		check(not world.virtual_influence, "setup turns off virtual influence for player one, as the original does")
		var anti := 0
		for source_row in world.influence_sources:
			if source_row["anti"]:
				anti += 1
		check(world.influence_sources.size() == 2 and anti == 1, "setup creates the quarry influence and one anti-influence zone")
		check(world.story_highlights.size() == 11, "setup places the eleven original 'Did you know' highlights")
		var boosted := 0
		for town in world.towns:
			if town.has("desire_boosts"):
				boosted += 1
		check(boosted == 1, "setup boosts the desires of exactly one town")
		var home: Vector3 = world.towns[0]["pos"]
		check(world.has_influence(home) and not world.has_influence(home + Vector3(2000, 0, 2000)), "the Hand has influence at home and none far away")
		var anti_node: Node3D = null
		for source_row in world.influence_sources:
			if source_row["anti"]:
				anti_node = source_row["node"]
		check(anti_node != null and not world.has_influence(anti_node.position), "anti-influence blocks the Hand at its centre")
		var counts := {}
		var cave_at_story_site := false
		var scaled_home := false
		var animated_count := 0
		for node in world.story_landmarks:
			var original_type: String = node.get_meta("original_type", "")
			counts[original_type] = int(counts.get(original_type, 0)) + 1
			if original_type == "Piper Cave Entrance" and Vector2(node.position.x, -node.position.z).distance_to(Vector2(1970.8, 2812.12)) < 0.01:
				cave_at_story_site = node.get_meta("original_animation_id", -1) == 189 and is_equal_approx(node.scale.x, 1.0)
			if original_type == "NORSE_ABODE_C" and Vector2(node.position.x, -node.position.z).distance_to(Vector2(1755.09, 2692.52)) < 0.01:
				scaled_home = is_equal_approx(node.scale.x, 0.99)
			if node is OriginalLandmark:
				animated_count += 1
				var landmark: OriginalLandmark = node
				var started := landmark.play_original()
				var before: Array[Transform3D] = []
				for bi in landmark.rig.bone_count:
					before.append(landmark.rig.skeleton.get_bone_pose(bi))
				var duration: float = landmark.animations.clips[landmark.clip]["duration"]
				landmark.advance(duration * 0.75)
				var changed := 0
				for bi in landmark.rig.bone_count:
					if not before[bi].is_equal_approx(landmark.rig.skeleton.get_bone_pose(bi)):
						changed += 1
				landmark.advance(duration)
				check(started and changed > 0 and not landmark.playing, original_type + " plays and finishes its original animation on request")
		check(counts.get("Piper Cave Entrance", 0) == 2 and counts.get("Norse Gate", 0) == 1 and counts.get("Gate Stone Plinth", 0) == 1, "both caves and the original gate and plinth are present")
		check(cave_at_story_site, "story cave exists at the scripted position with its original animation ID")
		check(animated_count == 4, "each original gate and cave has a matching animation controller")
		check(scaled_home, "first village house is spawned at its original scale")
		if vm != null:
			verify_follow_us_child(world)
			verify_carried_resources(world)
		if vm != null:
			verify_original_story_animation(world)
			verify_original_welcome_dance(world)
			verify_hand_demo_and_citadel(world)
			verify_village_membership_and_keys(world)
		check(not world.is_inside_tree(), "the game scene was never entered or started")
	finish(world)


func verify_village_membership_and_keys(world: Node) -> void:
	var bridge: StoryNatives = world.story_bridge
	var villager: Thing = world.story_create_villager(53, world.town_nodes[0].position)
	var flock := StoryFlock.new()
	world.add_child(flock)
	flock.attach(villager, true)
	var person := StoryVm.integer(bridge.register_object(villager, 4), StoryVm.OBJECT)
	var town := StoryVm.integer(bridge.register_object(world.town_nodes[0], 9), StoryVm.OBJECT)
	var reply := bridge.invoke(37, [person, town, StoryVm.integer(0, StoryVm.BOOL)], {})
	check(reply.get("ok", false) and villager.story_flock == null and flock.members.is_empty() and villager.town == 0, "family returns from the welcome flock to its actual village")
	var key: Thing
	for mobile in world.story_mobile_statics:
		if mobile.get_meta("story_mobile_subtype", -1) == 49:
			key = mobile
			break
	check(key != null, "first original gate key is registered from the installed landscape")
	if key == null:
		return
	var args := [StoryVm.integer(8), StoryVm.integer(49), StoryVm.number(key.position.x, StoryVm.VECTOR), StoryVm.number(key.position.y, StoryVm.VECTOR), StoryVm.number(-key.position.z, StoryVm.VECTOR), StoryVm.number(20), StoryVm.integer(0, StoryVm.BOOL)]
	reply = bridge.invoke(51, args, {})
	check(reply.get("ok", false) and bridge._object(reply["push"][0]) == key, "ProtectGateKeys finds the real original key rather than a substitute")
	if not reply.get("ok", false):
		return
	var handle: Dictionary = reply["push"][0]
	var locked := bridge.invoke(169, [StoryVm.integer(0, StoryVm.BOOL), handle], {})
	check(locked.get("ok", false) and not key.story_pickup_allowed, "original opening locks gate-key pickup until its quest")
	key.state = Thing.State.HELD
	var in_hand := bridge.invoke(21, [StoryVm.integer(9), handle], {})
	key.state = Thing.State.FLYING
	var flying := bridge.invoke(21, [StoryVm.integer(5), handle], {})
	key.state = Thing.State.IDLE
	check(in_hand.get("ok", false) and flying.get("ok", false) and StoryVm.as_float(in_hand["push"][0]) == 1.0 and StoryVm.as_float(flying["push"][0]) == 1.0, "key protection reads actual held and flying physical states")


func verify_hand_demo_and_citadel(world: Node) -> void:
	var loaded: bool = world.story_play_hand_demo(279)
	check(loaded and world.story_hand_demo.frames.size() == 590, "read all frames of the original drag tutorial recording")
	if loaded:
		var eye: Vector3 = world.story_hand_demo.pose()["eye"]
		check(eye.distance_to(Vector3(1493.645, 13.934, -2091.68)) < 0.002, "first demo camera pose comes from the installed recording")
		world.story_advance_hand_demo(60.0)
		var frame: int = world.story_hand_demo.frame
		world.story_advance_hand_demo(1.0)
		check(world.story_hand_demo.frame == frame and world.story_hand_demo.consume_trigger(), "recorded tutorial pauses until the script consumes its cue")
	loaded = world.story_play_hand_demo(244)
	check(loaded and world.story_hand_demo.frames.size() == 484, "GiveFood resolves its original givewood recording and all frames")
	if loaded:
		check(not world.story_hand_demo.pose()["hand"].is_finite(), "uninitialised recorded hand coordinates never become a world position")
		var cues := 0
		for ignored in 1200:
			world.story_advance_hand_demo(0.1)
			if world.story_hand_demo.consume_trigger(): cues += 1
			if not world.story_hand_demo.playing: break
		var actions: Array = world.story_hand_demo.take_actions()
		check(not world.story_hand_demo.playing and cues == 4 and actions.size() == 4, "resource tutorial plays all four original speech cues and recorded pickup/drop actions")
	var site: Node3D = world.story_build_citadel(Vector3(1915.05, 0.0, -2508.89), 0.375)
	check(site != null and site.progress == 0.0 and is_equal_approx(site.forced_desire, 1.875) and site.model.get_child_count() > 0, "planned temple loads the installed construction mesh and requests building desire without instant completion")


func verify_follow_us_child(world: Node) -> void:
	var son: Thing = world.story_create_villager(52, Vector3(1579.006, 11.458, -2220.133))
	if son == null:
		check(false, "create the FollowUs son before the age change")
		return
	var bridge: StoryNatives = world.story_bridge
	var handle := StoryVm.integer(bridge.register_object(son, 4), StoryVm.OBJECT)
	var adult_rig := son.rig
	var set_age := bridge.invoke(22, [StoryVm.integer(16), handle, StoryVm.number(8)], {})
	var set_scale := bridge.invoke(22, [StoryVm.integer(8), handle, StoryVm.number(0.7)], {})
	var set_speed := bridge.invoke(22, [StoryVm.integer(11), handle, StoryVm.number(0.2)], {})
	check(set_age.get("ok", false) and son.story_age == 8 and son.rig != adult_rig and son.rig.bone_count > 0, "FollowUs age property replaces the adult with the original child's rig")
	check(set_scale.get("ok", false) and son.scale.is_equal_approx(Vector3.ONE * 0.7), "FollowUs scale property updates the son")
	check(set_speed.get("ok", false) and is_equal_approx(son.story_speed_per_turn, 0.2), "FollowUs speed property stores movement per game turn")


func verify_carried_resources(world: Node) -> void:
	var villager: Thing = world.story_create_villager(53, Vector3.ZERO)
	if villager == null:
		check(false, "create original villager for carried resources")
		return
	var bridge: StoryNatives = world.story_bridge
	var handle := StoryVm.integer(bridge.register_object(villager, 4), StoryVm.OBJECT)
	var food := bridge.invoke(134, [StoryVm.integer(0), StoryVm.number(148.9), handle], {})
	var wood := bridge.invoke(134, [StoryVm.integer(1), StoryVm.number(148), handle], {})
	check(food.get("ok", false) and wood.get("ok", false) and villager.story_resources == Vector2i(148, 148) and StoryVm.as_float(food["push"][0]) == 0.0, "ADD_RESOURCE stores both tutorial resources and returns the original zero result")
	var carried_food := villager.rig.skeleton.get_node_or_null("CarriedFood") as BoneAttachment3D
	var carried_wood := villager.rig.skeleton.get_node_or_null("CarriedWood") as BoneAttachment3D
	check(carried_food != null and carried_wood != null and carried_food.bone_idx == 11 and carried_wood.bone_idx == 14 and carried_food.get_child(0).mesh != null and carried_wood.get_child(0).mesh != null, "food and wood use installed meshes attached to the animated hands")
	bridge.invoke(134, [StoryVm.integer(0), StoryVm.number(65535), handle], {})
	check(villager.story_resources.x == 147 and villager.story_resources.y == 148, "carried resource addition wraps the original unsigned 16-bit field")
	var before := villager.story_resources
	var invalid := bridge.invoke(134, [StoryVm.integer(2), StoryVm.number(148), handle], {})
	check(not invalid.get("ok", false) and villager.story_resources == before, "unsupported resources leave carried inventory intact")


func verify_original_story_animation(world: Node) -> void:
	var villager: Thing = world.story_create_villager(52, Vector3.ZERO)
	if not is_instance_valid(villager):
		check(false, "create original scripted villager for animation")
		return
	var bridge: StoryNatives = world.story_bridge
	var handle := StoryVm.integer(bridge.register_object(villager, 4), StoryVm.OBJECT)
	var age := bridge.invoke(22, [StoryVm.integer(16), handle, StoryVm.number(8)], {})
	var prepared := bridge.invoke(20, [handle, StoryVm.integer(418), StoryVm.integer(2)], {})
	var started := bridge.invoke(17, [handle, StoryVm.integer(200)], {})
	check(age.get("ok", false) and prepared.get("ok", false) and started.get("ok", false), "LHVM starts the original son's animation by its archive index")
	if not started.get("ok", false):
		return
	villager._process(5.7)
	var halfway := bridge.invoke(64, [handle], {})
	check(halfway.get("ok", false) and StoryVm.as_int(halfway["push"][0]) == 0 and villager.animation_name == "M_P_Waiting_Impateintly", "PLAYED remains false during the second repeat of the original clip")
	villager._process(5.6)
	var finished := bridge.invoke(64, [handle], {})
	check(finished.get("ok", false) and StoryVm.as_int(finished["push"][0]) == 1, "PLAYED becomes true after both original clip durations")
	villager.set_script_move(Vector3(10, 0, 0), 0.0)
	var overridden := bridge.invoke(68, [handle, StoryVm.integer(351)], {})
	if overridden.get("ok", false):
		villager._process(0.1)
	check(overridden.get("ok", false) and villager.animation_name == "M_P_Run_Man", "the scripted move switches to its original run animation")


func verify_original_welcome_dance(world: Node) -> void:
	var bridge: StoryNatives = world.story_bridge
	var anchor: Thing = world.story_create_villager(49, Vector3.ZERO)
	var dancer: Thing = world.story_create_villager(53, Vector3.ZERO)
	if not is_instance_valid(anchor) or not is_instance_valid(dancer):
		check(false, "prepare real villagers for the original welcome dance")
		return
	var focus := StoryVm.integer(bridge.register_object(anchor, 4), StoryVm.OBJECT)
	var member := StoryVm.integer(bridge.register_object(dancer, 4), StoryVm.OBJECT)
	var center := [StoryVm.number(10, StoryVm.VECTOR), StoryVm.number(5, StoryVm.VECTOR), StoryVm.number(20, StoryVm.VECTOR)]
	var original_flock := bridge.invoke(36, center, {})
	var original_dance := bridge.invoke(54, [focus, StoryVm.integer(14)] + center + [StoryVm.number(30)], {})
	check(original_flock.get("ok", false) and original_dance.get("ok", false), "LHVM loads the original NewDanceAroundPerson choreography")
	if not original_flock.get("ok", false) or not original_dance.get("ok", false):
		return
	var flock: Dictionary = original_flock["push"][0]
	var dance: Dictionary = original_dance["push"][0]
	var follower := StoryVm.integer(0, StoryVm.BOOL)
	bridge.invoke(20, [member, StoryVm.integer(311), StoryVm.integer(-1)], {})
	bridge.invoke(17, [member, StoryVm.integer(200)], {})
	var looped_before_joining := dancer.is_script_animation_playing()
	bridge.invoke(37, [member, flock, follower], {})
	check(looped_before_joining and not dancer.is_script_animation_playing(), "joining a flock releases the actor's previous infinite script animation")
	var detached := bridge.invoke(38, [member, flock], {})
	var transferred := bridge.invoke(37, [member, dance, follower], {})
	bridge.invoke(37, [focus, dance, follower], {})
	var flock_size := bridge.invoke(40, [flock], {})
	var dance_size := bridge.invoke(40, [dance], {})
	check(detached.get("ok", false) and transferred.get("ok", false) and StoryVm.as_float(flock_size["push"][0]) == 0.0 and StoryVm.as_float(dance_size["push"][0]) == 2.0, "the real crowd transfers from its flock to the counted dance")
	var formation := dancer.story_flock
	var first_radius := formation.follow_position(dancer).distance_to(formation.position)
	var second_radius := formation.follow_position(anchor).distance_to(formation.position)
	check(absf(first_radius - 10.8) < 0.002 and absf(second_radius - 8.07632) < 0.002, "both welcome formations use the original initial circle sizes")
	formation.advance(252.5)
	var changing_radius := formation.follow_position(anchor).distance_to(formation.position)
	check(absf(changing_radius - 8.5365) < 0.002, "welcome formations interpolate over the original size-change turn interval")
	bridge.invoke(39, [dance], {})
	check(dancer.story_flock == null and anchor.story_flock == null, "disband releases the welcome dance villagers")


func finish(world: Node) -> void:
	if world.story_bridge != null:
		world.story_bridge.clear_created()
	world.g3d.close()
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			node.free()
	world.free()
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)
