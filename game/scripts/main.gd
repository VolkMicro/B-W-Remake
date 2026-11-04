# Black & White island rebuilt in Godot: everything it shows is read from the player's own Black & White folder.
extends Node3D

const Data := preload("res://scripts/data.gd")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

const TOWN_NAMES := ["Norse village (your home)", "Celtic village by the lake", "Norse village on the east cliffs", "Japanese village", "Aztec village", "Celtic village in the west"]

var bw_dir := ""
var lnd := LndReader.new()
var g3d := G3dReader.new()
var island := IslandScript.new()
var host_info := HostInfoReader.new()

var cfg_hand: Dictionary = Data.SYSTEMS["hand"]
var cfg_villager: Dictionary = Data.SYSTEMS["villager_ai"]
var cfg_belief: Dictionary = Data.SYSTEMS["belief"]
var cfg_camera: Dictionary = Data.SYSTEMS["camera"]
var sea_y := 0.0

var towns: Array[Dictionary] = []
var things: Array[Thing] = []
var story_landmarks: Array[Node3D] = []
var alignment := 0.0
var won := false
var loaded := false

var cam := Camera3D.new()
var focus := Vector3.ZERO
var yaw := 0.6
var pitch := deg_to_rad(50.0)
var dist := 150.0

var held: Thing = null
var hand_ring := MeshInstance3D.new()
var hand_mat := StandardMaterial3D.new()
var sky_mat := ProceduralSkyMaterial.new()
var env := Environment.new()

var _left_down := false
var _right_down := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _grab_point := Vector3.ZERO
var _right_moved := 0.0

var hud := CanvasLayer.new()
var align_bar := ProgressBar.new()
var align_label := Label.new()
var towns_label := Label.new()
var msg_label := Label.new()
var help_label := Label.new()
var dialogue_caption := Label.new()
var dialogue: OriginalDialogue
var original_music: OriginalMusic
var _messages: Array[String] = []
var _msg_timer := 0.0

var ambience := AudioStreamPlayer.new()
var sea_player := AudioStreamPlayer.new()
var _ambience_waves: Array[AudioStreamWAV] = []

var test_mode := false
var _test_log: Array[String] = []
var _melty_checks := "" # Melty's test file: where to append "pass <check>" lines
const MELTY_SLUG := "black-white-godot-island"
var creature: IslandCreature
var campaign := ChlReader.new()
var villager_anims := AnmReader.new()
var landmark_anims := AnmReader.new()
var animation_clock := 0.0
var creature_panel := VBoxContainer.new()
var creature_status := Label.new()
var campaign_status := Label.new()
var choice_row := HBoxContainer.new()
var adviser_nodes: Array[Node3D] = []
var adviser_animations: Array[Dictionary] = []
var _adviser_time := 0.0
var _speaking_adviser := ""
var _save_clock := 0.0
var hand_rig: L3dRig
var hand_pivot := Node3D.new()
const HAND_LENGTH := 16.0 # world units at the default camera distance
const HAND_HOVER := 7.0
var _port_tests := false
var showcase_mode := false


func _ready() -> void:
	Engine.physics_ticks_per_second = int(Data.PORT_RULES["physics"]["step_hz"])
	get_window().title = "Black & White: Godot Island"
	_read_melty_test()
	_build_hud()
	bw_dir = _find_bw()
	if bw_dir == "":
		_say("Black & White was not found. Start this from Melty, or pass --bw=<your Black & White folder>.")
		return
	_say("Reading your Black & White island from %s ..." % bw_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_world()


func _find_bw() -> String:
	var cands: Array[String] = []
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
		var a: String = args[i]
		if a.begins_with("--bw="):
			cands.append(a.substr(5))
		elif a == "--bw" and i + 1 < args.size():
			cands.append(args[i + 1])
		if a == "--melty-test":
			test_mode = true
		if a.begins_with("--showcase="):
			showcase_mode = true
	cands.append(OS.get_environment("BW_GAME_DIR"))
	cands.append(OS.get_executable_path().get_base_dir().get_base_dir())
	for c in cands:
		if c != "" and FileAccess.file_exists(c.path_join("Data/AllMeshes.g3d")) and FileAccess.file_exists(c.path_join("Data/Landscape/Land1.lnd")):
			return c
	return ""


func _p(rel: String) -> String:
	return bw_dir.path_join(rel)


# ---------------------------------------------------------------- world

func _load_world() -> void:
	var t0 := Time.get_ticks_msec()
	if not lnd.load_file(_p(Data.SOURCES["landscape"])):
		_say("Could not read the island landscape.")
		return
	sea_y = lnd.sea_level
	if not g3d.open(_p(Data.SOURCES["meshes"]), _p("Data/AllMeshes.h")):
		_say("Could not read Black & White's meshes.")
		return
	if not host_info.load_file(_p(Data.SOURCES["object_info"]), g3d.mesh_offsets.size()):
		_say("Не удалось прочитать предметы оригинала: " + host_info.error)
		return
	island.load_file(_p(Data.SOURCES["island_script"]))
	_build_environment()
	_build_terrain()
	var wanted: Array[String] = []
	for profile in Data.VILLAGER_ANIMATIONS.values():
		for state_name in ["idle","walk","flee","held","flying","dead"]:
			if profile[state_name] not in wanted:
				wanted.append(profile[state_name])
	if not villager_anims.load_file(_p(Data.PORT_MODULES["villager_animations"]["source"]), wanted):
		_say("Анимации жителей не прочитаны: " + villager_anims.error)
		return
	if not _load_landmark_animations():
		_say("Анимации оригинальных ворот не прочитаны: " + landmark_anims.error)
		return
	_spawn_objects()
	_build_hand()
	_start_audio()
	add_child(cam)
	cam.far = 9000.0
	cam.current = true
	if towns.size() > 0:
		focus = towns[0]["pos"]
	_update_camera()
	loaded = true
	_load_preservation()
	var heights := PackedStringArray()
	for t in towns:
		heights.append("%.0f" % t["pos"].y)
	_log_test("town_heights", ",".join(heights))
	_log_test("island_loaded", "terrain, %d towns, %d things in %d ms" % [towns.size(), things.size(), Time.get_ticks_msec() - t0])
	_say("Первый остров. Выберите существо: 1 — обезьяна, 2 — корова, 3 — тигр.")
	if test_mode:
		var villagers := 0
		for t in things:
			if t.kind == "villager":
				villagers += 1
		melty_check("island-loaded", things.size() > 100, "only %d objects" % things.size())
		melty_check("villages-loaded", towns.size() >= 6 and villagers > 0, "%d towns, %d villagers" % [towns.size(), villagers])
		_run_test()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shots(a.substr(7))
		elif a.begins_with("--showcase="):
			_capture_preservation(a.substr(11))


# Saves views of the running game to PNG files (used to check the build and make store pictures).
func _shots(base: String) -> void:
	var views := [[0, 0.6, 50.0, 260.0], [1, 2.2, 40.0, 200.0], [0, 1.4, 30.0, 110.0], [-2, 0.3, 25.0, 14.0]]
	var n := 0
	for v in views:
		if v[0] == -2:
			for t in things:
				if t.kind == "villager":
					focus = t.position
					break
		elif v[0] >= 0:
			focus = towns[v[0]]["pos"]
		else:
			focus = Vector3(2560, 0, -2560)
		yaw = v[1]
		pitch = deg_to_rad(v[2])
		dist = v[3]
		_update_camera()
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [base, n])
		n += 1
	get_tree().quit()


