# One object on the island the Hand can interact with: a tree, a rock or a villager.
class_name Thing
extends Node3D

enum State { IDLE, HELD, FLYING, FLEE, DEAD }

var kind := "tree"
var town := -1
var home := Vector3.ZERO
var state := State.IDLE
var velocity := Vector3.ZERO
var launch_from := Vector3.ZERO
var thrown := false
var story_pickup_allowed := true
var story_move_allowed := true
var story_hold_position := false
var story_health := 1.0
var story_indestructible := false
var story_drowning := false
var story_resources := Vector2i.ZERO
var _resource_attachments: Dictionary = {}
var story_smooth_heading := true
var _render_heading := NAN
var world: Node = null # main.gd
var story_flock: StoryFlock
var flock_catching_up := false
var story_age := 0
var story_speed_per_turn := -1.0
var story_high_detail := false
var _ordinary_rig: L3dRig

var _target := Vector3.ZERO
var _script_move_active := false
var _script_waypoints := PackedVector3Array()
var _script_move_target := Vector3.ZERO
var _script_move_radius := 0.0
var _script_wander_radius := -1.0
var _script_wander_centre := Vector3.ZERO
var _script_wander_wait := Vector2(2.0, 7.0)
var _wait := 0.0
var _flee_left := 0.0
var _dead_time := 0.0
var impact_velocity := Vector3.ZERO
var _landed_notified := false
var _terrain_mesh_points: Dictionary = {}
var rig: L3dRig
var animation_profile := "male"
var animation_name := ""
var animation_walk := false
var _animation_age := 0.0
var _animation_accumulator := 0.0
var _animation_previous_state := -1
var _animation_phase := 0
var _pose: Array[Transform3D] = []
var _transition_from: Array[Transform3D] = []
var _transition_age := 1.0
var _script_animations: AnmReader
var _prepared_script_clip := ""
var _prepared_script_repeats := 0
var _script_clip := ""
var _script_clip_duration := 0.0
var _script_clip_end := 0.0
var _script_clip_age := 0.0
var _script_move_clip := ""
var _script_move_clip_age := 0.0


func _ready() -> void:
	_target = position
	_wait = randf() * 3.0
	_animation_phase = randi() % 8
	if rig:
		_animate(0.0, true)


func _physics_process(delta: float) -> void:
	animation_walk = false
	match state:
		State.FLYING:
			_fly(delta)
		State.IDLE, State.FLEE:
			if kind == "villager" and not (state == State.IDLE and is_script_animation_playing()):
				_walk(delta)
		State.DEAD:
			_dead_time += delta
			if _dead_time > 12.0:
				queue_free()


func _process(delta: float) -> void:
	if rig:
		if story_high_detail and has_meta("story_villager_subtype"):
			if not story_smooth_heading or not is_finite(_render_heading):
				_render_heading = rotation.y
			else:
				_render_heading = rotate_toward(_render_heading, rotation.y, delta * 4.0)
			rig.root.rotation.y = angle_difference(rotation.y, _render_heading)
		elif is_finite(_render_heading):
			rig.root.rotation.y = 0.0
			_render_heading = NAN
		if is_script_animation_playing():
			_script_clip_age += delta
		if not _script_move_clip.is_empty():
			_script_move_clip_age += delta
		_animate(delta)
		if is_script_animation_playing() and _script_clip_age >= _script_clip_end:
			_script_clip = ""
		_update_resource_visuals()


func add_story_resource(resource: int, amount: int) -> bool:
	if kind != "villager" or not resource in [0, 1] or amount < 0 or amount > 65535:
		return false
	# The original stores carried food and wood in unsigned 16-bit fields.
	story_resources[resource] = (story_resources[resource] + amount) & 65535
	_update_resource_visuals()
	return true


