extends RefCounted

const RECORD_SIZE := 124
const ACTION_PRESSED := 3
const ACTION_RELEASED := 4
const MAP_COORD_TO_METRES := 10.0 / 65536.0
var frames: Array[Dictionary] = []
var frame := 0
var elapsed := 0.0
var trigger_pending := false
var playing := false
var action_button_down := false
var action_press_count := 0
var action_release_count := 0
var _action_pressed_time := 0.0
var _actions: Array[Dictionary] = []


func start(bytes: PackedByteArray) -> bool:
	if bytes.is_empty() or bytes.size() % RECORD_SIZE != 0 or bytes.size() / RECORD_SIZE > 20000:
		return false
	var parsed: Array[Dictionary] = []
	var first := bytes.decode_u32(96)
	var last := first
	for offset in range(0, bytes.size(), RECORD_SIZE):
		var time := bytes.decode_u32(offset + 96)
		var eye := _point(bytes, offset + 60)
		var focus := _point(bytes, offset + 72)
		var cursor := Vector2(bytes.decode_float(offset + 52), bytes.decode_float(offset + 56))
		if time < last or not eye.is_finite() or not focus.is_finite() or not cursor.is_finite():
			return false
		var hand := _point(bytes, offset + 28)
		# Early records contain the original debug allocator's CDCDCDCD sentinel.
		if not hand.is_finite() or maxf(absf(hand.x), maxf(absf(hand.y), absf(hand.z))) > 20000.0:
			hand = Vector3.INF
		parsed.append({"time": (time - first) / 1000.0, "eye": eye, "focus": focus,
			"cursor": cursor.clamp(Vector2.ZERO, Vector2.ONE), "hand":hand,
			"action":bytes.decode_u32(offset), "trigger": bytes.decode_u32(offset + 92) != 0,
			"binding":_object_binding(bytes, offset)})
		last = time
	frames = parsed
	frame = 0
	elapsed = 0.0
	trigger_pending = frames[0]["trigger"]
	playing = true
	action_button_down = false
	action_press_count = 0
	action_release_count = 0
	_action_pressed_time = 0.0
	_actions.clear()
	return true


func advance(delta: float) -> void:
	if not playing or trigger_pending:
		return
	elapsed += delta
	while frame + 1 < frames.size() and elapsed >= float(frames[frame + 1]["time"]):
		frame += 1
		if frames[frame]["action"] in [ACTION_PRESSED, ACTION_RELEASED]:
			_record_action(frames[frame])
		if frames[frame]["trigger"]:
			trigger_pending = true
			elapsed = float(frames[frame]["time"])
			return
	if frame + 1 >= frames.size():
		playing = false


func _record_action(record: Dictionary) -> void:
	# These are input transitions, not pickup/drop commands. In givewood.hnd
	# the first release ends collection while the resource remains in the Hand;
	# the second press drops it. Actual resource ownership belongs to the world.
	var action := record.duplicate()
	var held_seconds := 0.0
	if int(record["action"]) == ACTION_PRESSED:
		action_button_down = true
		action_press_count += 1
		_action_pressed_time = float(record["time"])
		action["event"] = "action_pressed"
	else:
		if action_button_down:
			held_seconds = maxf(0.0, float(record["time"]) - _action_pressed_time)
		action_button_down = false
		action_release_count += 1
		action["event"] = "action_released"
	action["button_down"] = action_button_down
	action["press_count"] = action_press_count
	action["release_count"] = action_release_count
	action["held_seconds"] = held_seconds
	_actions.append(action)


func action_button_held_seconds() -> float:
	return maxf(elapsed - _action_pressed_time, 0.0) if action_button_down else 0.0


func consume_trigger() -> bool:
	var pending := trigger_pending
	trigger_pending = false
	return pending


func take_actions() -> Array[Dictionary]:
	var actions := _actions
	_actions = []
	return actions


func pose() -> Dictionary:
	if frames.is_empty():
		return {}
	var a := frames[frame]
	if trigger_pending or frame + 1 >= frames.size():
		return a
	var b := frames[frame + 1]
	var weight := 0.0
	if float(b["time"]) > float(a["time"]):
		weight = clampf(inverse_lerp(a["time"], b["time"], elapsed), 0.0, 1.0)
	return {"eye": a["eye"].lerp(b["eye"], weight), "focus": a["focus"].lerp(b["focus"], weight),
		"cursor": a["cursor"].lerp(b["cursor"], weight),
		"hand": a["hand"].lerp(b["hand"], weight) if a["hand"].is_finite() and b["hand"].is_finite() else a["hand"]}


static func _point(bytes: PackedByteArray, offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), -bytes.decode_float(offset + 8))


static func _object_binding(bytes: PackedByteArray, offset: int) -> Dictionary:
	var type := bytes.decode_u32(offset + 116)
	if type == 0:
		return {}
	# The playback resolves this script object type/subtype within 3 metres of
	# the recorded MapCoords. Raw pointers are never retained in HND recordings.
	var position := Vector3(bytes.decode_u32(offset + 104) * MAP_COORD_TO_METRES,
		bytes.decode_float(offset + 112), -bytes.decode_u32(offset + 108) * MAP_COORD_TO_METRES)
	return {"type":type, "subtype":bytes.decode_u32(offset + 120),
		"position":position, "distance":bytes.decode_float(offset + 100)}
