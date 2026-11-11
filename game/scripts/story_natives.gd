# Small, explicit bridge for original LHVM calls whose behaviour is understood.
# Unlisted calls return ok=false and therefore suspend the story VM safely.
class_name StoryNatives
extends RefCounted

const Data := preload("res://scripts/data.gd")
const FOLLOW_US_ANIMATIONS := [204, 207, 210, 223, 224, 229, 267, 272, 273, 279, 307, 311, 323, 334, 335, 340, 343, 390, 392, 393, 397, 398, 399, 407, 413, 418]
const FOLLOW_US_MOVE_ANIMATIONS := [351, 353, 379]
const WelcomeDance := preload("res://scripts/story_welcome_dance.gd")
var terrain: WeakRef
var _objects: Dictionary = {}
var _object_types: Dictionary = {}
var _created_markers: Array[Node3D] = []
var _created_flocks: Array[StoryFlock] = []
var _next_object := 1
var _random := RandomNumberGenerator.new()
var keep_old_creature := false
var profile_has_creature := false
var camera_editor := PackedByteArray()
var camera_shortcuts_enabled := true
var dialogue_owner := 0
var story_text_enum := -1
var clicked_thing: WeakRef
var hit_thing: WeakRef
var hitting_thing: WeakRef
var widescreen_owner := 0
var camera: RefCounted
var game_time: RefCounted
var villager_animation_path := ""
var welcome_dance_path := ""
var _villager_script_animations: AnmReader
var _timers: Array[RefCounted] = []
var _crowd_villager_handles: Dictionary = {}


func configure(world: Object) -> void:
	terrain = weakref(world) if is_instance_valid(world) else null


func record_contact(target: Node3D, hitter: Node3D) -> void:
	hit_thing = weakref(target) if is_instance_valid(target) else null
	hitting_thing = weakref(hitter) if is_instance_valid(hitter) else null


func register_object(object: Object, story_type := -1) -> int:
	if not is_instance_valid(object):
		return 0
	var id := _next_object
	_next_object += 1
	_objects[id] = weakref(object)
	_object_types[id] = story_type
	return id


func register_landmarks(landmarks: Array[Node3D]) -> int:
	var supported := {}
	for rule in Data.STORY_SEARCH_RULES.values():
		supported[int(rule["object_type"])] = true
	var registered := 0
	for landmark in landmarks:
		if not is_instance_valid(landmark):
			continue
		var story_type := int(landmark.get_meta("story_type", -1))
		if supported.has(story_type) and register_object(landmark, story_type) != 0:
			registered += 1
	return registered


func clear_created() -> void:
	for marker in _created_markers:
		if is_instance_valid(marker):
			marker.free()
	_created_markers.clear()
	for flock in _created_flocks:
		if is_instance_valid(flock):
			flock.disband()
			flock.free()
	_created_flocks.clear()