func _build_environment() -> void:
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.8)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.7, 0.8)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)


func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = lnd.build_mesh()
	var sm := ShaderMaterial.new()
	sm.shader = TERRAIN_SHADER
	sm.set_shader_parameter("mats", lnd.material_array())
	mi.material_override = sm
	add_child(mi)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24000, 24000)
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	water.material_override = wm
	water.position = Vector3(2560, sea_y, -2560)
	add_child(water)
	# dark sea bed under the open ocean, where the island has no landscape blocks
	var bed := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(24000, 24000)
	bed.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.04, 0.16, 0.26)
	bmat.roughness = 1.0
	bed.material_override = bmat
	bed.position = Vector3(2560, -0.6, -2560)
	add_child(bed)


func to_world(p: Vector2) -> Vector3:
	return Vector3(p.x, lnd.height_at(p.x, p.y), -p.y)


func ground_y(p: Vector3) -> float:
	return lnd.height_at(p.x, -p.z)


func ground_normal(p: Vector3) -> Vector3:
	var dx := ground_y(p + Vector3(0.5, 0, 0)) - ground_y(p - Vector3(0.5, 0, 0))
	var dz := ground_y(p + Vector3(0, 0, 0.5)) - ground_y(p - Vector3(0, 0, 0.5))
	return Vector3(-dx, 1.0, -dz).normalized()


func _place_mesh(mesh_name: Variant, p: Vector3, yaw_rad: float, scale_f: float, kind: String) -> Thing:
	var t := Thing.new()
	t.kind = kind
	t.world = self
	if kind == "villager":
		t.rig = g3d.rig(str(mesh_name))
		if t.rig == null:
			t.free()
			return null
		t.add_child(t.rig.root)
	else:
		var m := g3d.mesh_index(int(mesh_name)) if mesh_name is int else g3d.mesh(str(mesh_name))
		if m == null:
			t.free()
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.visibility_range_end = 1800.0 if kind != "house" else 3000.0
		t.add_child(mi)
	t.position = p
	t.rotation.y = -yaw_rad
	t.scale = Vector3.ONE * scale_f
	t.home = p
	add_child(t)
	return t


