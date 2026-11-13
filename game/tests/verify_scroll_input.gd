extends SceneTree
## Actual viewport input delivery, including the visible hand and HUD.

class ProbeWorld extends "res://scripts/main.gd":
	var received := 0
	var unhandled := 0
	func _ready() -> void: pass
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: received += 1
		super._input(event)
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: unhandled += 1
		super._unhandled_input(event)

var failed := 0
var passed := 0
var host := "C:/Games/Black and White Complete Collection"
var capture := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		if arg.begins_with("--capture="): capture = arg.substr(10)
	if not capture.is_empty(): DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failed += 1

func run() -> void:
	root.size = Vector2i(1600, 900)
	var world := ProbeWorld.new()
	world.bw_dir = host
	world.story_preview = true
	root.add_child(world)
	world.set_process(false)
	world.add_child(world.cam)
	world.cam.current = true
	world._build_hud()
	var opened := world.lnd.load_file(host.path_join(world.Data.SOURCES["landscape"]))
	opened = opened and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	opened = opened and world.island.load_file(host.path_join("Scripts/Land1.txt")) and world._load_landmark_animations()
	check(opened, "load actual original island and scroll meshes")
	if not opened: quit(1); return
	world.sea_y = world.lnd.sea_level
	if not capture.is_empty():
		world._build_environment()
		world._build_terrain()
	world._spawn_objects()
	world._build_hand()
	world._build_advisers()
	world._setup_original_dialogue()
	world.campaign.load_file(host.path_join("Scripts/Quests/challenge.chl"))
	world._start_story("SetupLand1")
	for i in 100: world.story_vm.tick()
	world.story_set_widescreen(true)
	world.story_set_widescreen(false)
	world._update_story_input_hint(0.0)
	world.loaded = true
	for type in [1, 2, 3]:
		var position := Vector3(1704, 0, -2594)
		var scroll: Node3D = world.story_create_highlight(type, position, 999)
		scroll.set_draw_height(14.0)
		var centre: Vector3 = scroll.global_position
		world.focus = centre
		world.dist = 55.0
		world.pitch = PI / 3.0
		world.yaw = 0.0
		world._update_camera()
		scroll.advance(0.0, world.cam)
		centre = scroll.visual.global_transform * scroll.visual.mesh.get_aabb().get_center()
		var screen: Vector2 = world.cam.unproject_position(centre)
		world._cursor_screen = screen
		for i in 30: world._update_world(1.0 / 60.0)
		var tip: Vector3 = world.hand_rig.root.global_transform * world.hand_pose.pointer_position()
		var tip_screen: Vector2 = world.cam.unproject_position(tip)
		print("SCROLL_POINTER type=", type, " cursor=", screen, " tip=", tip_screen, " gap=", screen.distance_to(tip_screen), " selected=", world.hand_target(screen).get("scroll") == scroll)
		check(world.hand_target(screen).get("scroll") == scroll, "type%d centre selects the visible scroll" % type)
		var shift := InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.pressed = true
		Input.parse_input_event(shift)
		Input.flush_buffered_events()
		await process_frame
		check(world._shift_camera, "type%d fixture begins an actual Shift rotation gesture" % type)
		world.story_camera.invoke(30, [], {"task":777})
		var release_shift := InputEventKey.new()
		release_shift.keycode = KEY_SHIFT
		release_shift.pressed = false
		Input.parse_input_event(release_shift)
		Input.flush_buffered_events()
		await process_frame
		check(not world._shift_camera and world.story_camera.owner_task != 0, "type%d release reaches input state while the cinematic still owns control" % type)
		world.story_camera.release()
		world._resume_player_camera()
		check(not world._shift_camera, "type%d releasing Shift during a cinema does not leave Action blocked" % type)
		var before: int = world.unhandled
		await viewport_click(screen)
		print("SCROLL_INPUT received=", world.received, " unhandled=", world.unhandled, " hovered_gui=", root.gui_get_hovered_control())
		check(world.unhandled == before + 1 and scroll.active and world.held == null, "type%d real viewport Action reaches and activates the scroll" % type)
		world.story_highlights.erase(scroll)
		scroll.free()
	await verify_hint(world)
	await verify_focus_loss(world)
	world.loaded = false
	for property in ["hand_ring", "hand_pivot", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if node.get_parent() == null: world.add_child(node)
	world.free()
	await process_frame
	print("SCROLL INPUT ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)

func verify_hint(world: ProbeWorld) -> void:
	var hint: Node3D
	var screen := Vector2.INF
	for candidate in world.story_highlights:
		if candidate.highlight_type != 1 or not candidate.has_meta("help_text"): continue
		world.focus = candidate.global_position
		world.dist = 55.0
		for angle in 16:
			world.yaw = float(angle) * TAU / 16.0
			world._update_camera()
			candidate.advance(0.0, world.cam)
			var centre: Vector3 = candidate.visual.global_transform * candidate.visual.mesh.get_aabb().get_center()
			var point: Vector2 = world.cam.unproject_position(centre)
			if world.hand_target(point).get("scroll") == candidate:
				hint = candidate
				screen = point
				break
		if hint != null: break
	check(hint != null, "an actual source-created Did You Know sign is visible and selectable")
	if hint == null: return
	await viewport_click(screen)
	var text_enum := int(hint.get_meta("help_text"))
	var caption: Dictionary = world.dialogue.caption_for_text_enum(text_enum)
	check(hint.active and world.story_help_is_open() and world.story_help_text.text == caption.get("text"), "viewport Action on the actual hint displays its installed text even without a voice sample")
	check(not world._shift_camera and not world._right_down and not world._action_release and world.held == null, "opening a help card cancels gestures without acquiring an item")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "capture the rendered original-text help card")
	await viewport_click(world.story_help_close.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(not world.story_help_is_open(), "the visible Continue button closes help through normal GUI input")
	check(world.story_show_help(text_enum), "a valid installed hint can be reopened")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await process_frame
	check(not world.story_help_is_open(), "Escape closes help without quitting the game")
	check(not world.story_show_help(-1) and not world.story_help_is_open(), "invalid help identifiers leave the panel closed")
	var count := 0
	var layout_enum := text_enum
	var longest := 0
	for candidate in world.story_highlights:
		if candidate.highlight_type != 1 or not candidate.has_meta("help_text"): continue
		var entry := int(candidate.get_meta("help_text"))
		var original: Dictionary = world.dialogue.caption_for_text_enum(entry)
		check(not original.is_empty() and world.story_show_help(entry) and world.story_help_text.text == original["text"], "source DYK%d displays its installed caption" % count)
		if str(original.get("text", "")).length() > longest:
			longest = str(original["text"]).length()
			layout_enum = entry
		count += 1
		world.story_close_help()
	check(count == 11, "all eleven original first-island hints have a usable text path")
	for size in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768)]:
		root.size = size
		world.story_show_help(layout_enum)
		await process_frame
		var bounds: Rect2 = world.story_help_panel.get_global_rect()
		check(bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= size.x and bounds.end.y <= size.y, "help text and close button fit the %dx%d window" % [size.x, size.y])
		world.story_close_help()
	root.size = Vector2i(1600, 900)
	world.dialogue.stop()

