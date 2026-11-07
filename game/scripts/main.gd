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
var story_mobile_statics: Array[Thing] = []
const StoryShark := preload("res://scripts/story_shark.gd")
const StoryIntroMovie := preload("res://scripts/story_intro_movie.gd")
const StoryFireTrail := preload("res://scripts/story_fire_trail.gd")
const StoryRescueHand := preload("res://scripts/story_rescue_hand.gd")
const StoryHandDemo := preload("res://scripts/story_hand_demo.gd")
const WoodHand := preload("res://scripts/story_wood_hand.gd")
const StoryHighlight := preload("res://scripts/story_highlight.gd")
const StoryCitadelSite := preload("res://scripts/story_citadel_site.gd")
const CitadelConstruction := preload("res://scripts/story_citadel_construction.gd")
const StoryAttachedMusic := preload("res://scripts/story_attached_music.gd")
const StoryTempleInterior := preload("res://scripts/story_temple_interior.gd")
var story_temple: StoryTempleInterior
var story_hand_demo := StoryHandDemo.new()
var story_camera_input := preload("res://scripts/story_camera_input.gd").new()
var _story_demo_wood: MeshInstance3D
var _story_demo_holding_wood := false
var _story_demo_name := ""
var _story_wood_hand: RefCounted
var _story_demo_wood_delivered := 0
var story_intro_movie: StoryIntroMovie
var story_fire_trail: StoryFireTrail
var story_rescue_hand: StoryRescueHand
var story_preview := false
var story_interface_level := 0
var story_citadel_interface := true
var story_shark_animations: AnmReader
var story_sharks: Array[Node3D] = []
var story_citadel: StoryCitadelSite
var story_construction: RefCounted
var alignment := 0.0
var won := false
var loaded := false

var cam := Camera3D.new()
var focus := Vector3.ZERO
var yaw := 0.6
var pitch := deg_to_rad(50.0)
var dist := 150.0
var _rendered_focus := Vector3.ZERO
var _focus_height_offset := 0.0

var held: Thing = null
var hand_ring := MeshInstance3D.new()
var hand_mat := StandardMaterial3D.new()
var sky_mat := ProceduralSkyMaterial.new()
var env := Environment.new()
var sun: DirectionalLight3D

var _left_down := false
var _right_down := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _grab_point := Vector3.ZERO
var _right_moved := 0.0
var _camera_input_idle := 0.0

var hud := CanvasLayer.new()
var align_bar := ProgressBar.new()
var align_label := Label.new()
var towns_label := Label.new()
var msg_label := Label.new()
var help_label := Label.new()
var dialogue_caption := Label.new()
var dialogue: OriginalDialogue
var original_music: OriginalMusic
var story_alignment_music_enabled := true
var story_letterbox: CanvasLayer
var story_fade_rect: ColorRect
var story_fade_tween: Tween
var story_sfx_bank := SoundBank.new()
var story_game_sfx_bank := SoundBank.new()
var story_sfx_streams: Dictionary = {}
var story_effects: Array[Node3D] = []
var story_gate_plinth: Node3D
var world_geometry := preload("res://scripts/story_world_geometry.gd").new()
var world_physics := preload("res://scripts/story_world_geometry.gd").new()
var _landmark_physics: Array[Dictionary] = []
var _cursor_screen := Vector2.INF
var _hovered_scroll: Node3D
var _hand_surface := Vector3.ZERO
var _hand_action := "hover"
var hand_pose := preload("res://scripts/story_hand_pose.gd").new()
var _hand_motion := Vector2.ZERO
var _hand_zoom_time := 0.0
var _hand_facing := Vector3.UP
var _hand_facing_started := false
var _messages: Array[String] = []
var _msg_timer := 0.0

var ambience := AudioStreamPlayer.new()
var sea_player := AudioStreamPlayer.new()
var _ambience_waves: Array[AudioStreamWAV] = []
var _ambience_delay := 8.0
var _tutorial_completed_hint := ""
var _tutorial_hint_time := 0.0
var _tutorial_last := ""

var test_mode := false
var _test_log: Array[String] = []
var _melty_checks := "" # Melty's test file: where to append "pass <check>" lines
const MELTY_SLUG := "black-white-godot-island"
var creature: IslandCreature
var campaign := ChlReader.new()
var story_vm: StoryVm
var _reported_suspended_tasks: Dictionary = {}
var story_bridge: StoryNatives
var story_camera := preload("res://scripts/story_camera.gd").new()
const StoneSparkles := preload("res://scripts/story_stone_sparkles.gd")
var story_stone_sparkle_frames: Array[Texture2D] = []
var story_time := preload("res://scripts/story_time.gd").new()
var _time_scale_before_story := 1.0
var _story_speed_applied := 1.0
var story_clock := 0.0
var story_state := "not started"
var story_journal: Dictionary = {}
var virtual_influence := true
var influence_sources: Array[Dictionary] = []
var story_highlights: Array[Node3D] = []
var story_highlights_visible := true
var town_nodes: Array[Node3D] = []
var villager_anims := AnmReader.new()
var landmark_anims := AnmReader.new()
var animation_clock := 0.0
var creature_panel := VBoxContainer.new()
var creature_status := Label.new()
var campaign_status := Label.new()
var choice_row := HBoxContainer.new()
var adviser_nodes: Array[Node3D] = []
var adviser_animations: Array[Dictionary] = []
const ADVISER_LAYER := 1 << 19
var _adviser_viewport: SubViewport
var _adviser_view_camera: Camera3D
var _adviser_targets: Dictionary = {}
var _adviser_tweens: Dictionary = {}
var _adviser_clinging: Dictionary = {}
var _adviser_time := 0.0
var _speaking_adviser := ""
var _adviser_speech_started := 0.0
var story_adviser_points: Dictionary = {}
var story_adviser_objects: Dictionary = {}
var story_adviser_looks: Dictionary = {}
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
		if a == "--story-preview":
			story_preview = true
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
	if story_preview and DisplayServer.get_name() != "headless":
		get_window().title = "Black & White — реставрация · Preview 9.1"
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_load_preservation()
	var heights := PackedStringArray()
	for t in towns:
		heights.append("%.0f" % t["pos"].y)
	_log_test("town_heights", ",".join(heights))
	_log_test("island_loaded", "terrain, %d towns, %d things in %d ms" % [towns.size(), things.size(), Time.get_ticks_msec() - t0])
	if not story_preview:
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
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)


func _update_story_time(delta: float) -> void:
	if story_time.speed != _story_speed_applied:
		if _story_speed_applied == 1.0:
			_time_scale_before_story = Engine.time_scale
		_story_speed_applied = story_time.speed
		Engine.time_scale = _time_scale_before_story * _story_speed_applied
	if not story_time.daylight_started or not is_instance_valid(sun):
		return
	story_time.advance(delta)
	# Use the scripted hour to approximate the original daylight and dawn colors.
	var elevation := sin((story_time.hour - 6.0) * TAU / 24.0)
	var daylight := smoothstep(-0.12, 0.35, elevation)
	sun.rotation_degrees = Vector3(-maxf(elevation, 0.0) * 72.0, 35.0 + (story_time.hour - 12.0) * 15.0, 0.0)
	sun.light_energy = 1.2 * daylight
	sun.light_color = Color(1.0, 0.56, 0.36).lerp(Color.WHITE, smoothstep(0.0, 0.6, elevation))
	env.ambient_light_energy = lerpf(0.12, 0.6, daylight)


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


func _place_mesh(mesh_name: Variant, p: Vector3, yaw_rad: float, scale_f: float, kind: String, submesh_states := PackedInt32Array()) -> Thing:
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
		var m := g3d.mesh_index(int(mesh_name), submesh_states) if mesh_name is int else g3d.mesh(str(mesh_name), submesh_states)
		if m == null:
			t.free()
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.visibility_range_end = 1800.0 if kind != "house" else 3000.0
		t.add_child(mi)
	t.position = p
	t.rotation.y = yaw_rad
	t.scale = Vector3.ONE * scale_f
	t.home = p
	add_child(t)
	if kind != "villager": world_geometry.register_node(t)
	if kind in ["rock", "gate_key", "food", "toy"]: world_physics.register_node(t)
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
	for c in island.all("CREATE_ABODE") + island.all("CREATE_TOWN_CENTRE"):
		var a: PackedStringArray = c["args"]
		var placement := IslandScript.placement("abode", a)
		if Data.ABODES.has(a[2]) and not placement.is_empty():
			# Existing abodes use their completed state. Graveyard states instead
			# represent separate graves, so they retain their own visibility rules.
			var states := PackedInt32Array() if a[2].contains("GRAVEYARD") else PackedInt32Array([0])
			var abode := _place_mesh(Data.ABODES[a[2]], to_world(IslandScript.pos(a[1])), placement["angle"], placement["scale"], "house", states)
			if abode:
				abode.town = int(a[0])
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
		landmark.rotation.y = float(placement["angle"])
		landmark.scale = Vector3.ONE * float(placement["scale"])
		landmark.set_meta("original_type", a[1])
		landmark.set_meta("story_type", 3)
		landmark.set_meta("original_animation_id", original["animation_id"])
		add_child(landmark)
		story_landmarks.append(landmark)
		if a[1] == "Gate Stone Plinth":
			story_gate_plinth = preload("res://scripts/story_gate_plinth.gd").new()
			landmark.add_child(story_gate_plinth)
			story_gate_plinth.configure(landmark, g3d)
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
			t.set_meta("story_mobile_subtype", int(a[1]))
			story_mobile_statics.append(t)
			var rotation_basis := Basis.from_euler(Vector3(-float(a[3]),-float(a[4]),-float(a[5])), EULER_ORDER_XYZ)
			var reflected := L3dRig.reflected(Transform3D(rotation_basis, Vector3.ZERO))
			t.basis = reflected.basis.scaled(Vector3.ONE * float(a[6]))
	for c in island.all("CREATE_VILLAGER_POS"):
		var a: PackedStringArray = c["args"]
		if not Data.VILLAGERS.has(a[2]):
			continue
		var p := to_world(IslandScript.pos(a[0]))
		var villager := _spawn_villager(a[2], p, to_world(IslandScript.pos(a[1])))
		if villager != null:
			villager.story_age = int(a[3])
	for landmark in story_landmarks:
		world_geometry.register_node(landmark, landmark, landmark.rig if landmark is OriginalLandmark else null)
		var type: String = landmark.get_meta("original_type", "")
		if type in ["Norse Gate", "Gate Stone Plinth"]:
			var proxy := MeshInstance3D.new()
			proxy.mesh = g3d.mesh_index(219 if type == "Norse Gate" else 336)
			proxy.visible = false
			landmark.add_child(proxy)
			_landmark_physics.append({"target":landmark,"visual":proxy,"type":type})
			world_physics.register_node(proxy, landmark, null, Callable(), true)
		else:
			world_physics.register_node(landmark, landmark, landmark.rig if landmark is OriginalLandmark else null)