func invoke(id: int, stack: Array, context: Dictionary) -> Dictionary:
	if not Data.STORY_NATIVES.has(str(id)):
		return {"ok":false}
	var row: Dictionary = Data.STORY_NATIVES[str(id)]
	var count: int = row["arguments"]
	if str(row["handler"]) in ["story_snapshot", "update_snapshot"]:
		if stack.size() < 2:
			return {"ok":false}
		var parameters := StoryVm.as_int(stack[stack.size() - 2])
		if parameters < 0 or parameters > 12 or (id == 238 and parameters == 12):
			return {"ok":false}
		count = (6 if id == 238 else 13) + parameters
	if stack.size() < count:
		return {"ok":false}
	var result: Array[Dictionary] = []
	match str(row["handler"]):
		"update_snapshot":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_update_snapshot") or not world.story_update_snapshot(stack.slice(stack.size() - count)):
				return {"ok":false}
		"hit_object":
			if id == 193:
				hit_thing = null
				hitting_thing = null
			else:
				var target := _object(stack.back())
				var hit: Object = hit_thing.get_ref() if hit_thing != null else null
				result.append(StoryVm.integer(int(is_instance_valid(target) and target == hit), StoryVm.BOOL))
		"object_info_bits":
			var object := _object(stack.back()) as OriginalLandmark
			if object == null: return {"ok":false}
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_landmark_info_bits"): return {"ok":false}
			result.append(StoryVm.number(float(world.story_landmark_info_bits(object))))
		"create_mobile_with_transform":
			var p := stack.size() - count
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_create_mobile_static") or StoryVm.as_int(stack[p + 2]) != 8: return {"ok":false}
			var actor: Thing = world.story_create_mobile_static(StoryVm.as_int(stack[p + 3]), _vector(stack, p + 4), StoryVm.as_float(stack[p]), StoryVm.as_float(stack[p + 1]))
			if actor == null: return {"ok":false}
			result.append(StoryVm.integer(register_object(actor, 8), StoryVm.OBJECT))
		"story_snapshot":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_record_snapshot") or not world.story_record_snapshot(stack.slice(stack.size() - count)):
				return {"ok":false}
		"highlight_active":
			var highlight := _object(stack.back()) as Node3D
			if highlight == null or not highlight.has_meta("highlight_type") or not highlight.has_method("set_active"):
				return {"ok":false}
			if id == 255:
				highlight.set_active(StoryVm.as_int(stack[stack.size() - count]) != 0)
			else:
				result.append(StoryVm.integer(int(highlight.active), StoryVm.BOOL))
		"draw_highlights":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_set_highlights_visible"):
				return {"ok":false}
			world.story_set_highlights_visible(StoryVm.as_int(stack.back()) != 0)
		"adviser_object_guidance":
			var p := stack.size() - count
			var spirit := StoryVm.as_int(stack[p])
			var target := _object(stack[p + 1]) as Node3D
			var world: Object = terrain.get_ref() if terrain else null
			if not spirit in [1, 2] or target == null or not is_instance_valid(world) or not world.has_method("story_guide_adviser_object"):
				return {"ok":false}
			world.story_guide_adviser_object(spirit, target)
		"random_integer":
			var lo := StoryVm.as_int(stack[stack.size() - 2])
			var hi := StoryVm.as_int(stack.back())
			if lo < 0 or hi < lo:
				return {"ok":false}
			# Original1.2 RandomULONG (0x6f8e20) draws (hi-lo+1), adds lo,
			# and pushes an INT. LostTheMother uses this to vary its callouts.
			result.append(StoryVm.integer(_random.randi_range(lo, hi)))
		"inside_temple":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_inside_temple"):
				return {"ok":false}
			result.append(StoryVm.integer(int(world.story_inside_temple()), StoryVm.BOOL))
		"vm_time":
			if not context.has("tick"):
				return {"ok":false}
			result.append(StoryVm.number(float(context["tick"]) / float(Data.STORY_VM["core"]["tick_rate"])))
		"widescreen_finished":
			# Letterbox changes are currently immediate, so no transition is pending.
			result.append(StoryVm.integer(1, StoryVm.BOOL))
		"object_in_view":
			var target := _object(stack.back()) as Node3D
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_position_in_view"):
				return {"ok":false}
			result.append(StoryVm.integer(int(is_instance_valid(target) and world.story_position_in_view(target.global_position if target.is_inside_tree() else target.position)), StoryVm.BOOL))
		"camera_input":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world):
				return {"ok": false}
			var input: RefCounted = world.get("story_camera_input")
			if input == null:
				return {"ok": false}
			if id == 237:
				var event := StoryVm.as_int(stack.back())
				if not event in [25, 28, 29]:
					return {"ok": false}
				result.append(StoryVm.number(input.total(event)))
			elif id == 413:
				result.append(StoryVm.integer(input.hand_state))
			else:
				input.set_angle_sound(id, StoryVm.as_int(stack.back()) != 0)
		"hand_haptics":
			var devices := Input.get_connected_joypads()
			if id == 304:
				result.append(StoryVm.integer(int(not devices.is_empty()), StoryVm.BOOL))
			elif StoryVm.as_int(stack.back()) == 16:
				for device in devices:
					Input.start_joy_vibration(device, 0.3, 0.1, 0.25)
			else:
				return {"ok":false}
		"position_in_view":
			var world: Object = terrain.get_ref() if terrain else null
			var point := _vector(stack, stack.size() - count)
			if not is_instance_valid(world) or not world.has_method("story_position_in_view") or not point.is_finite():
				return {"ok":false}
			result.append(StoryVm.integer(int(world.story_position_in_view(point)), StoryVm.BOOL))
		"villager_resources":
			var p := stack.size() - count
			var resource := StoryVm.as_int(stack[p])
			var amount := StoryVm.as_float(stack[p + 1])
			var villager := _object(stack.back()) as Thing
			if not resource in [0, 1] or not is_finite(amount) or amount < 0.0 or amount > 65535.0 or villager == null or villager.kind != "villager":
				return {"ok":false}
			if not villager.add_story_resource(resource, int(amount)):
				return {"ok":false}
			result.append(StoryVm.number(0.0))
		"citadel_interface":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_build_citadel"):
				return {"ok":false}
			world.story_citadel_interface = StoryVm.as_int(stack.back()) != 0
		"attach_music":
			var world: Object = terrain.get_ref() if terrain else null
			var target := _object(stack.back()) as Node3D
			var cue := StoryVm.as_int(stack[stack.size() - count])
			if not is_instance_valid(world) or not is_instance_valid(target) or not world.has_method("story_attach_music") or not world.story_attach_music(cue, target):
				return {"ok":false}
		"detach_music":
			var target := _object(stack.back()) as Node3D
			if not is_instance_valid(target):
				return {"ok":false}
			var music := target.get_node_or_null("StoryAttachedMusic")
			if music != null:
				music.queue_free()
		"build_citadel":
			var p := stack.size() - count
			var world: Object = terrain.get_ref() if terrain else null
			var position := _vector(stack, p)
			var amount := StoryVm.as_float(stack.back())
			if not is_instance_valid(world) or not world.has_method("story_build_citadel") or not position.is_finite() or not is_finite(amount) or amount < 0.0:
				return {"ok":false}
			var site: Node3D = world.story_build_citadel(position, amount)
			if site == null:
				return {"ok":false}
			if not site.has_meta("story_citadel"):
				site.set_meta("story_citadel", true)
				register_object(site, 18)
		"hand_demo":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_play_hand_demo"):
				return {"ok":false}
			match id:
				266:
					if not world.story_play_hand_demo(StoryVm.as_int(stack[stack.size() - count])):
						return {"ok":false}
				267:
					result.append(StoryVm.integer(int(not world.story_hand_demo.playing), StoryVm.BOOL))
				336:
					result.append(StoryVm.integer(int(world.story_hand_demo.consume_trigger()), StoryVm.BOOL))
		"dance_create":
			var p := stack.size() - count
			var focus := _object(stack[p]) as Thing
			var position := _vector(stack, p + 2)
			var timeout := StoryVm.as_float(stack.back())
			var world: Object = terrain.get_ref() if terrain else null
			if StoryVm.as_int(stack[p + 1]) != 14 or not position.is_finite() or not is_instance_valid(focus) or not world is Node3D or timeout != 30.0:
				return {"ok":false}
			var dance := WelcomeDance.new()
			if not dance.load_choreography(FileAccess.get_file_as_bytes(welcome_dance_path)):
				dance.free()
				return {"ok":false}
			dance.focus_actor = focus
			dance.position = position
			world.add_child(dance)
			_created_flocks.append(dance)
			result.append(StoryVm.integer(register_object(dance), StoryVm.OBJECT))
		"adviser_guidance":
			var p := stack.size() - count
			var spirit := StoryVm.as_int(stack[p])
			var world: Object = terrain.get_ref() if terrain else null
			if not spirit in [1, 2] or not is_instance_valid(world) or not world.has_method("story_guide_adviser"):
				return {"ok":false}
			var position := Vector3.INF
			if id == 9 or id == 139:
				position = _vector(stack, p + 1)
				if not position.is_finite() or (id == 9 and StoryVm.as_int(stack.back()) != 0):
					return {"ok":false}
			world.story_guide_adviser(spirit, position, id == 9 or id == 137)
		"adviser_motion":
			var p := stack.size() - count
			var spirit := StoryVm.as_int(stack[p])
			var world: Object = terrain.get_ref() if terrain else null
			if not spirit in [1, 2] or not is_instance_valid(world) or not world.has_method("story_move_adviser"):
				return {"ok":false}
			if id in [7, 300]:
				return {"ok":world.story_appear_adviser(spirit, id == 7), "pop":count, "push":result}
			if id in [8, 301]:
				return {"ok":world.story_hide_adviser(spirit, id == 8), "pop":count, "push":result}
			var screen := Vector2.INF
			if id == 166 or id == 167:
				screen = Vector2(StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2]))
				if not screen.is_finite() or screen != screen.clamp(Vector2.ZERO, Vector2.ONE):
					return {"ok":false}
			if not world.story_move_adviser(spirit, screen, id == 166):
				return {"ok":false}
		"dialogue_text":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_play_voice"):
				return {"ok":false}
			if id == 13:
				var text_enum := StoryVm.as_int(stack[stack.size() - 2])
				var single_line := StoryVm.as_int(stack[stack.size() - 3]) != 0
				if not world.story_play_voice(text_enum, single_line):
					return {"ok":false}
				story_text_enum = text_enum
			elif id == 15:
				result.append(StoryVm.integer(int(story_text_enum == -1 or not world.story_voice_playing(story_text_enum)), StoryVm.BOOL))
			else:
				world.story_clear_voice()
				story_text_enum = -1
		"id_size":
			var container := _object(stack.back()) as StoryFlock
			if not is_instance_valid(container):
				return {"ok":false}
			var size := 0
			for member in container.members:
				if is_instance_valid(member):
					size += 1
			result.append(StoryVm.number(float(size)))
		"call_in_villager":
			var p := stack.size() - count
			var container := _object(stack[p + 2])
			var exclude := StoryVm.as_int(stack.back()) != 0
			if StoryVm.as_int(stack[p]) != 4 or StoryVm.as_int(stack[p + 1]) != 5000 or not is_instance_valid(container):
				return {"ok":false}
			var villagers: Array[Thing]
			if container is StoryFlock and not exclude:
				villagers = container.members
			elif container.has_meta("town_index"):
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world) or not world.has_method("story_town_villagers"):
					return {"ok":false}
				villagers = world.story_town_villagers(int(container.get_meta("town_index")))
			else:
				return {"ok":false}
			var handle := 0
			for villager in villagers:
				if not is_instance_valid(villager) or villager.state != Thing.State.IDLE:
					continue
				var instance := villager.get_instance_id()
				handle = int(_crowd_villager_handles.get(instance, 0))
				if handle != 0 and exclude:
					handle = 0
					continue
				if handle == 0:
					handle = register_object(villager, 4)
					_crowd_villager_handles[instance] = handle
				break
			result.append(StoryVm.integer(handle, StoryVm.OBJECT))
		"interface_interaction":
			var level := StoryVm.as_int(stack.back())
			var world: Object = terrain.get_ref() if terrain else null
			if not level in [0, 1, 4, 13, 14, 15] or not is_instance_valid(world):
				return {"ok":false}
			world.story_interface_level = level
		"intro_movie":
			var world: Object = terrain.get_ref() if terrain else null
			if StoryVm.as_int(stack[stack.size() - count]) != 1 or StoryVm.as_int(stack.back()) != 1 or not is_instance_valid(world) or not world.has_method("story_play_intro_movie"):
				return {"ok":false}
			if not world.story_play_intro_movie():
				return {"ok":false}
			return {"ok":true,"pop":count,"push":result,"yield_task":true}
		"delete_script_actor":
			var actor_handle := StoryVm.as_int(stack[stack.size() - count])
			var actor := _object(stack[stack.size() - count]) as Node3D
			var mode := StoryVm.as_int(stack.back())
			var world: Object = terrain.get_ref() if terrain else null
			if mode not in [0, 1] or not is_instance_valid(world):
				return {"ok":false}
			# The native consumes an already-invalid handle without another delete.
			if actor == null: return {"ok":true,"pop":count,"push":[]}
			if mode == 1 and (not actor is Thing or actor.kind != "villager"): return {"ok":false}
			if not world.story_delete_object(actor, mode == 1):
				return {"ok":false}
			_objects.erase(actor_handle)
			_object_types.erase(actor_handle)
		"shark_walk_path":
			var p := stack.size() - count
			var actor := _object(stack[p])
			var path := StoryVm.as_int(stack[p + 2])
			var first := StoryVm.as_float(stack[p + 3])
			var last := StoryVm.as_float(stack[p + 4])
			var forwards := StoryVm.as_int(stack[p + 1]) != 0
			if not is_instance_valid(actor):
				return {"ok":false}
			if actor.has_method("walk_track"):
				if not actor.walk_track(camera_editor, path, first, last, forwards):
					return {"ok":false}
			elif actor is Thing and path == 22 and first == 0.0 and last == 1.0 and forwards:
				var track := preload("res://scripts/story_shark.gd").read_track(camera_editor, path)
				if track.is_empty() or not actor.set_script_path(track["points"]):
					return {"ok":false}
			else:
				return {"ok":false}
		"script_sound":
			var p := stack.size() - count
			var sound_id := StoryVm.as_int(stack[p])
			var position := _vector(stack, p + 2)
			var world: Object = terrain.get_ref() if terrain else null
			var spatial := StoryVm.as_int(stack.back()) != 0
			var bank := StoryVm.as_int(stack[p + 1])
			if not bank in [1, 5] or not position.is_finite():
				return {"ok":false}
			if not is_instance_valid(world) or not world.has_method("story_play_sfx") or not world.story_play_sfx(sound_id, position, spatial, bank):
				return {"ok":false}
		"game_thing_clicked":
			var target := _object(stack.back())
			var clicked: Object = clicked_thing.get_ref() if clicked_thing != null else null
			result.append(StoryVm.integer(int(is_instance_valid(target) and target == clicked), StoryVm.BOOL))
		"clear_clicked_object":
			clicked_thing = null
		"stone_sparkles":
			var p := stack.size() - count
			var stone := _object(stack[p + 1]) as Thing
			var duration := StoryVm.as_float(stack.back())
			var world: Object = terrain.get_ref() if terrain else null
			if StoryVm.as_int(stack[p]) == 34 and is_instance_valid(stone) and is_instance_valid(world) and is_finite(duration) and (duration >= 0.0 or duration == -1.0):
				var attached: Node3D = world.story_highlight_object(stone, duration)
				if attached == null: return {"ok":false}
				return {"ok":true,"pop":count,"push":[StoryVm.integer(register_object(attached), StoryVm.OBJECT)]}
			if StoryVm.as_int(stack[p]) != 10 or not is_instance_valid(stone) or stone.kind != "rock" or not is_finite(duration) or duration <= 0.0:
				return {"ok":false}
			if not is_instance_valid(world) or not world.has_method("story_spawn_stone_sparkles"):
				return {"ok":false}
			var effect: Node3D = world.story_spawn_stone_sparkles(stone, duration)
			if effect == null:
				return {"ok":false}
			result.append(StoryVm.integer(register_object(effect), StoryVm.OBJECT))
		"position_sparkles":
			var p := stack.size() - count
			var point := _vector(stack, p + 1)
			var seconds := StoryVm.as_float(stack.back())
			var world: Object = terrain.get_ref() if terrain else null
			if StoryVm.as_int(stack[p]) != 10 or not point.is_finite() or not is_finite(seconds) or seconds <= 0.0 or not is_instance_valid(world):
				return {"ok":false}
			var effect: Node3D = world.story_spawn_position_sparkles(point, seconds)
			if effect == null: return {"ok":false}
			result.append(StoryVm.integer(register_object(effect), StoryVm.OBJECT))
		"intro_actor":
			var p := stack.size() - count
			var actor := _object(stack.back()) as Thing
			if is_instance_valid(actor) and StoryVm.as_int(stack[p + 1]) == 19:
				# THING_JC_SPECIAL 19 calls Game3DObject::SetDisappear(false).
				actor.show()
				return {"ok":true,"pop":count,"push":result}
			if not is_instance_valid(actor) or not actor.has_meta("story_villager_subtype"):
				return {"ok":false}
			match StoryVm.as_int(stack[p + 1]):
				7:
					# The original only overrides the position while the intro renderer is active.
					actor.set_meta("story_intro_actor", true)
				8:
					actor.story_smooth_heading = StoryVm.as_int(stack[p]) != 0
				9:
					actor.rotation.y = -actor.rotation.y
					actor.story_smooth_heading = false
				_:
					return {"ok":false}
		"story_voice":
			var p := stack.size() - count
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_play_voice"):
				return {"ok":false}
			var text_enum := StoryVm.as_int(stack[p + 1])
			if id == 458:
				result.append(StoryVm.integer(int(world.story_voice_playing(text_enum)), StoryVm.BOOL))
			elif StoryVm.as_int(stack.back()) != 0 or not world.story_play_voice(text_enum):
				return {"ok":false}
		"villager_script_animation":
			var p := stack.size() - count
			var target := _object(stack[p])
			if id == 17 and target is StoryFlock and StoryVm.as_int(stack[p + 1]) == 244:
				target.crowd_mode = true
				return {"ok":true,"pop":count,"push":result}
			var villager := target as Thing
			if not is_instance_valid(villager) or villager.kind != "villager":
				return {"ok":false}
			match id:
				17: # ScriptPlayAnim or bounded ScriptWanderAroundPos adapter.
					var parameters: Vector2i = villager.get_meta("script_unsigned", Vector2i(-1, -1))
					match StoryVm.as_int(stack[p + 1]):
						200:
							if (parameters.y < 1 and parameters.y != -1) or not _ensure_villager_script_animation(parameters.x): return {"ok":false}
							if not villager.prepare_script_animation(_villager_script_animations, parameters.x, parameters.y) or not villager.play_script_animation(): return {"ok":false}
						199:
							if not villager.set_script_wander(villager.get_meta("script_position", Vector3.INF), float(villager.get_meta("script_float", -1.0)), parameters.x, parameters.y): return {"ok":false}
						_:
							return {"ok":false}
				18:
					var point := _vector(stack, p + 1)
					if not point.is_finite(): return {"ok":false}
					villager.set_meta("script_position", point)
				19:
					var value := StoryVm.as_float(stack[p + 1])
					if not is_finite(value): return {"ok":false}
					villager.set_meta("script_float", value)
				20: # SET_SCRIPT_ULONG, animation ID and repeat count
					var animation := StoryVm.as_int(stack[p + 1])
					var repeats := StoryVm.as_int(stack[p + 2])
					if animation < 0 or repeats < -1:
						return {"ok":false}
					villager.set_meta("script_unsigned", Vector2i(animation, repeats))
				64: # PLAYED
					result.append(StoryVm.integer(int(not villager.is_script_animation_playing()), StoryVm.BOOL))
				68: # OVERRIDE_STATE_ANIMATION
					var animation := StoryVm.as_int(stack[p + 1])
					if not _ensure_villager_script_animation(animation):
						return {"ok":false}
					if not villager.override_script_move_animation(_villager_script_animations, animation):
						return {"ok":false}
		"story_music":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_music_cue"):
				return {"ok":false}
			if not world.story_music_cue(StoryVm.as_int(stack.back()) if id == 44 else 0):
				return {"ok":false}
		"screen_fade":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_fade"):
				return {"ok":false}
			if id == 243:
				result.append(StoryVm.integer(int(world.story_fade_finished()), StoryVm.BOOL))
			else:
				var seconds := StoryVm.as_float(stack.back())
				if not is_finite(seconds) or seconds < 0.0:
					return {"ok":false}
				var color := Color.BLACK
				if id == 241:
					var p := stack.size() - count
					color = Color(StoryVm.as_float(stack[p]), StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2]))
				if not Vector3(color.r, color.g, color.b).is_finite():
						return {"ok":false}
				world.story_fade(id == 241, color, seconds)
		"dialogue_control":
			var task := int(context.get("task", 0))
			if task <= 0:
				return {"ok":false}
			if id == 120:
				if dialogue_owner == 0:
					dialogue_owner = task
				result.append(StoryVm.integer(int(dialogue_owner == task), StoryVm.BOOL))
			elif id == 122:
				# Installed native 0x710830 returns !IsDialogueControlled().
				# A query must not acquire or release the dialogue lock.
				result.append(StoryVm.integer(int(dialogue_owner == 0), StoryVm.BOOL))
			elif dialogue_owner == task:
				dialogue_owner = 0
		"widescreen":
			var world: Object = terrain.get_ref() if terrain else null
			var task := int(context.get("task", 0))
			if task <= 0 or not is_instance_valid(world) or not world.has_method("story_set_widescreen"):
				return {"ok":false}
			var enabled := StoryVm.as_int(stack.back()) != 0
			if widescreen_owner == 0 and enabled:
				widescreen_owner = task
				world.story_set_widescreen(true)
			elif widescreen_owner == task and not enabled:
				widescreen_owner = 0
				world.story_set_widescreen(false)
		"alignment_music":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_set_alignment_music"):
				return {"ok":false}
			world.story_set_alignment_music(StoryVm.as_int(stack.back()) != 0)
		"bookmark_switch":
			var command := StoryVm.as_int(stack.back())
			if command == 14 or command == 15:
				camera_shortcuts_enabled = command == 14
			elif command in [0, 1, 2, 4, 5]:
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world) or not world.has_method("story_intro_effect") or not world.story_intro_effect(command):
					return {"ok":false}
			elif command != 18: # Outside the original command table, which ignores it.
				return {"ok":false}
		"move_game_thing":
			var start := stack.size() - count
			var actor := _object(stack[start])
			var target := _vector(stack, start + 1)
			var radius := StoryVm.as_float(stack[start + 4])
			if actor is StoryFlock and target.is_finite() and radius == 0.0:
				actor.position = target
			elif not actor is Thing or not actor.set_script_move(target, radius):
				return {"ok":false}
		"set_focus":
			var start := stack.size() - count
			var target := _object(stack[start])
			var point := _vector(stack, start + 1)
			if target is StoryFlock and point.is_finite():
				for member in target.members:
					if is_instance_valid(member):
						member.set_script_focus(point)
			elif not target is Thing or not target.set_script_focus(point):
				return {"ok":false}
		"set_high_graphics_detail":
			var villager := _object(stack.back()) as Thing
			if villager == null or villager.kind != "villager":
				return {"ok":false}
			if not villager.set_story_high_detail(StoryVm.as_int(stack[stack.size() - count]) != 0):
				return {"ok":false}
		"singing_stone_interaction":
			var stone := _object(stack.back()) as Thing
			if not is_instance_valid(stone) or not int(stone.get_meta("story_mobile_subtype", -1)) in [5, 49, 50, 52]:
				return {"ok":false}
			var allowed := StoryVm.as_int(stack[stack.size() - 2]) != 0
			if id == 168:
				stone.story_move_allowed = allowed
			else:
				stone.story_pickup_allowed = allowed
		"script_camera":
			return camera.invoke(id, stack, context) if camera != null else {"ok":false}
		"script_camera_path":
			if camera == null or not camera.run_path(camera_editor, StoryVm.as_int(stack.back()), int(context.get("task", 0))):
				return {"ok":false}
		"indestructible":
			var actor := _object(stack.back()) as Thing
			if actor == null: return {"ok":false}
			actor.story_indestructible = StoryVm.as_int(stack[stack.size() - count]) != 0
		"weather_properties":
			var p := stack.size() - count
			var zone := _object(stack[p]) as Node3D
			var world: Object = terrain.get_ref() if terrain else null
			if zone == null or not is_instance_valid(world) or not world.story_weather.has(zone): return {"ok":false}
			match id:
				123:
					if not zone.set_weather(StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 3]), StoryVm.as_float(stack[p + 4]), StoryVm.as_float(stack[p + 5])): return {"ok":false}
				124:
					# This episode explicitly disables both kinds of lightning.
					# Nonzero lightning requests remain unsupported, not swallowed.
					for i in range(p + 1, stack.size()):
						if StoryVm.as_float(stack[i]) != 0.0: return {"ok":false}
					zone.set_meta("lightning_disabled", true)
				125:
					if not zone.set_lifetime(StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2])): return {"ok":false}
				126:
					var clouds := StoryVm.as_float(stack[p + 1])
					if not is_finite(clouds) or clouds < 0.0 or clouds > 32.0: return {"ok":false}
					if not zone.set_clouds(int(clouds), StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 3])): return {"ok":false}
				131:
					return {"ok":false}
		"weather_wind":
			var zone := _object(stack.back()) as Node3D
			var world: Object = terrain.get_ref() if terrain else null
			if zone == null or not is_instance_valid(world) or not world.story_weather.has(zone): return {"ok":false}
			zone.set_wind_affected(StoryVm.as_int(stack[stack.size() - count]) != 0)
		"follow_camera_object":
			var target := _object(stack[stack.size() - count]) as Thing
			if camera == null or not is_instance_valid(target) or target.kind != "villager" or target.rig == null:
				return {"ok":false}
			var distance := StoryVm.as_float(stack.back())
			var half_height := target.rig.bounds.size.y * absf(target.scale.y) * 0.5
			if not camera.follow(target, distance, half_height, int(context.get("task", 0))):
				return {"ok":false}
		"focus_follow_object":
			var target := _object(stack.back()) as Node3D
			var half_height: float = target.rig.bounds.size.y * absf(target.scale.y) * 0.5 if target is Thing and target.rig != null else 0.0
			if camera == null or target == null or not camera.follow_focus(target, int(context.get("task", 0)), half_height):
				return {"ok":false}
		"set_camera_zone":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("story_set_camera_zone"):
				return {"ok":false}
			if not world.story_set_camera_zone(StoryVm.as_int(stack.back())):
				return {"ok":false}
		"script_time":
			return game_time.invoke(id, stack, context) if game_time != null else {"ok":false}
		"script_timer":
			var timer_reply := _invoke_timer(id, stack, stack.size() - count, context)
			if not timer_reply.get("ok", false):
				return timer_reply
			result.assign(timer_reply["push"])
		"flock_create":
			var position := _vector(stack, stack.size() - count)
			if not position.is_finite():
				return {"ok":false}
			var flock := StoryFlock.new()
			flock.name = "StoryFlock%d" % _next_object
			flock.position = position
			var world: Object = terrain.get_ref() if terrain else null
			if world is Node3D:
				world.add_child(flock)
			_created_flocks.append(flock)
			result.append(StoryVm.integer(register_object(flock), StoryVm.OBJECT))
		"flock_attach", "flock_detach":
			var p := stack.size() - count
			var villager := _object(stack[p]) as Thing
			var container := _object(stack[p + 1])
			if count == 3 and (not is_instance_valid(villager) or not is_instance_valid(container)):
				# Original FLOCK_ATTACH pushes an empty object on either null
				# handle. HeadingHome can reach this after the source deletes an actor.
				result.append(StoryVm.integer(0, StoryVm.OBJECT))
				return {"ok":true,"pop":count,"push":result}
			if not is_instance_valid(villager) or villager.kind != "villager" or not is_instance_valid(container):
				return {"ok":false}
			if count == 3 and container is Node3D and container.has_meta("town_index"):
				if StoryVm.as_int(stack[p + 2]) != 0:
					return {"ok": false}
				if is_instance_valid(villager.story_flock):
					villager.story_flock.detach(villager)
				villager.town = int(container.get_meta("town_index"))
				villager.home = container.position
				result.append(StoryVm.integer(StoryVm.as_int(stack[p + 1]), StoryVm.OBJECT))
				return {"ok": true, "pop": count, "push": result}
			var flock := container as StoryFlock
			if not is_instance_valid(flock):
				return {"ok": false}
			if count == 3:
				flock.attach(villager, StoryVm.as_int(stack[p + 2]) != 0)
				result.append(StoryVm.integer(StoryVm.as_int(stack[p + 1]), StoryVm.OBJECT))
			else:
				if not flock.detach(villager):
					return {"ok":false}
				result.append(StoryVm.integer(StoryVm.as_int(stack[p]), StoryVm.OBJECT))
		"flock_disband":
			var flock := _object(stack.back()) as StoryFlock
			if not is_instance_valid(flock):
				return {"ok":false}
			_created_flocks.erase(flock)
			flock.disband()
			flock.free()
		"flock_spacing":
			var p := stack.size() - count
			var target := _object(stack[p])
			var inner := StoryVm.as_float(stack[p + 1])
			var outer := StoryVm.as_float(stack[p + 2])
			var mode := StoryVm.as_float(stack[p + 3])
			var world: Object = terrain.get_ref() if terrain else null
			var weather: Variant = world.get("story_weather") if is_instance_valid(world) else null
			if weather is Array and weather.has(target):
				if mode != 0.0 or not target.set_radii(inner, outer): return {"ok":false}
				return {"ok":true,"pop":count,"push":[]}
			var flock := target as StoryFlock
			if not is_instance_valid(flock) or not is_finite(inner) or not is_finite(outer) or mode != 0.0:
				return {"ok":false}
			if inner < 0.0 or inner > 65535.0 or outer < 0.0 or outer > 65535.0:
				return {"ok":false}
			var next_inner := floorf(inner) if inner != 0.0 else flock.inner_radius
			var next_outer := floorf(outer) if outer != 0.0 else flock.outer_radius
			if next_inner > next_outer:
				return {"ok":false}
			flock.inner_radius = next_inner
			flock.outer_radius = next_outer
		"convert_camera_record":
			var point: Variant = _camera_record(StoryVm.as_int(stack.back()), id == 82)
			if point == null:
				return {"ok":false}
			result.append(StoryVm.number(point.x, StoryVm.VECTOR))
			result.append(StoryVm.number(point.y, StoryVm.VECTOR))
			result.append(StoryVm.number(point.z, StoryVm.VECTOR))
		"get_position":
			var object_id: int = int(stack.back()["bits"])
			var object: Object = _objects[object_id].get_ref() if _objects.has(object_id) else null
			var position := Vector3.ZERO
			if is_instance_valid(object) and object is Node3D:
				position = object.global_position if object.is_inside_tree() else object.position
			# The island is mirrored on Z in the Godot scene.
			result.append(StoryVm.number(position.x, StoryVm.VECTOR))
			result.append(StoryVm.number(position.y, StoryVm.VECTOR))
			result.append(StoryVm.number(-position.z, StoryVm.VECTOR))
		"set_position":
			var p := stack.size() - count
			var actor := _object(stack[p]) as Thing
			var point := _vector(stack, p + 1)
			if not is_instance_valid(actor) or actor.kind not in ["villager", "gate_key"] or not point.is_finite():
				return {"ok":false}
			actor.position = point
		"distance":
			var p := stack.size() - count
			var a := Vector3(StoryVm.as_float(stack[p]), StoryVm.as_float(stack[p + 1]), StoryVm.as_float(stack[p + 2]))
			var b := Vector3(StoryVm.as_float(stack[p + 3]), StoryVm.as_float(stack[p + 4]), StoryVm.as_float(stack[p + 5]))
			if not a.is_finite() or not b.is_finite():
				return {"ok":false}
			# Original LHVM compares horizontal positions and snaps under 0.5 to zero.
			var distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			result.append(StoryVm.number(distance if distance >= 0.5 else 0.0))
		"exact_landmark":
			# Only the observed, unambiguous first-island use is supported.
			# Every other search blocks instead of guessing original behaviour.
			var p := stack.size() - count
			var rule: Dictionary = {}
			for candidate in Data.STORY_SEARCH_RULES.values():
				if int(candidate["object_type"]) == StoryVm.as_int(stack[p]):
					rule = candidate
					break
			if rule.is_empty():
				return {"ok":false}
			if StoryVm.as_int(stack[p]) != int(rule["object_type"]) or StoryVm.as_int(stack[p + 1]) != int(rule["any_subtype"]) or StoryVm.as_int(stack[p + 5]) != 0:
				return {"ok":false}
			var point := Vector2(StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 4]))
			if not point.is_finite() or not is_finite(StoryVm.as_float(stack[p + 3])):
				return {"ok":false}
			# FollowUs locates the same abode as SetupLand1 from a nearby point.
			if int(rule["object_type"]) == 2 and point.distance_to(Vector2(1714.962, 2593.09)) <= float(rule["position_tolerance"]):
				point = Vector2(1713.83, 2592.59)
			var matches: Array[int] = []
			for object_id in _object_types:
				if _object_types[object_id] != int(rule["object_type"]):
					continue
				var object: Object = _objects[object_id].get_ref()
				if not is_instance_valid(object) or not object is Node3D:
					continue
				var position: Vector3 = object.global_position if object.is_inside_tree() else object.position
				if Vector2(position.x, -position.z).distance_to(point) <= float(rule["position_tolerance"]):
					matches.append(object_id)
			if matches.size() != 1:
				return {"ok":false}
			result.append(StoryVm.integer(matches[0], StoryVm.OBJECT))
		"create_marker":
			var rule: Dictionary = Data.STORY_CREATE_RULES["create_marker"]
			var p := stack.size() - count
			var object_type := StoryVm.as_int(stack[p])
			var subtype := StoryVm.as_int(stack[p + 1])
			var position := Vector3(StoryVm.as_float(stack[p + 2]), StoryVm.as_float(stack[p + 3]), -StoryVm.as_float(stack[p + 4]))
			if not position.is_finite():
				return {"ok":false}
			if object_type == 15 and subtype == 2:
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world): return {"ok":false}
				var zone: Node3D = world.story_create_weather(position)
				if zone == null: return {"ok":false}
				result.append(StoryVm.integer(register_object(zone, 15), StoryVm.OBJECT))
				return {"ok":true,"pop":count,"push":result}
			if object_type == 26 and subtype == 5000:
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world) or not world.has_method("story_create_shark"):
					return {"ok":false}
				var shark: Node3D = world.story_create_shark(position)
				if shark == null:
					return {"ok":false}
				result.append(StoryVm.integer(register_object(shark, object_type), StoryVm.OBJECT))
				return {"ok":true,"pop":count,"push":result}
			if object_type == 4:
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world) or not world.has_method("story_create_villager"):
					return {"ok":false}
				var villager: Node3D = world.story_create_villager(subtype, position)
				if not is_instance_valid(villager):
					return {"ok":false}
				result.append(StoryVm.integer(register_object(villager, object_type), StoryVm.OBJECT))
				return {"ok":true,"pop":count,"push":result}
			if object_type == 8:
				var world: Object = terrain.get_ref() if terrain else null
				if not is_instance_valid(world) or not world.has_method("story_create_singing_stone"):
					return {"ok":false}
				var stone: Node3D = world.story_create_singing_stone(subtype, position)
				if not is_instance_valid(stone):
					return {"ok":false}
				stone.set_meta("story_mobile_subtype", subtype)
				result.append(StoryVm.integer(register_object(stone, object_type), StoryVm.OBJECT))
				return {"ok":true,"pop":count,"push":result}
			if object_type != int(rule["object_type"]) or subtype != int(rule["subtype"]) or _created_markers.size() >= int(rule["maximum_created"]):
				return {"ok":false}
			var marker := Node3D.new()
			marker.position = position
			_created_markers.append(marker)
			result.append(StoryVm.integer(register_object(marker, int(rule["object_type"])), StoryVm.OBJECT))
		"random_range":
			var lo := StoryVm.as_float(stack[stack.size() - 2])
			var hi := StoryVm.as_float(stack.back())
			if not is_finite(lo) or not is_finite(hi):
				return {"ok":false}
			result.append(StoryVm.number(lo + (hi - lo) * _random.randf()))
		"land_height":
			var world: Object = terrain.get_ref() if terrain else null
			if not is_instance_valid(world) or not world.has_method("ground_y"):
				return {"ok":false}
			var x := StoryVm.as_float(stack[stack.size() - 3])
			var z := StoryVm.as_float(stack[stack.size() - 1])
			if not is_finite(x) or not is_finite(z):
				return {"ok":false}
			# Original island coordinates use +Y across the map; Godot uses -Z.
			var height: float = world.ground_y(Vector3(x, 0, -z))
			if not is_finite(height):
				return {"ok":false}
			result.append(StoryVm.number(height))
		"thing_valid":
			var object_id: int = int(stack.back()["bits"])
			var valid := object_id != 0 and _objects.has(object_id) and is_instance_valid(_objects[object_id].get_ref())
			result.append(StoryVm.integer(int(valid), StoryVm.BOOL))
		"square_root":
			var value := StoryVm.as_float(stack.back())
			if not is_finite(value):
				return {"ok":false}
			result.append(StoryVm.number(sqrt(value) if value > 0.0 else 0.0))
		"skip_tutorial", "skip_creature_training":
			# This preservation build always starts with original training enabled.
			result.append(StoryVm.integer(0, StoryVm.BOOL))
		"keep_old_creature":
			result.append(StoryVm.integer(int(keep_old_creature), StoryVm.BOOL))
		"profile_has_creature":
			result.append(StoryVm.integer(int(profile_has_creature), StoryVm.BOOL))
		_:
			var reply := _invoke_world(str(row["handler"]), stack, stack.size() - count)
			if reply.is_empty():
				return {"ok":false}
			result = reply["result"]
	if result.size() != int(row["returns"]):
		return {"ok":false}
	return {"ok":true,"pop":count,"push":result}


