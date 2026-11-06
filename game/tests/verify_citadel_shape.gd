extends SceneTree

const Citadel := preload("res://scripts/story_citadel_site.gd")
var failures := 0
var source := ""
var capture := ""


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
		elif arg.begins_with("--capture="):
			capture = arg.substr(10)
	call_deferred("run_test")


func run_test() -> void:
	var folder := source.path_join("Data/Citadel/OutsideMeshes")
	var site := Citadel.new()
	root.add_child(site)
	if not site.configure(folder):
		check(false, "read original neutral stage-zero temple and entrance")
		site.free()
		quit(1)
		return
	check(not site.model.visible, "planned temple starts hidden before construction")
	var side_height := -INF
	var vertices := 0
	for child in site._finished.get_children():
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					vertices += 1
					if absf(vertex.x) > 18.0:
						side_height = maxf(side_height, vertex.y)
	check(vertices == 2446, "retain all 2446 finished temple vertices and construction submeshes")
	check(side_height < 7.0, "neutral first temple has low rounded outer walls, without evil spikes")
	check(site.mesh_height > 23.0 and site.mesh_height < 23.2, "neutral central roof keeps the original B_TEMPLE02 height")
	site.set_progress(0.1)
	check(site.model.visible and site._scaffold.visible and site._scaffold.position.y < -10.0,
		"construction scaffolding rises only after work begins")
	site.set_progress(0.5)
	check(is_zero_approx(site._scaffold.position.y) and site._scaffold.visible,
		"unfinished temple retains original scaffolding and clipping")
	check(not site.entrance_hit(Vector3(-5.4, 3.2, 60), Vector3(0, 0, -1)),
		"unfinished doorway cannot enter the temple")
	site.set_progress(1.0)
	check(not site._scaffold.visible and site.model.visible, "finished temple removes construction scaffolding")
	var local_entrance := site.entrance_position()
	check(local_entrance.distance_to(Vector3(-5.3945, 3.2045, 10.6425)) < 0.002,
		"door marker comes from the reflected original Entrance collision mesh")
	check(site.entrance_hit(local_entrance + Vector3(0, 0, 50), Vector3(0, 0, -1)),
		"ray selects the real original doorway")
	check(not site.entrance_hit(Vector3(8, 12, 60), Vector3(0, 0, -1)),
		"ray aimed at a temple wall does not select the doorway")
	site.position = Vector3(1915.05, 29.48, -2508.89)
	site.rotation.y = PI / 3.0
	site.scale = Vector3.ONE * 1.5
	check(site.entrance_position().distance_to(site.global_transform * local_entrance) < 0.001,
		"door location follows the actual temple translation, rotation and scale")
	check(site.entrance_hit(site.global_transform * (local_entrance + Vector3(0, 0, 50)), site.global_basis * Vector3(0, 0, -1)),
		"door hit testing follows the actual temple transform")
	var landscape := LndReader.new()
	check(landscape.load_file(source.path_join("Data/Landscape/Land1.lnd")), "read original first-island terrain for the authored entrance camera")
	var plan := IslandScript.new()
	plan.load_file(source.path_join("Scripts/Land1.txt"))
	var planned: PackedStringArray = plan.all("CREATE_PLANNED_CITADEL")[0]["args"]
	var plan_position := IslandScript.pos(planned[1])
	site.position = Vector3(plan_position.x, landscape.height_at(plan_position.x, plan_position.y), -plan_position.y)
	site.rotation.y = float(planned[4]) / 1000.0
	site.scale = Vector3.ONE * float(planned[5]) / 1000.0
	check(is_equal_approx(site.rotation.y, 36.0), "planned citadel rotation is 36 radians, from the original angle/1000 format")
	var scripted_door := Vector3(1902.9706, 29.48, -2516.4956)
	var entrance := site.entrance_position()
	check(Vector2(entrance.x, entrance.z).distance_to(Vector2(scripted_door.x, scripted_door.z)) < 3.0,
		"original entrance collision agrees with the authored CitadelGuide doorway")
	var source_camera := Vector3(1895.131, 36.532, -2521.745)
	check(site.entrance_hit(source_camera, (entrance - source_camera).normalized()),
		"authored CitadelGuide camera sees the real doorway with the planned 36-radian orientation")
	var authored_camera := Camera3D.new()
	root.add_child(authored_camera)
	authored_camera.position = source_camera
	authored_camera.fov = 70.0
	authored_camera.look_at(Vector3(1998.835, -24.839, -2459.214))
	var screen := authored_camera.unproject_position(entrance)
	var view_size := Vector2(root.size)
	check(not authored_camera.is_position_behind(entrance) and Rect2(view_size * 0.15, view_size * 0.7).has_point(screen),
		"actual door projects inside the central authored camera frame, using its original below-ground look-at")
	check(site.entrance_hit(authored_camera.project_ray_origin(screen), authored_camera.project_ray_normal(screen)),
		"projected door click intersects the original collision triangles from the authored camera")
	authored_camera.free()
	print("CITADEL source-camera=", source_camera, " entrance=", entrance, " scripted-door=", scripted_door)
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await render_comparison(site, folder, source_camera)
	site.free()
	print("CITADEL_SHAPE failures=", failures)
	quit(0 if failures == 0 else 1)


func render_comparison(site: Node3D, folder: String, source_camera: Vector3) -> void:
	root.size = Vector2i(1400, 680)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	root.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("34455b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.78, 0.78, 0.78)
	root.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 85.0
	root.add_child(camera)
	camera.position = Vector3(0, 75, 140)
	camera.look_at(Vector3(0, 8, 0))
	camera.current = true
	var raw_rig := L3dRig.new()
	var raw := raw_rig.load_bytes(Citadel._load_mesh_bytes(folder.path_join("b_first_temple_l3d.zzz")),
		func(_id: int, _argb: int): return site._finished_material, PackedInt32Array([0]))
	root.add_child(raw)
	raw.position.x = -45.0
	site.position = Vector3(45.0, 0, 0)
	site.rotation = Vector3.ZERO
	site.scale = Vector3.ONE
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(200, 120)
	ground.position.y = -1.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6a7961")
	ground.material_override = material
	root.add_child(ground)
	for item in [["BEFORE: raw first-temple mesh", 30], ["AFTER: original neutral stage 0", 740]]:
		var label := Label.new()
		label.text = item[0]
		label.position = Vector2(item[1], 30)
		label.add_theme_font_size_override("font_size", 26)
		root.add_child(label)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture)
	raw.free()
	for child in root.get_children():
		if child is Label:
			child.hide()
	var landscape := LndReader.new()
	landscape.load_file(source.path_join("Data/Landscape/Land1.lnd"))
	site.position = Vector3(1915.05, landscape.height_at(1915.05, 2508.89), -2508.89)
	site.rotation.y = 36.0
	ground.position = site.position + Vector3(0, -1.1, 0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0
	camera.position = source_camera
	camera.look_at(Vector3(1998.835, -24.839, -2459.214))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture.get_basename() + "-door.png")
