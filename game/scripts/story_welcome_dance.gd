extends StoryFlock
## Type 14 NewDanceAroundPerson, with the original two circle formations.

const COMMAND_BYTES := 56
const WELCOME_GROUPS := 2

var focus_actor: Thing
var _turn := 0.0
var _events: Array[Dictionary] = []
var _event_index := 0
var _radii := PackedFloat32Array([0.0, 0.0])
var _headings := PackedInt32Array([0, 0])
var _radius_changes: Array[Dictionary] = [{}, {}]
# Villager::DanceAnimation (original 1.2 at 0x423850) dispatches PLAY_ANIM
# through the table at 0xBE6970, stride 136. The first two words are male/female
# archive indices. These are precisely the slots used by NewDanceAroundPerson.
const ANIMATION_SLOTS := {
	0: [314, 265], 1: [315, 266], 2: [316, 267], 3: [236, 236],
	4: [238, 238], 5: [239, 239], 6: [240, 240], 7: [241, 241],
	8: [242, 242], 21: [287, 287], 22: [343, 343], 23: [323, 323],
}
var _animation_slots := PackedInt32Array([-1, -1])
var _dance_animations: AnmReader
var _dance_clips: Dictionary = {}


func load_choreography(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8 or bytes.decode_u32(0) != 1:
		return false
	var frames := bytes.decode_u32(4)
	if frames < 1 or frames > 256:
		return false
	var cursor := 8
	var previous_turn := 0.0
	var events: Array[Dictionary] = []
	var proportions := PackedInt32Array([0, 0])
	for frame in frames:
		if cursor + 12 > bytes.size():
			return false
		var turn := bytes.decode_float(cursor)
		var commands := bytes.decode_u32(cursor + 8)
		if not is_finite(turn) or turn < previous_turn or commands > 128:
			return false
		previous_turn = turn
		cursor += 12
		for command in commands:
			if cursor + 4 > bytes.size():
				return false
			var groups := bytes.decode_u32(cursor)
			cursor += 4
			if groups < 1 or groups > WELCOME_GROUPS or cursor + groups * 4 + 4 + COMMAND_BYTES > bytes.size():
				return false
			var selected := PackedInt32Array()
			for group in groups:
				var selector := bytes.decode_u32(cursor + group * 4)
				if selector >= WELCOME_GROUPS:
					return false
				selected.append(selector)
			cursor += groups * 4
			var kind := bytes.decode_u32(cursor)
			cursor += 4
			if kind == 0 and bytes.decode_u32(cursor) != 0:
				return false # Only Circle is used by this choreography.
			if kind == 6:
				if turn != 0.0 or bytes.decode_u32(cursor) != 0:
					return false # Both welcome groups have the same 50% proportion.
				for group in selected:
					proportions[group] = bytes.decode_u32(cursor + 4)
			elif kind == 2:
				var radius := bytes.decode_float(cursor)
				if not is_finite(radius) or radius <= 0.0:
					return false
				events.append({"turn":turn, "groups":selected, "radius":radius})
			elif kind == 3:
				var action := bytes.decode_u32(cursor + 16)
				var slot := int(bytes.decode_u32(cursor + 20)) if action == 10 else -1
				if slot >= 0 and not ANIMATION_SLOTS.has(slot):
					return false
				events.append({"turn":turn, "groups":selected, "slot":slot})
				if action == 7 or action == 8:
					events.append({"turn":turn, "groups":selected, "heading":action})
				elif action == 11:
					var radius := bytes.decode_float(cursor + 20)
					if not is_finite(radius) or radius <= 0.0:
						return false
					var end_turn := float(bytes.decode_u32(cursor + 28))
					if end_turn <= turn:
						return false
					events.append({"turn":turn, "end":end_turn, "groups":selected, "radius":radius})
			cursor += COMMAND_BYTES
	if cursor + 24 > bytes.size() or bytes.decode_u32(cursor + 4) != WELCOME_GROUPS or bytes.decode_u32(cursor + 8) != 14:
		return false
	if proportions != PackedInt32Array([50, 50]):
		return false
	_events = events
	inner_radius = 0.2
	outer_radius = 0.5
	advance(0.0)
	return _radii[0] > 0.0 and _radii[1] > 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(focus_actor) or focus_actor.state == Thing.State.DEAD:
		disband()
		queue_free()
		return
	if not members.is_empty():
		advance(delta * 10.0)
	for i in members.size():
		var member := members[i]
		if not is_instance_valid(member) or member.state != Thing.State.IDLE:
			continue
		var group := i % WELCOME_GROUPS
		var target := follow_position(member)
		var distance := Vector2(member.position.x - target.x, member.position.z - target.z).length()
		if distance > outer_radius or _animation_slots[group] < 0:
			_release_dance_animation(member)
		elif _load_dance_animations(member):
			var slot: Array = ANIMATION_SLOTS[_animation_slots[group]]
			var animation: int = slot[1 if member.animation_profile == "female" else 0]
			var clip: String = _dance_animations.names_by_index[animation]
			if member._script_clip != clip and member.prepare_script_animation(_dance_animations, animation, -1) and member.play_script_animation():
				_dance_clips[member.get_instance_id()] = clip
		var heading := _headings[i % WELCOME_GROUPS]
		if heading != 0:
			var center := position
			member.set_script_focus(center if heading == 7 else member.position * 2.0 - center)


func advance(turns: float) -> void:
	_turn += turns
	while _event_index < _events.size() and float(_events[_event_index]["turn"]) <= _turn:
		var event := _events[_event_index]
		_update_radii(event["turn"])
		for group in event["groups"]:
			if event.has("end"):
				_radius_changes[group] = {"start":event["turn"], "end":event["end"], "from":_radii[group], "to":event["radius"]}
			elif event.has("radius"):
				_radii[group] = event["radius"]
				_radius_changes[group].clear()
			if event.has("heading"):
				_headings[group] = event["heading"]
			if event.has("slot"):
				_animation_slots[group] = event["slot"]
		_event_index += 1
	_update_radii(_turn)


func _load_dance_animations(member: Thing) -> bool:
	if _dance_animations != null:
		return true
	var indices := PackedInt32Array()
	for pair in ANIMATION_SLOTS.values():
		for index in pair:
			if not indices.has(index):
				indices.append(index)
	var reader := AnmReader.new()
	var data = preload("res://scripts/data.gd")
	if not reader.load_file(member.world.bw_dir.path_join(data.PORT_MODULES["villager_animations"]["source"]), [], indices):
		push_error("Original welcome dance animations could not be read: " + reader.error)
		return false
	_dance_animations = reader
	return true


func _release_dance_animation(member: Thing) -> void:
	var instance := member.get_instance_id()
	if _dance_clips.get(instance, "") == member._script_clip:
		member._script_clip = ""
	_dance_clips.erase(instance)


func detach(villager: Thing) -> bool:
	_release_dance_animation(villager)
	return super.detach(villager)


func disband() -> void:
	for member in members:
		if is_instance_valid(member):
			_release_dance_animation(member)
	super.disband()


func _update_radii(turn: float) -> void:
	for group in WELCOME_GROUPS:
		var change := _radius_changes[group]
		if change.is_empty():
			continue
		var fraction := clampf(inverse_lerp(change["start"], change["end"], turn), 0.0, 1.0)
		_radii[group] = lerpf(change["from"], change["to"], fraction)
		if fraction >= 1.0:
			change.clear()


func follow_position(villager: Thing) -> Vector3:
	var slot := members.find(villager)
	if slot < 0:
		return position
	var group := slot % WELCOME_GROUPS
	var dancers := ceili(float(members.size() - group) / WELCOME_GROUPS)
	var angle := TAU * (float(slot / WELCOME_GROUPS) + float(group) * 0.5) / dancers
	return position + Vector3(cos(angle), 0.0, sin(angle)) * _radii[group]
