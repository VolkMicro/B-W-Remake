# Construct the island objects without entering the scene tree or running a game.
extends SceneTree

var source := ""
var failures: Array[String] = []
var passed := 0
var test_bridge: StoryNatives


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
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
		var expected: int = world.island.all("CREATE_ABODE").size() + world.island.all("CREATE_NEW_FEATURE").size() + world.island.all("CREATE_ANIMATED_STATIC").size()
		check(world.story_landmarks.size() == expected, "all original abode, feature, gate and cave objects are instantiated")
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
			world._start_story()
			for ignored in 300:
				if not world.story_vm.tick(): break
		var vm: StoryVm = world.story_vm
		check(original_ready and vm != null and vm.error.is_empty(), "the real first-island setup runs with no unported function (error: %s)" % (vm.error if vm else "none"))
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
		check(not world.is_inside_tree(), "the game scene was never entered or started")
	world.g3d.close()
	for property in ["cam", "hand_ring", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			node.free()
	world.free()
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)


func _test_only_observe_influence(id: int, stack: Array, context: Dictionary) -> Dictionary:
	if id == 254 and stack.size() >= 2:
		return {"ok":true,"pop":2,"push":[]}
	return test_bridge.invoke(id, stack, context)
