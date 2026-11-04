# Research: renders original creature clips frame by frame through MorphReader, for visual checks.
extends SceneTree

const Data := preload("res://scripts/data.gd")
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
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true
	root.size = Vector2i(1800, 500)
	for id in Data.CREATURES:
		for clipname in ["move/walk", "move/stand", "move/run"]:
			var holder := Node3D.new()
			root.add_child(holder)
			var spacing := 0.0
			var height := 0.0
			for k in 6:
				var rig := L3dRig.new()
				var node := rig.load_file(host.path_join(Data.CREATURES[id]["mesh_file"]))
				var morph := MorphReader.new()
				morph.load_file(host.path_join(Data.CREATURES[id]["animation_file"]), host.path_join("Data"))
				if not morph.clips.has(clipname):
					break
				holder.add_child(node)
				if spacing == 0.0:
					spacing = maxf(rig.bounds.size.x, rig.bounds.size.z) * 1.2 + 5.0
					height = rig.bounds.size.y
				node.position = Vector3(k * spacing, 0, 0)
				node.rotation_degrees.y = 90 if k % 2 == 0 else 0
				var clip: Dictionary = morph.clips[clipname]
				rig.apply_local_pose(morph.sample(clipname, float(clip["duration"]) * k / 6.0, rig.rests))
			cam.size = maxf(height * 1.3, spacing * 6.0 / 3.6)
			cam.position = Vector3(spacing * 2.5, height * 0.5, 1000)
			cam.look_at(Vector3(spacing * 2.5, height * 0.5, 0))
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s-%s.png" % [id, clipname.get_file()]))
			holder.queue_free()
			await process_frame
	var holder2 := Node3D.new()
	root.add_child(holder2)
	var k := 0
	var h := 0.0
	var sp := 0.0
	for id in Data.ADVISERS:
		for clipname in ["move/stand", Data.ADVISERS[id]["speech_clip"]]:
			for yaw in [0.0, 90.0, 180.0]:
				var rig := L3dRig.new()
				var node := rig.load_file(host.path_join(Data.ADVISERS[id]["file"]))
				var morph := MorphReader.new()
				morph.load_adviser(host.path_join(Data.ADVISERS[id]["file"]))
				holder2.add_child(node)
				if sp == 0.0:
					sp = maxf(rig.bounds.size.x, rig.bounds.size.z) * 1.3
					h = rig.bounds.size.y
				node.position = Vector3(k * sp, -rig.bounds.position.y, 0)
				node.rotation_degrees.y = yaw
				rig.apply_local_pose(morph.sample(clipname, 0.4, rig.rests))
				k += 1
	cam.size = maxf(h * 1.3, sp * k / 3.6)
	cam.position = Vector3(sp * (k - 1) * 0.5, h * 0.5, 1000)
	cam.look_at(Vector3(sp * (k - 1) * 0.5, h * 0.5, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("advisers.png"))
	quit(0)