# Calls that change or read the living island. Arguments arrive in the order the
# original script pushed them; anything outside the documented scope blocks.
func _invoke_world(handler: String, stack: Array, p: int) -> Dictionary:
	var world: Object = terrain.get_ref() if terrain else null
	if not is_instance_valid(world) or not world.has_method("story_add_influence"):
		return {}
	var rules: Dictionary = Data.PORT_RULES["story"]
	var player := int(rules["player_one"])
	var result: Array[Dictionary] = []
	match handler:
		"set_virtual_influence":
			# SET_VIRTUAL_INFLUENCE pops player, then enable.
			if int(round(StoryVm.as_float(stack[p + 1]))) != player:
				return {}
			world.story_set_virtual_influence(StoryVm.as_int(stack[p]) != 0)
		"influence_object":
			var object := _object(stack[p])
			var radius := StoryVm.as_float(stack[p + 1])
			if not object is Node3D or not is_finite(radius) or radius <= 0.0 or StoryVm.as_int(stack[p + 2]) != 0:
				return {}
			var handle: Node3D = world.story_add_influence(object.global_position if object.is_inside_tree() else object.position, radius, StoryVm.as_int(stack[p + 3]) != 0)
			handle.set_meta("follow_target", weakref(object))
			result.append(StoryVm.integer(register_object(handle, -2), StoryVm.OBJECT))
		"influence_position":
			var position := _vector(stack, p)
			var radius := StoryVm.as_float(stack[p + 3])
			if not position.is_finite() or not is_finite(radius) or radius <= 0.0 or StoryVm.as_int(stack[p + 4]) != 0:
				return {}
			var handle: Node3D = world.story_add_influence(position, radius, StoryVm.as_int(stack[p + 5]) != 0)
			result.append(StoryVm.integer(register_object(handle, -2), StoryVm.OBJECT))
		"call_near":
			# CALL_NEAR: type, subtype, position, radius, excluding scripted.
			var object_type := StoryVm.as_int(stack[p])
			var subtype := StoryVm.as_int(stack[p + 1])
			var is_town := object_type == int(rules["town_object_type"]) and subtype == 5000
			var is_mobile_static := object_type == 8 and subtype in [5, 49, 50, 52]
			var is_citadel := object_type == 18 and subtype == 5000
			var is_highlight := object_type == 37 and subtype in [0, 1, 2, 3]
			var is_rock: bool = object_type == 33 and (subtype == 5000 or not world.host_info.record(subtype).is_empty())
			var is_pillar := object_type == 3 and subtype == 34
			if not (is_town or is_mobile_static or is_citadel or is_highlight or is_rock or is_pillar) or StoryVm.as_int(stack[p + 6]) != 0:
				return {}
			var centre := _vector(stack, p + 2)
			var radius := StoryVm.as_float(stack[p + 5])
			if not centre.is_finite() or not is_finite(radius) or radius <= 0.0:
				return {}
			var best := 0
			var best_distance := radius
			for object_id in _object_types:
				if _object_types[object_id] != object_type and not (is_rock and _object_types[object_id] == 8):
					continue
				var town: Object = _objects[object_id].get_ref()
				if not town is Node3D:
					continue
				if is_mobile_static and town.get_meta("story_mobile_subtype", -1) != subtype:
					continue
				if is_rock and (not town is Thing or town.kind != "rock" or (subtype != 5000 and town.get_meta("story_mobile_subtype", -1) != subtype)):
					continue
				if is_pillar and town.get_meta("original_type", "") != "Pilar3 Lime":
					continue
				if is_highlight and town.get_meta("highlight_type", -1) != subtype:
					continue
				var d := Vector2(town.position.x - centre.x, town.position.z - centre.z).length()
				if d <= best_distance:
					best_distance = d
					best = object_id
			result.append(StoryVm.integer(best, StoryVm.OBJECT))
		"set_town_desire_boost":
			var town := _town(stack[p])
			var boost := StoryVm.as_float(stack[p + 2])
			if town < 0 or not is_finite(boost):
				return {}
			world.story_set_desire_boost(town, StoryVm.as_int(stack[p + 1]), boost)
		"belief_for_player":
			var town := _town(stack[p])
			if town < 0 or int(round(StoryVm.as_float(stack[p + 1]))) != player:
				return {}
			result.append(StoryVm.number(world.story_belief(town) / float(rules["belief_scale"])))
		"get_influence":
			var position := _vector(stack, p + 2)
			if not is_equal_approx(StoryVm.as_float(stack[p]), float(player)) or not position.is_finite():
				return {}
			result.append(StoryVm.number(world.story_influence_strength(position, StoryVm.as_int(stack[p + 1]) != 0)))
		"set_player_belief":
			var town := _town(stack[p])
			var belief := StoryVm.as_float(stack[p + 2])
			if town < 0 or int(round(StoryVm.as_float(stack[p + 1]))) != player or not is_finite(belief) or belief < 0.0:
				return {}
			world.story_set_belief(town, belief * float(rules["belief_scale"]))
		"create_highlight":
			var position := _vector(stack, p + 1)
			if not position.is_finite():
				return {}
			var highlight: Node3D = world.story_create_highlight(StoryVm.as_int(stack[p]), position, StoryVm.as_int(stack[p + 4]))
			if highlight == null:
				return {}
			result.append(StoryVm.integer(register_object(highlight, 37), StoryVm.OBJECT))
		"highlight_properties":
			var highlight := _object(stack[p])
			if not highlight is Node3D or not highlight.has_meta("highlight_type"):
				return {}
			highlight.set_meta("help_text", StoryVm.as_int(stack[p + 1]))
			highlight.set_meta("help_category", StoryVm.as_int(stack[p + 2]))
		"get_property", "set_property":
			var property := StoryVm.as_int(stack[p])
			var target := _object(stack[p + 1])
			# Checked GET_PROPERTY returns a numeric zero for a missing/deleted
			# handle before dispatching the property. Writes remain unsupported.
			if handler == "get_property" and target == null:
				result.append(StoryVm.number(0.0))
				return {"result":result}
			if target is Thing and property == 1:
				if handler == "get_property":
					result.append(StoryVm.number(0.0 if target.state == Thing.State.DEAD else target.story_health))
				elif target.kind != "villager" or not target.set_story_health(StoryVm.as_float(stack[p + 2])):
					return {}
				return {"result":result}
			if handler == "set_property" and target is Thing and property == 24:
				var altitude := StoryVm.as_float(stack[p + 2])
				if not is_finite(altitude): return {}
				target.position.y = world.ground_y(target.position) + altitude
				return {"result":result}
			if handler == "get_property" and target is Node3D and not target.has_meta("highlight_type") and property in [23, 24, 25]:
				var point: Vector3 = target.global_position if target.is_inside_tree() else target.position
				result.append(StoryVm.number(point.x if property == 23 else (point.y if property == 24 else -point.z)))
				return {"result":result}
			# ScriptEnums.h: FLYING=5, IN_HAND=9. Gate-key protection observes
			# actual physical state instead of assuming the keys remain on the ground.
			if handler == "get_property" and target is Thing and property in [5, 6, 9]:
				var active: bool = target.story_drowning if property == 6 else target.state == (Thing.State.FLYING if property == 5 else Thing.State.HELD)
				result.append(StoryVm.number(float(active)))
				return {"result":result}
			if is_instance_valid(target) and target.has_meta("story_citadel") and property == 22:
				if handler == "get_property":
					result.append(StoryVm.number(target.progress))
				else:
					var progress := StoryVm.as_float(stack[p + 2])
					if not is_finite(progress):
						return {}
					target.set_progress(progress)
				return {"result":result}
			if target is Thing and target.has_meta("story_villager_subtype") and (property in [8, 11] or (property == 16 and target.get_meta("story_villager_subtype") == 52)):
				if handler == "get_property":
					match property:
						8: result.append(StoryVm.number(target.scale.x))
						11: result.append(StoryVm.number(maxf(0.0, target.story_speed_per_turn)))
						16: result.append(StoryVm.number(target.story_age))
				else:
					var value := StoryVm.as_float(stack[p + 2])
					if property == 16:
						if not is_equal_approx(value, 8.0) or not target.set_story_child_age(8):
							return {}
					elif not is_finite(value) or value < 0.0 or (value == 0.0 and property != 11):
						return {}
					elif property == 11:
						target.story_speed_per_turn = value
					else:
						target.scale = Vector3.ONE * value
				return {"result":result}
			if not property in rules["highlight_property_ids"] or not target is Node3D or not target.has_meta("highlight_type"):
				return {}
			var key := "property_%d" % property
			if handler == "get_property":
				result.append(StoryVm.number(float(target.get_meta(key, 0.0))))
			else:
				var value := StoryVm.as_float(stack[p + 2])
				if not is_finite(value):
					return {}
				target.set_meta(key, value)
				if property == 24 and target.has_method("set_draw_height"):
					target.set_draw_height(value)
		"release_from_script":
			var object := _object(stack[p])
			if object == null:
				return {"result":result}
			if object is Thing:
				object.release_script_control()
		_:
			return {}
	return {"result":result}


