extends SceneTree

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
	var models := G3dReader.new()
	var animations := AnmReader.new()
	var data = preload("res://scripts/data.gd")
	var opened := models.open(source.path_join(data.SOURCES["meshes"]), source.path_join("Data/AllMeshes.h"))
	opened = opened and animations.load_file(source.path_join(data.PORT_MODULES["villager_animations"]["source"]), [], PackedInt32Array([129]))
	check(opened, "load original shark model and swimming animation")
	if not opened:
		quit(1)
		return
	var editor := FileAccess.get_file_as_bytes(source.path_join("Data/camera.edt"))
	var shark := preload("res://scripts/story_shark.gd").new()
	check(shark.configure(models, animations), "original shark skeleton matches swimming clip")
	for path_id in [20, 21]:
		for forward in [true, false]:
			check(shark.walk_track(editor, path_id, 0.0, 1.0, forward), "load original shark path %d forward=%s" % [path_id, forward])
			shark._process(0.0)
			var points: PackedVector3Array = shark.track["points"]
			var times: PackedFloat32Array = shark.track["times"]
			# Editor splines can have a final control knot beyond playback duration.
			var expected := points[0] if forward else points[-2].lerp(points[-1], inverse_lerp(times[-2], times[-1], float(shark.track["duration"])))
			check(shark.position.is_equal_approx(expected), "path keeps authored underwater height and endpoint")
			var direction := points[1] - points[0] if forward else points[-2] - points[-1]
			direction.y = 0.0
			check((shark.basis * Vector3.RIGHT).dot(direction.normalized()) > 0.999, "shark nose follows horizontal travel direction")
	shark.free()
	models.close()
	print("SHARK failures=", failures)
	quit(0 if failures == 0 else 1)