func _spawn_villager(profile: String, pos: Vector3, home: Vector3) -> Thing:
	var row: Dictionary = Data.VILLAGERS[profile]
	var villager := _place_mesh(row["mesh"], pos, randf() * TAU, float(row["scale"]), "villager")
	if villager:
		villager.animation_profile = row["animation_profile"]
		villager.home = home
		villager.town = _nearest_town(home, 400.0)
		things.append(villager)
	return villager


func story_create_villager(subtype: int, pos: Vector3) -> Thing:
	# FollowUs uses the Norse housewife (49), farmer (52), and shepherd (53).
	# The original adult meshes are shared by the farmer, shepherd, and forester.
	# FollowUs changes the son's age separately after creation.
	var profiles := {49: "NORSE_HOUSEWIFE", 52: "NORSE_FORESTER", 53: "NORSE_FORESTER"}
	if not profiles.has(subtype):
		var original := host_info.villager(subtype)
		if original.is_empty():
			return null
		var actor_rig := g3d.rig_index(original["mesh_id"])
		if actor_rig == null:
			return null
		var actor := Thing.new()
		actor.kind = "villager"
		actor.world = self
		actor.rig = actor_rig
		actor.add_child(actor_rig.root)
		actor.position = pos
		actor.home = pos
		actor.animation_profile = "female" if int(original["sex"]) == 1 else "male"
		actor.story_age = 25
		actor.story_hold_position = true
		actor.set_meta("story_villager_subtype", subtype)
		actor.set_meta("story_spawn_position", pos)
		add_child(actor)
		things.append(actor)
		return actor
	var villager := _spawn_villager(profiles[subtype], pos, pos)
	if villager:
		villager.set_meta("story_villager_subtype", subtype)
		villager.set_meta("story_spawn_position", pos)
		villager.story_hold_position = true
		# Original Norse villager info records start these three roles at age 25.
		villager.story_age = 25
	return villager


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
	m.visible = towns[i]["mine"] and not story_preview
	add_child(m)
	towns[i]["marker"] = m


func _build_hand() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 3.0
	hand_ring.mesh = null if story_preview else torus
	hand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hand_mat.albedo_color = Color(1, 1, 1, 0.8)
	hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hand_mat.no_depth_test = true
	hand_ring.material_override = hand_mat
	add_child(hand_ring)
	hand_rig = L3dRig.new()
	var visual := hand_rig.load_file(_p("Data/CreatureMesh/Hand_Boned_Base2.l3d"))
	if visual:
		visual.name = "OriginalHand"
		if not hand_pose.configure(bw_dir, hand_rig):
			push_error("Original hand animation cannot load: " + hand_pose.error)
		hand_pivot.add_child(visual)
		hand_ring.add_child(hand_pivot)


func _start_audio() -> void:
	_ambience_waves = SadReader.load_waves(_p(Data.SOURCES["ambience"]), 24)
	add_child(ambience)
	ambience.volume_db = -26.0
	ambience.finished.connect(func(): _ambience_delay = randf_range(12.0, 24.0))
	var sea := SadReader.load_waves(_p(Data.SOURCES["night_ambience"]), 2)
	if sea.size() > 0:
		add_child(sea_player)
		sea[0].loop_mode = AudioStreamWAV.LOOP_FORWARD
		sea[0].loop_end = sea[0].data.size() / (2 * (2 if sea[0].stereo else 1))
		sea_player.stream = sea[0]
		sea_player.volume_db = -24.0
		sea_player.play()
	_log_test("ambience_loaded", "%d countryside sounds" % _ambience_waves.size())


func _next_ambience() -> void:
	if _ambience_waves.is_empty():
		return
	ambience.stream = _ambience_waves[randi() % _ambience_waves.size()]
	ambience.play()


func _update_ambience(delta: float) -> void:
	# The score and original voices carry the opening. These country sounds are
	# occasional background details, rather than a second continuous soundtrack.
	var cinematic := story_camera.owner_task != 0 or not _speaking_adviser.is_empty() or story_inside_temple() or (story_intro_movie != null and story_intro_movie.active)
	sea_player.stream_paused = cinematic
	if cinematic:
		if ambience.playing:
			ambience.stop()
		_ambience_delay = maxf(_ambience_delay, 8.0)
		return
	if not ambience.playing:
		_ambience_delay -= delta
		if _ambience_delay <= 0.0:
			_next_ambience()


# ---------------------------------------------------------------- camera & input

func _update_camera() -> void:
	if story_camera.owner_task != 0:
		var view_eye: Vector3 = story_camera.eye
		var view_focus: Vector3 = story_camera.focus
		if not story_sharks.is_empty() and ground_y(view_eye) <= sea_y:
			var surface_view := story_camera.above_water_pose(sea_y)
			view_eye = surface_view["eye"]
			view_focus = surface_view["focus"]
		# Authored targets can intentionally lie below terrain, beyond the subject
		# (the temple-door shot does this). Raising that target changes the shot.
		# Keep the eye above the surface without rewriting its viewing direction.
		# Low authored dialogue shots are valid: raising them to the free-camera
		# three-unit clearance puts nearby speakers below the frame.
		view_eye.y = maxf(view_eye.y, maxf(ground_y(view_eye), sea_y) + 0.5)
		var offset: Vector3 = view_eye - view_focus
		_rendered_focus = view_focus
		cam.position = view_eye
		if offset.length_squared() > 0.00001:
			var up := Vector3.RIGHT if absf(offset.normalized().dot(Vector3.UP)) > 0.999 else Vector3.UP
			cam.basis = Basis.looking_at(-offset, up)
		return
	focus = story_camera.constrain_player_focus(focus)
	focus.y = maxf(ground_y(focus), sea_y) + _focus_height_offset
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = story_camera.constrain_player_eye(focus + off, focus, ground_y, sea_y)
	cam.look_at(focus, Vector3.UP)
	_rendered_focus = focus
	story_camera.update_player_pose(cam.position, focus)


func _camera_min_distance() -> float:
	return 4.0 if story_preview else float(cfg_camera["min_dist"])


