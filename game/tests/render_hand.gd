# Research: renders the original Hand mesh in its rest pose from several sides.
extends SceneTree

var host := ""
var out := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	call_deferred("_run")


func _run() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true
	root.size = Vector2i(1600, 500)
	var sp := 0.0
	var h := 0.0
	var k := 0
	for file in ["Data/CreatureMesh/Hand_Boned_Base2.l3d"]:
		for rot in [Vector3(0, 0, 0), Vector3(0, 90, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0)]:
			var rig := L3dRig.new()
			var node := rig.load_file(host.path_join(file))
			if node == null:
				print("fail ", rig.error)
				continue
			root.add_child(node)
			print("bones ", rig.bone_count, " surfaces ", rig.surface_count, " bounds ", rig.bounds)
			if sp == 0.0:
				sp = rig.bounds.get_longest_axis_size() * 1.2
			node.position = Vector3(k * sp, 0, 0) - rig.bounds.get_center().rotated(Vector3.UP, 0)
			node.rotation_degrees = rot
			k += 1
	cam.size = sp * 1.2
	cam.position = Vector3(sp * (k - 1) * 0.5, 0, 1000)
	cam.look_at(Vector3(sp * (k - 1) * 0.5, 0, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("hand.png"))
	quit(0)