func _nearest_town(p: Vector3, max_d: float) -> int:
	var best := -1
	var bd := max_d
	for i in towns.size():
		var d := Vector2(p.x - towns[i]["pos"].x, p.z - towns[i]["pos"].z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _load_landmark_animations() -> bool:
	var wanted_indices := PackedInt32Array()
	for command in island.all("CREATE_ANIMATED_STATIC"):
		var args: PackedStringArray = command["args"]
		var row := host_info.animated_static(args[1])
		if row.is_empty():
			return false
		var index: int = row["animation_id"]
		if not wanted_indices.has(index):
			wanted_indices.append(index)
	var wanted_names: Array[String] = []
	return landmark_anims.load_file(_p(Data.PORT_MODULES["villager_animations"]["source"]), wanted_names, wanted_indices)


func _spawn_objects() -> void:
	for c in island.all("CREATE_TOWN"):
		var a: PackedStringArray = c["args"]
		var mine := a[2] == "PLAYER_ONE"
		var idx := towns.size()
		towns.append({
			"name": TOWN_NAMES[idx] if idx < TOWN_NAMES.size() else "%s village" % a[4].capitalize(),
			"culture": a[4], "pos": to_world(IslandScript.pos(a[1])),
			"belief": float(cfg_belief["start_player_town"]) if mine else float(cfg_belief["start_neutral"]),
			"mine": mine, "marker": null})
	for i in towns.size():
		_make_marker(i)
	for c in island.all("CREATE_ABODE"):
		var a: PackedStringArray = c["args"]
		var placement := IslandScript.placement("abode", a)
		if Data.ABODES.has(a[2]) and not placement.is_empty():
			var abode := _place_mesh(Data.ABODES[a[2]], to_world(IslandScript.pos(a[1])), placement["angle"], placement["scale"], "house")
			if abode:
				abode.set_meta("original_type", a[2])
				abode.set_meta("story_type", 2)
				story_landmarks.append(abode)
	for c in island.all("CREATE_NEW_FEATURE"):
		var a: PackedStringArray = c["args"]
		var placement := IslandScript.placement("feature", a)
		if Data.FEATURES.has(a[1]) and not placement.is_empty():
			var landmark := _place_mesh(Data.FEATURES[a[1]], to_world(IslandScript.pos(a[0])), placement["angle"], placement["scale"], "house")
			if landmark:
				landmark.set_meta("original_type", a[1])
				landmark.set_meta("story_type", 3)
				story_landmarks.append(landmark)
	for c in island.all("CREATE_ANIMATED_STATIC"):
		var a: PackedStringArray = c["args"]
		var placement := IslandScript.placement("animated_static", a)
		var original := host_info.animated_static(a[1])
		if not Data.ANIMATED_STATICS.has(a[1]) or original.is_empty() or placement.is_empty():
			push_error("Original animated landmark cannot be loaded: " + a[1])
			continue
		var landmark := OriginalLandmark.new()
		if not landmark.configure(g3d, original, landmark_anims):
			push_error("Original animated landmark rig is invalid: " + a[1])
			landmark.free()
			continue
		landmark.position = to_world(IslandScript.pos(a[0]))
		landmark.rotation.y = -float(placement["angle"])
		landmark.scale = Vector3.ONE * float(placement["scale"])
		landmark.set_meta("original_type", a[1])
		landmark.set_meta("story_type", 3)
		landmark.set_meta("original_animation_id", original["animation_id"])
		add_child(landmark)
		story_landmarks.append(landmark)
	for c in island.all("CREATE_NEW_TREE"):
		var a: PackedStringArray = c["args"]
		var row: Dictionary = Data.TREES.get(a[2], {})
		if row.is_empty():
			continue
		var t := _place_mesh(row["mesh"], to_world(IslandScript.pos(a[1])), float(a[4]), float(a[5]), "tree")
		if t and row["pickable"]:
			things.append(t)
	for c in island.all("CREATE_MOBILE_STATIC"):
		var a: PackedStringArray = c["args"]
		var original := host_info.record(int(a[1]))
		if original.is_empty():
			push_error("Original mobile object record missing: " + a[1])
			continue
		var row: Dictionary = Data.STATICS.get(str(original["category"]), {})
		if row.is_empty():
			push_error("Original mobile object category is not supported: " + str(original["category"]))
			continue
		var pos := to_world(IslandScript.pos(a[0])) + Vector3(0, float(a[2]), 0)
		var t := _place_mesh(int(original["mesh_id"]), pos, 0.0, float(a[6]), row["kind"])
		if t and bool(row["pickable"]):
			things.append(t)
		if t:
			var rotation_basis := Basis.from_euler(Vector3(-float(a[3]),-float(a[4]),-float(a[5])), EULER_ORDER_XYZ)
			var reflected := L3dRig.reflected(Transform3D(rotation_basis, Vector3.ZERO))
			t.basis = reflected.basis.scaled(Vector3.ONE * float(a[6]))
	for c in island.all("CREATE_VILLAGER_POS"):
		var a: PackedStringArray = c["args"]
		if not Data.VILLAGERS.has(a[2]):
			continue
		var p := to_world(IslandScript.pos(a[0]))
		var row: Dictionary = Data.VILLAGERS[a[2]]
		var t := _place_mesh(row["mesh"], p, randf() * TAU, float(row["scale"]), "villager")
		if t:
			t.animation_profile = row["animation_profile"]
			t.home = to_world(IslandScript.pos(a[1]))
			t.town = _nearest_town(t.home, 400.0)
			things.append(t)


func _make_marker(i: int) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 60.0
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.95, 0.6, 0.55)
	m.material_override = mat
	m.position = towns[i]["pos"] + Vector3(0, 30, 0)
	m.visible = towns[i]["mine"]
	add_child(m)
	towns[i]["marker"] = m


func _build_hand() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 3.0
	hand_ring.mesh = torus
	hand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hand_mat.albedo_color = Color(1, 1, 1, 0.8)
	hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hand_mat.no_depth_test = true
	hand_ring.material_override = hand_mat
	add_child(hand_ring)
	hand_rig = L3dRig.new()
	var visual := hand_rig.load_file(_p("Data/CreatureMesh/Hand_Boned_Base2.l3d"))
	if visual:
		# The original mesh stands fingers-up with the back of the hand towards +Z.
		# Lay it palm-down over the land, fingers pointing away from the camera.
		visual.name = "OriginalHand"
		var length := maxf(hand_rig.bounds.get_longest_axis_size(), 1.0)
		var s := HAND_LENGTH / length
		visual.scale = Vector3.ONE * s
		visual.position = -hand_rig.bounds.get_center() * s
		hand_pivot.rotation_degrees.x = -90.0
		hand_pivot.position.y = HAND_HOVER
		hand_pivot.add_child(visual)
		hand_ring.add_child(hand_pivot)


func _start_audio() -> void:
	_ambience_waves = SadReader.load_waves(_p(Data.SOURCES["ambience"]), 24)
	add_child(ambience)
	ambience.volume_db = -6.0
	ambience.finished.connect(_next_ambience)
	_next_ambience()
	var sea := SadReader.load_waves(_p(Data.SOURCES["night_ambience"]), 2)
	if sea.size() > 0:
		add_child(sea_player)
		sea[0].loop_mode = AudioStreamWAV.LOOP_FORWARD
		sea[0].loop_end = sea[0].data.size() / (2 * (2 if sea[0].stereo else 1))
		sea_player.stream = sea[0]
		sea_player.volume_db = -14.0
		sea_player.play()
	_log_test("ambience_loaded", "%d countryside sounds" % _ambience_waves.size())


func _next_ambience() -> void:
	if _ambience_waves.is_empty():
		return
	ambience.stream = _ambience_waves[randi() % _ambience_waves.size()]
	ambience.play()


# ---------------------------------------------------------------- camera & input

func _update_camera() -> void:
	focus.y = maxf(ground_y(focus), sea_y)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = focus + off
	# Keep the eye above hills along its line of sight, so it never sits inside the land.
	var clearance := 4.0 + dist * 0.03
	var raise := 0.0
	for i in range(1, 9):
		var p := focus + off * (float(i) / 8.0)
		var lift := maxf(ground_y(p), sea_y) + clearance - p.y
		raise = maxf(raise, lift * 8.0 / float(i))
	cam.position.y += raise
	cam.look_at(focus, Vector3.UP)