func _resume_player_camera() -> void:
	# Resume from the image the player actually saw. The rendered camera may
	# have been raised for terrain/water clearance relative to the authored path.
	focus = _rendered_focus
	if focus.y < maxf(ground_y(focus), sea_y):
		# Replace a buried cinematic target with the visible point on its ray.
		# This keeps the same image while giving ground movement a usable pivot.
		focus = ground_point(get_viewport().get_visible_rect().size * 0.5)
	_focus_height_offset = maxf(0.0, focus.y - maxf(ground_y(focus), sea_y))
	var offset: Vector3 = cam.position - focus
	if offset.length_squared() > 0.00001:
		dist = clampf(offset.length(), _camera_min_distance(), cfg_camera["max_dist"])
		yaw = atan2(offset.x, offset.z)
		pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	_left_down = false
	_right_down = false
	_dragging = false


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
	if event is InputEventMouse:
		_cursor_screen = event.position
		if event is InputEventMouseMotion: _hand_motion = event.relative
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: _hand_zoom_time = 0.25
	if story_inside_temple():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			story_temple.close()
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if story_preview else Input.MOUSE_MODE_VISIBLE
		return
	if story_intro_movie != null and story_intro_movie.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			story_intro_movie.finish()
		return
	if story_camera.owner_task != 0:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_tree().quit()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and story_citadel_interface and story_citadel != null and story_citadel.progress >= 1.0:
					if story_citadel.entrance_hit(cam.project_ray_origin(mb.position), cam.project_ray_normal(mb.position)):
						story_enter_temple()
						return
				if mb.double_click and story_interface_level in [4, 13, 14, 15]:
					focus = ground_point(mb.position)
					_focus_height_offset = 0.0
				_left_down = true
				_dragging = false
				_press_pos = mb.position
				_grab_point = ground_point(mb.position)
			else:
				_left_down = false
				if not _dragging and story_interface_level == 0:
					_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_down = true
				_right_moved = 0.0
			else:
				_right_down = false
				story_camera_input.set_hand_state(0)
				if _right_moved < 6.0 and held and story_interface_level == 0:
					_throw(hand_target(mb.position)["point"])
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and story_interface_level in [0, 15]:
			var previous := dist
			dist = maxf(dist * 0.88, _camera_min_distance())
			story_camera_input.record_zoom(dist - previous)
			_camera_input_idle = 0.2
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and story_interface_level in [0, 15]:
			var previous := dist
			dist = minf(dist * 1.12, cfg_camera["max_dist"])
			story_camera_input.record_zoom(dist - previous)
			_camera_input_idle = 0.2
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
			_camera_input_idle = 0.2
			_right_moved += mm.relative.length()
			if story_interface_level in [0, 13, 14, 15]:
				var turn := -mm.relative.x * 0.006
				yaw += turn
				story_camera_input.record_rotation(turn)
			if story_interface_level in [0, 14, 15]:
				var previous := pitch
				# A cinematic can release outside the usual player pitch range.
				# Let input move inward from there without snapping on its first pixel.
				pitch = clampf(pitch + mm.relative.y * 0.004, minf(pitch, deg_to_rad(15)), maxf(pitch, deg_to_rad(85)))
				story_camera_input.record_pitch(pitch - previous)
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE and towns.size() > 0 and (story_bridge == null or story_bridge.camera_shortcuts_enabled):
			_focus_height_offset = 0.0
			if story_citadel_interface and story_citadel != null and story_citadel.progress >= 1.0:
				focus = story_citadel.position
			else:
				focus = towns[0]["pos"]
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif not story_preview and k.keycode >= KEY_1 and k.keycode <= KEY_3 and not is_instance_valid(creature):
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
	_update_ambience(delta)
	if story_intro_movie != null and story_intro_movie.active:
		return
	if story_intro_movie != null and not story_intro_movie.error.is_empty() and story_state == "running":
		story_state = "movie playback failed"
		campaign_status.text = story_intro_movie.error
	story_camera.advance(delta)
	_camera_input_idle = maxf(0.0, _camera_input_idle - delta)
	if _camera_input_idle == 0.0 and not _right_down:
		story_camera_input.set_hand_state(0)
	story_camera_input.advance(delta)
	story_advance_hand_demo(delta)
	if story_fire_trail != null and story_fire_trail.visible:
		story_fire_trail.advance(delta)
		story_camera.eye = story_fire_trail.camera_eye()
		story_camera.focus = story_fire_trail.position
	var camera_was_scripted: bool = story_camera.owner_task != 0
	_tick_story(delta)
	if story_intro_movie != null and story_intro_movie.active:
		return
	_update_story_time(delta)
	if camera_was_scripted and story_camera.owner_task == 0:
		_resume_player_camera()
	animation_clock += delta
	if story_camera.owner_task == 0:
		_move_player_camera(delta)
	_update_camera()
	_update_world(delta)
	if story_construction != null:
		story_construction.completion_prevented = story_vm != null and story_vm.variables.size() > 162 and StoryVm.as_float(story_vm.variables[162]) == 0.0
		story_construction.advance()


func _move_player_camera(delta: float) -> void:
	if story_interface_level not in [0, 13, 14, 15]:
		return
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	var rotation_delta := turn * delta * 1.2
	yaw += rotation_delta
	story_camera_input.record_rotation(rotation_delta)
	if rotation_delta != 0.0:
		_camera_input_idle = 0.2
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


func _update_world(delta: float) -> void:
	_sync_adviser_view()
	for highlight in story_highlights:
		if is_instance_valid(highlight):
			highlight.advance(delta, cam)
	var mouse := get_viewport().get_mouse_position()
	if _cursor_screen.is_finite(): mouse = _cursor_screen
	if story_hand_demo.playing:
		mouse = story_hand_demo.pose()["cursor"] * get_viewport().get_visible_rect().size
	var hand_active := story_camera.owner_task == 0 or story_hand_demo.playing
	var selection: Dictionary = hand_target(mouse) if hand_active else {"point":ground_point(mouse),"normal":Vector3.UP,"target":null}
	var gp: Vector3 = selection["point"]
	_hand_surface = gp
	if _hovered_scroll != null and is_instance_valid(_hovered_scroll): _hovered_scroll.set_hovered(false)
	_hovered_scroll = selection.get("scroll") as Node3D
	if _hovered_scroll != null: _hovered_scroll.set_hovered(true)
	_hand_action = "hold" if held != null else ("point" if _hovered_scroll != null else "hover")
	if held == null and _hovered_scroll == null and selection.get("target") is Thing:
		_hand_action = "pickup" if selection.has("pickup") and selection["target"].story_pickup_allowed else "point"
	if _dragging: _hand_action = "drag"
	if _right_down: _hand_action = "pitch" if absf(_hand_motion.y) > absf(_hand_motion.x) else "rotate"
	_hand_zoom_time = maxf(0.0, _hand_zoom_time - delta)
	if _hand_zoom_time > 0.0: _hand_action = "zoom"
	hand_ring.visible = hand_active
	hand_ring.transform = Transform3D.IDENTITY
	if held:
		held.position = gp + Vector3(0, float(cfg_hand["hold_height"]), 0)
	if hand_ring.visible and hand_rig != null:
		_update_hand_pose(delta, selection)
	_hand_motion = _hand_motion.lerp(Vector2.ZERO, 1.0 - exp(-delta * 15.0))
	for i in towns.size():
		if not towns[i]["mine"]:
			towns[i]["belief"] = maxf(0.0, towns[i]["belief"] - float(cfg_belief["decay_per_min"]) / 60.0 * delta)
	_update_hud(delta)
	_update_preservation_hud()
	_update_story_input_hint(delta)
	if is_instance_valid(original_music):
		original_music.set_alignment(alignment)
	_adviser_time += delta
	for id in story_adviser_objects.keys():
		var target: Object = story_adviser_objects[id].get_ref()
		if is_instance_valid(target):
			story_adviser_points[id] = target.global_position if target.is_inside_tree() else target.position
		else:
			story_adviser_objects.erase(id)
			story_adviser_points.erase(id)
	for adviser in adviser_animations:
		var rig: L3dRig = adviser["rig"]
		var animation: MorphReader = adviser["animation"]
		var id: String = adviser["id"]
		var anchor: Node3D = rig.root.get_parent()
		var size := get_viewport().get_visible_rect().size
		var screen := cam.unproject_position(anchor.global_position) / size
		var point := Vector2.INF
		var look := Vector2.INF
		if story_adviser_points.has(id):
			point = cam.unproject_position(story_adviser_points[id]) / size
		if story_adviser_looks.has(id):
			look = cam.unproject_position(story_adviser_looks[id]) / size
		var voice: AudioStreamPlayer = dialogue._player if id == _speaking_adviser and is_instance_valid(dialogue) else null
		var pose: RefCounted = adviser["pose"]
		pose.camera = cam
		anchor.rotation.y = pose.facing_yaw(screen, _adviser_clinging.get(id, false))
		rig.apply_local_pose(pose.sample(animation, rig, id, delta, screen, point, look, voice, _adviser_clinging.get(id, false)))
	_save_clock += delta
	if _save_clock >= float(Data.PORT_RULES["save"]["autosave_seconds"]):
		_save_clock = 0.0
		_save_preservation(false)


func _click(screen: Vector2) -> void:
	var selection := hand_target(screen)
	if held:
		if story_gate_plinth != null:
			var ray_origin := cam.project_ray_origin(screen)
			var contact: Variant = selection["point"] if selection.get("target") == story_gate_plinth.landmark else null
			if contact != null and ray_origin.distance_to(contact) <= ray_origin.distance_to(ground_point(screen)) + 0.05:
				var record := host_info.record(int(held.get_meta("story_mobile_subtype", -1)))
				# This is the key's original ApplyThisToObject action, validated
				# against the plinth. The generic terrain-drop boundary is separate.
				if story_gate_plinth.accept(record):
					world_geometry.register_node(story_gate_plinth, story_gate_plinth.landmark)
					var key := held
					story_delete_object(key)
					_log_test("gate_key", "actual key installed; info bits=%d" % story_gate_plinth.info_bits())
					return
		var gp: Vector3 = selection["point"]
		if gp.y <= sea_y + 0.05 and held.kind != "rock":
			_say("That would drown. Put it on land.")
			return
		if not has_influence(gp):
			_say("Это вне вашего влияния.")
			return
		held.position = gp + Vector3(0, 5, 0)
		held.velocity = Vector3.ZERO
		held.thrown = false
		held.state = Thing.State.FLYING
		held = null
		return
	var highlight := selection.get("scroll") as Node3D
	if highlight != null:
		story_bridge.clicked_thing = weakref(highlight)
		highlight.set_active(true)
		if highlight.highlight_type == 1 and highlight.has_meta("help_text"):
			story_play_voice(int(highlight.get_meta("help_text")))
		return
	var best: Thing = null
	best = selection.get("pickup") as Thing
	if best:
		if story_bridge != null: story_bridge.clicked_thing = weakref(best)
		if best.story_pickup_allowed and best.story_move_allowed and has_influence(best.position): pick_up(best)


