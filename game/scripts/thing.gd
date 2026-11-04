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
var world: Node = null # main.gd

var _target := Vector3.ZERO
var _wait := 0.0
var _flee_left := 0.0
var _dead_time := 0.0
var impact_velocity := Vector3.ZERO
var _landed_notified := false
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
			if kind == "villager":
				_walk(delta)
		State.DEAD:
			_dead_time += delta
			if _dead_time > 12.0:
				queue_free()


func _process(delta: float) -> void:
	if rig:
		_animate(delta)


func _animate(delta: float, force := false) -> void:
	var data = preload("res://scripts/data.gd")
	var cfg: Dictionary = data.PORT_RULES["villager_animation"]
	var profile: Dictionary = data.VILLAGER_ANIMATIONS[animation_profile]
	_animation_age += delta
	_transition_age += delta
	_animation_accumulator += delta
	var hz: float = cfg["update_hz"]
	if world.cam.position.distance_to(position) > float(cfg["near_distance"]):
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
	var clip: String = profile[action]
	if animation_name != clip:
		_transition_from = _pose.duplicate()
		_transition_age = 0.0
		animation_name = clip
	if _animation_previous_state != state:
		_animation_age = 0.0
		_animation_previous_state = state
	var seconds: float = _animation_age if state in [State.FLYING,State.DEAD] else world.animation_clock
	var phase := _animation_phase if state not in [State.FLYING,State.DEAD] else 0
	var next: Array[Transform3D] = world.villager_anims.sample(clip, seconds, phase, state != State.DEAD)
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
		var g: float = world.ground_y(position)
		if position.y <= world.sea_y and g <= world.sea_y + 0.05:
			position.y = world.sea_y
			velocity = Vector3.ZERO
			state = State.IDLE
			if kind == "villager":
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
		if position.y <= g:
			position.y = g
			impact_velocity = velocity
			if not _landed_notified:
				_landed_notified = true
				world.on_landed(self)
			if not is_instance_valid(self) or state == State.DEAD or is_queued_for_deletion():
				return
			var n: Vector3 = world.ground_normal(position)
			var incoming := velocity.dot(n)
			if incoming < 0.0:
				velocity -= (1.0 + float(profile["restitution"])) * incoming * n
			var normal_v := n * velocity.dot(n)
			velocity = normal_v + (velocity - normal_v) * float(profile["friction"])
			if bool(profile["roll"]):
				rotation.z += position.distance_to(previous) / maxf(float(profile["radius"]), 0.1)
			if velocity.length() < float(cfg["settle_speed"]) or not bool(profile["roll"]):
				velocity = Vector3.ZERO
				state = State.IDLE
				return


func _walk(delta: float) -> void:
	var ai: Dictionary = world.cfg_villager
	var speed: float = ai["speed"]
	if state == State.FLEE:
		speed = ai["flee_speed"]
		_flee_left -= delta
		if _flee_left <= 0.0:
			state = State.IDLE
			_target = position
	var flat := Vector3(_target.x - position.x, 0.0, _target.z - position.z)
	if flat.length() < 1.0:
		_wait -= delta
		if _wait <= 0.0:
			var r: float = ai["wander_radius"]
			var a := randf() * TAU
			_target = home + Vector3(cos(a), 0.0, sin(a)) * randf() * r
			_wait = 2.0 + randf() * 5.0
		return
	var step := flat.normalized() * minf(speed * delta, flat.length())
	var next := position + step
	if world.ground_y(next) <= world.sea_y + 0.2:
		_target = position # don't walk into the sea
		return
	position = next
	position.y = world.ground_y(position)
	rotation.y = atan2(step.x, step.z)
	animation_walk = true


func flee_from(p: Vector3) -> void:
	if state == State.DEAD or state == State.HELD or state == State.FLYING:
		return
	var away := Vector3(position.x - p.x, 0.0, position.z - p.z)
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	_target = position + away.normalized() * 30.0
	_flee_left = world.cfg_villager["flee_time"]
	state = State.FLEE


func die() -> void:
	state = State.DEAD
	rotation.x = 0.0 if rig else PI / 2.0
	position.y = world.ground_y(position) + 0.3