func verify_focus_loss(world: ProbeWorld) -> void:
	var carried := Thing.new()
	carried.kind = "rock"
	world.add_child(carried)
	world.pick_up(carried) # Declared held-item precondition for interruption tests.
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		var press := InputEventMouseButton.new()
		press.button_index = button
		press.position = Vector2(800, 450)
		press.pressed = true
		Input.parse_input_event(press)
		Input.flush_buffered_events()
	check(world._shift_camera and world._left_down and world._middle_down and world._right_down, "focus fixture establishes real pressed camera buttons")
	world._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not world._shift_camera and not world._left_down and not world._middle_down and not world._right_down and not world._action_release, "losing window focus clears pending camera and Action gestures")
	check(world.held == carried and carried.state == Thing.State.HELD and carried.velocity == Vector3.ZERO, "focus loss keeps the held item without dropping or throwing it")
	var overlay := Control.new()
	overlay.size = Vector2(root.size)
	root.add_child(overlay)
	await process_frame
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.position = Vector2(800, 450)
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
	var release_shift := InputEventKey.new()
	release_shift.keycode = KEY_SHIFT
	Input.parse_input_event(release_shift)
	Input.flush_buffered_events()
	var before := world.unhandled
	await viewport_click(Vector2(800, 450))
	check(world.unhandled == before and world.held == carried, "a GUI-covered Action is consumed without picking up or releasing a world object")
	root.remove_child(overlay)
	overlay.free()
	world.held = null
	carried.free()

func viewport_click(screen: Vector2, button := MOUSE_BUTTON_RIGHT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = screen
		event.global_position = screen
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
