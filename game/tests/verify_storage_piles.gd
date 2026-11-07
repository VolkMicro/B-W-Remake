extends SceneTree
## Integrator check: real installed meshes, anchors and one authoritative stock.
## This fixture edits quantities explicitly; it is not a manual playthrough.

class StorageWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass

var host := "C:/Games/Black and White Complete Collection"
var capture := ""
var failures := 0
var passed := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	root.size = Vector2i(1600, 900)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	var world := StorageWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	var valid := world.lnd.load_file(host.path_join("Data/Landscape/Land1.lnd"))
	valid = valid and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	valid = valid and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	valid = valid and world.island.load_file(host.path_join("Scripts/Land1.txt"))
	check(valid, "load actual island, object quantities and storage meshes")
	if not valid:
		dispose(world)
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	check(world.host_info.storage_piles.size() == 6, "source has one grain and five wood definitions")
	var storage_nodes: Array[Node3D] = []
	for command in world.island.all("CREATE_ABODE"):
		var args: PackedStringArray = command["args"]
		if not args[2].ends_with("STORAGE_PIT"): continue
		var placement := IslandScript.placement("abode", args)
		var storage := world._place_mesh(world.Data.ABODES[args[2]], world.to_world(IslandScript.pos(args[1])), placement["angle"], placement["scale"], "house", PackedInt32Array([0]))
		storage.set_meta("original_type", args[2])
		storage_nodes.append(storage)
		var store = world.story_bind_storage(storage, Vector2i(int(args[5]), int(args[6])))
		var view = world.story_storage_view(storage)
		check(store != null and view != null, "bind actual " + args[2] + " to stock and six piles")
		if store == null or view == null: continue
		check(store.snapshot() == Vector2i(int(args[5]), int(args[6])), "preserve original aggregate stocks including overflow")
		var metrics: PackedVector3Array = world.g3d.extra_metric_positions(world.Data.ABODES[args[2]])
		check(metrics.size() == 18 and metrics[0].distance_to(Vector3(-3.584351, 0, -7.524393)) < 0.0001, "read ExtraMetrics and reflect Z exactly once")
		var total := Vector2i.ZERO
		var anchors_correct := true
		var transforms_correct := true
		for i in 6:
			var state: Dictionary = view.state(i)
			var mesh_instance: MeshInstance3D = view.pile(i)
			total[int(state["resource"])] += int(state["amount"])
			var anchor: Vector3 = storage.global_transform * metrics[5 if i == 0 else i - 1]
			anchor.y += world.ground_y(anchor) - world.ground_y(storage.global_position)
			anchors_correct = anchors_correct and mesh_instance.global_position.distance_to(anchor + Vector3.UP * float(state["y_offset"])) < 0.001
			transforms_correct = transforms_correct and mesh_instance.scale.is_equal_approx(Vector3.ONE) and absf(angle_difference(mesh_instance.rotation.y, storage.rotation.y)) < 0.0001
		check(total == store.snapshot() and view.get_child_count() == 6, "all quantities represented once; no seventh grain clone")
		check(anchors_correct and transforms_correct, "actual anchors use building pose and terrain; pile size remains one")
	check(storage_nodes.size() == 2, "both actual first-island storage pits tested")
	if storage_nodes.is_empty():
		dispose(world)
		quit(1)
		return
	var storage := storage_nodes[0]
	var store = world.story_resource_store(storage)
	var view = world.story_storage_view(storage)
	if view == null:
		dispose(world)
		quit(1)
		return
	if not capture.is_empty():
		if DisplayServer.get_name() == "headless":
			check(false, "captures require rendering")
		else:
			world._build_environment()
			world._build_terrain()
			world.add_child(world.cam)
			world.cam.current = true
			world.cam.far = 9000.0
			var centre := storage.global_position + Vector3.UP * 3.0
			world.cam.position = centre + Basis(Vector3.UP, storage.rotation.y) * Vector3(22, 45, 48)
			world.cam.look_at(centre)
			await save_capture("-full.png")
	var initial: Vector2i = store.snapshot()
	var grain_taken: int = store.take(0, initial.x - 7500)
	var wood_taken: int = store.take(1, initial.y - 12500)
	view.advance(0.0)
	check(view.state(0)["amount"] == 7500 and view.state(3)["amount"] == 2500 and view.state(5)["amount"] == 0, "withdrawals immediately update real pile targets")
	view.advance(0.5)
	check(view.state(0)["proportion"] > view.state(0)["target"], "actual food mesh lowers continuously during transition")
	view.advance(0.5)
	check(absf(float(view.state(0)["proportion"]) - 0.774375) < 0.00001 and absf(float(view.state(3)["proportion"]) - 0.525) < 0.00001, "actual meshes reach food/wood half-stock levels")
	check(not view.pile(4).visible and not view.pile(5).visible, "spent wood piles disappear after settling")
	if not capture.is_empty() and DisplayServer.get_name() != "headless": await save_capture("-partial.png")
	check(store.add(0, grain_taken) == grain_taken and store.add(1, wood_taken) == wood_taken and store.snapshot() == initial, "return conserves quantities including initial overflow")
	view.advance(1.0)
	check(view.state(5)["amount"] == 10000 and view.pile(5).visible, "last wood pile retains 10000 overflow and returns to view")
	store.take(0, 2147483647)
	store.take(1, 2147483647)
	view.advance(1.0)
	var empty := true
	for i in 6: empty = empty and not view.pile(i).visible and view.state(i)["amount"] == 0
	check(empty and store.take(0, 100) == 0 and store.take(1, 100) == 0, "empty actual storage is invisible and cannot issue resource")
	if not capture.is_empty() and DisplayServer.get_name() != "headless": await save_capture("-empty.png")
	storage.set_meta("story_food_stock", 1000)
	storage.set_meta("story_wood_stock", 500)
	view.advance(1.0)
	check(view.state(0)["amount"] == 1000 and view.state(1)["amount"] == 500 and store.snapshot() == Vector2i(1000, 500), "legacy metadata writes and view share one wallet")
	var before := world.things.size()
	world._spawn_food()
	check(world.things.size() == before, "campaign does not spawn three unquantified sandbox wheat props")
	dispose(world)
	await process_frame
	print("RESULT ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)

func dispose(world: Node) -> void:
	# _ready is suppressed by the fixture, so attach its preallocated nodes
	# before freeing the world, as in the other isolated world probes.
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if is_instance_valid(node) and node.get_parent() == null: world.add_child(node)
	world.free()

func save_capture(suffix: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
	check(root.get_texture().get_image().save_png(capture + suffix) == OK, "save actual storage " + suffix)
