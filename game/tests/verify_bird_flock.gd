extends SceneTree
## Installed animal12 meshes and flap animation, genuine container natives.
class BirdWorld extends Node3D:
	var bw_dir := "C:/Games/Black and White Complete Collection"
	var host_info := HostInfoReader.new()
	var g3d := G3dReader.new()

var passed := 0
var failed := 0
var capture := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture = arg.substr(10)
	if not capture.is_empty(): DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failed += 1

func run() -> void:
	root.size = Vector2i(1280,720)
	var world := BirdWorld.new()
	root.add_child(world)
	var opened := world.g3d.open(world.bw_dir.path_join("Data/AllMeshes.g3d"), world.bw_dir.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(world.bw_dir.path_join("Scripts/info.dat"),world.g3d.mesh_offsets.size())
	check(opened,"load installed animal metadata and actual meshes")
	if not opened: quit(1); return
	var bridge := StoryNatives.new()
	bridge.configure(world)
	var created := bridge.invoke(36,[StoryVm.number(0,StoryVm.VECTOR),StoryVm.number(0,StoryVm.VECTOR),StoryVm.number(0,StoryVm.VECTOR)],{})
	check(created.get("ok",false),"source FLOCK_CREATE returns a real container")
	if not created.get("ok",false): quit(1); return
	var handle: Dictionary = created["push"][0]
	var flock := bridge._object(handle) as StoryFlock
	flock.set_process(false)
	check(flock.scripted_bird_count()==0,"new source container is empty")
	var populated := bridge.invoke(109,[handle,StoryVm.number(20),StoryVm.integer(6),StoryVm.integer(12)],{})
	check(populated.get("ok",false) and populated.get("pop",-1)==4 and populated.get("push",[]).is_empty(),"POPULATE_CONTAINER consumes the real count20/type6/subtype12 arguments")
	if not populated.get("ok",false): world.g3d.close();bridge.clear_created();world.free();quit(1);return
	check(flock.scripted_bird_count()==20 and flock._bird_rigs.size()==20,"all twenty requested birds have actual scene nodes and rigs")
	check(flock._bird_clip=="M_dove_flap" and flock._bird_rigs[0].bone_count==5,"installed animal12 supplies its real five-bone flap clip")
	var size := bridge.invoke(40,[handle],{})
	check(size.get("ok",false) and StoryVm.as_float(size["push"][0])==20.0,"ID_SIZE reports the actual populated container")
	var before: Vector3 = flock._bird_orbit.get_child(0).position
	var pose_before: Array[Transform3D] = []
	for bone in 5: pose_before.append(flock._bird_rigs[0].skeleton.get_bone_pose(bone))
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(0,30,40)
		camera.look_at(Vector3(0,20,0))
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation = Vector3(-0.8,0.3,0)
		world.add_child(light)
		var background := WorldEnvironment.new()
		background.environment = Environment.new()
		background.environment.background_mode = Environment.BG_COLOR
		background.environment.background_color = Color(0.35,0.5,0.7)
		background.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		background.environment.ambient_light_energy = 0.7
		world.add_child(background)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture.get_basename()+"-a.png")==OK,"capture installed flock before animation advance")
	flock._process(0.3)
	check(flock._bird_orbit.get_child(0).position.distance_to(before)>0.1,"birds move through the new orbit presentation rather than remaining frozen")
	var animated := false
	for bone in 5:
		if not flock._bird_rigs[0].skeleton.get_bone_pose(bone).is_equal_approx(pose_before[bone]): animated=true
	check(animated,"the actual installed wing-bone pose advances")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture.get_basename()+"-b.png")==OK,"capture installed flock after animation advance")
	for values in [[20.0,20,12],[20.0,6,6],[20.5,6,12],[0.0,6,12],[65.0,6,12],[NAN,6,12]]:
		var invalid := bridge.invoke(109,[handle,StoryVm.number(values[0]),StoryVm.integer(values[1]),StoryVm.integer(values[2])],{})
		check(not invalid.get("ok",false) and flock.scripted_bird_count()==20,"unsupported population leaves existing birds unchanged: "+str(values))
	check(not bridge.invoke(109,[handle,StoryVm.number(20),StoryVm.integer(6),StoryVm.integer(12)],{}).get("ok",false) and flock.scripted_bird_count()==20,"bounded single-fill scope rejects an unintended duplicate population")
	flock.disband()
	size=bridge.invoke(40,[handle],{})
	check(flock.scripted_bird_count()==0 and StoryVm.as_float(size["push"][0])==0.0,"disband removes populated birds and releases their animation state")
	check(bridge.invoke(39,[handle],{}).get("ok",false) and bridge._object(handle)==null,"source FLOCK_DISBAND invalidates its container handle")
	bridge.clear_created()
	world.g3d.close()
	world.free()
	await process_frame
	print("BIRD FLOCK ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
