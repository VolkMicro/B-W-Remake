extends SceneTree

class CameraWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass
	func ground_y(_point: Vector3) -> float:
		return 5.0

var failures := 0

func _initialize() -> void:
	call_deferred("run_test")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func run_test() -> void:
	var world := CameraWorld.new()
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	world.cfg_camera = {"min_dist":4.0, "max_dist":3000.0}
	for target in [Vector3(5, -20, -20), Vector3(5, 12, -20)]:
		world.story_camera.owner_task = 7
		world.story_camera.eye = Vector3(10, 16, 30)
		world.story_camera.focus = target
		world._update_camera()
		var before: Transform3D = world.cam.transform
		check(world._rendered_focus == target, "cinematic keeps authored target including below-ground look-through points")
		world.story_camera.release()
		world._resume_player_camera()
		for i in 60:
			world._update_camera()
		check(world.cam.position.distance_to(before.origin) < 0.001 and world.cam.basis.is_equal_approx(before.basis), "handover preserves rendered eye and orientation for sixty player-camera frames")
	world.story_camera.owner_task = 7
	world.story_camera.eye = Vector3(10, 2, 30)
	world.story_camera.focus = Vector3(5, -20, -20)
	world._update_camera()
	check(world.cam.position.y >= 5.5, "buried scripted eye clears terrain while preserving authored viewing target")
	world.story_camera.eye = Vector3(10, 5.9, 30)
	world._update_camera()
	check(world.cam.position == world.story_camera.eye, "valid low dialogue camera retains its authored eye rather than looking over the speaker")
	world.story_preview = true
	world._ambience_waves = [AudioStreamWAV.new()]
	world.add_child(world.ambience)
	world.add_child(world.sea_player)
	world._ambience_delay = 1.0
	world._update_ambience(2.0)
	check(not world.ambience.playing and world._ambience_delay >= 8.0, "cinematic defers added bird ambience until after the shot")
	for property in ["hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			world.add_child(node)
	world.free()
	await process_frame
	await create_timer(0.1).timeout
	print("CAMERA HANDOVER failures=", failures)
	quit(0 if failures == 0 else 1)
