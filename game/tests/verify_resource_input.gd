extends SceneTree
## Real installed hand, meshes and input dispatch, with a controlled fixture clock.
class ResourceWorld extends "res://scripts/main.gd":
	var manual := false
	func _ready() -> void: pass
	func _process(delta: float) -> void:
		if manual and loaded:
			_move_player_camera(delta)
			_update_camera()
			_update_world(delta)

var host := "C:/Games/Black and White Complete Collection"
var capture := ""
var world: ResourceWorld
var failures := 0
var passed := 0
var manual := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
		if arg == "--manual": manual = true
	root.size = Vector2i(1600, 900)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	world = ResourceWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	var loaded := world.lnd.load_file(host.path_join("Data/Landscape/Land1.lnd"))
	loaded = loaded and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	loaded = loaded and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	loaded = loaded and world.island.load_file(host.path_join("Scripts/Land1.txt"))
	check(loaded, "read actual hand resource profiles and storage meshes")
	if not loaded: finish(); return
	world.sea_y = world.lnd.sea_level
	world.towns.append({"pos":world.to_world(Vector2(1826.79,2641.36)),"mine":true,"belief":1.0,"name":"test"})
	var storage: Thing
	for command in world.island.all("CREATE_ABODE"):
		var args: PackedStringArray = command["args"]
		if args[2] != "NORSE_ABODE_STORAGE_PIT": continue
		var placement := IslandScript.placement("abode",args)
		storage = world._place_mesh(world.Data.ABODES[args[2]],world.to_world(IslandScript.pos(args[1])),placement["angle"],placement["scale"],"house",PackedInt32Array([0]))
		storage.set_meta("original_type",args[2])
		world.story_bind_storage(storage,Vector2i(int(args[5]),int(args[6])))
		world.world_physics.register_node(storage)
		break
	check(storage != null, "create actual village storage")
	if storage == null: finish(); return
	world._build_hand()
	world.add_child(world.cam)
	world.cam.current = true
	world.cam.far = 9000.0
	world.focus = storage.position
	world.dist = 72.0
	world.yaw = storage.rotation.y + 0.45
	world.pitch = deg_to_rad(52)
	world._update_camera()
	world.loaded = true
	check(world.resource_interaction.configure(world), "configure new resource controller with original data")
	check(world.host_info.hand_resources[0]["mesh_id"] == 323 and world.host_info.hand_resources[1]["mesh_id"] == 329, "use actual HandFood/HandWood meshes rather than sandbox placeholders")
	if not capture.is_empty():
		world._build_environment()
		world._build_terrain()
	if manual:
		if capture.is_empty():
			world._build_environment()
			world._build_terrain()
		world.manual = true
		world.get_window().title = "Black & White — проверка мыши и склада"
		print("RESOURCE_MANUAL_READY native input, normal time; diagnostic fixture, not campaign")
		return
	await process_frame
	world._hand_pointer_dynamics.reset(Vector2(400,300))
	for cursor in [Vector2(420,310),Vector2(460,330),Vector2(500,340)]:
		var motion := InputEventMouseMotion.new()
		motion.position = cursor
		motion.relative = Vector2(5,2)
		Input.parse_input_event(motion)
	await process_frame
	world._update_world(0.02)
	var split_phases: Vector2 = world._hand_pointer_phases
	check(split_phases.distance_to(Vector2(0,0.75)) < 0.0001, "real mouse events feed source absolute-cursor lag once per frame")
	world._hand_pointer_dynamics.reset(Vector2(400,300))
	var single := InputEventMouseMotion.new()
	single.position = Vector2(500,340)
	single.relative = Vector2(100,40)
	Input.parse_input_event(single)
	await process_frame
	world._update_world(0.02)
	check(world._hand_pointer_phases.distance_to(split_phases) < 0.0001, "hand animation response is independent of event count and relative delta")
	var store = world.story_resource_store(storage)
	var initial: Vector2i = store.snapshot()
	for index in [0,1]:
		var screen := screen_for_resource(storage,index)
		check(screen.is_finite(), "cursor ray selects visible resource%d inside actual storage" % index)
		if not screen.is_finite(): continue
		var pose_before: Array[Transform3D] = world.hand_pose.sample(0.01)
		var yaw_before := world.yaw
		await button(MOUSE_BUTTON_RIGHT,screen,true)
		check(world.resource_interaction.amount() == 25 and world.resource_interaction.collecting(), "RMB begins original initial25 resource%d" % index)
		for step in 12:
			world.resource_interaction.advance(1.0/30.0)
			world.resource_interaction.advance_visuals(1.0/30.0)
		var quantity := world.resource_interaction.amount()
		check(quantity == 57 and store.stock(index) + quantity == initial[index], "held Action gathers four turns and conserves resource%d" % index)
		await button(MOUSE_BUTTON_RIGHT,screen,false)
		world.resource_interaction.advance(2.0)
		check(world.resource_interaction.amount() == quantity and not world.resource_interaction.collecting(), "release stops gathering but keeps resource%d in hand" % index)
		world._cursor_screen = screen
		world._update_world(0.05)
		check(world._hand_action == "hold_side" and world.hand_pose.state == "hold_side", "normal hover cannot overwrite actual multipickup pose")
		check(world.resource_interaction.visual.visible and world.resource_interaction.visual.mesh == world.g3d.mesh_index(world.host_info.hand_resources[index]["mesh_id"]), "held quantity has its original visible resource model")
		var pose_after: Array[Transform3D] = world.hand_pose.sample(0.05)
		check(pose_changed(pose_before,pose_after), "original hand skeleton changes for resource grasp")
		check(world.resource_interaction.stream.active_count() > 0, "pickup creates visible resource transport independent of quantity")
		if not capture.is_empty(): await shot("-held%d.png" % index)
		await button(MOUSE_BUTTON_RIGHT,screen,true)
		await button(MOUSE_BUTTON_RIGHT,screen,false)
		check(world.resource_interaction.amount() == 0 and store.snapshot() == initial, "second Action returns actual resource%d once" % index)
		check(world.yaw == yaw_before, "resource Action never rotates camera")
		world.resource_interaction.advance_visuals(1.0)
		check(world.resource_interaction.stream.active_count() == 0, "transport ends without retaining duplicate economic resource")
	# LMB is camera; MMB and Shift rotate without collecting or releasing.
	var screen := screen_for_resource(storage,0)
	await button(MOUSE_BUTTON_LEFT,screen,true)
	await button(MOUSE_BUTTON_LEFT,screen,false)
	check(world.resource_interaction.amount() == 0, "LMB Move does not collect storage")
	var before := world.yaw
	await button(MOUSE_BUTTON_MIDDLE,Vector2(800,450),true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(850,450)
	motion.relative = Vector2(50,0)
	Input.parse_input_event(motion)
	await process_frame
	await button(MOUSE_BUTTON_MIDDLE,motion.position,false)
	check(world.yaw != before and store.snapshot() == initial, "middle-button camera rotation preserves stocks")
	# A ground drop owns real quantity and uses existing swept item physics.
	var wood_screen := screen_for_resource(storage,1)
	await button(MOUSE_BUTTON_RIGHT,wood_screen,true)
	await button(MOUSE_BUTTON_RIGHT,wood_screen,false)
	var ground_screen := Vector2(400,650)
	var ground := world.hand_target(ground_screen)
	check(ground.get("target") == null and ground["point"].y > world.sea_y, "select bare land for quantified resource drop")
	await button(MOUSE_BUTTON_RIGHT,ground_screen,true)
	await button(MOUSE_BUTTON_RIGHT,ground_screen,false)
	var dropped: Thing = world.things.back() if not world.things.is_empty() else null
	check(dropped != null and dropped.get_meta("loose_resource",false) and world.resource_interaction.amount() == 0, "Action places a real quantified wood pile on land")
	if dropped != null:
		var drop_scale := dropped.scale.x
		# A second real transfer with a different hand depth must create the
		# same world pile, even though its held presentation changes with zoom.
		var saved_hand_transform := world.hand_rig.root.global_transform
		world._hand_surface_motion.reset(1000.0)
		world.hand_rig.root.basis = world.hand_rig.root.basis.scaled_local(Vector3.ONE * 5.6363636364)
		check(world.resource_interaction.begin(world.hand_target(wood_screen)), "start a second quantified transfer at far hand depth")
		world.resource_interaction.stop()
		# begin updates the pose; set the actual far-distance presentation.
		world.hand_rig.root.basis = saved_hand_transform.basis.scaled_local(Vector3.ONE * 5.6363636364)
		world.resource_interaction.update_visual()
		world.resource_interaction.release(ground)
		var second_drop: Thing = world.things.back()
		check(second_drop != dropped and is_equal_approx(second_drop.scale.x, drop_scale), "equal quantities dropped at different hand scales have identical world collision size")
		var second_store = world.story_resource_store(second_drop)
		store.add(1, second_store.take(1, 25))
		world.things.erase(second_drop)
		world.resource_stores.erase(second_drop.get_instance_id())
		second_drop.state = Thing.State.DEAD
		second_drop.queue_free()
		world.hand_rig.root.global_transform = saved_hand_transform
		world._hand_surface_initialized = false
		dropped.set_physics_process(false)
		for step in 600:
			if dropped.state != Thing.State.FLYING: break
			dropped._fly(1.0/60.0)
		var loose_store = world.story_resource_store(dropped)
		check(loose_store.stock(1) == 25 and store.stock(1) + 25 == initial.y, "ground stock and warehouse conserve every dropped unit")
		check(dropped.position.y >= world.ground_y(dropped.position)-0.03 and dropped.state != Thing.State.FLYING, "dropped resource collides with actual island and settles")
		var loose_screen := Vector2.INF
		for child in dropped.get_children():
			if not child is MeshInstance3D: continue
			var faces: PackedVector3Array = child.mesh.get_faces()
			for i in range(0,faces.size(),3):
				var p: Vector3 = child.global_transform * ((faces[i]+faces[i+1]+faces[i+2])/3.0)
				var candidate := world.cam.unproject_position(p)
				if world.hand_target(candidate).get("target") == dropped:
					loose_screen = candidate
					break
		check(loose_screen.is_finite(), "cursor selects actual fallen resource geometry")
		var near_miss := Vector2.INF
		var loose_centre := world.cam.unproject_position(dropped.position + Vector3.UP * 1.5)
		for offset in [Vector2(25,0),Vector2(-25,0),Vector2(0,25),Vector2(0,-25)]:
			var candidate: Vector2 = loose_centre + offset
			var hit := world.world_geometry.raycast(world.cam.project_ray_origin(candidate),world.cam.project_ray_normal(candidate),world.cam.position.distance_to(world.ground_point(candidate)))
			if hit.get("target") != dropped and world.hand_target(candidate).get("target") == dropped:
				near_miss = candidate
				break
		check(near_miss.is_finite() and world.hand_target(near_miss).get("resource",-1) == 1, "forgiving near-miss selection keeps a loose pile on the resource gathering path")
		if near_miss.is_finite(): loose_screen = near_miss
		if loose_screen.is_finite():
			await button(MOUSE_BUTTON_RIGHT,loose_screen,true)
			await button(MOUSE_BUTTON_RIGHT,loose_screen,false)
			check(world.resource_interaction.amount() == 25 and world.held == null, "Action regathers fallen resource without cloning quantity or lifting its rigid body")
			await button(MOUSE_BUTTON_RIGHT,wood_screen,true)
			await button(MOUSE_BUTTON_RIGHT,wood_screen,false)
			check(store.snapshot() == initial and world.resource_interaction.amount() == 0, "warehouse to hand to ground to hand to warehouse conserves stock")
	var storage_hit := world.world_physics.raycast(storage.global_position+Vector3.UP*100.0,Vector3.DOWN,150.0)
	check(storage_hit.get("target") == storage and storage_hit["point"].y > world.ground_y(storage.global_position)+1.0, "original warehouse and its resource meshes participate in item physics")
	# Gesture release samples actual carried world positions, not a target arc.
	var rock_row: Dictionary = world.host_info.record(2)
	var rock_point: Vector3 = world.hand_target(Vector2(520,620))["point"]
	var rock := world._place_mesh(rock_row["mesh_id"],rock_point,0.0,0.7,"rock")
	world.things.append(rock)
	rock.set_physics_process(false)
	var rock_screen := screen_for_thing(rock)
	check(rock_screen.is_finite(), "cursor selects original rock for gesture input")
	if rock_screen.is_finite():
		await button(MOUSE_BUTTON_RIGHT,rock_screen,true)
		await button(MOUSE_BUTTON_RIGHT,rock_screen,false)
		check(world.held == rock and rock.state == Thing.State.HELD, "first Action release keeps picked object held")
		await button(MOUSE_BUTTON_RIGHT,rock_screen,true)
		await flick(rock_screen,Vector2(12,-2))
		await button(MOUSE_BUTTON_RIGHT,rock_screen+Vector2(72,-12),false)
		check(world.held == null and rock.state == Thing.State.FLYING and rock.thrown and rock.velocity.length() > 2.0, "moving hand then releasing Action transfers world velocity immediately")
		var released := rock.position
		rock._fly(1.0/60.0)
		check(rock.position.distance_to(released) > 0.01 and rock.position.distance_to(released) < 5.1, "thrown object follows a continuous physical trajectory without target teleport")
		for step in 600:
			if rock.state != Thing.State.FLYING: break
			rock._fly(1.0/60.0)
		check(rock.state != Thing.State.FLYING and rock.position.y >= world.ground_y(rock.position)-0.03, "gesture-thrown original rock collides and settles above terrain")
		# A camera gesture must retain the carried object and cancel pending fling.
		world.pick_up(rock)
		await button(MOUSE_BUTTON_RIGHT,rock_screen,true)
		await button(MOUSE_BUTTON_MIDDLE,rock_screen,true)
		await button(MOUSE_BUTTON_RIGHT,rock_screen,false)
		await button(MOUSE_BUTTON_MIDDLE,rock_screen,false)
		check(world.held == rock, "camera gesture with Action held cancels throw and retains object")
		var saved_focus := world.focus
		var saved_dist := world.dist
		var saved_yaw := world.yaw
		for camera_input in ["wheel","walk","turn"]:
			await button(MOUSE_BUTTON_RIGHT,rock_screen,true)
			if camera_input == "wheel":
				await button(MOUSE_BUTTON_WHEEL_DOWN,rock_screen,true)
				await button(MOUSE_BUTTON_WHEEL_DOWN,rock_screen,false)
			else:
				var key := InputEventKey.new()
				key.keycode = KEY_W if camera_input == "walk" else KEY_Q
				key.pressed = true
				Input.parse_input_event(key)
				await process_frame
				world._move_player_camera(0.1)
				key.pressed = false
				Input.parse_input_event(key)
				await process_frame
			world._update_camera()
			world._update_world(0.1)
			await button(MOUSE_BUTTON_RIGHT,rock_screen,false)
			check(world.held == rock and not world._action_release, "camera %s cancels accidental momentum and retains held object" % camera_input)
		world.focus = saved_focus
		world.dist = saved_dist
		world.yaw = saved_yaw
		world._update_camera()
		await button(MOUSE_BUTTON_RIGHT,rock_screen,true)
		var placed_from := rock.position
		await button(MOUSE_BUTTON_RIGHT,rock_screen,false)
		check(world.held == null and not rock.thrown and rock.velocity.is_zero_approx(), "slow Action release places object with zero initial velocity")
		check(rock.position.distance_to(placed_from) < 0.001, "slow release begins at the visible grip without a ground-anchor teleport")
	wood_screen = screen_for_resource(storage,1)
	await button(MOUSE_BUTTON_RIGHT,wood_screen,true)
	await button(MOUSE_BUTTON_RIGHT,wood_screen,false)
	await button(MOUSE_BUTTON_RIGHT,wood_screen,true)
	await flick(wood_screen,Vector2(12,-2))
	await button(MOUSE_BUTTON_RIGHT,wood_screen+Vector2(72,-12),false)
	var thrown_resource: Thing = world.things.back()
	check(thrown_resource.get_meta("loose_resource",false) and thrown_resource.thrown and thrown_resource.velocity.length() > 2.0, "same gesture throws a quantified resource body")
	check(world.resource_interaction.amount() == 0 and world.story_resource_store(thrown_resource).stock(1) == 25 and store.stock(1)+25 == initial.y, "resource throw conserves warehouse plus actual flying quantity")
	# Empty source: real input must not spawn held quantity or resource mesh.
	store.take(0,2147483647)
	world.story_storage_view(storage).sync(true)
	await button(MOUSE_BUTTON_RIGHT,screen,true)
	await button(MOUSE_BUTTON_RIGHT,screen,false)
	check(world.resource_interaction.amount() == 0, "empty storage cannot manufacture resources via repeated Action")
	finish()

func button(index: MouseButton, screen: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = screen
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func screen_for_resource(storage: Node3D,index: int) -> Vector2:
	var view = world.story_storage_view(storage)
	for i in 6:
		if int(view.state(i)["resource"]) != index: continue
		var mesh_instance: MeshInstance3D = view.pile(i)
		var bounds := mesh_instance.mesh.get_aabb()
		var points := PackedVector3Array([bounds.get_center()])
		for j in 8: points.append(bounds.get_endpoint(j).lerp(bounds.get_center(),0.2))
		for point in points:
			var screen := world.cam.unproject_position(mesh_instance.global_transform * point)
			var selection := world.hand_target(screen)
			if selection.get("target") == storage and selection.get("resource",-1) == index: return screen
	return Vector2.INF

func screen_for_thing(thing: Thing) -> Vector2:
	for child in thing.get_children():
		if not child is MeshInstance3D: continue
		var faces: PackedVector3Array = child.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var point: Vector3 = child.global_transform*((faces[i]+faces[i+1]+faces[i+2])/3.0)
			var screen := world.cam.unproject_position(point)
			if world.hand_target(screen).get("pickup") == thing: return screen
	return Vector2.INF

func flick(start: Vector2,step: Vector2) -> void:
	for i in range(1,7):
		var event := InputEventMouseMotion.new()
		event.position = start+step*i
		event.relative = step
		Input.parse_input_event(event)
		await process_frame
		world._update_world(1.0/60.0)

func pose_changed(a: Array[Transform3D],b: Array[Transform3D]) -> bool:
	for i in mini(a.size(),b.size()):
		if not a[i].is_equal_approx(b[i]): return true
	return false

func shot(suffix: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
	check(root.get_texture().get_image().save_png(capture+suffix)==OK,"capture actual resource hand")

func finish() -> void:
	for property in ["cam","hand_ring","hand_pivot","hud","align_bar","align_label","towns_label","msg_label","help_label","dialogue_caption","creature_panel","creature_status","campaign_status","choice_row","ambience","sea_player"]:
		var node: Node = world.get(property)
		if is_instance_valid(node) and node.get_parent()==null: world.add_child(node)
	world.free()
	print("RESOURCE INPUT ",passed," passed; ",failures," failed")
	quit(0 if failures==0 else 1)
