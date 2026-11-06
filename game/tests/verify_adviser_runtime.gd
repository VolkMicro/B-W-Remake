extends SceneTree

class AdviserWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := AdviserWorld.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			world.bw_dir = arg.substr(5)
	world.story_preview = true
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	world._build_hud()
	world._build_advisers()
	world._setup_original_dialogue()
	check(world.adviser_animations.size() == 2, "load both original adviser rigs and animation packs")
	for item in world.adviser_animations:
		var reader: MorphReader = item["animation"]
		var rig: L3dRig = item["rig"]
		var hover := "adviser/Yogi_Hover" if item["id"] == "good" else "adviser/Demon_Hover"
		var speech: String = world.Data.ADVISERS[item["id"]]["speech_clip"]
		var a := reader.sample(hover, 0.0, rig.rests)
		var b := reader.sample(hover, 0.5, rig.rests)
		var c := reader.sample(speech, 0.13, rig.rests, hover, 0.5)
		var hover_changes := 0
		var face_changes := 0
		for i in rig.bone_count:
			if not a[i].is_equal_approx(b[i]): hover_changes += 1
			if not b[i].is_equal_approx(c[i]): face_changes += 1
		check(hover_changes > 0 and face_changes > 0, "%s floats and layers original speech channels over its body motion" % item["id"])
		for child in rig.root.get_children():
			if child is MeshInstance3D:
				check(not child.mesh.surface_get_material(0).no_depth_test and child.layers == world.ADVISER_LAYER and (world.cam.cull_mask & world.ADVISER_LAYER) == 0, "%s retains self-occlusion in a separate interface render layer" % item["id"])
	check(world.story_move_adviser(1, Vector2(0.2, 0.85)), "good adviser flies to its scripted screen anchor")
	var bridge := StoryNatives.new()
	bridge.configure(world)
	var adviser: Node3D = world.cam.get_node("Adviser_good")
	world.story_hide_adviser(1)
	var ejected := bridge.invoke(7, [StoryVm.integer(1)], {})
	check(ejected.get("ok", false) and adviser.visible, "SPIRIT_EJECT reveals the adviser instead of hiding it")
	await create_timer(0.7).timeout
	check(adviser.position.is_equal_approx(world._adviser_targets["good"]), "ejected adviser completes its flight to the scripted anchor")
	var homed := bridge.invoke(8, [StoryVm.integer(1)], {})
	await create_timer(0.7).timeout
	check(homed.get("ok", false) and not adviser.visible, "SPIRIT_HOME finishes its outward flight and hides the adviser")
	check(world.story_play_voice(5128), "start original movement-instruction voice")
	var deadline := Time.get_ticks_msec() + 10000
	while world.dialogue != null and not world.dialogue._player.playing and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.dialogue != null and world.dialogue.error.is_empty() and world.dialogue._player.playing and world.dialogue._player.stream.get_length() > 0.5, "original adviser voice decodes into an actively playing audio stream")
	check(world._speaking_adviser == "good" and not world.dialogue_caption.text.is_empty(), "spoken line selects the good adviser's mouth animation and original caption")
	if world.dialogue != null:
		world.dialogue.stop()
	for property in ["hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			world.add_child(node)
	world.free()
	await process_frame
	await process_frame
	print("ADVISERS failures=", failures)
	quit(0 if failures == 0 else 1)
