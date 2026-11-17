# Membership for the first-island scripted villager flocks.
class_name StoryFlock
extends Node3D

var members: Array[Thing] = []
var leader: Thing
var crowd_mode := false
var inner_radius := 30.0
var outer_radius := 80.0
const CROWD_ANIMATIONS := [204, 203, 418, 227, 234, 385]
var _crowd_animations: AnmReader
var _crowd_load_attempted := false
var _crowd_clips: Dictionary = {}
var _bird_orbit: Node3D
var _bird_rigs: Array[L3dRig] = []
var _bird_animations: AnmReader
var _bird_clip := ""
var _bird_age := 0.0


func populate_scripted_birds(world: Node, count: int) -> bool:
	# Bounded POPULATE_CONTAINER(Animal6, subtype12) presentation. The source
	# supplies count and centre; orbit motion is explicitly new port policy.
	if count < 1 or count > 64 or is_instance_valid(_bird_orbit) or not is_inside_tree(): return false
	if not ResourceLoader.exists("res://scripts/orbit_actors.gd"): return false
	var info: Dictionary = world.host_info.animal(12)
	if info.is_empty(): return false
	var reader := AnmReader.new()
	if not reader.load_file(world.bw_dir.path_join(preload("res://scripts/data.gd").PORT_MODULES["villager_animations"]["source"]), [], PackedInt32Array([int(info["animation_id"])])): return false
	var clip: String = reader.names_by_index.get(int(info["animation_id"]), "")
	if clip.is_empty(): return false
	var orbit: Node3D = load("res://scripts/orbit_actors.gd").new()
	var actors: Array[Node3D] = []
	var rigs: Array[L3dRig] = []
	for i in count:
		var rig: L3dRig = world.g3d.rig_index(int(info["mesh_id"]))
		if rig == null or rig.bone_count != int(reader.clips[clip]["bones"]):
			if rig != null: rig.root.free()
			orbit.free()
			return false
		var actor := Node3D.new()
		actor.name = "ScriptBird%d" % i
		actor.set_meta("story_animal_subtype", 12)
		actor.add_child(rig.root)
		orbit.add_child(actor)
		actors.append(actor)
		rigs.append(rig)
	add_child(orbit)
	if not orbit.configure(actors, 14.0, maxf(0.0, float(info["normal_altitude"])), 0.35):
		orbit.free()
		return false
	_bird_orbit = orbit
	_bird_rigs = rigs
	_bird_animations = reader
	_bird_clip = clip
	_process(0.0)
	return true


func scripted_bird_count() -> int:
	if not is_instance_valid(_bird_orbit): return 0
	var count := 0
	for actor in _bird_orbit.get_children():
		if is_instance_valid(actor) and actor.has_meta("story_animal_subtype"): count += 1
	return count


func _process(delta: float) -> void:
	if not is_instance_valid(_bird_orbit) or not _bird_orbit.advance(delta): return
	_bird_age += delta
	var duration := float(_bird_animations.clips[_bird_clip]["duration"])
	for i in _bird_rigs.size():
		var rig := _bird_rigs[i]
		if not is_instance_valid(rig.root): continue
		var pose: Array[Transform3D] = _bird_animations.sample(_bird_clip, _bird_age + duration * float(i) / _bird_rigs.size())
		rig.apply_local_pose(pose)


func _physics_process(_delta: float) -> void:
	if not crowd_mode:
		return
	for member in members:
		if not is_instance_valid(member) or member.state != Thing.State.IDLE:
			continue
		var instance := member.get_instance_id()
		if _crowd_clips.has(instance) and member.is_script_animation_playing():
			continue
		if not _load_crowd_animations(member):
			continue
		# ScriptInCrowd refreshes its state animation only when the previous
		# gesture ends. Original RandomCrowdAnimation (1.2, 0x4241B0) chooses
		# from 25 equally likely values; most select the ordinary standing clip.
		var choice := randi_range(0, 24)
		var animation := crowd_animation(choice)
		if member.prepare_script_animation(_crowd_animations, animation, 1) and member.play_script_animation():
			_crowd_clips[instance] = member._script_clip


static func crowd_animation(choice: int) -> int:
	match choice:
		0: return 204
		1: return 203
		2: return 418
		3: return 227
		4, 5: return 234
	return 385


func _load_crowd_animations(member: Thing) -> bool:
	if _crowd_animations != null:
		return true
	if _crowd_load_attempted:
		return false
	_crowd_load_attempted = true
	if not is_instance_valid(member.world):
		return false
	var data = preload("res://scripts/data.gd")
	var reader := AnmReader.new()
	if not reader.load_file(member.world.bw_dir.path_join(data.PORT_MODULES["villager_animations"]["source"]), [], PackedInt32Array(CROWD_ANIMATIONS)):
		push_error("Original crowd animations could not be read: " + reader.error)
		return false
	_crowd_animations = reader
	return true


func _release_crowd_animation(member: Thing) -> void:
	var instance := member.get_instance_id()
	if _crowd_clips.get(instance, "") == member._script_clip:
		member._script_clip = ""
	_crowd_clips.erase(instance)


func follow_position(_villager: Thing) -> Vector3:
	return leader.position if is_instance_valid(leader) and leader.state != Thing.State.DEAD else position


func attach(villager: Thing, as_leader: bool) -> void:
	if is_instance_valid(villager.story_flock) and villager.story_flock != self:
		villager.story_flock.detach(villager)
	if not members.has(villager):
		members.append(villager)
	# Original FLOCK_ATTACH changes the living actor to MoveInFlock (state 27).
	# A previous infinite script animation must release movement at that point.
	villager._script_clip = ""
	villager._script_move_active = false
	villager._script_waypoints.clear()
	villager._script_move_clip = ""
	villager.story_flock = self
	villager.flock_catching_up = false
	if as_leader:
		leader = villager


func detach(villager: Thing) -> bool:
	if not members.has(villager):
		return false
	members.erase(villager)
	_release_crowd_animation(villager)
	villager.story_flock = null
	villager.flock_catching_up = false
	if leader == villager:
		leader = null
	return true


func disband() -> void:
	if is_instance_valid(_bird_orbit): _bird_orbit.free()
	_bird_orbit = null
	_bird_rigs.clear()
	_bird_animations = null
	_bird_clip = ""
	for member in members:
		if is_instance_valid(member):
			_release_crowd_animation(member)
			member.story_flock = null
			member.flock_catching_up = false
	members.clear()
	leader = null
