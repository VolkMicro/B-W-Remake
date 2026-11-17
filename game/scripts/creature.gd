# Original models/animations, a legacy teaching prototype and a bounded source
# actor adapter. Lionhead's full learning AI is not yet reproduced.
class_name IslandCreature
extends Node3D

const Data := preload("res://scripts/data.gd")
var world: Node
var species := ""
var rig: L3dRig
var morph: MorphReader
var hunger := 0.3
var nature := 0.0
var trust := 0.5
var memory := {"help":0.5,"scare":0.5}
var last_action := ""
var last_action_age := 999.0
var following := true
var action := "stand"
var action_time := 0.0
var _decision := 8.0
var _action_left := 0.0
var _visual_form := "base"
var _animation_tick := 0.0
var _target := Vector3.ZERO
var _rules: Dictionary = Data.PORT_RULES["creature"]
var story_actor := false
var story_player_id := -1
var story_home := Vector3.INF
var story_script_controlled := false
var story_development_phase := -1
var story_in_development_script := false
var story_desires: Dictionary = {}
var story_tether_center := Vector3.INF
var story_tether_radius := 0.0
var story_fatigue := 0.0
var _story_sleep_phase := ""
var _story_clock: RefCounted
var _story_move_active := false
var _story_tether_moving := false
var _story_stop_distance := 0.5
var _story_look_target: WeakRef
var _story_look_camera := false
var _story_look_point := Vector3.INF


func configure(owner_world: Node, id: String, pos: Vector3) -> bool:
	world = owner_world
	species = id
	position = pos
	_target = pos
	hunger = float(_rules["initial_hunger"])
	var row: Dictionary = Data.CREATURES[id]
	rig = L3dRig.new()
	var visual := rig.load_file(world._p(row["mesh_file"]))
	if visual == null:
		world._say("Не удалось прочитать существо: " + rig.error)
		return false
	add_child(visual)
	visual.scale = Vector3.ONE * float(row["scale"])
	morph = MorphReader.new()
	if not morph.load_file(world._p(row["animation_file"]), world._p("Data")):
		world._say("Не удалось прочитать анимации: " + morph.error)
		return false
	name = "Creature_" + id
	return true


func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or rig == null or morph == null:
		return
	if story_actor:
		# Source-created actors must not run the older sandbox teaching loop.
		advance_story(delta)
		return
	hunger = clampf(hunger + float(_rules["hunger_per_second"]) * delta, 0.0, 1.0)
	last_action_age += delta
	_action_left = maxf(0.0, _action_left - delta)
	_decision -= delta
	if _action_left <= 0.0:
		if following:
			_target = world.focus
		var flat := Vector3(_target.x - position.x, 0.0, _target.z - position.z)
		if flat.length() > float(_rules["follow_distance"]):
			var step := flat.normalized() * minf(float(Data.CREATURES[species]["speed"]) * delta, flat.length())
			var next := position + step
			if world.ground_y(next) > world.sea_y + 0.5:
				position = next
				position.y = world.ground_y(position)
				rotation.y = atan2(step.x, step.z)
				_set_action("walk")
			else:
				_set_action("stand")
		else:
			_set_action("stand")
		if _decision <= 0.0:
			_decide()
	action_time += delta
	_animation_tick += delta
	if _animation_tick >= 1.0 / 30.0:
		_animation_tick = 0.0
		var clip: String = Data.CREATURE_ACTIONS[action]["clip"]
		rig.apply_local_pose(morph.sample(clip, action_time, rig.rests))
	_update_form()


func enter_story_control() -> bool:
	if morph == null or not ResourceLoader.exists("res://scripts/clip_clock.gd"): return false
	var clock: RefCounted = load("res://scripts/clip_clock.gd").new()
	var durations := {}
	for clip in morph.clips: durations[clip] = float(morph.clips[clip]["duration"])
	if not clock.configure(durations): return false
	_story_clock = clock
	# World normalization for the young glade actors is explicit port policy;
	# the sandbox's much larger display scale must not overlap all three bodies.
	rig.root.scale = Vector3.ONE * float(Data.PORT_RULES["story"]["creature_visual_scale"])
	story_actor = true
	story_script_controlled = true
	following = false
	return true


func play_story_animation(index: int, repeats: int) -> bool:
	if _story_clock == null or not morph.names_by_index.has(index): return false
	if not _story_clock.start(morph.names_by_index[index], repeats): return false
	_story_move_active = false
	_story_sleep_phase = ""
	story_script_controlled = true
	return true


func story_animation_playing() -> bool:
	return _story_clock != null and bool(_story_clock.snapshot()["playing"])