func _object(value: Dictionary) -> Object:
	var object_id := int(value["bits"])
	if not _objects.has(object_id):
		return null
	var object: Object = _objects[object_id].get_ref()
	if is_instance_valid(object) and object is Node and object.get_meta("story_deleted", false): return null
	return object if is_instance_valid(object) else null


func _load_villager_script_animations() -> bool:
	if _villager_script_animations != null:
		return true
	var reader := AnmReader.new()
	var indices := PackedInt32Array(FOLLOW_US_ANIMATIONS + FOLLOW_US_MOVE_ANIMATIONS)
	if not reader.load_file(villager_animation_path, [], indices):
		return false
	_villager_script_animations = reader
	return true


func _ensure_villager_script_animation(index: int) -> bool:
	if index < 0 or not _load_villager_script_animations():
		return false
	if _villager_script_animations.names_by_index.has(index):
		return true
	var additional := AnmReader.new()
	if not additional.load_file(villager_animation_path, [], PackedInt32Array([index])):
		return false
	var clip: String = additional.names_by_index[index]
	_villager_script_animations.names_by_index[index] = clip
	_villager_script_animations.clips[clip] = additional.clips[clip]
	return true


func _town(value: Dictionary) -> int:
	var town := _object(value)
	return int(town.get_meta("town_index", -1)) if town is Node3D else -1