func ground_point(screen: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var step := 4.0
	var t := 0.0
	var prev := 0.0
	while t < 8000.0:
		var p := o + dir * t
		if p.y <= maxf(ground_y(p), sea_y):
			var lo := prev
			var hi := t
			for i in 12:
				var mid := (lo + hi) * 0.5
				var q := o + dir * mid
				if q.y <= maxf(ground_y(q), sea_y):
					hi = mid
				else:
					lo = mid
			var hit := o + dir * hi
			hit.y = maxf(ground_y(hit), sea_y)
			return hit
		prev = t
		t += step
		step = minf(step * 1.05, 40.0)
	return o + dir * 8000.0


func _unhandled_input(event: InputEvent) -> void:
	if not loaded:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_down = true
				_dragging = false
				_press_pos = mb.position
				_grab_point = ground_point(mb.position)
			else:
				_left_down = false
				if not _dragging:
					_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_down = true
				_right_moved = 0.0
			else:
				_right_down = false
				if _right_moved < 6.0 and held:
					_throw(ground_point(mb.position))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = maxf(dist * 0.88, cfg_camera["min_dist"])
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = minf(dist * 1.12, cfg_camera["max_dist"])
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down:
			if mm.position.distance_to(_press_pos) > 6.0:
				_dragging = true
			if _dragging:
				var now := ground_point(mm.position)
				focus += Vector3(_grab_point.x - now.x, 0, _grab_point.z - now.z)
				_update_camera()
		if _right_down:
			_right_moved += mm.relative.length()
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.004, deg_to_rad(15), deg_to_rad(85))
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE and towns.size() > 0:
			focus = towns[0]["pos"]
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif k.keycode >= KEY_1 and k.keycode <= KEY_3 and not is_instance_valid(creature):
			choose_creature(["ape", "cow", "tiger"][k.keycode - KEY_1])
		elif k.keycode == KEY_C and is_instance_valid(creature):
			creature.following = not creature.following
			_say("Существо идёт за Рукой." if creature.following else "Существо остаётся здесь.")
		elif k.keycode == KEY_R and is_instance_valid(creature):
			creature.feedback(true)
		elif k.keycode == KEY_F and is_instance_valid(creature):
			creature.feedback(false)
		elif k.keycode == KEY_F5:
			_save_preservation()
		elif k.keycode == KEY_F9:
			_restore_preservation()
		elif k.keycode == KEY_H:
			for adviser in adviser_nodes:
				adviser.visible = not adviser.visible


func _process(delta: float) -> void:
	if not loaded:
		return
	animation_clock += delta
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	yaw += turn * delta * 1.2
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if mv != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		focus += (fwd * -mv.y + right * mv.x) * dist * 0.9 * delta
	_update_camera()
	var mouse := get_viewport().get_mouse_position()
	var gp := ground_point(mouse)
	hand_ring.position = gp + Vector3(0, 0.6, 0)
	hand_ring.scale = Vector3.ONE * clampf(dist / 200.0, 0.4, 5.0)
	hand_pivot.rotation.y = yaw
	if held:
		held.position = gp + Vector3(0, float(cfg_hand["hold_height"]), 0)
	for i in towns.size():
		if not towns[i]["mine"]:
			towns[i]["belief"] = maxf(0.0, towns[i]["belief"] - float(cfg_belief["decay_per_min"]) / 60.0 * delta)
	_update_hud(delta)
	_update_preservation_hud()
	if is_instance_valid(original_music):
		original_music.set_alignment(alignment)
	_adviser_time += delta
	for adviser in adviser_animations:
		var rig: L3dRig = adviser["rig"]
		var animation: MorphReader = adviser["animation"]
		var clip := "move/stand"
		if adviser["id"] == _speaking_adviser:
			clip = Data.ADVISERS[_speaking_adviser]["speech_clip"]
		rig.apply_local_pose(animation.sample(clip, _adviser_time, rig.rests))
	_save_clock += delta
	if _save_clock >= float(Data.PORT_RULES["save"]["autosave_seconds"]):
		_save_clock = 0.0
		_save_preservation(false)


func _click(screen: Vector2) -> void:
	if held:
		var gp := ground_point(screen)
		if gp.y <= sea_y + 0.05 and held.kind != "rock":
			_say("That would drown. Put it on land.")
			return
		held.position = gp + Vector3(0, 5, 0)
		held.velocity = Vector3.ZERO
		held.thrown = false
		held.state = Thing.State.FLYING
		held = null
		return
	var best: Thing = null
	var bd := 30.0
	for t in things:
		if not is_instance_valid(t) or t.state == Thing.State.DEAD or t.state == Thing.State.FLYING:
			continue
		if cam.is_position_behind(t.position):
			continue
		var d := cam.unproject_position(t.position + Vector3(0, 1.5, 0)).distance_to(screen)
		if d < bd:
			bd = d
			best = t
	if best:
		pick_up(best)


func pick_up(t: Thing) -> void:
	held = t
	t._landed_notified = false
	t.state = Thing.State.HELD
	t.rotation.x = 0.0
	var what := {"tree": "a tree", "rock": "a rock", "villager": "a villager"}
	_say("You pick up %s." % what.get(t.kind, "it"))


func _throw(target: Vector3) -> void:
	var t := held
	held = null
	throw_thing(t, t.position, target)


func throw_thing(t: Thing, from: Vector3, target: Vector3) -> void:
	var g: float = cfg_hand["gravity"]
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var tt := maxf(flat.length() / float(cfg_hand["throw_speed"]), 0.5)
	t.position = from
	t.velocity = flat / tt + Vector3(0, (target.y - from.y) / tt + 0.5 * g * tt, 0)
	t.launch_from = from
	t.thrown = true
	t._landed_notified = false
	t.state = Thing.State.FLYING