func set_script_move(point: Vector3, radius: float) -> bool:
	if not story_actor or not point.is_finite() or not is_finite(radius) or radius < 0.0 or radius > 1000.0: return false
	_target = point
	_story_stop_distance = radius
	_story_move_active = true
	_story_tether_moving = false
	_story_sleep_phase = ""
	_story_look_target = null
	_story_look_camera = false
	_story_look_point = Vector3.INF
	_story_clock.stop()
	return true


func set_script_focus(point: Vector3) -> bool:
	if not story_actor or not point.is_finite(): return false
	_story_look_point = point
	_story_look_target = null
	_story_look_camera = false
	return true


func story_action(id: int, target: Node3D) -> bool:
	# Installed action names establish intent; the look/point/sit adaptation
	# below is bounded presentation, not the original creature decision system.
	if _story_clock == null or not is_instance_valid(target) or id not in [17, 81, 82, 163, 168, 188, 189]: return false
	if id == 17 and not story_home.is_finite(): return false
	var clip := "static/start_sleep" if id == 17 else ("static/start_sit" if id == 81 else ("point/lo_right" if id in [163, 168] else ""))
	if not clip.is_empty() and not _story_clock.start(clip, 1): return false
	if clip.is_empty(): _story_clock.stop()
	_story_move_active = false
	_story_tether_moving = false
	_story_sleep_phase = "starting" if id == 17 else ""
	_story_look_camera = id in [82, 168]
	_story_look_target = null if _story_look_camera else weakref(target)
	_story_look_point = Vector3.INF
	story_script_controlled = true
	return true


func set_story_fatigue(value: float) -> bool:
	if not is_finite(value) or value < 0.0 or value > 1.0: return false
	if value == 0.0 and _story_sleep_phase in ["starting","sleeping"]:
		if not _story_clock.start("static/end_sleep",1): return false
		_story_sleep_phase = "ending"
	story_fatigue = value
	return true


func release_story_control() -> void:
	story_script_controlled = false
	_story_move_active = false
	_story_look_target = null
	_story_look_camera = false
	_story_look_point = Vector3.INF
	_story_clock.stop()
	# Subsequent source training commands remain responsible for behavior;
	# release does not activate the unrelated sandbox learning prototype.


func initialize_story_development(phase: Dictionary, initialize_tether := true) -> bool:
	if not story_actor or story_player_id != 1 or not story_home.is_finite() or not phase.has("enable") or not phase.has("disable") or not phase["enable"] is Array or not phase["disable"] is Array: return false
	var next := {}
	for id in 40: next[id] = false
	for key in ["enable","disable"]:
		for id in phase[key]:
			if not id is int or id < 0 or id >= 40: return false
			next[id] = key == "enable"
	story_desires = next
	story_development_phase = 0
	if _story_tether_moving:
		_story_move_active = false
		_story_tether_moving = false
	if initialize_tether:
		story_tether_center = story_home
		story_tether_radius = 12.0
	last_action = ""
	last_action_age = 999.0
	return true


func set_story_training(active: bool) -> void:
	story_in_development_script = active
	if active and _story_tether_moving:
		_story_move_active = false
		_story_tether_moving = false


func advance_story(delta: float) -> void:
	if _story_clock == null or not _story_clock.advance(delta): return
	action_time += delta
	if not story_script_controlled and not story_in_development_script and story_development_phase == 0 and story_tether_center.is_finite():
		var from_home := Vector2(position.x - story_tether_center.x, position.z - story_tether_center.z)
		if from_home.length() > story_tether_radius:
			# Bounded movement consumer of the initialized source tether. The
			# complete desire decision/learning system is still unported.
			_target = story_tether_center
			_story_move_active = true
			_story_tether_moving = true
			_story_stop_distance = 0.0
	var clip := "move/stand"
	var seconds := action_time
	var loop := true
	if _story_move_active:
		var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
		if flat.length() <= _story_stop_distance:
			_story_move_active = false
			_story_tether_moving = false
		else:
			# Reuse the port's existing creature walking policy for source movement.
			var step := flat.normalized() * minf(float(Data.CREATURES[species]["speed"]) * delta, maxf(0, flat.length() - _story_stop_distance))
			position += step
			position.y = world.ground_y(position)
			if not step.is_zero_approx(): rotation.y = atan2(step.x, step.z)
			clip = "move/walk"
	var look := _story_look_point
	if _story_look_camera: look = world.cam.global_position
	elif _story_look_target != null:
		var target := _story_look_target.get_ref() as Node3D
		if is_instance_valid(target): look = target.global_position if target.is_inside_tree() else target.position
	if look.is_finite():
		var flat := Vector3(look.x - global_position.x, 0, look.z - global_position.z)
		if not flat.is_zero_approx(): rotation.y = atan2(flat.x, flat.z)
	var state: Dictionary = _story_clock.snapshot()
	if _story_sleep_phase == "starting" and state["completed"]:
		_story_clock.start("static/sleep",-1)
		_story_sleep_phase = "sleeping"
		state = _story_clock.snapshot()
	elif _story_sleep_phase == "ending" and state["completed"]:
		_story_clock.stop()
		_story_sleep_phase = ""
		state = _story_clock.snapshot()
	if not str(state["name"]).is_empty():
		clip = state["name"]
		seconds = state["position"]
		loop = not state["completed"]
	rig.apply_local_pose(morph.sample_creature(clip, seconds, rig, loop))