func _find_pickup(screen: Vector2, surface: Vector3) -> Thing:
	var best: Thing
	var bd := 30.0
	for t in things:
		if not is_instance_valid(t) or t.state in [Thing.State.DEAD, Thing.State.FLYING, Thing.State.HELD]:
			continue
		if cam.is_position_behind(t.position):
			continue
		var centre := t.position + Vector3(0, 1.5, 0)
		if cam.position.distance_to(centre) > cam.position.distance_to(surface) + 3.0: continue
		var d := cam.unproject_position(centre).distance_to(screen)
		if d < bd:
			bd = d
			best = t
	return best


func pick_up(t: Thing) -> void:
	held = t
	t._landed_notified = false
	t.state = Thing.State.HELD
	t.rotation.x = 0.0
	var what := {"tree": "a tree", "rock": "a rock", "villager": "a villager", "gate_key": "a gate key"}
	_say("You pick up %s." % what.get(t.kind, "it"))


func _throw(target: Vector3) -> void:
	var t := held
	held = null
	throw_thing(t, t.position, target)


func hand_target(screen: Vector2) -> Dictionary:
	var point := ground_point(screen)
	var origin := cam.project_ray_origin(screen)
	var direction := cam.project_ray_normal(screen)
	var distance := origin.distance_to(point)
	var hit := world_geometry.raycast(origin, direction, distance)
	var result := {"point":point,"normal":ground_normal(point),"target":null}
	if not hit.is_empty():
		result = hit
		distance = origin.distance_to(hit["point"])
	if held != null and story_gate_plinth != null and result.get("target") != story_gate_plinth.landmark:
		var record := host_info.record(int(held.get_meta("story_mobile_subtype", -1)))
		if story_gate_plinth.can_accept(record):
			var contact: Variant = story_gate_plinth.drop_hit(cam, screen)
			if contact != null and origin.distance_to(contact) <= distance + 0.5:
				result = {"point":contact,"normal":Vector3.UP,"target":story_gate_plinth.landmark}
	if held == null:
		var nearest := INF
		for scroll in story_highlights:
			if not is_instance_valid(scroll) or not scroll.screen_hit(cam, screen): continue
			var centre: Vector3 = scroll.visual.global_transform * scroll.visual.mesh.get_aabb().get_center()
			var depth := origin.distance_to(centre)
			# The enlarged click area still respects a wall or terrain in front.
			if depth > distance + 1.0: continue
			var score := cam.unproject_position(centre).distance_squared_to(screen)
			if score < nearest:
				nearest = score
				result = {"point":centre,"normal":Vector3.UP,"target":scroll,"scroll":scroll}
		if not result.has("scroll"):
			var direct := result.get("target") as Thing
			var pickup := direct if direct != null and things.has(direct) and direct.state not in [Thing.State.FLYING, Thing.State.DEAD, Thing.State.HELD] else _find_pickup(screen, result["point"])
			if pickup != null:
				if result.get("target") == pickup: result["pickup"] = pickup
				else: result = {"point":pickup.position + Vector3(0, 1.5, 0),"normal":Vector3.UP,"target":pickup,"pickup":pickup,"cursor_plane":true}
	return result


func _update_hand_pose(delta: float, selection: Dictionary) -> void:
	hand_pose.set_state(_hand_action)
	var pose: Array[Transform3D] = hand_pose.sample(delta, _hand_motion)
	if pose.is_empty(): return
	var contact: Vector3 = selection["point"]
	var normal: Vector3 = selection["normal"]
	if held != null:
		var top := Vector3.ZERO
		for offset in world_geometry.body_offsets(held):
			if offset.y > top.y: top = offset
		contact = held.position + Vector3(0, top.y, 0)
		normal = Vector3.UP
	var towards_eye := (cam.position - contact).normalized()
	if held == null and selection.get("target") != null:
		if selection.has("scroll") or selection.has("cursor_plane"): normal = towards_eye
		# Original ObtainRequiredHandPosition, 0x5B6808: its normal points
		# along the ray, opposite our BVH's normal. Bias toward viewer and up.
		normal = (normal + towards_eye * 0.25 + Vector3.UP * 0.5).normalized()
	if not _hand_facing_started:
		_hand_facing = normal
		_hand_facing_started = true
	else:
		# Source smooths three normal components independently. Normalized lerp
		# also avoids an unstable axis-angle for almost parallel float32 normals.
		var smoothed := _hand_facing.lerp(normal, 1.0 - exp(-maxf(delta, 0.0) / 0.13))
		_hand_facing = smoothed.normalized() if smoothed.length_squared() > 0.000001 else normal
	var depth := maxf(0.5, -cam.to_local(contact).z)
	var pixels := get_viewport().get_visible_rect().size.y / 900.0 * 76.0
	var units := cam.project_position(Vector2(1, 1), depth).distance_to(cam.project_position(Vector2(1, 2), depth))
	var scale := pixels * units / maxf(hand_rig.bounds.get_longest_axis_size(), 1.0)
	var cursor_ray := -towards_eye
	var orientation: Basis = hand_pose.source_orientation(atan2(cursor_ray.x, cursor_ray.z), _hand_facing, true)
	var geometry: Dictionary = hand_pose.geometry(orientation, pose)
	var anchor: Vector3 = geometry["grip"] if held != null else geometry["anchor"]
	var origin := Vector3.ZERO
	# Move toward the eye along the cursor ray to clear surfaces. Raising only
	# world Y shifts the visible fingertip away from the place a click will hit.
	for iteration in 4:
		origin = contact - anchor * scale
		var source_bounds: AABB = geometry["bounds"]
		var bounds := AABB(source_bounds.position * scale, source_bounds.size * scale)
		var raise := maxf(0.04, bounds.get_longest_axis_size() * 0.025)
		for i in 8:
			var point := origin + bounds.get_endpoint(i)
			raise = maxf(raise, maxf(ground_y(point), sea_y) + 0.04 - point.y)
		raise = maxf(raise, world_geometry.vertical_clearance(AABB(origin + bounds.position, bounds.size)))
		if towards_eye.y > 0.1:
			origin += towards_eye * minf(raise / towards_eye.y, contact.distance_to(cam.position) * 0.75)
		else: origin.y += raise
		var actual_depth := maxf(0.5, -cam.to_local(origin + anchor * scale).z)
		# units are proportional to depth. Iterate the clearance/size solution,
		# then retain the scale used to compute this final placement.
		var corrected := pixels * units * actual_depth / depth / maxf(hand_rig.bounds.get_longest_axis_size(), 1.0)
		if iteration == 3 or absf(corrected - scale) < scale * 0.005: break
		scale = corrected
	var basis := orientation.scaled_local(Vector3.ONE * scale)
	hand_rig.apply_local_pose(pose)
	hand_rig.root.transform = Transform3D(basis, origin)
	for visual in hand_rig.root.get_children():
		if visual is MeshInstance3D: visual.transparency = 0.0 if has_influence(contact) else 0.5


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

func story_set_widescreen(enabled: bool) -> void:
	if story_letterbox == null:
		if not enabled:
			return
		story_letterbox = CanvasLayer.new()
		story_letterbox.layer = hud.layer + 1
		add_child(story_letterbox)
		for anchors in [Vector2(0.0, 0.12), Vector2(0.88, 1.0)]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			story_letterbox.add_child(bar)
			bar.anchor_right = 1.0
			bar.anchor_top = anchors.x
			bar.anchor_bottom = anchors.y
	story_letterbox.visible = enabled
	for control in hud.get_children():
		if control is Control and control != dialogue_caption:
			control.visible = not enabled and not story_preview


func _show_story_problem() -> void:
	# The opening shows only original guidance and subtitles. Surface an actual
	# failure without exposing the unrelated creature-selection prototype panel.
	for control in creature_panel.get_children():
		if control is Control:
			control.visible = control == campaign_status
	creature_panel.show()
	creature_panel.get_parent().show()


func story_fade(cover: bool, color: Color, seconds: float) -> void:
	if story_fade_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = hud.layer + 2
		add_child(layer)
		story_fade_rect = ColorRect.new()
		story_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(story_fade_rect)
		story_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		story_fade_rect.color = Color.TRANSPARENT
	if story_fade_tween != null and story_fade_tween.is_valid():
		story_fade_tween.kill()
	if cover:
		story_fade_rect.color = Color(color, story_fade_rect.color.a)
	var alpha := 1.0 if cover else 0.0
	if seconds <= 0.0 or not is_inside_tree():
		story_fade_rect.color.a = alpha
		return
	story_fade_tween = create_tween()
	story_fade_tween.tween_property(story_fade_rect, "color:a", alpha, seconds)


func story_fade_finished() -> bool:
	return story_fade_tween == null or not story_fade_tween.is_running()