func _invoke_timer(id: int, stack: Array, p: int, context: Dictionary) -> Dictionary:
	if not context.has("tick"):
		return {"ok":false}
	var now := float(context["tick"]) / float(Data.STORY_VM["core"]["tick_rate"])
	var timer: Object
	if id != 146:
		timer = _object(stack[p])
		if not timer is RefCounted or not _timers.has(timer):
			return {"ok":false}
	if id == 145 or id == 146:
		var duration := StoryVm.as_float(stack.back())
		if not is_finite(duration) or duration < 0.0:
			return {"ok":false}
		if id == 146:
			timer = RefCounted.new()
			_timers.append(timer)
		timer.set_meta("started", now)
		timer.set_meta("duration", duration)
		if id == 146:
			return {"ok":true,"push":[StoryVm.integer(register_object(timer), StoryVm.OBJECT)]}
		return {"ok":true,"push":[]}
	var elapsed := maxf(0.0, now - float(timer.get_meta("started")))
	var value := maxf(0.0, float(timer.get_meta("duration")) - elapsed) if id == 147 else elapsed
	return {"ok":true,"push":[StoryVm.number(value)]}


func _camera_record(camera_id: int, use_focus: bool) -> Variant:
	const RECORD_SIZE := 68
	const PAYLOAD_SIZE_OFFSET := 32
	const EYE_OFFSET := 36
	const FOCUS_OFFSET := 48
	if camera_editor.size() < RECORD_SIZE or camera_editor.slice(0, 14).get_string_from_ascii() != "LiOnHeAdEDITOR":
		return null
	var name_bytes := ("Cam%d" % camera_id).to_ascii_buffer()
	var record_point: Variant = null
	var field_offset := FOCUS_OFFSET if use_focus else EYE_OFFSET
	for offset in range(14, camera_editor.size() - RECORD_SIZE + 1):
		if camera_editor[offset] != name_bytes[0] or camera_editor[offset + name_bytes.size()] != 0:
			continue
		if camera_editor.slice(offset, offset + name_bytes.size()) != name_bytes or camera_editor.decode_u32(offset + PAYLOAD_SIZE_OFFSET) != 32:
			continue
		var point := Vector3(
			camera_editor.decode_float(offset + field_offset),
			camera_editor.decode_float(offset + field_offset + 4),
			camera_editor.decode_float(offset + field_offset + 8))
		if record_point != null or not point.is_finite():
			return null
		record_point = point
	return record_point


# Original vectors use +Y across the map; the Godot island runs along -Z.
func _vector(stack: Array, p: int) -> Vector3:
	return Vector3(StoryVm.as_float(stack[p]), StoryVm.as_float(stack[p + 1]), -StoryVm.as_float(stack[p + 2]))

