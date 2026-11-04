extends SceneTree

const Data := preload("res://scripts/data.gd")
var failures: Array[String] = []
var passed := 0
var source := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS ", description)
	else:
		failures.append(description)
		printerr("FAIL ", description)


func _run() -> void:
	if source == "":
		printerr("Test requires --bw source folder")
		quit(2)
		return
	var campaign := ChlReader.new()
	check(campaign.load_file(source.path_join("Scripts/Quests/challenge.chl")), "original campaign parsed: " + campaign.error)
	check(campaign.scripts.has("SetupLand1") and campaign.instruction_count > 100000, "real first island campaign indexed")
	print("CAMPAIGN scripts=", campaign.scripts.size(), " natives=", campaign.native_calls.size(), " execution=NOT_IMPLEMENTED")
	var animations := AnmReader.new()
	var wanted: Array[String] = []
	for profile in Data.VILLAGER_ANIMATIONS.values():
		for key in ["idle","walk","flee","held","flying","dead"]:
			if profile[key] not in wanted:
				wanted.append(profile[key])
	check(animations.load_file(source.path_join("Data/AllAnims.anm"), wanted), "original villager animation archive: " + animations.error)
	var g3d := G3dReader.new()
	check(g3d.open(source.path_join("Data/AllMeshes.g3d"), source.path_join("Data/AllMeshes.h")), "original villager model archive")
	var info := HostInfoReader.new()
	check(info.load_file(source.path_join("Scripts/info.dat"), g3d.mesh_offsets.size()), "read original versioned object table: " + info.error)
	check(info.mobile_statics.size() == 61 and info.version == "bw_1_2", "installed original object table version and count")
	check(info.animals.size() == 31, "original wildlife information table is read")
	var cow := info.animal(8)
	check(cow.get("mesh_id", -1) == g3d.name_to_index.get("MSH_A_COW_1", -2) and cow.get("animation_id", -1) == 42 and cow.get("age_scales", PackedFloat32Array()).size() == 20, "original cow model, default animation and age scales come from host data")
	var seagull := info.animal(15)
	check(seagull.get("mesh_id", -1) == g3d.name_to_index.get("MSH_A_SEAGULL_1", -2) and seagull.get("animation_id", -1) == 18 and is_equal_approx(seagull.get("normal_altitude", -1.0), 40.0), "original seagull model, animation and flight data come from host data")
	check(info.animal(-1).is_empty() and info.animal(31).is_empty(), "out-of-range original wildlife records are rejected")
	check(info.record(0).get("mesh_id",-1) == g3d.name_to_index.get("MSH_B_CELT_FENCE_SHORT",-2) and info.record(2).get("mesh_id",-1) == g3d.name_to_index.get("MSH_Z_SPELLROCK01",-2), "original fences and rocks use their actual mesh IDs")
	check(info.record(49).get("mesh_id",-1) == g3d.name_to_index.get("MSH_O_GATE_TOTEM_APE",-2), "original ape gate uses its own original mesh")
	var island := IslandScript.new()
	check(island.load_file(source.path_join("Scripts/Land1.txt")), "read original island object placements")
	var cave := info.animated_static("Piper Cave Entrance")
	check(cave.get("mesh_id", -1) == g3d.name_to_index.get("MSH_B_MINE_ENTRANCE", -2) and cave.get("animation_id", -1) == 189, "original cave entrance uses its real model and animation record")
	check(info.animated_static("Norse Gate").get("mesh_id", -1) == g3d.name_to_index.get("MSH_B_NORS_GATE", -2), "original gate uses its real model")
	check(info.animated_static("Gate Stone Plinth").get("mesh_id", -1) == g3d.name_to_index.get("MSH_O_GATE_TOTEM_PLINTHE", -2), "original plinth uses its real model")
	var animated_placements := island.all("CREATE_ANIMATED_STATIC")
	check(animated_placements.size() == 4, "all first-island gate and cave placements are read")
	var found_story_cave := false
	for command in animated_placements:
		var args: PackedStringArray = command["args"]
		var record := info.animated_static(args[1])
		var mesh := g3d.mesh_index(int(record.get("mesh_id", -1)))
		var placement := IslandScript.placement("animated_static", args)
		check(not record.is_empty() and mesh != null and mesh.get_surface_count() > 0 and not placement.is_empty(), "original animated landmark " + args[1] + " loads as a real model")
		if args[1] == "Piper Cave Entrance" and IslandScript.pos(args[0]).distance_to(Vector2(1970.8, 2812.12)) < 0.01:
			found_story_cave = is_equal_approx(placement["angle"], -2.302) and is_equal_approx(placement["scale"], 1.0)
	check(found_story_cave, "first-island story cave uses its original position and rotation")
	var abode := island.all("CREATE_ABODE")[0]["args"] as PackedStringArray
	var abode_placement := IslandScript.placement("abode", abode)
	check(is_equal_approx(abode_placement["scale"], 0.990) and is_equal_approx(abode_placement["angle"], 4.710), "original abode scale and angle use thousandths")
	var checked_feature := false
	for command in island.all("CREATE_NEW_FEATURE"):
		var args: PackedStringArray = command["args"]
		if args[1] == "Pilar3 Lime" and args[2] == "1047" and args[3] == "474":
			var placement := IslandScript.placement("feature", args)
			checked_feature = is_equal_approx(placement["angle"], 1.047) and is_equal_approx(placement["scale"], 0.474)
			break
	check(checked_feature, "original landscape features retain their rotation and scale")
	check(IslandScript.placement("feature", PackedStringArray(["x"])) == {}, "truncated placement is rejected")
	var types := {}
	for command in island.all("CREATE_MOBILE_STATIC"):
		var index := int(command["args"][1])
		if types.has(index): continue
		types[index] = true
		var record := info.record(index)
		var category: Dictionary = Data.STATICS.get(str(record.get("category",-1)),{})
		check(not record.is_empty() and not category.is_empty() and g3d.mesh_index(int(record.get("mesh_id",-1))) != null, "original island object type %d has actual model and behaviour" % index)
	check(types.size() >= 16, "all distinct first-island mobile object types are covered")
	var bad_info := HostInfoReader.new()
	check(not bad_info._read_info(PackedByteArray([0,1,2]), g3d.mesh_offsets.size()), "unknown object table versions are rejected")
	for id in Data.VILLAGERS:
		var row: Dictionary = Data.VILLAGERS[id]
		var rig := g3d.rig(row["mesh"])
		check(rig != null and rig.bone_count == 22, id + " instanced 22-bone original skeleton")
		if rig == null:
			continue
		root.add_child(rig.root)
		var profile: Dictionary = Data.VILLAGER_ANIMATIONS[row["animation_profile"]]
		for key in ["idle","walk","flee","held","flying","dead"]:
			var pose := animations.sample(profile[key], 0.13)
			var valid := pose.size() == rig.bone_count
			for transform in pose:
				valid = valid and transform.is_finite()
			check(valid, id + " compatible original " + key + " pose")
			rig.apply_local_pose(pose)
		var a := animations.sample(profile["walk"], 0.0)
		var b := animations.sample(profile["walk"], 0.35)
		var changed := 0
		for bi in a.size():
			if not a[bi].is_equal_approx(b[bi]):
				changed += 1
		check(changed > 5, id + " gait changes multiple joints across real keyframes")
		var idle_bounds := deformed_bounds(rig, animations.sample(profile["idle"], 0.0))
		print("POSE ", id, " bind_width=",rig.bounds.size.x," idle_width=",idle_bounds.size.x," idle_height=",idle_bounds.size.y)
		# T-pose means hands remain at shoulder height. Width alone is not a
		# valid oracle: clothing and carried tools affect each mesh's bounds.
		var idle_pose := global_bone_pose(rig, animations.sample(profile["idle"], 0.0))
		var joints: Dictionary = Data.VILLAGER_SKELETONS["human"]
		var left_drop: float = idle_pose[joints["left_shoulder"]].origin.y - idle_pose[joints["left_hand"]].origin.y
		var right_drop: float = idle_pose[joints["right_shoulder"]].origin.y - idle_pose[joints["right_hand"]].origin.y
		print("JOINTS ",id," left_drop=",left_drop," right_drop=",right_drop," root=",idle_pose[0].origin)
		check(left_drop > joints["minimum_hand_drop"] and right_drop > joints["minimum_hand_drop"], id + " original idle holds both hands below shoulders")
		rig.root.free()
	g3d.close()
	for id in Data.CREATURES:
		var row: Dictionary = Data.CREATURES[id]
		var rig := L3dRig.new()
		var visual := rig.load_file(source.path_join(row["mesh_file"]))
		check(visual != null, id + " model: " + rig.error)
		if visual == null:
			continue
		root.add_child(visual)
		check(rig.bone_count > 30 and rig.surface_count > 0 and rig.texture_count > 0, id + " skeleton, surfaces, original embedded textures")
		var anim := MorphReader.new()
		check(anim.load_file(source.path_join(row["animation_file"]), source.path_join("Data")), id + " animations: " + anim.error)
		for action in Data.CREATURE_ACTIONS:
			var clip: String = Data.CREATURE_ACTIONS[action]["clip"]
			check(anim.clips.has(clip), id + " has original " + clip)
			var before := anim.sample(clip, 0.0, rig.rests)
			var after := anim.sample(clip, 0.53, rig.rests)
			var finite := before.size() == rig.bone_count and after.size() == rig.bone_count
			for pose in after:
				finite = finite and pose.is_finite()
			check(finite, id + " valid animated pose " + action)
			rig.apply_local_pose(after)
		print("MODEL ", id, " bones=", rig.bone_count, " textures=", rig.texture_count, " bounds=", rig.bounds, " clips=", anim.clips.size())
		visual.free()
		for form in ["good_file", "evil_file"]:
			var form_rig := L3dRig.new()
			var form_visual := form_rig.load_file(source.path_join(row[form]))
			check(form_visual != null and form_rig.bone_count == rig.bone_count, id + " original " + form)
			if form_visual:
				form_visual.free()
	for id in Data.ADVISERS:
		var rig := L3dRig.new()
		var visual := rig.load_file(source.path_join(Data.ADVISERS[id]["file"]))
		check(visual != null and rig.bone_count > 0 and rig.texture_count > 0, "original adviser " + id + ": " + rig.error)
		print("ADVISER ", id, " bounds=", rig.bounds)
		var animation := MorphReader.new()
		check(animation.load_adviser(source.path_join(Data.ADVISERS[id]["file"])), "original adviser animation " + id + ": " + animation.error)
		check(animation.clips.has(Data.ADVISERS[id]["speech_clip"]), "original speaking animation exists for adviser " + id)
		if animation.clips.has(Data.ADVISERS[id]["speech_clip"]):
			var pose1 := animation.sample(Data.ADVISERS[id]["speech_clip"], 0.0, rig.rests)
			var pose2 := animation.sample(Data.ADVISERS[id]["speech_clip"], 0.15, rig.rests)
			var changed := 0
			for bi in pose1.size():
				if not pose1[bi].is_equal_approx(pose2[bi]): changed += 1
			check(changed > 0, "original adviser speaking pose animates " + id)
		if animation.clips.has("move/stand"):
			check(animation.sample("move/stand", 0.3, rig.rests).size() == rig.bone_count, "adviser animation matches skeleton " + id)
		if visual:
			visual.free()
	var hand := L3dRig.new()
	var visual := hand.load_file(source.path_join("Data/CreatureMesh/Hand_Boned_Base2.l3d"))
	check(visual != null and hand.bone_count > 0, "original god Hand")
	if visual:
		visual.free()
	var broken := L3dRig.new()
	check(broken.load_file("res://project.godot") == null, "reject non-model input")
	# Validate teaching with the real controller, independent of drawing a scene.
	var world := FakeWorld.new()
	world.source = source
	world.villager_anims = animations
	root.add_child(world)
	var actor := Thing.new()
	actor.kind = "villager"
	actor.world = world
	actor.animation_profile = "female"
	actor.rig = g3d.rig("MSH_P_NORS_F_A_1")
	actor.add_child(actor.rig.root)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	var expected_states := {Thing.State.IDLE:"idle",Thing.State.FLEE:"flee",Thing.State.HELD:"held",Thing.State.FLYING:"flying",Thing.State.DEAD:"dead"}
	for state in expected_states:
		actor.state = state
		actor._animate(0.2, true)
		check(actor.animation_name == Data.VILLAGER_ANIMATIONS["female"][expected_states[state]], "villager controller selects original " + expected_states[state])
	actor.state = Thing.State.IDLE
	actor.animation_walk = true
	actor._animate(0.2, true)
	check(actor.animation_name == "M_P_Walk_Woman", "moving woman selects original female gait")
	g3d.close()
	var creature := IslandCreature.new()
	check(creature.configure(world, "ape", Vector3.ZERO), "creature controller loads original ape")
	world.add_child(creature)
	creature.set_physics_process(false)
	creature.perform("help", 0)
	var initial: float = creature.memory["help"]
	check(creature.feedback(true) and creature.memory["help"] > initial, "praise reinforces the preceding helpful act")
	check(not creature.feedback(true), "one act cannot be praised twice")
	creature.perform("scare", 0)
	initial = creature.memory["scare"]
	check(creature.feedback(false) and creature.memory["scare"] < initial, "punishment discourages the preceding cruel act")
	creature.perform("help", 0)
	creature.last_action_age = 99.0
	check(not creature.feedback(true), "expired feedback cannot train an unrelated action")
	var saved := creature.snapshot()
	creature.hunger = 0.99
	creature.restore(saved)
	check(is_equal_approx(creature.hunger, saved["hunger"]) and creature.memory == saved["memory"], "teaching state round trips through save data")
	var food := Thing.new()
	food.kind = "food"
	food.world = world
	world.add_child(food)
	var hunger := creature.hunger
	check(creature.feed(food) and creature.hunger < hunger, "actual food delivery reduces hunger")
	# Fixed step sweep: a fast rock hits a standing villager between endpoints.
	var rock := Thing.new()
	rock.kind = "rock"
	rock.world = world
	rock.position = Vector3(-2, 1, 0)
	rock.velocity = Vector3(300, 0, 0)
	rock.thrown = true
	world.add_child(rock)
	rock.set_physics_process(false)
	var villager := Thing.new()
	villager.kind = "villager"
	villager.world = world
	world.add_child(villager)
	villager.set_physics_process(false)
	world.things = [rock, villager]
	rock.state = Thing.State.FLYING
	rock._fly(1.0 / 60.0)
	check(villager.state == Thing.State.DEAD, "swept fast rock hits villager rather than tunneling")
	rock.position = Vector3(0, 5, 20)
	rock.velocity = Vector3.ZERO
	rock._landed_notified = false
	rock.thrown = false
	rock.state = Thing.State.FLYING
	for i in 600:
		rock._fly(1.0 / 60.0)
		if rock.state == Thing.State.IDLE:
			break
	check(rock.state == Thing.State.IDLE and rock.position.y >= 0 and world.landings == 1, "rock bounces, settles and dispatches one landing")
	world.free()
	await process_frame
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)