func _build_hud() -> void:
	hud.layer = 3
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
	help_label.add_theme_font_size_override("font_size", 20)
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
	if test_mode or story_preview:
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
	note.text = "Оригинальные модели и анимации.\nПодготовка острова — из оригинального сценария;\nзадания и воспитание ещё переносятся."
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
	if indexed:
		_start_story("LandControl1" if story_preview else Data.PORT_RULES["story"]["first_island_script"])
	_build_advisers()
	_spawn_food()
	if not test_mode and not showcase_mode:
		if not story_preview:
			_restore_preservation(false)
		_setup_original_dialogue()
		_setup_original_music()
		if not story_preview and is_instance_valid(dialogue) and not is_instance_valid(creature):
			dialogue.play_event("creature_choice")
	if story_preview:
		for control in hud.get_children():
			if control is Control and control != dialogue_caption:
				control.hide()


func _setup_original_music() -> void:
	var candidate := OriginalMusic.new()
	if not candidate.configure(bw_dir):
		_say("Не удалось прочитать музыку: " + candidate.error)
		candidate.free()
		return
	original_music = candidate
	add_child(original_music)
	original_music.set_alignment(alignment)
	original_music.set_alignment_enabled(story_alignment_music_enabled)


func story_set_alignment_music(enabled: bool) -> void:
	story_alignment_music_enabled = enabled
	if is_instance_valid(original_music):
		original_music.set_alignment_enabled(enabled)


func story_music_cue(cue: int) -> bool:
	if cue == 0:
		if is_instance_valid(original_music):
			original_music.stop_story_cue()
		return true
	if is_instance_valid(original_music):
		return original_music.start_story_cue(cue)
	return not is_inside_tree() and OriginalMusic.STORY_CUES.has(cue) and FileAccess.file_exists(_p(OriginalMusic.STORY_CUES[cue]))


func story_record_snapshot(values: Array) -> bool:
	if values.size() < 13:
		return false
	var parameters := StoryVm.as_int(values[values.size() - 2])
	if parameters < 0 or parameters > 12 or values.size() != 13 + parameters:
		return false
	var id := StoryVm.as_int(values.back())
	var eye := Vector3(StoryVm.as_float(values[1]), StoryVm.as_float(values[2]), -StoryVm.as_float(values[3]))
	var target := Vector3(StoryVm.as_float(values[4]), StoryVm.as_float(values[5]), -StoryVm.as_float(values[6]))
	if id < 0 or not eye.is_finite() or not target.is_finite():
		return false
	# SNAPSHOT has a counted template-argument list. Preserve all source cells,
	# identifiers and camera data for the original story book, never quest flags.
	story_journal[id] = {"source_cells":values.duplicate(true),"eye":eye,"focus":target,
		"success":clampf(StoryVm.as_float(values[7]), 0.0, 1.0),
		"alignment":clampf(StoryVm.as_float(values[8]), -1.0, 1.0),
		"help_text":StoryVm.as_int(values[9]),
		"script_name":campaign.constant_string(StoryVm.as_int(values[10])),"image":null}
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_capture_story_snapshot.call_deferred(id)
	_log_test("journal", "recorded original snapshot %d" % id)
	return true


func story_update_snapshot(values: Array) -> bool:
	if values.size() < 6: return false
	var count := StoryVm.as_int(values[values.size() - 2])
	var id := StoryVm.as_int(values.back())
	if count < 0 or count >= 12 or values.size() != 6 + count or not story_journal.has(id): return false
	var success := StoryVm.as_float(values[0])
	var moral := StoryVm.as_float(values[1])
	if not is_finite(success) or not is_finite(moral): return false
	var entry: Dictionary = story_journal[id]
	entry["success"] = clampf(success, 0.0, 1.0)
	entry["alignment"] = clampf(moral, -1.0, 1.0)
	entry["help_text"] = StoryVm.as_int(values[2])
	entry["script_name"] = campaign.constant_string(StoryVm.as_int(values[3]))
	entry["update_cells"] = values.duplicate(true)
	_log_test("journal", "updated source snapshot %d success=%.2f" % [id, entry["success"]])
	return true


func _capture_story_snapshot(id: int) -> void:
	await RenderingServer.frame_post_draw
	if story_journal.has(id):
		story_journal[id]["image"] = get_viewport().get_texture().get_image()


func story_attach_music(cue: int, target: Node3D) -> bool:
	if cue != 29:
		return false
	var path := _p("Audio/Music/chant/celt_chant_vox.sad")
	if not FileAccess.file_exists(path):
		return false
	if not is_inside_tree():
		return true
	if target.has_node("StoryAttachedMusic"):
		return true
	var player := StoryAttachedMusic.new()
	player.name = "StoryAttachedMusic"
	player.unit_size = 20.0
	player.max_distance = 140.0
	player.volume_db = -18.0
	if not player.start(path):
		player.free()
		return false
	target.add_child(player)
	return true


func story_position_in_view(point: Vector3) -> bool:
	if is_inside_tree():
		return not cam.is_position_behind(point) and get_viewport().get_visible_rect().has_point(cam.unproject_position(point))
	var direction: Vector3 = (story_camera.focus - story_camera.eye).normalized()
	var toward: Vector3 = (point - story_camera.eye).normalized()
	return direction.dot(toward) >= cos(deg_to_rad(cam.fov * 0.5))


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


func story_play_sfx(sound_id: int, position: Vector3, spatial: bool, bank_type := 5) -> bool:
	if not bank_type in [1, 5]: return false
	var bank := story_game_sfx_bank if bank_type == 1 else story_sfx_bank
	var stream_key := "%d:%d" % [bank_type, sound_id]
	if not story_sfx_streams.has(stream_key):
		var path := "Audio/SFX/Game/InGame.sad" if bank_type == 1 else "Audio/SFX/Script/Scriptsfx.sad"
		if bank.entries.is_empty() and not bank.open(_p(path)):
			return false
		for key in bank.entries:
			if int(bank.entries[key]["id"]) != sound_id:
				continue
			var sample := bank.sample(key)
			if sample.get("format", "") == "pcm_wav":
				var stream := AudioStreamWAV.load_from_buffer(sample["payload"])
				if stream != null:
					story_sfx_streams[stream_key] = stream
			break
	if not story_sfx_streams.has(stream_key):
		return false
	if is_inside_tree():
		var player: Node
		if spatial:
			player = AudioStreamPlayer3D.new()
			player.position = position
		else:
			player = AudioStreamPlayer.new()
		player.stream = story_sfx_streams[stream_key]
		player.finished.connect(player.queue_free)
		add_child(player)
		player.play()
	return true


func story_play_voice(text_enum: int, single_line := true) -> bool:
	if is_instance_valid(dialogue):
		return dialogue.play_text_enum(text_enum, single_line)
	if is_inside_tree():
		return false
	var reader := OriginalDialogue.new()
	var found := reader.configure(bw_dir) and reader.has_text_enum(text_enum)
	reader.free()
	return found


func story_voice_playing(text_enum: int) -> bool:
	return is_instance_valid(dialogue) and dialogue.is_text_enum_playing(text_enum)


func story_clear_voice() -> void:
	if is_instance_valid(dialogue):
		dialogue.stop()


func story_appear_adviser(spirit: int, fly := false) -> bool:
	if not is_inside_tree():
		return true
	var adviser := cam.get_node_or_null("Adviser_" + ("good" if spirit == 1 else "evil")) as Node3D
	if adviser == null:
		return false
	var id := "good" if spirit == 1 else "evil"
	var target: Vector3 = _adviser_targets.get(id, adviser.position)
	if _adviser_tweens.has(id) and _adviser_tweens[id].is_valid():
		_adviser_tweens[id].kill()
	if fly:
		if not adviser.visible:
			adviser.position = target + Vector3(-8.0 if target.x < 0.0 else 8.0, 0.0, 0.0)
		_adviser_tweens[id] = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_adviser_tweens[id].tween_property(adviser, "position", target, 0.6)
	else:
		adviser.position = target
	adviser.show()
	return true


func story_hide_adviser(spirit: int, fly := false) -> bool:
	if not is_inside_tree():
		return true
	var id := "good" if spirit == 1 else "evil"
	var adviser := cam.get_node_or_null("Adviser_" + id) as Node3D
	if adviser == null:
		return false
	if _adviser_tweens.has(id) and _adviser_tweens[id].is_valid():
		_adviser_tweens[id].kill()
	if fly and adviser.visible:
		var destination := adviser.position + Vector3(-8.0 if adviser.position.x < 0.0 else 8.0, 0.0, 0.0)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_adviser_tweens[id] = tween
		tween.tween_property(adviser, "position", destination, 0.6)
		tween.tween_callback(adviser.hide)
	else:
		adviser.hide()
	return true


func story_move_adviser(spirit: int, screen: Vector2, clinging := false) -> bool:
	if not is_inside_tree():
		return true
	var id := "good" if spirit == 1 else "evil"
	_adviser_clinging[id] = clinging
	var adviser := cam.get_node_or_null("Adviser_" + id) as Node3D
	if adviser == null:
		return false
	if not screen.is_finite():
		return story_hide_adviser(spirit)
	var target := cam.to_local(cam.project_position(screen * get_viewport().get_visible_rect().size, 10.0))
	_adviser_targets[id] = target
	if _adviser_tweens.has(id) and _adviser_tweens[id].is_valid():
		_adviser_tweens[id].kill()
	if not adviser.visible:
		adviser.position = Vector3(target.x * 2.0, target.y, target.z)
	adviser.show()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_adviser_tweens[id] = tween
	tween.tween_property(adviser, "position", target, 0.6)
	return true


