extends SceneTree

class TempleWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := TempleWorld.new()
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): world.bw_dir = arg.substr(5)
		elif arg.begins_with("--capture="): capture = arg.substr(10)
	root.add_child(world)
	var bridge := StoryNatives.new()
	bridge.configure(world)
	check(StoryVm.as_int(bridge.invoke(405, [], {})["push"][0]) == 0, "INSIDE_TEMPLE reports the actual outside scene")
	check(world.story_enter_temple(), "load original main temple room, floor and embedded skins")
	if world.story_temple != null:
		var room = world.story_temple
		check(room._frames == 150 and is_equal_approx(room._duration, 5.0), "read all 150 original temple-entry camera frames")
		check(room.camera.position.distance_to(Vector3(-0.43732, 11.92198, -74.28525)) < 0.001, "entry starts at the original camera position")
		check(StoryVm.as_int(bridge.invoke(405, [], {})["push"][0]) == 1, "entering the real room satisfies the original inside-temple query")
		await create_timer(5.2).timeout
		check(room.camera.position.is_equal_approx(room._point(149, 0)), "entry camera reaches the original final frame")
		if not capture.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture)
		world.loaded = true
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		world._unhandled_input(escape)
		world.loaded = false
		check(not world.story_inside_temple() and StoryVm.as_int(bridge.invoke(405, [], {})["push"][0]) == 0, "Escape returns to the island and clears the actual temple state")
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	await process_frame
	print("TEMPLE failures=", failures)
	quit(0 if failures == 0 else 1)