func deformed_bounds(rig: L3dRig, pose: Array[Transform3D]) -> AABB:
	var global_pose := global_bone_pose(rig, pose)
	var result := AABB()
	var initialized := false
	for child in rig.root.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh: ArrayMesh = child.mesh
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for vi in vertices.size():
				var bone := bones[vi * 4]
				var p: Vector3 = global_pose[bone] * rig.global_rests[bone].affine_inverse() * vertices[vi]
				if initialized:
					result = result.expand(p)
				else:
					result = AABB(p, Vector3.ZERO)
					initialized = true
	return result


func global_bone_pose(rig: L3dRig, pose: Array[Transform3D]) -> Array[Transform3D]:
	var global_pose: Array[Transform3D] = []
	for bi in rig.bone_count:
		global_pose.append(global_pose[rig.parents[bi]] * pose[bi] if rig.parents[bi] >= 0 else pose[bi])
	return global_pose


class FakeWorld extends Node3D:
	var source := ""
	var focus := Vector3.ZERO
	var alignment := 0.0
	var sea_y := -10.0
	var cfg_hand := {"gravity":60.0}
	var things: Array = []
	var landings := 0
	var cam := Camera3D.new()
	var animation_clock := 1.0
	var villager_anims: AnmReader
	func _exit_tree() -> void:
		cam.free()
	func _p(path: String) -> String:
		return source.path_join(path)
	func _say(_text: String) -> void:
		pass
	func _log_test(_name: String, _text: String) -> void:
		pass
	func add_belief(_town: int, _amount: float) -> void:
		pass
	func _nearest_town(_pos: Vector3, _distance: float) -> int:
		return 0
	func ground_y(_pos: Vector3) -> float:
		return 0.0
	func ground_normal(_pos: Vector3) -> Vector3:
		return Vector3.UP
	func _act(_action: String, _town: int, _text: String) -> void:
		pass
	func on_landed(_thing: Thing) -> void:
		landings += 1