func story_guide_adviser(spirit: int, point: Vector3, pointing: bool) -> void:
	var id := "good" if spirit == 1 else "evil"
	if pointing:
		story_adviser_objects.erase(id)
	var targets := story_adviser_points if pointing else story_adviser_looks
	if point.is_finite():
		targets[id] = point
	else:
		targets.erase(id)


func story_guide_adviser_object(spirit: int, target: Node3D) -> void:
	story_guide_adviser(spirit, target.global_position if target.is_inside_tree() else target.position, true)
	story_adviser_objects["good" if spirit == 1 else "evil"] = weakref(target)


func _show_adviser_line(speaker: String, text: String) -> void:
	_adviser_speech_started = _adviser_time
	var name := ""
	if speaker == "HELP_TEXT_NARRATOR_GOOD_SPIRIT":
		name = "Добрый советник"
		_speaking_adviser = "good"
	elif speaker == "HELP_TEXT_NARRATOR_EVIL_SPIRIT":
		name = "Злой советник"
		_speaking_adviser = "evil"
	else:
		_speaking_adviser = ""
	var cleaned := text.replace("$m1", "").replace("$m2", "").strip_edges()
	dialogue_caption.text = cleaned if name.is_empty() else "%s: %s" % [name, cleaned]


func _build_advisers() -> void:
	if is_inside_tree():
		_build_adviser_view()
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
		# Advisers belong to the camera interface. Terrain must not clip their
		# bodies when the camera is close to the ground or to the temple.
		for child in visual.get_children():
			if child is MeshInstance3D:
				for surface in child.mesh.get_surface_count():
					var material := child.mesh.surface_get_material(surface) as StandardMaterial3D
					if material != null:
						material.no_depth_test = false
						material.disable_receive_shadows = true
				child.layers = ADVISER_LAYER
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.scale = Vector3.ONE * scale_f
		visual.position.y = -reader.bounds.position.y * scale_f
		anchor.position = Vector3(float(row["side"]) * 5.7, -3.1, -10)
		_adviser_targets[id] = anchor.position
		cam.add_child(anchor)
		anchor.visible = not story_preview
		adviser_nodes.append(anchor)
		var animation := MorphReader.new()
		if animation.load_adviser(_p(row["file"])):
			adviser_animations.append({"id":id,"rig":reader,"animation":animation,"pose":preload("res://scripts/story_adviser_pose.gd").new()})
		else:
			_say("Анимация советника не прочитана: " + animation.error)
	_sync_adviser_view()


func _build_adviser_view() -> void:
	cam.cull_mask &= ~ADVISER_LAYER
	_adviser_viewport = SubViewport.new()
	_adviser_viewport.transparent_bg = true
	_adviser_viewport.world_3d = get_viewport().find_world_3d()
	_adviser_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_adviser_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_adviser_viewport)
	_adviser_view_camera = Camera3D.new()
	_adviser_view_camera.cull_mask = ADVISER_LAYER
	_adviser_view_camera.near = 0.05
	_adviser_view_camera.far = 100.0
	var adviser_environment := Environment.new()
	adviser_environment.background_mode = Environment.BG_CLEAR_COLOR
	adviser_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	adviser_environment.ambient_light_color = Color.WHITE
	adviser_environment.ambient_light_energy = 0.6
	_adviser_view_camera.environment = adviser_environment
	_adviser_viewport.add_child(_adviser_view_camera)
	_adviser_view_camera.current = true
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = _adviser_viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _sync_adviser_view() -> void:
	if _adviser_viewport == null:
		return
	_adviser_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	_adviser_view_camera.global_transform = cam.global_transform
	_adviser_view_camera.fov = cam.fov


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


func _update_story_input_hint(delta: float) -> void:
	if not story_preview or story_vm == null:
		return
	help_label.visible = story_camera.owner_task == 0 and not story_inside_temple()
	var current := ""
	var instructions := ""
	for task in story_vm.tasks.values():
		var script: String = task["script"]
		if script not in ["TeachRotate", "TeachPitch", "TeachZoom"]:
			continue
		current = script
		var event := 25 if script == "TeachRotate" else (28 if script == "TeachPitch" else 29)
		var needed := 60.0 if event == 25 else (25.0 if event == 28 else 15.0)
		# Required* is an absolute HelpProfile count written by the original CHL.
		# Display that same counter; the HUD never advances the objective itself.
		var required := StoryVm.as_float(task["locals"][3])
		var completed := clampf(story_camera_input.total(event) - (required - needed), 0.0, needed + 1.0) if required > 0.0 else 0.0
		instructions = "Зажмите ПКМ и двигайте мышь влево / вправо" if event == 25 else ("Зажмите ПКМ и двигайте мышь вверх / вниз" if event == 28 else "Крутите колесо мыши — приближение / отдаление")
		instructions += " · %d%%" % int(completed / (needed + 1.0) * 100.0)
		break
	if not _tutorial_last.is_empty() and current != _tutorial_last:
		for task in story_vm.finished.values():
			if task["script"] == _tutorial_last:
				_tutorial_completed_hint = "Поворот освоен ✓" if _tutorial_last == "TeachRotate" else ("Наклон освоен ✓" if _tutorial_last == "TeachPitch" else "Масштаб освоен ✓")
				_tutorial_hint_time = 3.0
				break
	_tutorial_last = current
	_tutorial_hint_time = maxf(0.0, _tutorial_hint_time - delta)
	if story_camera.owner_task != 0 or story_inside_temple():
		help_label.text = ""
	elif not instructions.is_empty():
		help_label.text = instructions
	elif _tutorial_hint_time > 0.0:
		help_label.text = _tutorial_completed_hint
	elif story_citadel_interface and story_citadel != null and story_citadel.progress >= 1.0:
		help_label.text = "Дважды нажмите ЛКМ на дверь храма, чтобы войти · ПКМ: поворот · колесо: масштаб"
	else:
		help_label.text = "Тяните землю с зажатой ЛКМ · ПКМ: поворот и наклон · колесо: масштаб"


func _save_preservation(announce := true) -> bool:
	if test_mode or showcase_mode or story_preview or not is_instance_valid(creature):
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
	if test_mode or story_preview:
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
	var setup_ran := story_state == "running" and story_vm.finished.size() > 0 and influence_sources.size() == 2 and story_highlights.size() == 11 and not virtual_influence
	melty_check("story-setup", setup_ran, "%s; %d influences, %d highlights" % [story_state, influence_sources.size(), story_highlights.size()])
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


# ---------------------------------------------------------------- original story

# Runs the first island's own setup script from the player's CHL. Any call that
# is not ported yet stops the story cleanly and is reported, never faked.
func _start_story(script_name: String = Data.PORT_RULES["story"]["first_island_script"]) -> void:
	story_bridge = StoryNatives.new()
	story_bridge.configure(self)
	story_bridge.camera_editor = FileAccess.get_file_as_bytes(_p("Data/camera.edt"))
	story_bridge.camera = story_camera
	story_bridge.game_time = story_time
	story_bridge.villager_animation_path = _p(Data.PORT_MODULES["villager_animations"]["source"])
	story_bridge.welcome_dance_path = _p("Scripts/Dance/NewDanceAroundPerson")
	story_bridge.register_landmarks(story_landmarks)
	for mobile in story_mobile_statics:
		story_bridge.register_object(mobile, 8)
	for i in towns.size():
		var anchor := Node3D.new()
		anchor.name = "StoryTown%d" % i
		anchor.position = towns[i]["pos"]
		anchor.set_meta("town_index", i)
		add_child(anchor)
		town_nodes.append(anchor)
		story_bridge.register_object(anchor, int(Data.PORT_RULES["story"]["town_object_type"]))
	story_vm = StoryVm.new()
	if story_preview:
		story_vm.isolate_unbound_tasks = true
		story_vm.strict_scripts = PackedStringArray(["LandControl1", "LandControlAll", "SetupLand1", "FollowUs", "LostTheMother", "WeAreWayAhead", "Drag", "Rotating", "TeachRotate", "TeachPitch", "Zoom", "TeachZoom", "GiveFood", "CitadelGuideCinema", "CheckCitadel", "PreventCitadelCompletion", "TunnelOfUltimateDoom"])
	if story_vm.configure(campaign, story_bridge.invoke) and story_vm.start(script_name) > 0:
		story_state = "running"
	else:
		story_state = "could not start"
	_log_test("story", story_state)


