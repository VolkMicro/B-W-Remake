extends "res://tests/verify_opening_runtime.gd"
## Tests the QA route planner through real camera input on declared flat-world
## fixtures. It does not establish campaign progression or original fidelity.
class CameraWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func ground_y(_point: Vector3) -> float: return 5.0

var failed := 0

func _initialize() -> void: call_deferred("run_driver_cases")
func _process(_delta: float) -> bool: return false

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failed += 1

func run_driver_cases() -> void:
	root.size = Vector2i(800,600)
	for fixture in [
		{"label":"low inherited pitch forward", "pitch":5.0, "offset":0.0, "target":Vector3(100,5,0), "blocked":false},
		{"label":"sideways target", "pitch":45.0, "offset":0.0, "target":Vector3(180,5,100), "blocked":false},
		{"label":"negative pitch with elevated pivot", "pitch":-6.0, "offset":40.0, "target":Vector3(120,5,20), "blocked":false},
		{"label":"outside authored camera zone", "pitch":45.0, "offset":0.0, "target":Vector3(100,5,-100), "blocked":true}]:
		world = CameraWorld.new()
		root.add_child(world)
		world.add_child(world.cam)
		world.cam.current = true
		world.cam.fov = 70.0
		world.cfg_camera = {"min_dist":4.0,"max_dist":3000.0}
		world.story_preview = true
		world.focus = Vector3(100,5,100)
		world._focus_height_offset = fixture["offset"]
		world.pitch = deg_to_rad(fixture["pitch"])
		world.yaw = 0.0
		world.dist = 57.8037414550781
		if fixture["blocked"]:
			world.story_camera._zone = PackedVector2Array([Vector2(50,50),Vector2(150,50),Vector2(150,150),Vector2(50,150)])
		world.loaded = true
		world.set_process(false)
		world._update_camera()
		input_failure = ""
		var reached := false
		var increased := false
		var outside_zone := false
		var actions := 0
		for i in 600:
			actions += 1
			var before: Vector3 = world.focus
			var previous_gap := Vector2(before.x-fixture["target"].x,before.z-fixture["target"].z).length()
			if drive_to_position(fixture["target"]):
				reached = true
				break
			world._update_camera()
			var gap := Vector2(world.focus.x-fixture["target"].x,world.focus.z-fixture["target"].z).length()
			if gap > previous_gap + 0.1: increased = true
			if fixture["blocked"] and world.story_camera.constrain_player_focus(world.focus).distance_to(world.focus)>0.01: outside_zone = true
			if not input_failure.is_empty(): break
			await process_frame
		print("DRIVER CASE ",fixture["label"]," reached=",reached," actions=",actions," focus=",world.focus," pitch=",world.pitch," failure=",input_failure)
		if fixture["blocked"]:
			check(not reached and not input_failure.is_empty(),"unreachable camera target fails explicitly within a bounded input budget")
			check(not outside_zone,"route planning never moves focus outside the actual camera zone")
		else:
			check(reached and input_failure.is_empty(),str(fixture["label"])+" reaches the target through input alone")
			check(not increased,str(fixture["label"])+" does not fire the focus away from its target")
		for property in ["hand_ring","hand_pivot","hud","align_bar","align_label","towns_label","msg_label","help_label","dialogue_caption","creature_panel","creature_status","campaign_status","choice_row","ambience","sea_player"]:
			var node: Variant=world.get(property)
			if node is Node and is_instance_valid(node) and node.get_parent()==null: world.add_child(node)
		world.free()
		await process_frame
	print("OPENING DRIVER failures=",failed)
	quit(0 if failed==0 else 1)