func _update_resource_visuals() -> void:
	if rig == null or not is_instance_valid(world) or world.g3d == null:
		return
	for resource in 2:
		var attachment: BoneAttachment3D = _resource_attachments.get(resource)
		if is_instance_valid(attachment):
			attachment.visible = story_resources[resource] > 0 and state != State.DEAD
			continue
		if story_resources[resource] == 0:
			continue
		var mesh: ArrayMesh = world.g3d.mesh("MSH_O_BAG" if resource == 0 else "MSH_O_WOOD_INHAND")
		if mesh == null:
			continue
		var data = preload("res://scripts/data.gd")
		var joints: Dictionary = data.VILLAGER_SKELETONS["human"]
		var bone: int = joints["right_hand"] if resource == 0 else joints["left_hand"]
		if bone >= rig.bone_count:
			continue
		attachment = BoneAttachment3D.new()
		attachment.name = "CarriedFood" if resource == 0 else "CarriedWood"
		attachment.bone_idx = bone
		rig.skeleton.add_child(attachment)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		# Original props follow animated hand bones. Attachment offsets and size
		# are reconstructed until the original draw transforms are recovered.
		var bounds := mesh.get_aabb()
		var size := 0.7 / maxf(bounds.get_longest_axis_size(), 0.001)
		visual.scale = Vector3.ONE * size
		visual.position = -bounds.get_center() * size + Vector3(0, -0.2, 0)
		attachment.add_child(visual)
		_resource_attachments[resource] = attachment


func prepare_script_animation(reader: AnmReader, animation: int, repeats: int) -> bool:
	var clip := _matching_script_clip(reader, animation)
	if clip.is_empty():
		return false
	_script_animations = reader
	_prepared_script_clip = clip
	_prepared_script_repeats = repeats
	return true


func play_script_animation() -> bool:
	if _prepared_script_clip.is_empty() or state != State.IDLE:
		return false
	_script_wander_radius = -1.0
	_script_clip = _prepared_script_clip
	_script_clip_duration = float(_script_animations.clips[_script_clip]["duration"])
	_script_clip_end = INF if _prepared_script_repeats == -1 else _script_clip_duration * _prepared_script_repeats
	_script_clip_age = 0.0
	return true


func is_script_animation_playing() -> bool:
	return not _script_clip.is_empty()


func override_script_move_animation(reader: AnmReader, animation: int) -> bool:
	var clip := _matching_script_clip(reader, animation)
	if clip.is_empty():
		return false
	_script_animations = reader
	if clip != _script_move_clip:
		_script_move_clip = clip
		_script_move_clip_age = 0.0
	return true


func _matching_script_clip(reader: AnmReader, animation: int) -> String:
	var clip: String = reader.names_by_index.get(animation, "")
	if rig == null or clip.is_empty() or reader.clips[clip]["bones"] != rig.bone_count:
		return ""
	return clip


func _animate(delta: float, force := false) -> void:
	var data = preload("res://scripts/data.gd")
	var cfg: Dictionary = data.PORT_RULES["villager_animation"]
	var profile: Dictionary = data.VILLAGER_ANIMATIONS[animation_profile]
	_animation_age += delta
	_transition_age += delta
	_animation_accumulator += delta
	var hz: float = cfg["update_hz"]
	if not story_high_detail and world.cam.position.distance_to(position) > float(cfg["near_distance"]):
		hz = float(cfg["far_update_hz"])
	if not force and _animation_accumulator < 1.0 / hz and _animation_previous_state == state:
		return
	_animation_accumulator = 0.0
	var action := "walk" if animation_walk else "idle"
	match state:
		State.FLEE: action = "flee"
		State.HELD: action = "held"
		State.FLYING: action = "flying"
		State.DEAD: action = "dead"
	var scripted := state == State.IDLE and is_script_animation_playing()
	var scripted_move := state == State.IDLE and _script_move_active and not _script_move_clip.is_empty()
	var clip: String = _script_clip if scripted else profile[action]
	if scripted_move and not scripted:
		clip = _script_move_clip
	if animation_name != clip:
		_transition_from = _pose.duplicate()
		_transition_age = 0.0
		animation_name = clip
	if _animation_previous_state != state:
		_animation_age = 0.0
		_animation_previous_state = state
	var seconds: float = _animation_age if state in [State.FLYING,State.DEAD] else world.animation_clock
	var phase := _animation_phase if state not in [State.FLYING,State.DEAD] else 0
	var next: Array[Transform3D]
	if scripted:
		var clip_time := fposmod(_script_clip_age, _script_clip_duration) if _script_clip_age < _script_clip_end else _script_clip_duration
		next = _script_animations.sample(clip, clip_time, 0, false, true)
	elif scripted_move:
		next = _script_animations.sample(clip, _script_move_clip_age)
	else:
		next = world.villager_anims.sample(clip, seconds, phase, state != State.DEAD)
	if next.size() != rig.bone_count:
		return
	var blend := clampf(_transition_age / float(cfg["blend_seconds"]), 0.0, 1.0)
	_pose = []
	for bi in next.size():
		_pose.append(_transition_from[bi].interpolate_with(next[bi], blend) if blend < 1.0 and _transition_from.size() == next.size() else next[bi])
	rig.apply_local_pose(_pose)