func _tick_story(delta: float) -> void:
	if story_vm == null or story_state != "running":
		return
	story_clock += delta
	var step := 1.0 / float(Data.STORY_VM["core"]["tick_rate"])
	var budget := 4
	while story_clock >= step and budget > 0:
		story_clock -= step
		budget -= 1
		if not story_vm.tick():
			story_camera.release()
			story_time.release_speed()
			story_bridge.dialogue_owner = 0
			story_bridge.widescreen_owner = 0
			story_set_widescreen(false)
			if story_fade_rect != null:
				story_fade(false, Color.BLACK, 0.0)
			story_set_alignment_music(true)
			story_music_cue(0)
			story_interface_level = 0
			story_hand_demo.playing = false
			if story_fire_trail != null:
				story_fire_trail.free()
				story_fire_trail = null
			var native: int = story_vm.error.get("detail", {}).get("native_id", -1)
			story_state = "stopped at original function %d" % native if native >= 0 else "stopped: " + str(story_vm.error.get("kind", "?"))
			campaign_status.text = "Сюжет первого острова: остановлен на ещё не перенесённой команде %d" % native
			_show_story_problem()
			_log_test("story", story_state)
			return
		if story_camera.owner_task != 0 and not story_vm.tasks.has(story_camera.owner_task):
			story_camera.release()
		for id in story_vm.suspended:
			if _reported_suspended_tasks.has(id): continue
			_reported_suspended_tasks[id] = true
			_log_test("quest_suspended", str(story_vm.suspended[id]))
			# Release only resources held by that quest, never another cutscene.
			if story_camera.owner_task == id: story_camera.release()
			if story_time.speed_owner == id: story_time.release_speed()
			if story_bridge.dialogue_owner == id: story_bridge.dialogue_owner = 0
			if story_bridge.widescreen_owner == id:
				story_bridge.widescreen_owner = 0
				story_set_widescreen(false)
		if story_time.speed_owner != 0 and not story_vm.tasks.has(story_time.speed_owner):
			story_time.release_speed()
		if story_bridge.dialogue_owner != 0 and not story_vm.tasks.has(story_bridge.dialogue_owner):
			story_bridge.dialogue_owner = 0
		if story_intro_movie != null and story_intro_movie.active:
			return
		if story_bridge.widescreen_owner != 0 and not story_vm.tasks.has(story_bridge.widescreen_owner):
			story_bridge.widescreen_owner = 0
			story_set_widescreen(false)
	var setup_done := story_vm.finished.size() > 0
	campaign_status.text = "Сюжет первого острова: подготовка выполнена" if setup_done else "Сюжет первого острова: подготовка…"


func story_play_hand_demo(name_offset: int) -> bool:
	var filename := campaign.constant_string(name_offset).to_lower()
	if not filename in ["drag", "rotate", "pitch", "zoom", "zoomreminder", "givewood"]:
		return false
	_story_demo_name = filename
	if filename == "givewood":
		_story_wood_hand = WoodHand.new()
		if not _story_wood_hand.configure(_p("Scripts/info.dat")):
			return false
		_story_demo_wood_delivered = 0
	return story_hand_demo.start(FileAccess.get_file_as_bytes(_p("Data/HandDemo").path_join(filename + ".hnd")))


func story_advance_hand_demo(delta: float) -> void:
	if not story_hand_demo.playing:
		return
	var interval_start := story_hand_demo.elapsed
	story_hand_demo.advance(delta)
	var pose := story_hand_demo.pose()
	story_camera.eye = pose["eye"]
	story_camera.focus = pose["focus"]
	if _story_demo_name == "givewood" and is_inside_tree():
		for action in story_hand_demo.take_actions():
			_story_wood_hand.advance(maxf(float(action["time"]) - interval_start, 0.0))
			interval_start = float(action["time"])
			if action["event"] == "action_pressed":
				if _story_wood_hand.amount == 0:
					var binding: Dictionary = action["binding"]
					if story_construction == null or binding.get("type", 0) != 16 or binding.get("subtype", -1) != 5:
						continue
					var source_point: Vector3 = binding["position"]
					if not _story_wood_hand.begin(func(requested: int) -> int: return story_construction.take_storage_wood(source_point, requested)):
						continue
					var mesh := g3d.mesh("MSH_O_WOOD_INHAND")
					if mesh != null:
						_story_demo_wood = MeshInstance3D.new()
						_story_demo_wood.mesh = mesh
						_story_demo_wood.scale = Vector3.ONE * (6.0 / maxf(mesh.get_aabb().get_longest_axis_size(), 0.001))
						add_child(_story_demo_wood)
				else:
					var carried: int = _story_wood_hand.take_all()
					_story_demo_wood_delivered += story_construction.add_wood(carried)
					_log_test("wood_demo", "delivered %d actual wood to the building site" % carried)
					if is_instance_valid(_story_demo_wood):
						var dropped := _story_demo_wood
						var tween := create_tween()
						tween.tween_property(dropped, "position:y", ground_y(dropped.position) + 1.0, 0.4)
						tween.tween_callback(dropped.queue_free)
			else:
				# Releasing stops collection; it does not release the held resource.
				_story_wood_hand.release()
		_story_wood_hand.advance(maxf(story_hand_demo.elapsed - interval_start, 0.0))
		_story_demo_holding_wood = _story_wood_hand.amount > 0
		if _story_demo_holding_wood and is_instance_valid(_story_demo_wood):
			var hand: Vector3 = pose["hand"]
			_story_demo_wood.position = hand if hand.is_finite() else ground_point(pose["cursor"] * get_viewport().get_visible_rect().size) + Vector3.UP * 8.0


func story_intro_effect(command: int) -> bool:
	match command:
		0:
			if story_fire_trail != null:
				return false
			var textures := StoneSparkles.load_frames(_p("Data/Textures"), "misc0", 48, 3)
			if textures.size() != 3:
				return false
			story_fire_trail = StoryFireTrail.new()
			story_fire_trail.configure(textures)
			story_fire_trail.hide()
			add_child(story_fire_trail)
		1:
			if story_fire_trail == null:
				return false
			story_fire_trail.show()
		2:
			if story_fire_trail == null:
				return false
			story_fire_trail.free()
			story_fire_trail = null
		4:
			if story_rescue_hand != null:
				return false
			var hand := StoryRescueHand.new()
			if not hand.configure(_p("Data/MISC")):
				hand.free()
				return false
			story_rescue_hand = hand
			add_child(hand)
		5:
			if story_rescue_hand == null:
				return false
			story_rescue_hand.trigger()
		_:
			return false
	return true


func story_play_intro_movie() -> bool:
	var path := _p("Data/INTRO.bik")
	if not is_inside_tree():
		return FileAccess.file_exists(path)
	if story_intro_movie != null:
		return false
	var movie := StoryIntroMovie.new()
	add_child(movie)
	movie.playback_finished.connect(_story_intro_movie_finished)
	if not movie.start(path):
		movie.queue_free()
		return false
	story_intro_movie = movie
	_log_test("intro_movie", "started")
	return true


func _story_intro_movie_finished() -> void:
	# FollowUs covers the scene before SET_AVI_SEQUENCE and deliberately has no
	# later SET_FADE_IN. Movie cleanup must uncover the island before its next
	# scripted camera shot; hiding only the movie leaves a permanent black screen.
	if story_fade_rect != null:
		story_fade(false, Color.BLACK, 0.0)
	_log_test("intro_movie", "returned to island")


func story_town_villagers(town: int) -> Array[Thing]:
	var villagers: Array[Thing] = []
	for thing in things:
		if is_instance_valid(thing) and thing.kind == "villager" and thing.town == town and not thing.has_meta("story_villager_subtype"):
			villagers.append(thing)
	return villagers


func story_delete_object(object: Node3D) -> bool:
	var influence_index := -1
	for i in influence_sources.size():
		if influence_sources[i]["node"] == object: influence_index = i
	if influence_index >= 0:
		influence_sources.remove_at(influence_index)
	elif story_effects.has(object):
		story_effects.erase(object)
	elif object is Thing:
		if is_instance_valid(object.story_flock):
			object.story_flock.detach(object)
		things.erase(object)
		story_mobile_statics.erase(object)
		if held == object:
			held = null
	elif story_sharks.has(object):
		story_sharks.erase(object)
	elif story_highlights.has(object):
		story_highlights.erase(object)
	else:
		return false
	object.free()
	return true


func story_build_citadel(request: Vector3, amount: float) -> Node3D:
	for entry in island.all("CREATE_PLANNED_CITADEL"):
		var args: PackedStringArray = entry["args"]
		if args.size() < 6 or args[3] != "PLAYER_ONE":
			continue
		var position := to_world(IslandScript.pos(args[1]))
		if Vector2(request.x - position.x, request.z - position.z).length() > 0.02:
			continue
		if story_citadel == null:
			var site := StoryCitadelSite.new()
			if not site.configure(_p("Data/Citadel/OutsideMeshes")):
				site.free()
				return null
			site.position = position
			# Citadel script angles are radians * 1000, like abode angles.
			# The original LH matrix becomes a positive Y rotation after Z reflection.
			site.rotation.y = float(args[4]) / 1000.0
			site.scale = Vector3.ONE * float(args[5]) / 1000.0
			add_child(site)
			story_citadel = site
			var construction := CitadelConstruction.new()
			if not construction.configure(self, site, int(args[0])):
				_say("Не удалось загрузить стройку храма: " + construction.error)
				site.free()
				story_citadel = null
				return null
			story_construction = construction
			world_geometry.register_node(site._finished, site, null, func(): return site._base_y + site.mesh_height * site.progress)
			world_geometry.register_node(site._scaffold, site, null, func(): return site._base_y + site.mesh_height * (1.0 - clampf((site.progress - 0.8) / 0.2, 0.0, 1.0)))
			world_physics.register_node(site._finished, site, null, func(): return site._base_y + site.mesh_height * site.progress)
		# BUILD_BUILDING sets a town desire (amount * 5), never build progress.
		# Villagers must deliver and consume wood to complete the building.
		story_construction.set_forced_desire(amount * 5.0)
		return story_citadel
	return null


