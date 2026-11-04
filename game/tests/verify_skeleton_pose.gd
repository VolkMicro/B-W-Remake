# Check poses actually installed in Godot, not just decoded animation arrays.
extends SceneTree

const Data := preload("res://scripts/data.gd")
var host := ""
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failures.append(label)
		printerr("FAIL ", label)


func transform_error(a: Transform3D, b: Transform3D) -> float:
	var error := a.origin.distance_to(b.origin)
	for axis in 3:
		error = maxf(error, a.basis[axis].distance_to(b.basis[axis]))
	return error


func check_applied_pose(rig: L3dRig, expected: Array[Transform3D], label: String, rest_pose := false) -> void:
	if expected.size() != rig.bone_count:
		check(false, label + " has compatible bone count")
		return
	var globals: Array[Transform3D] = []
	var max_local := 0.0
	var max_global := 0.0
	for bi in rig.bone_count:
		var parent: int = rig.parents[bi]
		globals.append(globals[parent] * expected[bi] if parent >= 0 else expected[bi])
		max_local = maxf(max_local, transform_error(rig.skeleton.get_bone_pose(bi), expected[bi]))
		max_global = maxf(max_global, transform_error(rig.skeleton.get_bone_global_pose(bi), globals[bi]))
	print("POSE ERROR ", label, " local=", max_local, " global=", max_global)
	# Original rest matrices can contain slight shear. Skeleton3D stores poses
	# as rotation and scale, so its rest decomposition has a bounded error;
	# animation frames are tested with the much stricter threshold.
	var local_limit := 0.08 if rest_pose else 0.01
	var global_limit := 0.10 if rest_pose else 0.05
	check(max_local < local_limit and max_global < global_limit, label + " matches the original local and hierarchical pose")


func _run() -> void:
	if host.is_empty():
		printerr("Original game folder is required")
		quit(2)
		return
	var models := G3dReader.new()
	var animations := AnmReader.new()
	var opened := models.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	var wanted: Array[String] = ["M_P_Stand", "M_P_Walk_Man", "M_P_Walk_Woman"]
	opened = opened and animations.load_file(host.path_join("Data/AllAnims.anm"), wanted)
	check(opened, "open original villager models and animations")
	if opened:
		for id in Data.VILLAGERS:
			var row: Dictionary = Data.VILLAGERS[id]
			var rig := models.rig(row["mesh"])
			if rig == null:
				check(false, id + " model loads")
				continue
			root.add_child(rig.root)
			check_applied_pose(rig, rig.rests, id + " initial rest", true)
			var profile: Dictionary = Data.VILLAGER_ANIMATIONS[row["animation_profile"]]
			for action in ["idle", "walk"]:
				var pose := animations.sample(profile[action], 0.31)
				rig.apply_local_pose(pose)
				check_applied_pose(rig, pose, id + " " + action)
				if action == "idle":
					var joints: Dictionary = Data.VILLAGER_SKELETONS["human"]
					var left: float = rig.skeleton.get_bone_global_pose(joints["left_shoulder"]).origin.y - rig.skeleton.get_bone_global_pose(joints["left_hand"]).origin.y
					var right: float = rig.skeleton.get_bone_global_pose(joints["right_shoulder"]).origin.y - rig.skeleton.get_bone_global_pose(joints["right_hand"]).origin.y
					check(left > float(joints["minimum_hand_drop"]) and right > float(joints["minimum_hand_drop"]), id + " actual idle hands are below the shoulders")
			rig.root.free()
	models.close()
	for id in Data.CREATURES:
		var row: Dictionary = Data.CREATURES[id]
		var rig := L3dRig.new()
		var visual := rig.load_file(host.path_join(row["mesh_file"]))
		var morph := MorphReader.new()
		if visual == null or not morph.load_file(host.path_join(row["animation_file"]), host.path_join("Data")):
			check(false, id + " original creature files load")
			if visual: visual.free()
			continue
		root.add_child(visual)
		check_applied_pose(rig, rig.rests, id + " initial rest", true)
		for clip in ["move/stand", "move/walk"]:
			var pose := morph.sample(clip, 0.31, rig.rests)
			rig.apply_local_pose(pose)
			# Creature frames are rotations relative to the (slightly sheared) rest basis,
			# so they inherit the rest decomposition tolerance.
			check_applied_pose(rig, pose, id + " " + clip, true)
			var turned := 0
			for bi in rig.bone_count:
				if pose[bi].basis.orthonormalized().get_rotation_quaternion().angle_to(rig.rests[bi].basis.orthonormalized().get_rotation_quaternion()) < 1.2:
					turned += 1
			check(turned * 10 >= rig.bone_count * 9, id + " " + clip + " stays near the original bind orientation")
		visual.free()
	for id in Data.ADVISERS:
		var row: Dictionary = Data.ADVISERS[id]
		var rig := L3dRig.new()
		var visual := rig.load_file(host.path_join(row["file"]))
		var morph := MorphReader.new()
		if visual == null or not morph.load_adviser(host.path_join(row["file"])):
			check(false, id + " original adviser files load")
			if visual: visual.free()
			continue
		root.add_child(visual)
		check_applied_pose(rig, rig.rests, id + " initial rest", true)
		var pose := morph.sample(row["speech_clip"], 0.31, rig.rests)
		rig.apply_local_pose(pose)
		check_applied_pose(rig, pose, id + " speaking")
		visual.free()
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)
