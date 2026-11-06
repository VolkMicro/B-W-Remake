extends SceneTree

class KeyWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass

var failures := 0
var passed := 0
var host := "C:/Games/Black and White Complete Collection"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures += 1
	print("PASS " if ok else "FAIL ", label)

func handle(bridge: StoryNatives, object: Object) -> Dictionary:
	return StoryVm.integer(bridge.register_object(object), StoryVm.OBJECT)

func run() -> void:
	var world := KeyWorld.new()
	world.bw_dir = host
	root.add_child(world)
	var ready := world.lnd.load_file(host.path_join(world.Data.SOURCES["landscape"]))
	ready = ready and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	ready = ready and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	ready = ready and world.island.load_file(host.path_join("Scripts/Land1.txt")) and world._load_landmark_animations()
	check(ready, "load actual original first-island key, gate and plinth assets")
	if not ready:
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	world._spawn_objects()
	for thing in world.things:
		thing.set_process(false)
		thing.set_physics_process(false)
	var bridge := StoryNatives.new()
	world.story_bridge = bridge
	bridge.configure(world)
	var plinth: Node3D = world.story_gate_plinth
	var plinth_id := handle(bridge, plinth.landmark)
	check(StoryVm.as_float(bridge.invoke(320, [plinth_id], {})["push"][0]) == 0.0, "an empty source plinth reports zero info bits")
	check(not plinth.accept(world.host_info.record(2)) and not plinth.accept(world.host_info.record(50)) and plinth.info_bits() == 0, "ordinary rock and blank quarry stone cannot masquerade as delivered keys")
	var gate: OriginalLandmark
	for landmark in world.story_landmarks:
		if landmark.get_meta("original_type", "") == "Norse Gate": gate = landmark
	check(StoryVm.as_float(bridge.invoke(320, [handle(bridge, gate)], {})["push"][0]) == 0.0, "an unrelated animated gate does not inherit the plinth's slots")
	for subtype in [49, 51, 52]: check(plinth.accept(world.host_info.record(subtype)), "accept actual source key subtype %d" % subtype)
	check(plinth.info_bits() == 7 and plinth.get_child_count() == 3, "three genuine mesh identities produce the original complete info value and three visible stones")
	check(not plinth.accept(world.host_info.record(52)) and plinth.get_child_count() == 3, "full plinth refuses a fourth stone without changing its visible slots")
	var key: Thing
	for mobile in world.story_mobile_statics:
		if mobile.get_meta("story_mobile_subtype", -1) == 49: key = mobile
	check(key != null and key.kind == "gate_key" and world.things.has(key), "source gate key is an actual interactive item with its own physical profile")
	check(not bridge.invoke(320, [handle(bridge, key)], {}).get("ok", false), "OBJECT_INFO_BITS rejects a non-AnimatedStatic object")
	var gate_id := handle(bridge, gate)
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var found := false
	for x in [0.0, -10.0, 10.0]:
		from = gate.global_transform * Vector3(x, 8, 8)
		to = gate.global_transform * Vector3(x, 8, -8)
		if not gate.segment_contact(from, to).is_empty():
			found = true
			break
	check(found, "a swept segment meets actual closed-gate triangles")
	bridge.invoke(193, [], {})
	key.position = from
	key.velocity = (to - from) * 5.0
	key.state = Thing.State.FLYING
	key._fly(0.2)
	check(StoryVm.as_int(bridge.invoke(194, [gate_id], {})["push"][0]) == 1 and key.impact_velocity.length() > 1.0, "real item physics contact records the struck gate for the original hit native")
	check(StoryVm.as_int(bridge.invoke(194, [plinth_id], {})["push"][0]) == 0, "hitting the gate does not count as hitting the plinth")
	bridge.invoke(193, [], {})
	check(StoryVm.as_int(bridge.invoke(194, [gate_id], {})["push"][0]) == 0, "CLEAR_HIT_OBJECT clears the actual contact record")
	key.state = Thing.State.IDLE
	var fx := bridge.invoke(53, [StoryVm.integer(34), handle(bridge, key), StoryVm.number(-1.0)], {})
	check(fx.get("ok", false), "source indefinite object highlight creates a real attached effect handle")
	if fx.get("ok", false):
		check(StoryVm.as_int(bridge.invoke(256, [fx["push"][0]], {})["push"][0]) == 1, "attached highlight remains a valid source object")
		world.story_delete_object(key)
		check(StoryVm.as_int(bridge.invoke(256, [fx["push"][0]], {})["push"][0]) == 0, "consuming a key also invalidates its attached highlight")
	var influence := world.story_add_influence(Vector3(1600, 0, -2400), 20, false)
	var influence_count := world.influence_sources.size()
	check(world.story_delete_object(influence) and world.influence_sources.size() == influence_count - 1, "source key cleanup removes its actual influence node")
	world.campaign.load_file(host.path_join("Scripts/Quests/challenge.chl"))
	var snapshot := [StoryVm.integer(1)]
	for coordinate in [1, 2, 3, 4, 5, 6]: snapshot.append(StoryVm.number(coordinate, StoryVm.VECTOR))
	snapshot.append_array([StoryVm.number(0), StoryVm.number(0), StoryVm.integer(2455), StoryVm.integer(1991), StoryVm.number(4258), StoryVm.integer(1), StoryVm.integer(55)])
	check(bridge.invoke(57, snapshot, {}).get("ok", false), "counted source snapshot accepts its one template parameter")
	var update := [StoryVm.number(0.25), StoryVm.number(0), StoryVm.integer(2455), StoryVm.integer(2025), StoryVm.number(4257), StoryVm.integer(1), StoryVm.integer(55)]
	var reply := bridge.invoke(238, update, {})
	check(reply.get("ok", false) and reply.get("pop", 0) == 7 and world.story_journal[55]["success"] == 0.25, "counted update consumes seven cells and records actual source progress")
	check(world.story_journal[55]["eye"] == Vector3(1, 2, -3) and world.story_journal[55]["source_cells"] == snapshot, "updating progress preserves the original snapshot camera and source record")
	update[5] = StoryVm.integer(12)
	check(not bridge.invoke(238, update, {}).get("ok", false) and world.story_journal[55]["success"] == 0.25, "malformed counted update cannot corrupt the saved event")
	check(world.story_play_sfx(174, Vector3.ZERO, false, 1) and world.story_sfx_streams.has("1:174"), "key reward sound decodes from the actual InGame bank")
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	print("GATE KEYS ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)