# ---------------------------------------------------------------- rules

func on_landed(t: Thing) -> void:
	if t.kind == "food":
		if is_instance_valid(creature):
			creature.feed(t)
		return
	var p := t.position
	var ti := _nearest_town(p, cfg_belief["town_radius"])
	match t.kind:
		"tree":
			t.rotation.x = 0.0
			if ti >= 0 and not t.has_meta("gift_%d" % ti):
				t.set_meta("gift_%d" % ti, true)
				_act("gift_wood", ti, "%s thanks you for the wood." % towns[ti]["name"])
		"rock":
			if not t.thrown:
				return
			var crushed := 0
			var scared := 0
			for v in things:
				if not is_instance_valid(v) or v.kind != "villager" or v.state == Thing.State.DEAD or v.state == Thing.State.HELD:
					continue
				var d := Vector2(v.position.x - p.x, v.position.z - p.z).length()
				if d < float(cfg_hand["crush_radius"]):
					v.die()
					crushed += 1
				elif d < float(cfg_hand["scare_radius"]):
					v.flee_from(p)
					scared += 1
			var near := ti if ti >= 0 else _nearest_town(p, float(cfg_belief["town_radius"]) * 2.0)
			for i in crushed:
				_act("rock_crush", near, "A villager is crushed by your rock.")
			if scared > 0:
				_act("rock_scare", near, "%d villagers flee in terror." % scared)
				_log_test("rock_scare", "%d villagers fled" % scared)
		"villager":
			var flown := Vector2(p.x - t.launch_from.x, p.z - t.launch_from.z).length()
			if t.thrown and flown > float(cfg_hand["fling_kill_dist"]):
				t.die()
				_act("villager_fling", ti, "The villager did not survive the flight.")
				return
			if p.y <= sea_y + 0.05:
				t.die()
				_say("The villager drowned.")
				return
			if ti >= 0 and ti != t.town:
				_act("villager_missionary", ti, "Your villager preaches about you in %s." % towns[ti]["name"])
				t.town = ti
			t.home = p
	t.thrown = false


func _act(action: String, ti: int, text: String) -> void:
	var row: Dictionary = Data.ACTIONS[action]
	alignment = clampf(alignment + float(row["alignment"]), -100.0, 100.0)
	if ti >= 0:
		add_belief(ti, float(row["belief"]))
	_say(text)
	_log_test("action_" + action, text)


func add_belief(ti: int, amount: float) -> void:
	var town := towns[ti]
	if town["mine"]:
		return
	town["belief"] = minf(float(town["belief"]) + amount, float(cfg_belief["convert_at"]))
	if town["belief"] >= float(cfg_belief["convert_at"]):
		town["mine"] = true
		town["marker"].visible = true
		_say("%s now worships you!" % town["name"])
		_log_test("town_converted", town["name"])
		var all_mine := true
		for t in towns:
			all_mine = all_mine and t["mine"]
		if all_mine and not won and bool(Data.SYSTEMS["win"]["enabled"]):
			won = true
			_say("Every village on the island worships you. You are the one true god!")


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	add_child(hud)
	var font_col := Color(1, 0.96, 0.85)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Black & White — Godot Island"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", font_col)
	box.add_child(title)
	align_label.add_theme_color_override("font_color", font_col)
	box.add_child(align_label)
	align_bar.min_value = -100
	align_bar.max_value = 100
	align_bar.show_percentage = false
	align_bar.custom_minimum_size = Vector2(260, 12)
	box.add_child(align_bar)
	towns_label.add_theme_color_override("font_color", font_col)
	box.add_child(towns_label)
	hud.add_child(panel)
	msg_label.anchor_left = 0.5
	msg_label.anchor_right = 0.5
	msg_label.anchor_top = 1.0
	msg_label.anchor_bottom = 1.0
	msg_label.offset_left = -400
	msg_label.offset_right = 400
	msg_label.offset_top = -150
	msg_label.offset_bottom = -60
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	msg_label.add_theme_font_size_override("font_size", 20)
	msg_label.add_theme_color_override("font_color", Color.WHITE)
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(msg_label)
	dialogue_caption.anchor_left = 0.5
	dialogue_caption.anchor_right = 0.5
	dialogue_caption.anchor_top = 1.0
	dialogue_caption.anchor_bottom = 1.0
	dialogue_caption.offset_left = -570
	dialogue_caption.offset_right = 570
	dialogue_caption.offset_top = -260
	dialogue_caption.offset_bottom = -160
	dialogue_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	dialogue_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_caption.add_theme_font_size_override("font_size", 22)
	dialogue_caption.add_theme_color_override("font_color", Color.WHITE)
	dialogue_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	dialogue_caption.add_theme_constant_override("outline_size", 6)
	hud.add_child(dialogue_caption)
	help_label.text = "Left click: pick up / put down   Left drag: move the land   Right click: throw   Right drag or Q/E: turn   Wheel: zoom   Space: home"
	help_label.text = "ЛКМ: взять / положить · тянуть: камера · ПКМ: бросить / вращать · колесо: масштаб · C: следовать · R/F: похвала/наказание · F5/F9: сохранить/загрузить"
	help_label.add_theme_font_size_override("font_size", 15)
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_left = 16
	help_label.offset_top = -32
	help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	help_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(help_label)
	_build_preservation_hud()


func _update_hud(delta: float) -> void:
	align_bar.value = alignment
	var word := "Neutral"
	if alignment > 25:
		word = "Good"
	elif alignment < -25:
		word = "Evil"
	align_label.text = "Your nature: %s" % word
	var lines := PackedStringArray()
	for t in towns:
		lines.append(("★ " if t["mine"] else "• ") + "%s — %d%%" % [t["name"], int(t["belief"])])
	towns_label.text = "\n".join(lines)
	var evil := clampf(-alignment / 100.0, 0.0, 1.0)
	var good := clampf(alignment / 100.0, 0.0, 1.0)
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.8).lerp(Color(0.35, 0.08, 0.06), evil).lerp(Color(0.35, 0.6, 0.95), good)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9).lerp(Color(0.55, 0.3, 0.25), evil)
	hand_mat.albedo_color = Color(1, 1, 1, 0.8).lerp(Color(1, 0.2, 0.1, 0.85), evil)
	_msg_timer -= delta
	if _msg_timer <= 0.0 and _messages.size() > 0:
		_messages.pop_front()
		_msg_timer = 4.0
		msg_label.text = "\n".join(_messages)


