extends SceneTree

class HandWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass

var host := "C:/Games/Black and White Complete Collection"
var capture := ""
var failures := 0
var passed := 0

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var world := HandWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	var opened := world.lnd.load_file(host.path_join(world.Data.SOURCES["landscape"]))
	opened = opened and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	opened = opened and world.island.load_file(host.path_join("Scripts/Land1.txt")) and world._load_landmark_animations()
	check(opened, "load original hand, landscape, visible meshes and collision hull sources")
	if not opened:
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	if not capture.is_empty():
		world._build_environment()
		world._build_terrain()
	world._spawn_objects()
	for thing in world.things:
		thing.set_process(false)
		thing.set_physics_process(false)
	world._build_hand()
	world.story_bridge = StoryNatives.new()
	world.story_bridge.configure(world)
	check(world.towns.all(func(t:Dictionary): return not t["marker"].visible), "restoration village has no prototype pillar of light")
	check(world.hand_ring.mesh == null, "original hand cursor has no ground torus")
	var plinth: OriginalLandmark = world.story_gate_plinth.landmark
	var key: Thing
	for item in world.story_mobile_statics:
		if item.get_meta("story_mobile_subtype", -1) == 52: key = item
	var top: float = plinth.position.y + world.g3d.mesh_index(336).get_aabb().end.y
	key.position = plinth.position + Vector3(0, 22, 0)
	key.state = Thing.State.FLYING
	key.velocity = Vector3.ZERO
	for i in 600: key._fly(1.0 / 60.0) if key.state == Thing.State.FLYING else key._physics_process(0.0)
	var minimum := INF
	for offset in world.world_geometry.body_offsets(key): minimum = minf(minimum, key.position.y + offset.y)
	check(key.state == Thing.State.IDLE and minimum >= top - 0.02 and minimum < top + 0.2, "released key rests on the original solid plinth hull for ten seconds")
	check(world.story_gate_plinth.info_bits() == 0, "physical contact alone does not fabricate a key quest completion")
	key.position = plinth.position + Vector3(0, 30, 0)
	key.state = Thing.State.FLYING
	key.velocity = Vector3(0, -250, 0)
	var penetrated := false
	for i in 180:
		if key.state == Thing.State.FLYING: key._fly(1.0 / 60.0)
		for offset in world.world_geometry.body_offsets(key): penetrated = penetrated or key.position.y + offset.y < top - 0.05
	check(not penetrated, "fast falling key cannot tunnel through the plinth")
	key.state = Thing.State.IDLE
	key.position = world.to_world(Vector2(1652.78, 2323.02))
	check(world.story_gate_plinth.accept(world.host_info.record(52)), "install actual tiger key through the source plinth operation")
	var installed := world.story_gate_plinth.get_child(0) as MeshInstance3D
	var installed_bottom := installed.position.y + installed.mesh.get_aabb().position.y
	check(absf(installed.position.y - (plinth.rig.bounds.size.y - 0.2)) < 0.0001 and installed_bottom >= plinth.rig.bounds.end.y - 0.25, "installed key uses plinth height and is fully exposed above its intended source overlap")
	world.world_geometry.register_node(world.story_gate_plinth, plinth)
	world._update_landmark_physics()
	var centre := plinth.position + Vector3(0, 4, 0)
	world.cam.position = centre + Vector3(12, 20, 30)
	world.cam.look_at(centre)
	var screen := world.cam.unproject_position(centre)
	var target := world.hand_target(screen)
	check(target.get("target") == plinth and target["point"].y > world.ground_y(target["point"]) + 3.0, "hand cursor lands on the visible pedestal rather than the ground beneath it")
	world._hand_action = "point"
	for i in 30: world._update_hand_pose(1.0 / 60.0, target)
	var pointer := world.hand_rig.root.global_transform * world.hand_pose.pointer_position()
	check(world.cam.unproject_position(pointer).distance_to(world.cam.unproject_position(target["point"])) < 0.5, "animated fingertip stays aligned with the selectable surface after clearance")
	check(world.hand_rig.root.basis.determinant() < 0.0, "ordinary cursor uses the original right-hand reflection")
	var ground_key := world.to_world(Vector2(1652.78, 2323.02))
	# Isolate the mobile surface above the original trees, whose real triangles
	# correctly occlude the lower test ray in this densely wooded area.
	key.position = ground_key + Vector3.UP * 80.0
	var key_centre: Vector3 = key.position + world.world_geometry.body_offsets(key)[1]
	for visual in key.get_children():
		if visual is MeshInstance3D: key_centre = key.global_transform * (visual.transform * visual.mesh.get_aabb().get_center())
	world.cam.position = key_centre + Vector3(10, 8, 18)
	world.cam.look_at(key_centre)
	await process_frame
	var key_selection := world.hand_target(world.cam.unproject_position(key_centre))
	check(key_selection.get("pickup") == key and key_selection["point"].y > ground_key.y + 79.0, "cursor selects a mobile object's visible mesh above the landscape")
	key.state = Thing.State.HELD
	await process_frame
	check(world.hand_target(world.cam.unproject_position(key_centre)).get("target") != key, "held object cannot become its own cursor surface")
	key.state = Thing.State.IDLE
	key.position = ground_key
	world.cam.position = centre + Vector3(12, 20, 30)
	world.cam.look_at(centre)
	await process_frame
	var near_size := hand_screen_size(world)
	world.cam.position = centre + Vector3(36, 60, 90)
	world.cam.look_at(centre)
	world._update_hand_pose(0.0, target)
	var far_size := hand_screen_size(world)
	check(near_size > 30.0 and far_size > near_size * 0.8 and far_size < near_size * 1.2, "hand maintains its cursor size after clearance at three times the camera distance")
	world.cam.position = centre + Vector3(12, 20, 30)
	world.cam.look_at(centre)
	world._hand_action = "rotate"
	world.held = key
	key.position = centre + Vector3(0, 10, 0)
	for i in 30: world._update_hand_pose(1.0 / 60.0, target)
	var grip := world.hand_rig.root.global_transform * world.hand_pose.grip_position()
	var key_top := 0.0
	for offset in world.world_geometry.body_offsets(key): key_top = maxf(key_top, offset.y)
	check(world.cam.unproject_position(grip).distance_to(world.cam.unproject_position(key.position + Vector3.UP * key_top)) < 0.5, "camera gestures preserve the actual grip attachment while carrying an item")
	world.held = null
	world._hand_action = "point"
	key.position = world.to_world(Vector2(1652.78, 2323.02))
	for i in 30: world._update_hand_pose(1.0 / 60.0, target)
	if not capture.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-plinth.png")
	var scroll := world.story_create_highlight(3, plinth.position + Vector3(-12, 0, 0), 55)
	scroll.set_draw_height(14)
	var scroll_centre: Vector3 = scroll.visual.global_transform * scroll.visual.mesh.get_aabb().get_center()
	world.cam.position = scroll_centre + Vector3(0, 12, 35)
	world.cam.look_at(scroll_centre)
	scroll.advance(0.0, world.cam)
	var padded := world.cam.unproject_position(scroll_centre) + Vector2(24, 0)
	check(world.hand_target(padded).get("scroll") == scroll, "scroll can be targeted twenty-four pixels from its centre")
	world._hand_action = "point"
	for i in 30: world._update_hand_pose(1.0 / 60.0, world.hand_target(padded))
	var click := InputEventMouseButton.new()
	click.position = padded
	click.button_index = MOUSE_BUTTON_LEFT
	world.loaded = true
	click.pressed = true
	world._unhandled_input(click)
	click.pressed = false
	world._unhandled_input(click)
	world.loaded = false
	check(scroll.active and world.story_bridge.clicked_thing.get_ref() == scroll and world.held == null, "forgiving scroll area works through actual mouse press and release")
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-scroll.png")
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(20, 20, 1)
	wall.mesh = box
	wall.transform = Transform3D(world.cam.basis, world.cam.position.lerp(scroll_centre, 0.5))
	world.add_child(wall)
	world.world_geometry.register_node(wall)
	check(world.hand_target(padded).get("scroll") == null, "larger scroll area still rejects a scroll behind a solid wall")
	for property in ["hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	print("HAND WORLD ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)


func hand_screen_size(world: Node) -> float:
	var geometry: Dictionary = world.hand_pose.geometry(world.hand_rig.root.basis)
	var bounds: AABB = geometry["bounds"]
	var rect := Rect2(world.cam.unproject_position(world.hand_rig.root.position + bounds.get_center()), Vector2.ZERO)
	for i in 8: rect = rect.expand(world.cam.unproject_position(world.hand_rig.root.position + bounds.get_endpoint(i)))
	return maxf(rect.size.x, rect.size.y)