func _fly(delta: float) -> void:
	var data = preload("res://scripts/data.gd")
	var cfg: Dictionary = data.PORT_RULES["physics"]
	var profile: Dictionary = data.PHYSICS_PROFILES[kind]
	velocity.y -= float(world.cfg_hand["gravity"]) * delta
	velocity = velocity.limit_length(float(cfg["max_speed"]))
	var steps := clampi(int(ceil(velocity.length() * delta / float(cfg["sweep_spacing"]))), 1, int(cfg["max_sweep_steps"]))
	var dt := delta / float(steps)
	for step in steps:
		var previous := position
		position += velocity * dt
		var resting_on_object := false
		if world.has_method("story_gate_contact"):
			var contact: Dictionary = world.story_gate_contact(previous, position, self)
			if not contact.is_empty():
				var normal: Vector3 = contact["normal"]
				position = contact.get("root", contact["point"]) + normal * 0.03
				impact_velocity = velocity
				velocity = velocity.bounce(normal) * float(profile["restitution"])
				if normal.y > 0.6 and velocity.length() < float(cfg["settle_speed"]):
					velocity = Vector3.ZERO
					resting_on_object = true
		# A wall/platform contact can also overlap the ground during the same
		# step. Resolve that support before accepting the final resting pose.
		var g: float = world.ground_y(position)
		var support_y := _terrain_support_y()
		if position.y <= world.sea_y and g <= world.sea_y + 0.05:
			position.y = world.sea_y
			velocity = Vector3.ZERO
			state = State.IDLE
			if kind == "villager":
				story_drowning = true
				die()
				world._say("Житель утонул.")
			elif kind == "food":
				queue_free()
			return
		if kind == "rock" and thrown:
			for other in world.things:
				if not is_instance_valid(other) or other == self or other.kind != "villager" or other.state in [State.DEAD, State.HELD]:
					continue
				var center: Vector3 = other.position + Vector3(0, 1.0, 0)
				if position.distance_to(center) < float(profile["radius"]) + 0.7 and velocity.length() > float(cfg["settle_speed"]):
					other.die()
					world._act("rock_crush", world._nearest_town(position, 90.0), "Камень сбил жителя.")
		if position.y <= support_y:
			position.y = support_y
			impact_velocity = velocity
			if not _landed_notified:
				_landed_notified = true
				world.on_landed(self)
			if not is_instance_valid(self) or state == State.DEAD or is_queued_for_deletion():
				return
			# Landing actions can alter the transform (a dropped tree is laid
			# down). Re-evaluate support for the resulting visible pose as well.
			position.y = maxf(position.y, _terrain_support_y())
			var n: Vector3 = world.ground_normal(position)
			var incoming := velocity.dot(n)
			if incoming < 0.0:
				velocity -= (1.0 + float(profile["restitution"])) * incoming * n
			var normal_v := n * velocity.dot(n)
			velocity = normal_v + (velocity - normal_v) * float(profile["friction"])
			if bool(profile["roll"]):
				rotation.z += position.distance_to(previous) / maxf(float(profile["radius"]), 0.1)
				# Rotation changes every support corner. Correct the new pose even
				# when this is the last flight step before entering IDLE.
				position.y = maxf(position.y, _terrain_support_y())
			if velocity.length() < float(cfg["settle_speed"]) or not bool(profile["roll"]):
				velocity = Vector3.ZERO
				state = State.IDLE
				return
		if resting_on_object:
			state = State.IDLE
			if not _landed_notified:
				_landed_notified = true
				world.on_landed(self)
			return


