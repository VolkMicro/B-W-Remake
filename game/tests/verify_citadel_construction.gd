extends SceneTree

const Site := preload("res://scripts/story_citadel_site.gd")
const Construction := preload("res://scripts/story_citadel_construction.gd")

class ConstructionWorld extends "res://scripts/main.gd":
	var route_water_rect := Rect2()
	func _ready() -> void:
		pass
	func ground_y(point: Vector3) -> float:
		if route_water_rect.has_point(Vector2(point.x, point.z)):
			return sea_y - 1.0
		return super.ground_y(point)

var source := ""
var failures := 0


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
	call_deferred("run_test")


func run_test() -> void:
	var world := ConstructionWorld.new()
	world.bw_dir = source
	root.add_child(world)
	check(world.lnd.load_file(source.path_join("Data/Landscape/Land1.lnd")), "load actual first-island terrain for resource routes")
	check(world.g3d.open(source.path_join("Data/AllMeshes.g3d"), source.path_join("Data/AllMeshes.h")), "load actual villagers and storage-pit geometry")
	check(world.island.load_file(source.path_join("Scripts/Land1.txt")), "load original first-island resource inventories")
	var stock_point := world.to_world(Vector2(1826.79, 2641.36))
	world.towns.append({"pos":stock_point})
	var storage := world._place_mesh(world.Data.ABODES["NORSE_ABODE_STORAGE_PIT"], stock_point, 3.73, 1.0, "house")
	storage.set_meta("original_type", "NORSE_ABODE_STORAGE_PIT")
	world.story_landmarks.append(storage)
	var site := Site.new()
	check(site.configure(source.path_join("Data/Citadel/OutsideMeshes")), "load neutral temple construction model")
	world.add_child(site)
	site.position = world.to_world(Vector2(1915.05, 2508.89))
	site.rotation.y = 36.0
	var construction := Construction.new()
	if not construction.configure(world, site, 0):
		check(false, "configure resource construction: " + construction.error)
		quit(1)
		return
	check(construction.wood_cost == 6500 and construction.max_builders == 100,
		"read the installed temple's 6500 wood cost and 100-builder maximum")
	check(construction._profiles["male"]["per_cycle"] == 50 and construction._profiles["female"]["per_cycle"] == 40
		and construction._profiles["male"]["capacity"] == 250, "read original male/female build-cycle consumption and wood carrying capacity")
	check(construction.storage_wood() == 30000, "storage starts with exactly the original village's 30000 wood")
	construction.set_forced_desire(0.375 * 5.0)
	check(site.progress == 0.0 and site.forced_desire == 1.875, "BUILD_BUILDING's desire has no immediate completion effect")
	construction.add_wood(250)
	for i in 10:
		construction.advance()
	check(site.progress == 0.0 and construction.wood == 250, "site wood without a real available builder cannot advance construction")
	construction.wood = 0
	var builder := world._spawn_villager("NORSE_FORESTER", stock_point, stock_point)
	builder.story_age = 25
	builder.town = 0
	builder.set_process(false)
	builder.set_physics_process(false)
	storage.set_meta("story_wood_stock", 0)
	for i in 3:
		construction.advance()
	check(site.progress == 0.0 and builder.story_resources.y == 0, "available builders without wood cannot advance construction")
	storage.set_meta("story_wood_stock", 30000)
	construction.advance()
	construction.advance()
	check(construction.storage_wood() == 29750 and builder.story_resources.y == 250 and construction.wood == 0,
		"builder physically at storage withdraws and visibly carries 250 wood")
	check(site.progress == 0.0, "wood still in transit gives no construction progress")
	var start := builder.position
	for step in 2000:
		builder._physics_process(0.1)
		construction.advance()
		if construction.wood > 0:
			break
	check(builder.position.distance_to(start) > 100.0 and construction.wood == 250 and builder.story_resources.y == 0,
		"actual villager walks the real terrain from storage to the temple and delivers its carried wood")
	check(site.progress == 0.0 and construction.jobs[0]["state"] == "into", "arrival starts the original entry animation before work can consume wood")
	var into_name: String = construction.jobs[0]["clip"]
	builder._process(float(construction.animations.clips[into_name]["duration"]) + 0.01)
	construction.advance()
	check(site.progress == 0.0 and construction.jobs[0]["state"] == "build", "entry animation completion starts one of the three original work clips")
	var clip: String = construction.jobs[0]["clip"]
	var duration: float = construction.animations.clips[clip]["duration"]
	builder._process(duration * 0.5)
	construction.advance()
	check(site.progress == 0.0 and construction.wood == 250, "partially played work animation cannot consume wood or build")
	builder._process(duration * 0.5 + 0.01)
	var work_position := builder.position
	builder._physics_process(2.2)
	builder._physics_process(2.2)
	check(builder.story_hold_position and builder.position.is_equal_approx(work_position),
		"assigned builder holds its work position between completed animation cycles")
	construction.advance()
	check(is_equal_approx(site.progress, 50.0 / 6500.0) and construction.wood == 200,
		"one completed male work cycle consumes 50 wood and builds exactly 50/6500")
	check(construction.storage_wood() + construction.wood + builder.story_resources.y + construction.wood_consumed == 30000,
		"storage, carrying, site inventory and consumed wood conserve all original resources")
	var before := site.progress
	builder.state = Thing.State.HELD
	construction.advance()
	check(construction.jobs.is_empty() and site.progress == before, "a picked-up or interrupted builder cannot complete a work cycle")
	builder.state = Thing.State.IDLE
	site.set_progress(0.899)
	for step in 100:
		builder._physics_process(0.1)
		builder._process(0.1)
		construction.advance()
		if site.progress >= 0.9:
			break
	check(is_equal_approx(site.progress, 0.9), "PreventCitadelCompletion stops real building at the original 90% cap")
	construction.completion_prevented = false
	site.set_progress(0.999)
	for step in 100:
		builder._physics_process(0.1)
		builder._process(0.1)
		construction.advance()
		if site.progress >= 1.0:
			break
	check(site.progress == 1.0 and construction.jobs.is_empty(), "after the original script releases its cap, a completed work cycle finishes the temple")
	check(construction.take_storage_wood(stock_point, 123) == 123 and construction.storage_wood() == 29627,
		"the recorded Hand demo can debit the same real storage inventory")
	check(construction.add_wood(123) == 123, "the recorded Hand demo can deliver its actual carried wood to the site")
	var female := world._spawn_villager("NORSE_HOUSEWIFE", builder.position, stock_point)
	female.story_age = 25
	female.town = 0
	female.set_process(false)
	female.set_physics_process(false)
	world.things.assign([female])
	site.set_progress(0.0)
	construction.wood = 40
	var previous_used := construction.wood_consumed
	for step in 100:
		female._physics_process(0.1)
		female._process(0.1)
		construction.advance()
		if construction.wood_consumed > previous_used:
			break
	check(construction.wood_consumed - previous_used == 40 and is_equal_approx(site.progress, 40.0 / 6500.0),
		"the actual female rig plays original build animations and consumes its own 40-wood cycle")
	site.set_progress(1.0)
	construction.advance()
	world.things.assign([builder, female])
	site.set_progress(0.99)
	construction.wood = 0
	var needed := 65 # Exact 1% of original 6500 cost, independent of float error.
	construction.advance()
	check(construction.jobs.size() == 1 and construction.jobs[0]["reserved_wood"] == needed,
		"one reserved partial pickup prevents other empty workers from making redundant supply journeys")
	var actual_hand_wood := construction.take_storage_wood(stock_point, needed)
	construction.add_wood(actual_hand_wood)
	var supplied_stock := construction.storage_wood()
	construction.advance()
	check(construction.jobs[0]["state"] == "site" and construction.jobs[0]["reserved_wood"] == 0 and construction.storage_wood() == supplied_stock,
		"a real Hand delivery cancels an already-covered outgoing pickup before an empty round trip")
	site.set_progress(1.0)
	construction.advance()
	world.things.assign([builder])
	storage.set_meta("story_wood_stock", 0)
	site.set_progress(1.0 - 149.0 / 6500.0)
	construction.wood = 1
	previous_used = construction.wood_consumed
	for step in 100:
		builder._physics_process(0.1)
		builder._process(0.1)
		construction.advance()
		if not construction.jobs.is_empty() and construction.jobs[0]["state"] == "waiting":
			break
	check(not construction.jobs.is_empty() and construction.jobs[0]["state"] == "waiting" and construction.wood == 0,
		"an actual completed cycle waits at the site when its last wood is consumed")
	var grant_bridge := StoryNatives.new()
	grant_bridge.configure(world)
	var grant_handle := StoryVm.integer(grant_bridge.register_object(builder, 4), StoryVm.OBJECT)
	var granted := grant_bridge.invoke(134, [StoryVm.integer(1), StoryVm.number(148), grant_handle], {})
	construction.jobs[0]["reserved_wood"] = 50 # A stale promise must not survive returning to the site.
	construction.advance()
	check(granted.get("ok", false) and builder.story_resources.y == 148 and construction.jobs[0]["state"] == "site"
		and construction.jobs[0]["reserved_wood"] == 0,
		"original ADD_RESOURCE wood sends its waiting carrier to delivery and clears any stale pickup reservation")
	construction.advance()
	check(builder.story_resources.y == 0 and construction.wood == 148,
		"externally granted carried wood reaches the real site inventory instead of deadlocking its own demand")
	for step in 100:
		builder._physics_process(0.1)
		builder._process(0.1)
		construction.advance()
		if site.progress == 1.0:
			break
	check(site.progress == 1.0 and construction.wood_consumed - previous_used == 149 and construction.wood == 0,
		"waiting, the original 148-wood grant and completed work cycles finish without invented supplies")
	# The original footpath/hug movement goes around water. A direct straight
	# walk in the port stops forever at the shore and can reserve all needed wood.
	world.route_water_rect = Rect2(Vector2(1820, -2590), Vector2(150, 20))
	builder.position = stock_point
	site.set_progress(0.99)
	storage.set_meta("story_wood_stock", 30000)
	construction.wood = 0
	previous_used = construction.wood_consumed
	construction.advance()
	construction.advance()
	check(builder._script_move_active and not builder._script_waypoints.is_empty(),
		"a water barrier changes the actual carrier route into dry-land waypoints")
	var stayed_dry := true
	for step in 1200:
		builder._physics_process(0.1)
		builder._process(0.1)
		construction.advance()
		stayed_dry = stayed_dry and world.ground_y(builder.position) > world.sea_y + 0.2
		if site.progress == 1.0:
			break
	check(stayed_dry and site.progress == 1.0 and construction.wood_consumed - previous_used == 65
		and construction.storage_wood() == 29935,
		"a real carrier walks around the shore, delivers and finishes using exactly its 65 reserved wood")
	builder.position = Vector3(1850, 0, -2580)
	site.set_progress(0.99)
	construction.advance()
	check(construction.jobs.is_empty() and construction._wood_needed() == 65,
		"an unreachable carrier releases its job and reservation so other workers can fetch the remaining supply")
	world.route_water_rect = Rect2()
	var native_site: Node3D = world.story_build_citadel(site.position, 0.375)
	check(native_site != null and native_site.progress == 0.0 and native_site.forced_desire == 1.875,
		"integrated original BUILD_BUILDING native requests desire, never instant progress")
	# Exercise the real scene method, not a second copy of its pickup/drop FSM.
	world.story_construction = construction
	world.add_child(world.cam)
	storage.set_meta("story_wood_stock", 30000)
	construction.wood = 0
	world.campaign.load_file(source.path_join("Scripts/Quests/challenge.chl"))
	check(world.story_play_hand_demo(244), "main starts the installed givewood input recording with original hand settings")
	var retained := false
	for step in 1600:
		world.story_advance_hand_demo(0.05)
		world.story_hand_demo.consume_trigger()
		if world.story_hand_demo.action_release_count == 1:
			retained = retained or (world._story_demo_holding_wood and world._story_wood_hand.amount == 860 and is_instance_valid(world._story_demo_wood))
		if not world.story_hand_demo.playing:
			break
	check(retained, "main keeps the actual 860 wood and its visible prop after the first button release")
	check(world._story_demo_wood_delivered == 860 and construction.wood == 860 and construction.storage_wood() == 29140,
		"main transfers the recorded hand's real supply from the same storage to the site exactly once")
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			world.add_child(node)
	world.free()
	print("CITADEL_CONSTRUCTION failures=", failures)
	quit(0 if failures == 0 else 1)
