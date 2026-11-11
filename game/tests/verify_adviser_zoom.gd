extends SceneTree

class AdviserWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var host := "C:/Games/Black and White Complete Collection"
var capture := ""
var passed := 0
var failures := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	root.size = Vector2i(1600, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	var world := AdviserWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	check(world.lnd.load_file(host.path_join("Data/Landscape/Land1.lnd")), "load actual first-island terrain")
	world.sea_y = world.lnd.sea_level
	world._build_environment()
	if DisplayServer.get_name() != "headless": world._build_terrain()
	world._build_advisers()
	check(world.adviser_animations.size() == 2, "load both actual adviser skeletons and authored clips")
	world.focus = world.to_world(Vector2(1600, 2300))
	world.dist = 40.0
	world._update_camera()
	world._sync_adviser_view()
	await process_frame
	await process_frame
	world.story_move_adviser(1, Vector2(0.8, 0.85))
	world.story_move_adviser(2, Vector2(0.2, 0.85))
	await create_timer(0.7).timeout
	world.loaded = true
	world.story_interface_level = 15
	for i in 50:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = Vector2(800, 450)
		world._unhandled_input(wheel)
	world._update_camera()
	check(is_equal_approx(world.dist, float(world.cfg_camera["max_dist"])), "actual tutorial wheel input reaches maximum zoom distance")
	for dimensions in [Vector2i(1600, 900), Vector2i(1200, 900), Vector2i(1920, 800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		world._sync_adviser_view()
		for i in 30: world._advance_advisers(1.0 / 60.0)
		for item in world.adviser_animations:
			var anchor: Node3D = item["rig"].root.get_parent()
			var projected: Vector2 = world.cam.unproject_position(anchor.global_position) / root.get_visible_rect().size
			var expected := Vector2(0.8 if item["id"] == "good" else 0.2, 0.85)
			check(projected.distance_to(expected) < 0.002, "%s scripted screen anchor survives zoom and aspect %s (actual %s)" % [item["id"], dimensions, projected])
		var before := snapshot_bones(world)
		var before_image := await draw(world, "")
		for i in 24: world._advance_advisers(1.0 / 60.0)
		var after_image := await draw(world, "-hover-%dx%d.png" % [dimensions.x, dimensions.y])
		var after := snapshot_bones(world)
		for id in ["good", "evil"]:
			check(bone_change(before[id], after[id]) > 0.001, "%s authored hover keeps animating at maximum zoom %s" % [id, dimensions])
			if before_image != null and after_image != null:
				check(image_change(before_image, after_image, id == "good") > 5, "%s rendered pixels keep animating at %s" % [id, dimensions])
	world.story_move_adviser(1, Vector2(0.75, 0.8))
	await create_timer(0.2).timeout
	root.size = Vector2i(1280, 960)
	await process_frame
	await process_frame
	world._sync_adviser_view()
	await create_timer(0.5).timeout
	world._sync_adviser_view()
	var good_anchor: Node3D = world.cam.get_node("Adviser_good")
	var landed: Vector2 = world.cam.unproject_position(good_anchor.global_position) / root.get_visible_rect().size
	check(landed.distance_to(Vector2(0.75, 0.8)) < 0.002, "resize during adviser flight preserves its normalized destination")
	world.cam.keep_aspect = Camera3D.KEEP_WIDTH
	world.cam.fov = 60.0
	world._sync_adviser_view()
	await process_frame
	await process_frame
	var world_projection: Projection = world.cam.get_camera_projection()
	var overlay_projection: Projection = world._adviser_view_camera.get_camera_projection()
	check(world_projection.x.distance_to(overlay_projection.x) < 0.00001 and world_projection.y.distance_to(overlay_projection.y) < 0.00001, "adviser overlay copies the world's field of view and keep-aspect projection")
	world.cam.keep_aspect = Camera3D.KEEP_HEIGHT
	world.cam.fov = 75.0
	root.size = Vector2i(1920, 800)
	await process_frame
	await process_frame
	world._sync_adviser_view()
	world.story_move_adviser(1, Vector2(0.8, 1.0), true)
	world.story_move_adviser(2, Vector2(0.2, 1.0), true)
	await create_timer(0.7).timeout
	for i in 240: world._advance_advisers(1.0 / 60.0)
	for item in world.adviser_animations:
		var rig: L3dRig = item["rig"]
		var head: int = item["animation"].adviser_metadata["head_bone"]
		var head_world: Vector3 = rig.root.global_transform * rig.skeleton.get_bone_global_pose(head).origin
		var screen: Vector2 = world.cam.unproject_position(head_world) / root.get_visible_rect().size
		check(screen.y > 0.7 and screen.y < 0.97, "%s retains the authored bottom-edge cling with visible head" % item["id"])
	await draw(world, "-cling-maxzoom.png")
	world._setup_original_dialogue()
	check(world.story_play_voice(5128), "start original adviser tutorial voice while clinging")
	var mouth_open := false
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not mouth_open:
		await process_frame
		world._advance_advisers(1.0 / 60.0)
		for item in world.adviser_animations:
			if item["id"] == "good" and item["pose"]._mouth > 0.1: mouth_open = true
	check(mouth_open and world._adviser_clinging.get("good", false), "original voice drives the speaking pose while the authored cling remains active")
	await draw(world, "-cling-speaking-maxzoom.png")
	if world.dialogue != null: world.dialogue.stop()
	await create_timer(0.1).timeout
	world.loaded = false
	for property in ["hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Node = world.get(property)
		if is_instance_valid(node) and node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	print("ADVISER ZOOM ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)

func snapshot_bones(world: Node) -> Dictionary:
	var result := {}
	for item in world.adviser_animations:
		var rig: L3dRig = item["rig"]
		var transforms: Array[Transform3D] = []
		for bone in rig.bone_count: transforms.append(rig.skeleton.get_bone_pose(bone))
		result[item["id"]] = transforms
	return result

func bone_change(before: Array[Transform3D], after: Array[Transform3D]) -> float:
	var error := 0.0
	for i in before.size():
		error = maxf(error, before[i].origin.distance_to(after[i].origin))
		for axis in 3: error = maxf(error, before[i].basis[axis].distance_to(after[i].basis[axis]))
	return error

func draw(world: Node, suffix: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = world._adviser_viewport.get_texture().get_image()
	if not capture.is_empty() and not suffix.is_empty():
		var path := capture + suffix
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		check(root.get_texture().get_image().save_png(path) == OK, "save rendered adviser frame " + suffix)
	return image

func image_change(before: Image, after: Image, right_half: bool) -> int:
	var changes := 0
	for y in range(0, before.get_height(), 3):
		var start := before.get_width() / 2 if right_half else 0
		var end := before.get_width() if right_half else before.get_width() / 2
		for x in range(start, end, 3):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if Vector4(a.r, a.g, a.b, a.a).distance_to(Vector4(b.r, b.g, b.b, b.a)) > 0.05: changes += 1
	return changes