func story_inside_temple() -> bool:
	return story_temple != null and story_temple.active


func story_enter_temple() -> bool:
	if story_temple == null:
		var interior := StoryTempleInterior.new()
		add_child(interior)
		if not interior.start(_p("Data/Citadel/engine")):
			_say("Не удалось прочитать интерьер храма: " + interior.error)
			interior.queue_free()
			return false
		story_temple = interior
	else:
		story_temple.active = true
		story_temple.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		story_temple._camera_age = 0.0
		story_temple.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_log_test("temple", "entered original main room")
	return true


func story_set_virtual_influence(enabled: bool) -> void:
	virtual_influence = enabled


func story_set_camera_zone(name_offset: int) -> bool:
	var filename := campaign.constant_string(name_offset)
	if filename.is_empty() or filename.get_file() != filename or filename.contains(":") or filename.get_extension().to_lower() != "exc":
		return false
	var folder := _p("Data/Zones")
	var path := folder.path_join(filename)
	if FileAccess.file_exists(path):
		return story_camera.load_zone(FileAccess.get_file_as_bytes(path))
	# CHL and installed filenames can differ in letter case.
	for installed_name in DirAccess.get_files_at(folder):
		if installed_name.nocasecmp_to(filename) == 0:
			return story_camera.load_zone(FileAccess.get_file_as_bytes(folder.path_join(installed_name)))
	return false


func story_add_influence(position: Vector3, radius: float, anti: bool) -> Node3D:
	var handle := Node3D.new()
	handle.name = "StoryInfluence%d" % influence_sources.size()
	handle.position = Vector3(position.x, ground_y(position), position.z)
	add_child(handle)
	influence_sources.append({"node":handle, "radius":radius, "anti":anti})
	_log_test("influence", "%s r=%.0f at %.0f,%.0f" % ["anti" if anti else "add", radius, position.x, -position.z])
	return handle


func story_set_desire_boost(town: int, desire: int, boost: float) -> void:
	var boosts: Dictionary = towns[town].get("desire_boosts", {})
	boosts[desire] = boost
	towns[town]["desire_boosts"] = boosts


func story_belief(town: int) -> float:
	return 100.0 if towns[town]["mine"] else float(towns[town]["belief"])


func story_set_belief(town: int, belief: float) -> void:
	if towns[town]["mine"]:
		return
	towns[town]["belief"] = clampf(belief, 0.0, float(cfg_belief["convert_at"]))


func story_create_shark(position: Vector3) -> Node3D:
	if story_shark_animations == null:
		var reader := AnmReader.new()
		if not reader.load_file(_p(Data.PORT_MODULES["villager_animations"]["source"]), [], PackedInt32Array([129])):
			return null
		story_shark_animations = reader
	var shark := StoryShark.new()
	if not shark.configure(g3d, story_shark_animations):
		shark.free()
		return null
	shark.position = position
	add_child(shark)
	story_sharks.append(shark)
	return shark


func story_create_singing_stone(subtype: int, position: Vector3) -> Thing:
	if subtype != 5 and subtype != 6:
		return null
	var record := host_info.record(subtype)
	if record.is_empty() or int(record["category"]) != subtype:
		return null
	var kind := "rock" if subtype == 5 else "scenery"
	position.y = ground_y(position)
	if subtype == 6:
		# This host mesh is an empty L3D. The base still has a script position.
		var base := Thing.new()
		base.kind = kind
		base.position = position
		add_child(base)
		return base
	var stone := _place_mesh(record["mesh_id"], position, 0.0, 1.0, kind)
	if stone and subtype == 5:
		things.append(stone)
	return stone


func story_spawn_stone_sparkles(stone: Thing, seconds: float) -> Node3D:
	if story_stone_sparkle_frames.is_empty():
		story_stone_sparkle_frames = StoneSparkles.load_frames(_p("Data/Textures"))
		if story_stone_sparkle_frames.is_empty():
			return null
	var sparkles := StoneSparkles.new()
	sparkles.position = to_local(stone.global_position) if stone.is_inside_tree() else stone.position
	sparkles.start(story_stone_sparkle_frames, seconds)
	add_child(sparkles)
	story_effects.append(sparkles)
	return sparkles


func story_landmark_info_bits(landmark: OriginalLandmark) -> int:
	return story_gate_plinth.info_bits() if story_gate_plinth != null and landmark == story_gate_plinth.landmark else 0


func story_gate_contact(from: Vector3, to: Vector3, hitter: Thing) -> Dictionary:
	_update_landmark_physics()
	var contact := world_physics.sweep(from, to, hitter)
	if not contact.is_empty() and story_bridge != null:
		story_bridge.record_contact(contact["target"], hitter)
	return contact


func _update_landmark_physics() -> void:
	for entry in _landmark_physics:
		var landmark: OriginalLandmark = entry["target"]
		var opening := landmark.gate_open
		var mesh_id := 220 if opening else 219
		if entry["type"] == "Gate Stone Plinth":
			mesh_id = 336 if opening else 336 + mini(story_gate_plinth.installed_meshes.size(), 2)
		entry["visual"].mesh = g3d.mesh_index(mesh_id)


func story_highlight_object(target: Thing, seconds: float) -> Node3D:
	var effect := preload("res://scripts/story_object_highlight.gd").new()
	if not effect.configure(target, seconds):
		effect.free()
		return null
	target.add_child(effect)
	story_effects.append(effect)
	return effect


func story_create_mobile_static(subtype: int, pos: Vector3, angle: float, size: float) -> Thing:
	var record := host_info.record(subtype)
	if record.is_empty() or not pos.is_finite() or not is_finite(angle) or not is_finite(size) or size <= 0.0: return null
	var row: Dictionary = Data.STATICS.get(str(record["category"]), {})
	if row.is_empty(): return null
	var actor := _place_mesh(int(record["mesh_id"]), pos, angle, size, row["kind"])
	if actor != null:
		actor.set_meta("story_mobile_subtype", subtype)
		story_mobile_statics.append(actor)
		if row["pickable"]: things.append(actor)
	return actor


func story_create_highlight(type: int, position: Vector3, challenge: int) -> Node3D:
	var highlight := StoryHighlight.new()
	if not highlight.configure(g3d, host_info.highlight(type), type, challenge, ground_y(position)):
		highlight.free()
		return null
	highlight.name = "StoryHighlight%d" % story_highlights.size()
	highlight.position = Vector3(position.x, ground_y(position), position.z)
	highlight.visible = story_highlights_visible
	add_child(highlight)
	story_highlights.append(highlight)
	return highlight


func story_set_highlights_visible(enabled: bool) -> void:
	story_highlights_visible = enabled
	for highlight in story_highlights:
		if is_instance_valid(highlight): highlight.visible = enabled


# The god may only touch the world inside his influence, as in the original.
func story_influence_strength(p: Vector3, anti := false) -> float:
	var strength := 0.0
	if not anti:
		if virtual_influence or story_vm == null:
			return 1.0
		var town_radius := float(Data.PORT_RULES["story"]["town_influence_radius"])
		for town in towns:
			if town["mine"] and Vector2(p.x - town["pos"].x, p.z - town["pos"].z).length() < town_radius:
				strength = 1.0
	for source in influence_sources:
		if source["anti"] != anti:
			continue
		var node: Node3D = source["node"]
		if is_instance_valid(node):
			strength = maxf(strength, InfluenceMath.strength_at(node.position, p, float(source["radius"]), host_info.influence_settings))
	return strength


func has_influence(p: Vector3) -> bool:
	for source in influence_sources:
		var node: Node3D = source["node"]
		if source["anti"] and Vector2(p.x - node.position.x, p.z - node.position.z).length() < float(source["radius"]):
			return false
	if virtual_influence or story_vm == null:
		return true
	var town_radius := float(Data.PORT_RULES["story"]["town_influence_radius"])
	for town in towns:
		if town["mine"] and Vector2(p.x - town["pos"].x, p.z - town["pos"].z).length() < town_radius:
			return true
	var settings: Dictionary = host_info.influence_settings
	for source in influence_sources:
		var node: Node3D = source["node"]
		if source["anti"]:
			continue
		if settings.is_empty():
			if Vector2(p.x - node.position.x, p.z - node.position.z).length() < float(source["radius"]):
				return true
		elif InfluenceMath.strength_at(node.position, p, float(source["radius"]), settings) > 0.0:
			return true
	return false


# Close views of walking villagers and the advisers, so a test recording shows their animation.
func _test_closeups() -> void:
	var shown := 0
	var moved := false
	# Keep the creature out of the villager close-ups (it follows the camera otherwise).
	if is_instance_valid(creature):
		creature.following = false
		creature._target = creature.position
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
	if story_preview:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ambience.stop()
	ambience.stream = null
	sea_player.stop()
	sea_player.stream = null
	if story_bridge != null:
		story_bridge.clear_created()
	if _story_speed_applied != 1.0:
		Engine.time_scale = _time_scale_before_story
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
