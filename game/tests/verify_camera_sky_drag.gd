extends SceneTree
## New port input policy: a sky ray cannot anchor or move a terrain drag.
## This tests real mouse handlers on a synthetic flat world, not original fidelity.
class CameraWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func ground_y(_point: Vector3) -> float: return 5.0

var failed := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failed += 1

func button(world: Node, point: Vector2, down: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	event.double_click = double
	world._unhandled_input(event)

func motion(world: Node, point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	world._unhandled_input(event)

func run() -> void:
	root.size = Vector2i(800,600)
	var world := CameraWorld.new()
	root.add_child(world)
	world.add_child(world.cam)
	world.cam.current = true
	world.story_preview = true
	world.cfg_camera = {"min_dist":4.0,"max_dist":3000.0}
	world.focus = Vector3(100,5,100)
	world.dist = 57.8037414550781
	world.pitch = deg_to_rad(5.0)
	world.yaw = 0.0
	world.loaded = true
	world._update_camera()
	await process_frame
	var center := Vector2(root.size) * 0.5
	var sky := center + Vector2(0,-180)
	var land := center + Vector2(0,150)
	check(world.cam.project_ray_normal(sky).y > 0.0 and world.cam.project_ray_normal(land).y < 0.0,"fixture has a real sky ray and a real land ray")
	var before: Vector3 = world.focus
	button(world,sky,true)
	motion(world,center,center-sky)
	button(world,center,false)
	print("SKY PRESS focus displacement=",world.focus.distance_to(before))
	check(world.focus.distance_to(before)<0.001,"pressing sky cannot send the free camera thousands of units away")
	# Re-establish fixture camera only between independent input scenarios.
	world.focus = before
	world._focus_height_offset = 0.0
	world._update_camera()
	button(world,land,true)
	motion(world,sky,sky-land)
	button(world,sky,false)
	print("DRAG TO SKY focus displacement=",world.focus.distance_to(before))
	check(world.focus.distance_to(before)<0.001,"dragging a valid ground anchor into sky pauses the pan")
	world.focus = before
	world._update_camera()
	button(world,land,true)
	motion(world,land+Vector2(24,0),Vector2(24,0))
	button(world,land+Vector2(24,0),false)
	check(world.focus.distance_to(before)>0.01 and world.focus.distance_to(before)<100.0,"ordinary valid ground drag still moves the camera")
	world.focus = before
	world._update_camera()
	world.story_interface_level = 13
	button(world,sky,true,true)
	button(world,sky,false)
	check(world.focus.distance_to(before)<0.001,"sky double-click does not replace the camera pivot with a miss fallback")
	for property in ["hand_ring","hand_pivot","hud","align_bar","align_label","towns_label","msg_label","help_label","dialogue_caption","creature_panel","creature_status","campaign_status","choice_row","ambience","sea_player"]:
		var node: Variant=world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent()==null: world.add_child(node)
	world.free()
	await process_frame
	print("CAMERA SKY DRAG failures=",failed)
	quit(0 if failed==0 else 1)
