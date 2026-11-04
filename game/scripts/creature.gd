# Reconstructed teaching loop, using the player's real model and animations.
# This is not yet a reproduction of Lionhead's full learning AI.
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