func _say(text: String) -> void:
	print(text)
	_messages.append(text)
	while _messages.size() > 4:
		_messages.pop_front()
	_msg_timer = 5.0
	msg_label.text = "\n".join(_messages)


# ---------------------------------------------------------------- test mode (no one playing)

func _read_melty_test() -> void:
	var f := OS.get_environment("LOCALAPPDATA").path_join("Melty/test/%s.json" % MELTY_SLUG)
	if not FileAccess.file_exists(f):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(f))
	if typeof(j) != TYPE_DICTIONARY:
		return
	test_mode = true
	_melty_checks = str(j.get("checks", ""))
	if j.has("seed"):
		seed(int(j["seed"]))


func melty_check(check: String, ok: bool, why := "") -> void:
	var line := ("pass %s" % check) if ok else ("fail %s: %s" % [check, why])
	print("Melty check: ", line)
	if _melty_checks == "":
		return
	var f := FileAccess.open(_melty_checks, FileAccess.READ_WRITE) if FileAccess.file_exists(_melty_checks) else FileAccess.open(_melty_checks, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()


func _log_test(check: String, detail: String) -> void:
	_test_log.append("%s: %s" % [check, detail])
	if test_mode:
		print("TEST ", check, " ", detail)


func _run_test() -> void:
	# Plays a short round by itself: gift a tree to a neutral town, then throw a rock into a village.
	await get_tree().create_timer(2.0).timeout
	var target := 1
	var tree: Thing = null
	var bd := 1e9
	for t in things:
		if t.kind == "tree":
			var d := t.position.distance_to(towns[target]["pos"])
			if d < bd:
				bd = d
				tree = t
	focus = towns[target]["pos"]
	dist = 180.0
	await get_tree().create_timer(1.0).timeout
	var before: float = towns[target]["belief"]
	if tree:
		pick_up(tree)
		await get_tree().create_timer(1.0).timeout
		throw_thing(tree, cam.position.lerp(towns[target]["pos"], 0.7), towns[target]["pos"] + Vector3(6, 0, 6))
		held = null
	await get_tree().create_timer(4.0).timeout
	_log_test("belief_rose", "%.0f -> %.0f" % [before, towns[target]["belief"]])
	melty_check("gift-raises-belief", towns[target]["belief"] > before, "belief stayed at %.0f" % before)
	var rock: Thing = null
	for t in things:
		if t.kind == "rock":
			rock = t
			break
	var vill: Thing = null
	for t in things:
		if t.kind == "villager" and t.state != Thing.State.DEAD:
			vill = t
			break
	if rock and vill:
		focus = vill.position
		await get_tree().create_timer(1.5).timeout
		pick_up(rock)
		await get_tree().create_timer(1.0).timeout
		throw_thing(rock, cam.position.lerp(vill.position, 0.7), vill.position + Vector3(8, 0, 0))
		held = null
	await get_tree().create_timer(5.0).timeout
	var fled := false
	for l in _test_log:
		if l.begins_with("rock_scare"):
			fled = true
	melty_check("rock-scares-villagers", fled, "no villager fled from the rock")
	print("TEST done: ", "; ".join(_test_log))
	_run_preservation_test()


# ---------------------------------------------------------------- preservation work

func _build_preservation_hud() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -410
	panel.offset_right = -16
	panel.offset_top = 16
	creature_panel.custom_minimum_size.x = 370
	panel.add_child(creature_panel)
	campaign_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	campaign_status.custom_minimum_size.x = 370
	campaign_status.add_theme_color_override("font_color", Color("e6ce9e"))
	campaign_status.text = "Перенос первого острова · рабочая версия"
	creature_panel.add_child(campaign_status)
	creature_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creature_status.custom_minimum_size.x = 370
	creature_panel.add_child(creature_status)
	creature_panel.add_child(choice_row)
	var index := 1
	for id in Data.CREATURES:
		var button := Button.new()
		button.text = "%d. %s" % [index, Data.CREATURES[id]["name"]]
		button.pressed.connect(choose_creature.bind(id))
		choice_row.add_child(button)
		index += 1
	var buttons := HBoxContainer.new()
	for pair in [["Хвалить (R)",true],["Наказать (F)",false]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func():
			if is_instance_valid(creature):
				creature.feedback(pair[1]))
		buttons.add_child(button)
	creature_panel.add_child(buttons)
	var note := Label.new()
	note.text = "Оригинальные модели и анимации.\nВоспитание пока упрощено; сюжет ещё не исполняется."
	note.add_theme_font_size_override("font_size", 13)
	creature_panel.add_child(note)
	hud.add_child(panel)


func _load_preservation() -> void:
	var indexed := campaign.load_file(_p(Data.PORT_MODULES["campaign"]["source"]))
	if indexed:
		campaign_status.text = "Первый остров · найдено %d оригинальных сценариев\nСюжетный режим ещё в переносе" % campaign.scripts.size()
		_log_test("campaign-index", "%d scripts; %d native functions require bindings" % [campaign.scripts.size(), campaign.native_calls.size()])
	else:
		campaign_status.text = "Сценарии не прочитаны: " + campaign.error
	_build_advisers()
	_spawn_food()
	if not test_mode and not showcase_mode:
		_restore_preservation(false)
		_setup_original_dialogue()
		_setup_original_music()
		if is_instance_valid(dialogue) and not is_instance_valid(creature):
			dialogue.play_event("creature_choice")


func _setup_original_music() -> void:
	var candidate := OriginalMusic.new()
	if not candidate.configure(bw_dir):
		_say("Не удалось прочитать музыку: " + candidate.error)
		candidate.free()
		return
	original_music = candidate
	add_child(original_music)
	original_music.set_alignment(alignment)


func _setup_original_dialogue() -> void:
	var candidate := OriginalDialogue.new()
	if not candidate.configure(bw_dir):
		_say("Не удалось прочитать голоса советников: " + candidate.error)
		candidate.free()
		return
	dialogue = candidate
	add_child(dialogue)
	dialogue.line_started.connect(_show_adviser_line)
	dialogue.line_finished.connect(func():
		_speaking_adviser = ""
		dialogue_caption.text = "")
	dialogue.sequence_finished.connect(func(): dialogue_caption.text = "")


func _show_adviser_line(speaker: String, text: String) -> void:
	var name := "Советник"
	if speaker == "HELP_TEXT_NARRATOR_GOOD_SPIRIT":
		name = "Добрый советник"
		_speaking_adviser = "good"
	elif speaker == "HELP_TEXT_NARRATOR_EVIL_SPIRIT":
		name = "Злой советник"
		_speaking_adviser = "evil"
	else:
		_speaking_adviser = ""
	var cleaned := text.replace("$m1", "").replace("$m2", "").strip_edges()
	dialogue_caption.text = "%s: %s" % [name, cleaned]


func _build_advisers() -> void:
	for id in Data.ADVISERS:
		var row: Dictionary = Data.ADVISERS[id]
		var reader := L3dRig.new()
		var visual := reader.load_file(_p(row["file"]))
		if visual == null:
			_say("Советник не прочитан: " + reader.error)
			continue
		var height := maxf(reader.bounds.size.y, 0.1)
		var scale_f := 2.7 / height
		var anchor := Node3D.new()
		anchor.name = "Adviser_" + id
		anchor.add_child(visual)
		visual.scale = Vector3.ONE * scale_f
		visual.position.y = -reader.bounds.position.y * scale_f
		anchor.position = Vector3(float(row["side"]) * 5.7, -3.1, -10)
		cam.add_child(anchor)
		adviser_nodes.append(anchor)
		var animation := MorphReader.new()
		if animation.load_adviser(_p(row["file"])):
			adviser_animations.append({"id":id,"rig":reader,"animation":animation})
		else:
			_say("Анимация советника не прочитана: " + animation.error)


func _spawn_food() -> void:
	# Grain is supplied at original storage pits, not copied into the port.
	for c in island.all("CREATE_ABODE"):
		var args: PackedStringArray = c["args"]
		if not args[2].ends_with("STORAGE_PIT"):
			continue
		var p := to_world(IslandScript.pos(args[1]))
		for i in 3:
			var pos := p + Vector3(5 + i * 3, 0, 5)
			pos.y = ground_y(pos)
			var grain := _place_mesh("MSH_O_WHEAT_INHAND", pos, 0.0, 1.0, "food")
			if grain:
				things.append(grain)


func choose_creature(id: String, restored: Dictionary = {}) -> bool:
	if not Data.CREATURES.has(id):
		return false
	if is_instance_valid(creature):
		if restored.is_empty():
			return false
		creature.queue_free()
	var offset: Array = Data.PORT_RULES["creature"]["spawn_offset"]
	var spawn := focus + Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	if restored.has("position") and restored["position"] is Array and restored["position"].size() == 3:
		var p: Array = restored["position"]
		spawn = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if not spawn.is_finite() or ground_y(spawn) <= sea_y:
		spawn = towns[0]["pos"] + Vector3(25, 0, 20)
	spawn.y = ground_y(spawn)
	var next := IslandCreature.new()
	if not next.configure(self, id, spawn):
		next.free()
		return false
	creature = next
	add_child(creature)
	if not restored.is_empty():
		creature.restore(restored)
	choice_row.visible = false
	focus = spawn
	dist = 100.0
	_say("Ваше существо — %s. C — следовать. После поступка R — похвалить, F — наказать." % Data.CREATURES[id]["name"])
	if is_instance_valid(dialogue) and restored.is_empty():
		dialogue.play_event("creature_chosen")
	_log_test("creature-loaded", "%s; %d bones; %d clips" % [id, creature.rig.bone_count, creature.morph.clips.size()])
	return true


func _update_preservation_hud() -> void:
	if not is_instance_valid(creature):
		creature_status.text = "Выберите спутника. После выбора воспитывайте его поступками."
		return
	creature_status.text = "%s · голод %d%% · доверие %d%%\nНрав: %+.0f · %s\nУсвоено: помощь %d%% / страх %d%%" % [Data.CREATURES[creature.species]["name"],creature.hunger * 100,creature.trust * 100,creature.nature,"следует за Рукой" if creature.following else "остаётся здесь",creature.memory["help"] * 100,creature.memory["scare"] * 100]


func _save_preservation(announce := true) -> bool:
	if test_mode or showcase_mode or not is_instance_valid(creature):
		return false
	var beliefs: Array[Dictionary] = []
	for town in towns:
		beliefs.append({"belief":town["belief"],"mine":town["mine"]})
	var save := {"version":Data.PORT_RULES["save"]["version"],"creature":creature.snapshot(),"alignment":alignment,"towns":beliefs}
	var path: String = Data.PORT_RULES["save"]["file"]
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		if announce:
			_say("Не удалось сохранить игру.")
		return false
	f.store_string(JSON.stringify(save))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	if announce:
		_say("Остров и воспитание сохранены." if err == OK else "Не удалось завершить сохранение.")
	return err == OK


func _restore_preservation(announce := true) -> bool:
	if test_mode:
		return false
	var path: String = Data.PORT_RULES["save"]["file"]
	if not FileAccess.file_exists(path):
		if announce:
			_say("Сохранения пока нет.")
		return false
	var save = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not save is Dictionary or int(save.get("version", -1)) != int(Data.PORT_RULES["save"]["version"]):
		_say("Сохранение не распознано.")
		return false
	var cs = save.get("creature", {})
	if not cs is Dictionary or not Data.CREATURES.has(cs.get("species", "")):
		return false
	if not choose_creature(cs["species"], cs):
		return false
	alignment = clampf(float(save.get("alignment", 0.0)), -100.0, 100.0)
	var saved_towns = save.get("towns", [])
	if saved_towns is Array and saved_towns.size() == towns.size():
		for i in towns.size():
			if saved_towns[i] is Dictionary:
				towns[i]["belief"] = clampf(float(saved_towns[i].get("belief", 0)), 0, 100)
				towns[i]["mine"] = bool(saved_towns[i].get("mine", false))
				towns[i]["marker"].visible = towns[i]["mine"]
	if announce:
		_say("Сохранение загружено.")
	return true


func _run_preservation_test() -> void:
	melty_check("campaign-index-loaded", campaign.scripts.has("SetupLand1"), campaign.error)
	melty_check("advisers-loaded", adviser_nodes.size() == 2, "expected two original adviser meshes")
	var learn_failed: Array[String] = []
	for id in Data.CREATURES:
		var ok := choose_creature(id, {"position":[towns[0]["pos"].x + 25,0,towns[0]["pos"].z + 20]})
		melty_check("creature-" + id, ok and creature.rig.bone_count > 0 and creature.morph.clips.has("move/walk"), "original creature rig/animation unavailable")
		if not ok:
			continue
		focus = creature.position
		dist = 100
		await get_tree().create_timer(2.0).timeout
		creature.perform("help", 0)
		var before: float = creature.memory["help"]
		creature.feedback(true)
		if creature.memory["help"] <= before:
			learn_failed.append(id)
		await get_tree().create_timer(3.0).timeout
	melty_check("creatures-learn", learn_failed.is_empty(), "praise did not reinforce: " + ", ".join(learn_failed))
	_port_tests = true
	await _test_closeups()


# Close views of walking villagers and the advisers, so a test recording shows their animation.
func _test_closeups() -> void:
	var shown := 0
	var moved := false
	for t in things:
		if shown >= 4:
			break
		if t.kind != "villager" or t.state == Thing.State.DEAD or t.rig == null or t.rig.skeleton == null:
			continue
		t._target = t.position + Vector3(10, 0, 4)
		t._wait = 0.0
		var sk: Skeleton3D = t.rig.skeleton
		var last := sk.get_bone_count() - 1
		var before := sk.get_bone_global_pose(last)
		for i in 12:
			focus = t.position
			dist = 14.0
			pitch = deg_to_rad(22.0)
			yaw = 0.4 + i * 0.05
			_update_camera()
			await get_tree().create_timer(0.5).timeout
		if not sk.get_bone_global_pose(last).is_equal_approx(before):
			moved = true
		shown += 1
	melty_check("villagers-animate", moved, "villager bones did not move")
	if not creature:
		return
	# Walk the creature between villages for the rest of the run; Melty closes the game.
	creature.following = true
	dist = 150.0
	pitch = deg_to_rad(30.0)
	var stop := 0
	var waited := 0
	while is_inside_tree():
		stop = (stop + 1) % towns.size()
		var goal: Vector3 = towns[stop]["pos"]
		while is_inside_tree() and Vector2(focus.x - goal.x, focus.z - goal.z).length() > 10.0:
			var step := Vector3(goal.x - focus.x, 0, goal.z - focus.z)
			if Vector2(creature.position.x - focus.x, creature.position.z - focus.z).length() < 40.0:
				focus += step.normalized() * minf(7.0 * 0.1, step.length())
				waited = 0
			else:
				waited += 1
				if waited > 100: # blocked by water: carry on from where the camera is
					creature.position = Vector3(focus.x, ground_y(focus), focus.z)
			focus.y = ground_y(focus)
			yaw += 0.002
			await get_tree().create_timer(0.1).timeout


func _exit_tree() -> void:
	g3d.close()


func _capture_preservation(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().create_timer(2.0).timeout
	choose_creature("ape")
	await get_tree().create_timer(3.0).timeout
	await _capture_frame(folder.path_join("ape-and-advisers.png"))
	var villager: Thing = null
	for thing in things:
		if thing.kind == "villager" and thing.state != Thing.State.DEAD:
			villager = thing
			break
	if villager:
		for adviser in adviser_nodes:
			adviser.visible = false
		creature.following = false
		focus = villager.position
		dist = 13.0
		pitch = deg_to_rad(25.0)
		yaw = 0.4
		villager._target = villager.position
		villager._wait = 8.0
		await get_tree().create_timer(0.5).timeout
		await _capture_frame(folder.path_join("villager-idle.png"))
		villager._target = villager.position + Vector3(12,0,0)
		await get_tree().create_timer(0.3).timeout
		focus = villager.position
		await _capture_frame(folder.path_join("villager-walk-a.png"))
		await get_tree().create_timer(0.35).timeout
		focus = villager.position
		await _capture_frame(folder.path_join("villager-walk-b.png"))
		print("SHOWCASE villager ",villager.animation_name," bones ",villager.rig.bone_count)
	for adviser in adviser_nodes:
		adviser.visible = true
	for id in ["cow","tiger"]:
		choose_creature(id,{"position":[towns[0]["pos"].x+25,0,towns[0]["pos"].z+20]})
		focus = creature.position
		dist = 100
		pitch = deg_to_rad(30)
		yaw = 0.6
		await get_tree().create_timer(2.0).timeout
		creature.perform("help",0)
		creature.feedback(true)
		await get_tree().create_timer(0.6).timeout
		await _capture_frame(folder.path_join(id+"-and-advisers.png"))
	print("SHOWCASE complete")
	get_tree().quit()


func _capture_frame(path: String) -> void:
	_update_camera()
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SHOWCASE image ",path.get_file()," ",err)
