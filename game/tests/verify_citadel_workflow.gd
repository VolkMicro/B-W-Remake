extends SceneTree

const Site := preload("res://scripts/story_citadel_site.gd")
const Construction := preload("res://scripts/story_citadel_construction.gd")

class ConstructionWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var source := ""
var failures := 0
var workflow_seed := 0
var source_tutorial := false


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
		elif arg.begins_with("--seed="):
			workflow_seed = arg.substr(7).to_int()
		elif arg == "--source-tutorial":
			source_tutorial = true
	call_deferred("run_test")


func run_test() -> void:
	seed(workflow_seed)
	print("WORKFLOW seed=", workflow_seed)
	check(Construction._whole_wood_cost(2500.000000000001) == 2500,
		"fractional-progress roundoff cannot reserve a spurious 2501st wood unit")
	check(Construction._whole_wood_cost(2500.5) == 2501 and Construction._whole_wood_cost(0.01) == 1,
		"genuine fractional wood costs still require the next whole resource unit")
	var world := ConstructionWorld.new()
	world.bw_dir = source
	root.add_child(world)
	world.lnd.load_file(source.path_join("Data/Landscape/Land1.lnd"))
	world.g3d.open(source.path_join("Data/AllMeshes.g3d"), source.path_join("Data/AllMeshes.h"))
	world.island.load_file(source.path_join("Scripts/Land1.txt"))
	for command in world.island.all("CREATE_TOWN"):
		world.towns.append({"pos":world.to_world(IslandScript.pos(command["args"][1]))})
	var stock_point := world.to_world(Vector2(1826.79, 2641.36))
	var storage := world._place_mesh(world.Data.ABODES["NORSE_ABODE_STORAGE_PIT"], stock_point, 3.73, 1.0, "house")
	storage.set_meta("original_type", "NORSE_ABODE_STORAGE_PIT")
	world.story_landmarks.append(storage)
	for command in world.island.all("CREATE_VILLAGER_POS"):
		var args: PackedStringArray = command["args"]
		var home: Vector3 = world.to_world(IslandScript.pos(args[1]))
		if not world.Data.VILLAGERS.has(args[2]) or world._nearest_town(home, 400.0) != 0:
			continue
		var builder := world._spawn_villager(args[2], world.to_world(IslandScript.pos(args[0])), home)
		builder.story_age = int(args[3])
		builder.set_process(false)
		builder.set_physics_process(false)
	var site := Site.new()
	site.configure(source.path_join("Data/Citadel/OutsideMeshes"))
	world.add_child(site)
	site.position = world.to_world(Vector2(1915.05, 2508.89))
	site.rotation.y = 36.0
	var construction := Construction.new()
	check(construction.configure(world, site, 0), "configure construction with the original whole village population")
	var source_cap := StoryVm.as_float(StoryVm.number(0.9))
	site.set_progress(source_cap)
	check(construction._wood_needed() == 650, "original float32 90% property leaves exactly 650 whole wood units to build")
	site.set_progress(0.0)
	construction.set_forced_desire(2.5)
	if source_tutorial:
		site.set_progress(0.375)
		world.story_construction = construction
		world.add_child(world.cam)
		world.campaign.load_file(source.path_join("Scripts/Quests/challenge.chl"))
	var cap_time := -1.0
	var completion_time := -1.0
	var resume_positions := {}
	var paused_workers_held := true
	var demo_started := false
	var demo_finished := false
	for tick in 4000:
		var elapsed := tick * 0.1
		world.animation_clock = elapsed
		for builder in world.things:
			builder._physics_process(0.1)
			builder._process(0.1)
		if cap_time >= 0.0 and construction.completion_prevented:
			site.set_progress(source_cap)
		if source_tutorial and elapsed >= 120.0 and not demo_started:
			demo_started = world.story_play_hand_demo(244)
		if source_tutorial and demo_started and not demo_finished:
			world.story_advance_hand_demo(0.1)
			world.story_hand_demo.consume_trigger()
			if not world.story_hand_demo.playing:
				demo_finished = true
				construction.completion_prevented = false
		construction.advance()
		if tick % 200 == 0:
			print("WORKFLOW t=", elapsed, " progress=", site.progress, " jobs=", construction.jobs.size(), " stock=", construction.storage_wood(), " site=", construction.wood, " carried=", carried_wood(world))
		if cap_time < 0.0 and site.progress >= 0.9:
			cap_time = elapsed
			for job in construction.jobs:
				resume_positions[job["builder"].get_instance_id()] = job["builder"].position
		elif cap_time >= 0.0 and elapsed < cap_time + 30.0:
			for job in construction.jobs:
				var builder: Thing = job["builder"]
				paused_workers_held = paused_workers_held and builder.story_hold_position and builder.position.distance_to(resume_positions[builder.get_instance_id()]) < 0.001
		if not source_tutorial and cap_time >= 0.0 and elapsed >= cap_time + 30.0:
			construction.completion_prevented = false
		if site.progress >= 1.0:
			completion_time = elapsed
			break
	check(cap_time >= 0.0, "whole original village reaches the script's 90% construction cap")
	check(paused_workers_held and not resume_positions.is_empty(), "the tutorial's 90% cap retains actual workers and supplies without sending them wandering home")
	check(completion_time > cap_time and (source_tutorial or completion_time - cap_time < 45.0),
		"after a 30-second tutorial pause, builders resume and finish without another supply round trip")
	check(construction.storage_wood() + construction.wood + construction.wood_consumed + carried_wood(world) == 30000,
		"full village, multiple deliveries, pause and completion conserve every unit of original wood")
	var expected_cost := 4063 if source_tutorial else 6500
	var withdrawn := 30000 - construction.storage_wood()
	check(withdrawn == expected_cost if not source_tutorial else withdrawn >= expected_cost and withdrawn <= expected_cost + 860,
		"pickup reservations avoid excess withdrawals while retaining any real Hand supplies already collected")
	check(construction.wood_consumed == expected_cost and site.progress == 1.0,
		"completed original work cycles consume exactly the remaining whole-wood cost and reach exact completion")
	if source_tutorial:
		check(demo_finished and world._story_demo_wood_delivered == 860,
			"the real HND recording delivers exactly 860 wood before releasing the original tutorial cap")
	print("WORKFLOW FINAL ", JSON.stringify(construction.diagnostics()))
	print("WORKFLOW cap_time=", cap_time, " completion_time=", completion_time, " population=", world.things.size())
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			world.add_child(node)
	world.g3d.close()
	world.free()
	print("CITADEL_WORKFLOW failures=", failures)
	quit(0 if failures == 0 else 1)


func carried_wood(world: Node) -> int:
	var result := 0
	for builder in world.things:
		result += builder.story_resources.y
	return result