func _decide() -> void:
	_decision = float(_rules["decision_seconds"])
	if hunger > 0.7:
		world._say("%s голодно. Принесите зерно со склада." % Data.CREATURES[species]["name"])
	var town: int = world._nearest_town(position, 90.0)
	if town < 0:
		return
	var total := float(memory["help"]) + float(memory["scare"])
	var picked := "help" if randf() * total < float(memory["help"]) else "scare"
	perform(picked, town)


func perform(id: String, town: int) -> void:
	last_action = id
	last_action_age = 0.0
	_set_action(id)
	_action_left = float(Data.CREATURE_ACTIONS[id]["duration"])
	nature = clampf(nature + float(Data.CREATURE_ACTIONS[id]["alignment"]), -100.0, 100.0)
	if id == "help":
		world.add_belief(town, 3.0)
		world._say("Существо приветствует жителей. Похвалите его (R), если это правильно.")
	else:
		for thing in world.things:
			if is_instance_valid(thing) and thing.kind == "villager" and thing.position.distance_to(position) < 30.0:
				thing.flee_from(position)
		world.add_belief(town, 2.0)
		world._say("Существо пугает жителей. R — одобрить, F — запретить этот поступок.")
	world._log_test("creature_" + id, "town %d" % town)


func feedback(positive: bool) -> bool:
	if last_action == "" or last_action_age > float(_rules["feedback_seconds"]):
		world._say("Дождитесь поступка существа: похвала и наказание относятся к последнему действию.")
		return false
	var id := "praise" if positive else "punish"
	var row: Dictionary = Data.CREATURE_ACTIONS[id]
	memory[last_action] = clampf(float(memory[last_action]) + float(row["learning"]), 0.05, 0.95)
	trust = clampf(trust + (0.04 if positive else -0.04), 0.0, 1.0)
	_set_action(id)
	_action_left = float(row["duration"])
	# Approving cruelty teaches evil; discouraging it teaches kindness.
	var moral := 1.0 if last_action == "help" else -1.0
	nature = clampf(nature + moral * (5.0 if positive else -5.0), -100.0, 100.0)
	world.alignment = clampf(world.alignment + float(row["alignment"]), -100.0, 100.0)
	world._say(("Существо запомнило одобрение: " if positive else "Существо запомнило запрет: ") + ("помогать жителям" if last_action == "help" else "пугать жителей"))
	last_action = ""
	return true


func feed(food: Thing) -> bool:
	if food.kind != "food" or food.position.distance_to(position) > float(_rules["interaction_radius"]):
		return false
	hunger = maxf(0.0, hunger - 0.4)
	food.state = Thing.State.DEAD
	food.visible = false
	food.queue_free()
	_set_action("eat")
	_action_left = float(Data.CREATURE_ACTIONS["eat"]["duration"])
	world._say("Существо съело зерно.")
	return true


func _set_action(id: String) -> void:
	if action != id:
		action = id
		action_time = 0.0


func _update_form() -> void:
	var threshold := float(_rules["morph_threshold"])
	var next := "good" if nature >= threshold else ("evil" if nature <= -threshold else "base")
	if next == _visual_form:
		return
	var row: Dictionary = Data.CREATURES[species]
	var next_rig := L3dRig.new()
	var file: String = row["mesh_file"] if next == "base" else row[next + "_file"]
	var visual := next_rig.load_file(world._p(file))
	if visual == null:
		return
	rig.root.queue_free()
	rig = next_rig
	add_child(visual)
	visual.scale = Vector3.ONE * float(row["scale"])
	_visual_form = next


func snapshot() -> Dictionary:
	return {"species":species,"position":[position.x,position.y,position.z],"hunger":hunger,"nature":nature,"trust":trust,"memory":memory.duplicate(),"following":following}


func restore(save: Dictionary) -> void:
	hunger = clampf(float(save.get("hunger", 0.3)), 0.0, 1.0)
	nature = clampf(float(save.get("nature", 0.0)), -100.0, 100.0)
	trust = clampf(float(save.get("trust", 0.5)), 0.0, 1.0)
	following = bool(save.get("following", true))
	var saved_memory: Dictionary = save.get("memory", {})
	for id in memory:
		memory[id] = clampf(float(saved_memory.get(id, 0.5)), 0.05, 0.95)
	_update_form()