func _terrain_support_y() -> float:
	var height: float = world.ground_y(position)
	for offset in preload("res://scripts/story_world_geometry.gd").body_offsets(self):
		height = maxf(height, world.ground_y(position + offset) - offset.y)
	# LND is piecewise planar, so a rotated bounding box's corners alone can
	# miss terrain underneath its interior. Include the actual mesh vertices.
	# Cache local points, not transformed support: scale/rotation may change.
	for child in get_children():
		if not child is MeshInstance3D or child.mesh == null: continue
		if not _terrain_mesh_points.has(child.mesh):
			var points := PackedVector3Array()
			for surface in child.mesh.get_surface_count():
				points.append_array(child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
			_terrain_mesh_points[child.mesh] = points
		var transform: Transform3D = Transform3D(basis, position) * child.transform
		for local in _terrain_mesh_points[child.mesh]:
			var point: Vector3 = transform * local
			height = maxf(height, world.ground_y(point) - (point.y - position.y))
	return height


func _walk(delta: float) -> void:
	if state == State.IDLE and is_instance_valid(story_flock) and story_flock.crowd_mode:
		set_script_focus(world.story_camera.eye)
		return
	var ai: Dictionary = world.cfg_villager
	var speed: float = ai["speed"]
	if story_speed_per_turn >= 0.0:
		var data = preload("res://scripts/data.gd")
		speed = story_speed_per_turn * float(data.STORY_VM["core"]["tick_rate"])
		if speed == 0.0 and state == State.IDLE:
			return
	if state == State.IDLE and _script_move_active:
		var offset := _script_move_target - position
		offset.y = 0.0
		var distance := offset.length()
		if distance > _script_move_radius + 0.001:
			_walk_step(offset / distance * minf(speed * delta, distance - _script_move_radius))
			return
		if not _script_waypoints.is_empty():
			_script_move_target = _script_waypoints[0]
			_script_waypoints.remove_at(0)
			return
		_script_move_active = false
		_script_move_clip = ""
		_target = position
		_wait = 2.0
	var following_flock := state == State.IDLE and is_instance_valid(story_flock) and story_flock.leader != self
	if state == State.IDLE and story_hold_position and not following_flock:
		return
	if following_flock:
		# The original uses a dedicated MoveInFlock state. This port follows the
		# designated leader, or the group's position when it has no leader.
		_target = story_flock.follow_position(self)
	if state == State.FLEE:
		speed = ai["flee_speed"]
		_flee_left -= delta
		if _flee_left <= 0.0:
			state = State.IDLE
			_target = position
	var flat := Vector3(_target.x - position.x, 0.0, _target.z - position.z)
	if following_flock:
		var distance := flat.length()
		var threshold := story_flock.inner_radius if flock_catching_up else story_flock.outer_radius
		flock_catching_up = distance > threshold
		if flock_catching_up:
			_walk_step(flat / distance * minf(speed * delta, distance - story_flock.inner_radius))
		return
	if flat.length() < 1.0:
		_wait -= delta
		if _wait <= 0.0:
			var r: float = _script_wander_radius if _script_wander_radius >= 0.0 else float(ai["wander_radius"])
			var centre: Vector3 = _script_wander_centre if _script_wander_radius >= 0.0 else home
			var a := randf() * TAU
			_target = centre + Vector3(cos(a), 0.0, sin(a)) * randf() * r
			_wait = randf_range(_script_wander_wait.x, _script_wander_wait.y) if _script_wander_radius >= 0.0 else 2.0 + randf() * 5.0
		return
	if not _walk_step(flat.normalized() * minf(speed * delta, flat.length())):
		_target = position


func _walk_step(step: Vector3) -> bool:
	var next := position + step
	if world.ground_y(next) <= world.sea_y + 0.2:
		return false
	position = next
	position.y = world.ground_y(position)
	rotation.y = atan2(step.x, step.z)
	animation_walk = true
	return true


func set_script_move(target: Vector3, radius: float) -> bool:
	if kind != "villager" or state != State.IDLE or not target.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	_script_wander_radius = -1.0
	_script_move_target = target
	story_hold_position = true
	_script_waypoints.clear()
	_script_clip = ""
	_script_move_radius = radius
	_script_move_active = true
	return true


func set_script_wander(centre: Vector3, radius: float, minimum_turns: int, maximum_turns: int) -> bool:
	if kind != "villager" or state != State.IDLE or not centre.is_finite() or not is_finite(radius) or radius < 0.0 or radius > 1000.0 or minimum_turns < 0 or maximum_turns < minimum_turns or maximum_turns > 65535:
		return false
	# Adapt the existing provisional wanderer to the script's centre/radius
	# and wait-turn bounds. Its random distribution is not an original solver.
	_script_wander_centre = centre
	_script_wander_radius = radius
	var rate := float(preload("res://scripts/data.gd").STORY_VM["core"]["tick_rate"])
	_script_wander_wait = Vector2(float(minimum_turns) / rate, float(maximum_turns) / rate)
	_script_move_active = false
	_script_waypoints.clear()
	_script_clip = ""
	_script_move_clip = ""
	story_hold_position = false
	_target = position
	_wait = 0.0
	return true


func release_script_control() -> void:
	story_hold_position = false
	_script_wander_radius = -1.0
	_script_move_active = false
	_script_waypoints.clear()
	_script_clip = ""
	_script_move_clip = ""
	_target = position


func set_script_path(points: PackedVector3Array) -> bool:
	if points.is_empty() or not set_script_move(points[0], 0.0):
		return false
	_script_waypoints = points.slice(1)
	return true


func set_script_focus(target: Vector3) -> bool:
	if (kind != "villager" and get_meta("story_mobile_subtype", -1) != 5) or not target.is_finite():
		return false
	var direction := target - position
	if not Vector2(direction.x, direction.z).is_zero_approx():
		rotation.y = atan2(direction.x, direction.z)
	return true


func set_story_child_age(age: int) -> bool:
	# FollowUs makes its scripted Norse farmer the eight-year-old son.
	if get_meta("story_villager_subtype", -1) != 52 or age != 8:
		return false
	if story_age == age:
		return true
	var child_rig: L3dRig = world.g3d.rig("MSH_P_BOY_WHITE_1")
	if child_rig == null:
		return false
	if rig != null:
		rig.root.free()
	rig = child_rig
	add_child(rig.root)
	_pose.clear()
	_transition_from.clear()
	animation_name = ""
	story_age = age
	return true


func set_story_high_detail(enabled: bool) -> bool:
	if story_high_detail == enabled:
		return true
	var family := {49: "nors_woman", 52: "nors_boy", 53: "nors_man"}
	var subtype := int(get_meta("story_villager_subtype", -1))
	var detail_file := "Data/MISC/Intro/%s.l3d" % family[subtype] if family.has(subtype) else ""
	if subtype == 77:
		detail_file = "Data/MISC/sable.l3d"
	if enabled and not detail_file.is_empty():
		var close_up := L3dRig.new()
		var model := close_up.load_file(world.bw_dir.path_join(detail_file))
		if model == null:
			return false
		if rig == null or close_up.bone_count != rig.bone_count:
			model.free()
			return false
		_ordinary_rig = rig
		_ordinary_rig.root.hide()
		rig = close_up
		add_child(model)
	elif not enabled and _ordinary_rig != null:
		rig.root.free()
		rig = _ordinary_rig
		rig.root.show()
		_ordinary_rig = null
	_pose.clear()
	_transition_from.clear()
	story_high_detail = enabled
	return true


func flee_from(p: Vector3) -> void:
	if state == State.DEAD or state == State.HELD or state == State.FLYING:
		return
	var away := Vector3(position.x - p.x, 0.0, position.z - p.z)
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	_target = position + away.normalized() * 30.0
	_flee_left = world.cfg_villager["flee_time"]
	state = State.FLEE


func set_story_health(value: float) -> bool:
	if not is_finite(value) or value < 0.0 or value > 1.0 or (state == State.DEAD and value > 0.0):
		return false
	# The checked native health setter ignores lethal writes while the
	# indestructible flag is set; it does not replace them with full health.
	if story_indestructible and value <= 0.01: return true
	story_health = value
	if value == 0.0: die()
	return true


func die() -> void:
	if story_indestructible: return
	story_health = 0.0
	state = State.DEAD
	rotation.x = 0.0 if rig else PI / 2.0
	position.y = world.ground_y(position) + 0.3
