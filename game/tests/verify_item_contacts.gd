extends SceneTree

class ContactWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func on_landed(_thing: Thing) -> void: pass

var failures := 0
var passed := 0
var host := "C:/Games/Black and White Complete Collection"
var capture := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	if not capture.is_empty():
		root.size = Vector2i(1600, 900)
		root.content_scale_size = Vector2i(1600, 900)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	var world := ContactWorld.new()
	world.bw_dir = host
	root.add_child(world)
	var opened := world.lnd.load_file(host.path_join("Data/Landscape/Land1.lnd"))
	opened = opened and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	check(opened, "load original landscape triangles and mobile meshes")
	if not opened:
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	if not capture.is_empty():
		if DisplayServer.get_name() == "headless":
			printerr("--capture requires a rendered Godot process")
			world.free()
			quit(2)
			return
		world._build_environment()
		world._build_terrain()
		world.add_child(world.cam)
		world.cam.current = true
		world.cam.far = 9000.0
	await verify_resting_rotation(world)
	verify_self_sweep(world)
	for kind in ["rock", "gate_key"]:
		var record: Dictionary = world.host_info.record(5 if kind == "rock" else 52)
		var below := 0
		var path_below := 0
		var worst := 0.0
		for i in 12:
			var start: Vector3 = world.to_world(Vector2(1652.78 + (i % 3) * 3.0, 2323.02 + (i / 3) * 3.0))
			var actor: Thing = world._place_mesh(record["mesh_id"], start + Vector3.UP * 12.0, i * 0.37, 1.0, kind)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.rotation.x = i * 0.19
			actor.rotation.z = i * 0.28
			actor.state = Thing.State.FLYING
			actor.velocity = Vector3(8.0 if i % 2 == 0 else -8.0, -100.0, 3.0)
			for step in 600:
				if actor.state != Thing.State.FLYING: break
				actor._fly(1.0 / 60.0)
				var path_clearance := minimum_clearance(actor, world)
				if path_clearance < -0.03:
					path_below += 1
					if path_below == 1:
						print("REPRO path ", kind, " scenario=", i, " frame=", step, " state=", actor.state, " clearance=", path_clearance, " root=", actor.position, " rotation=", actor.rotation)
			var clearance := minimum_clearance(actor, world)
			worst = minf(worst, clearance)
			if clearance < -0.03: below += 1
			actor.free()
		check(below == 0, "%s at tiger key has no mesh below rendered terrain after settling (%d penetrations, minimum %.4f)" % [kind, below, worst])
		check(path_below == 0, "%s stays above terrain throughout flight (%d penetrating frames)" % [kind, path_below])
	await verify_rock_floor(world)
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if is_instance_valid(node) and node.get_parent() == null: world.add_child(node)
	world.free()
	print("ITEM CONTACTS ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)

func verify_resting_rotation(world: Node) -> void:
	var geometry = preload("res://scripts/story_world_geometry.gd")
	var record: Dictionary = world.host_info.record(2)
	var actor: Thing = world._place_mesh(record["mesh_id"], world.to_world(Vector2(1634.074, 2303.932)), 0.0, 1.708553, "rock")
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.rotation = Vector3(1.971071, -1.121987, 1.596552)
	var support: float = world.ground_y(actor.position)
	for offset in geometry.body_offsets(actor): support = maxf(support, world.ground_y(actor.position + offset) - offset.y)
	actor.position.y = support + 0.001
	actor.velocity = Vector3(-1.495529, -1.0, -1.415657)
	actor.state = Thing.State.FLYING
	actor._fly(1.0 / 60.0)
	var clearance := minimum_clearance(actor, world)
	check(actor.state == Thing.State.IDLE and clearance >= -0.03, "ordinary rock remains above the real slope after its final roll (minimum %.4f)" % clearance)
	var settled := actor.position
	for i in 600: actor._physics_process(1.0 / 60.0)
	check(actor.position.is_equal_approx(settled) and minimum_clearance(actor, world) >= -0.03, "resting ordinary rock stays clear for ten seconds")
	if not capture.is_empty(): await capture_contact(world, [actor], "-roll.png")
	actor.free()

func verify_self_sweep(world: Node) -> void:
	var geometry = preload("res://scripts/story_world_geometry.gd").new()
	var actor: Thing = world._place_mesh(world.host_info.record(2)["mesh_id"], Vector3(1652, 100, -2323), 0.0, 1.0, "rock")
	actor.set_process(false)
	actor.set_physics_process(false)
	geometry.register_node(actor)
	actor.state = Thing.State.FLYING
	check(geometry.sweep(actor.position, actor.position + Vector3(20, 0, 0), actor).is_empty(), "swept item does not collide with its own actual mesh")
	actor.free()

func verify_rock_floor(world: Node) -> void:
	var opened: bool = world.island.load_file(host.path_join("Scripts/Land1.txt")) and world._load_landmark_animations()
	check(opened, "load actual island object placements for rock collision")
	if not opened: return
	world._spawn_objects()
	for actor in world.things:
		actor.set_process(false)
		actor.set_physics_process(false)
	var floor: Thing
	var distance := INF
	var bounds := AABB()
	for candidate in world.story_mobile_statics:
		if candidate.kind != "rock": continue
		var visual := candidate.get_child(0) as MeshInstance3D
		if visual == null: continue
		var box: AABB = visual.global_transform * visual.mesh.get_aabb()
		var d: float = Vector2(candidate.position.x - 1652.78, candidate.position.z + 2323.02).length()
		if box.size.y > 3.0 and d < distance:
			floor = candidate
			distance = d
			bounds = box
	check(floor != null, "nearby real boulder can support a dropped item")
	if floor == null: return
	var visual := floor.get_child(0) as MeshInstance3D
	var triangles := TriangleMesh.new()
	triangles.create_from_faces(visual.mesh.get_faces())
	var origin := bounds.get_center() + Vector3.UP * (bounds.size.y + 20.0)
	var inverse := visual.global_transform.affine_inverse()
	var hit := triangles.intersect_segment(inverse * origin, inverse * (origin - Vector3.UP * 100.0))
	check(not hit.is_empty(), "vertical probe intersects the boulder's real upper triangles")
	if hit.is_empty(): return
	var top: Vector3 = visual.global_transform * hit["position"]
	print("BOULDER REPRO subtype=", floor.get_meta("story_mobile_subtype"), " position=", floor.position, " distance_to_key=", distance, " top=", top)
	var falling: Thing = world._place_mesh(world.host_info.record(2)["mesh_id"], top + Vector3.UP * 12.0, 0.0, 0.25, "rock")
	falling.set_process(false)
	falling.set_physics_process(false)
	falling.state = Thing.State.FLYING
	falling.velocity = Vector3(0, -200, 0)
	var contact_captured := false
	for i in 600:
		if falling.state != Thing.State.FLYING: break
		falling._fly(1.0 / 60.0)
		if not capture.is_empty() and not contact_captured and not falling.impact_velocity.is_zero_approx():
			await capture_contact(world, [floor, falling], "-boulder.png")
			contact_captured = true
	var maximum := -INF
	for point in preload("res://scripts/story_world_geometry.gd").body_offsets(falling): maximum = maxf(maximum, falling.position.y + point.y)
	check(falling.state == Thing.State.IDLE and maximum >= top.y - 0.05, "fast rock drop stops above the real boulder rather than falling through to LND")
	falling.free()

func capture_contact(world: Node, actors: Array, suffix: String) -> void:
	var bounds := AABB()
	var found := false
	for actor in actors:
		for child in actor.get_children():
			if not child is MeshInstance3D or child.mesh == null: continue
			var box: AABB = child.global_transform * child.mesh.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
	var centre := bounds.get_center()
	var distance := maxf(bounds.size.length() * 1.8, 6.0)
	var eye := centre + Vector3.UP * distance
	var score := INF
	for direction in 8:
		var angle := TAU * float(direction) / 8.0
		var candidate := centre + Vector3(cos(angle), 1.0, sin(angle)).normalized() * distance
		var lift := 0.0
		for i in range(1, 65):
			var fraction := float(i) / 64.0
			var point := centre.lerp(candidate, fraction)
			lift = maxf(lift, (world.ground_y(point) + 0.5 - point.y) / fraction)
		candidate.y += lift
		var candidate_score := candidate.y
		var obstruction: Dictionary = world.world_geometry.raycast(candidate, centre - candidate, candidate.distance_to(centre))
		if not obstruction.is_empty() and not actors.has(obstruction["target"]): candidate_score += 10000.0
		if candidate_score < score:
			score = candidate_score
			eye = candidate
	world.cam.position = eye
	world.cam.look_at(centre)
	print("CAPTURE VIEW ", suffix, " target=", centre, " eye=", eye, " size=", bounds.size)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var filename := capture + suffix
	DirAccess.make_dir_recursive_absolute(filename.get_base_dir())
	var error := root.get_texture().get_image().save_png(filename)
	if error != OK:
		failures += 1
		printerr("FAIL capture ", filename, " error=", error)
	else:
		print("CAPTURE ", filename, " viewport=", root.size)

func minimum_clearance(actor: Thing, world: Node) -> float:
	var minimum := INF
	for child in actor.get_children():
		if not child is MeshInstance3D or child.mesh == null: continue
		var transform: Transform3D = actor.transform * child.transform
		var faces: PackedVector3Array = child.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			for point in [faces[i], faces[i + 1], faces[i + 2], (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0]:
				var positioned: Vector3 = transform * point
				minimum = minf(minimum, positioned.y - world.ground_y(positioned))
	return minimum
