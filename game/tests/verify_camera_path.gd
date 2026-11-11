extends SceneTree

const Controller := preload("res://scripts/story_camera.gd")

var failures := 0


func _initialize() -> void:
	var editor := make_editor()
	var camera := Controller.new()
	var owner := {"task": 71}
	check(not camera.run_path(editor, 39, 71), "path requires an acquired script camera")
	camera.invoke(30, [], owner)
	check(camera.run_path(editor, 39, 72) and camera.owner_task == 71, "nested path preserves the actual camera owner")
	check(camera.eye == Vector3(0, 10, 0) and camera.focus == Vector3(0, 0, -10), "path starts at its authored first eye and focus")
	check(not arrived(camera, owner), "starting a path does not fabricate immediate arrival")
	camera.advance(0.25)
	check(camera.eye.is_equal_approx(Vector3(2.5, 10, 0)) and camera.focus.is_equal_approx(Vector3(0, 2.5, -10)), "both authored channels advance at their independent millisecond key times")
	camera.advance(0.25)
	check(camera.focus == Vector3(0, 5, -10) and not arrived(camera, owner), "short focus channel settles while the eye is still travelling")
	camera.advance(0.5)
	check(camera.eye == Vector3(10, 10, 0) and camera.focus == Vector3(0, 5, -10) and arrived(camera, owner), "camera arrives only after the longest authored channel ends")
	check(camera.owner_task == 71, "path completion retains script ownership until END_CAMERA_CONTROL")
	camera.run_path(editor, 39, 71)
	camera.advance(0.25)
	var before_eye: Vector3 = camera.eye
	check(not camera.run_path(editor.slice(0, editor.size() - 1), 39, 71) and not camera.run_path(editor, 999, 71), "truncated and missing path records are rejected")
	check(camera.eye == before_eye and not arrived(camera, owner), "failed path replacement preserves active playback")
	camera.advance(0.25)
	check(camera.eye == Vector3(5, 10, 0), "preserved path keeps its elapsed time")
	var invalid := editor.duplicate()
	invalid.encode_float(14 + 40 + 36 + 36 * 2 + 4, 0.0)
	check(not camera.run_path(invalid, 39, 71), "non-increasing key times are rejected atomically")
	camera.invoke(1, [StoryVm.number(4), StoryVm.number(5), StoryVm.number(6)], owner)
	camera.advance(2.0)
	check(camera.eye == Vector3(4, 5, -6) and arrived(camera, owner), "explicit eye command cancels a path without a later path overwrite")
	camera.run_path(editor, 39, 71)
	camera.invoke(31, [], {"task":72})
	check(camera.owner_task == 71 and not arrived(camera, owner), "another task cannot release the camera path owner")
	camera.invoke(31, [], owner)
	var released_eye: Vector3 = camera.eye
	camera.advance(5.0)
	check(camera.owner_task == 0 and camera.eye == released_eye and arrived(camera, owner), "owner release stops playback and returns control")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bw="):
			verify_installed(argument.substr(5))
	quit(0 if failures == 0 else 1)


func verify_installed(host: String) -> void:
	var editor := FileAccess.get_file_as_bytes(host.path_join("Data/camera.edt"))
	var track := Controller.read_path(editor, 39)
	check(not track.is_empty(), "installed Track39 loads as a paired camera path")
	if track.is_empty(): return
	check(track["eye"]["points"].size() == 4 and track["focus"]["points"].size() == 4, "Lost Brother camera contains four eye and four focus keys")
	check(track["eye"]["duration"] == 5470 and track["focus"]["duration"] == 760, "installed camera preserves unequal eye and focus durations")
	# Independent byte reads prevent confusing the walker's focus-only output
	# or the unrelated static Cam39 with the actual camera eye channel.
	var record := -1
	var record_name := "Track39".to_ascii_buffer()
	for p in range(14, editor.size() - 40):
		if editor.slice(p, p + record_name.size()) == record_name and editor[p + record_name.size()] == 0:
			record = p
			break
	check(record >= 0, "installed source contains the requested named track")
	if record < 0: return
	var first := record + 40
	var second := first + int(editor.decode_u16(first))
	var eye_first := read_point(editor, first + 36)
	var eye_second := read_point(editor, first + 48)
	var focus_first := read_point(editor, second + 36)
	var first_eye_key_time := editor.decode_float(first + 36 + 36 * 4 + 4)
	var camera := Controller.new()
	var owner := {"task":73}
	camera.invoke(30, [], owner)
	camera.run_path(editor, 39, 73)
	check(camera.eye == eye_first and camera.focus == focus_first and eye_first.distance_to(focus_first) > 1.0, "actual camera eye and focus are distinct and match their own source channels")
	camera.advance(first_eye_key_time * 0.0005)
	check(camera.eye.distance_to(eye_first.lerp(eye_second, 0.5)) < 0.002 and not arrived(camera, owner), "actual Lost Brother eye passes through its intermediate segment rather than jumping to its destination")
	var focus_after: Vector3 = camera.focus
	camera.advance(0.2)
	check(camera.focus == focus_after and not arrived(camera, owner), "installed short focus track holds its final sample while the eye continues")
	camera.advance(10.0)
	check(arrived(camera, owner) and camera.eye.distance_to(eye_first) > 10.0 and camera.owner_task == 73, "actual installed path finishes with camera movement and ownership intact")
	camera.release()


func make_editor() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(14 + 40 + 116 * 2)
	var signature := "LiOnHeAdEDITOR".to_ascii_buffer()
	for i in signature.size(): bytes[i] = signature[i]
	var p := 14
	var name_bytes := "Track39".to_ascii_buffer()
	for i in name_bytes.size(): bytes[p + i] = name_bytes[i]
	bytes.encode_u32(p + 32, 4 + 116 * 2)
	write_channel(bytes, p + 40, 1000, [Vector3(0, 10, 0), Vector3(10, 10, 0)])
	write_channel(bytes, p + 40 + 116, 500, [Vector3(0, 0, 10), Vector3(0, 5, 10)])
	return bytes


func write_channel(bytes: PackedByteArray, start: int, duration: int, points: Array[Vector3]) -> void:
	bytes.encode_u16(start, 116)
	bytes.encode_u32(start + 4, 2)
	bytes.encode_u32(start + 16, duration)
	for i in 2:
		var p := start + 36 + i * 12
		bytes.encode_float(p, points[i].x)
		bytes.encode_float(p + 4, points[i].y)
		bytes.encode_float(p + 8, points[i].z)
	bytes.encode_float(start + 36 + 36 * 2, 0.0)
	bytes.encode_float(start + 36 + 36 * 2 + 4, float(duration))


func read_point(bytes: PackedByteArray, p: int) -> Vector3:
	return Vector3(bytes.decode_float(p), bytes.decode_float(p + 4), -bytes.decode_float(p + 8))


func arrived(camera: RefCounted, owner: Dictionary) -> bool:
	return StoryVm.as_int(camera.invoke(35, [], owner)["push"][0]) != 0


func check(ok: bool, message: String) -> void:
	if ok: print("PASS ", message)
	else:
		failures += 1
		printerr("FAIL ", message)
