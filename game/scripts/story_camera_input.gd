extends RefCounted

# Original HelpProfile records each active help event at most once per 100 ms
# game turn (Trigger 0x5c46e0, accumulator 0x449040, Process 0x5c4660).
# These are turn counts, not mouse-event counts or accumulated degrees.
const TURN_SECONDS := 0.1
const ROTATE_EVENT := 25
const PITCH_EVENT := 28
const ZOOM_EVENT := 29
var totals := {ROTATE_EVENT: 0, PITCH_EVENT: 0, ZOOM_EVENT: 0}
var hand_state := 0
var angle_sound_axis := 0
var _pending := {}
var _clock := 0.0


func record_rotation(radians: float) -> void:
	_record(ROTATE_EVENT, radians)
	if radians != 0.0:
		hand_state = 21


func record_pitch(radians: float) -> void:
	_record(PITCH_EVENT, radians)
	if radians != 0.0:
		hand_state = 21


func record_zoom(distance: float) -> void:
	_record(ZOOM_EVENT, distance)
	if distance != 0.0:
		hand_state = 22


func _record(event: int, amount: float) -> void:
	if is_finite(amount) and not is_zero_approx(amount):
		_pending[event] = true


func set_hand_state(value: int) -> void:
	hand_state = value


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_clock += delta
	if _clock + 0.000001 < TURN_SECONDS:
		return
	_clock = fposmod(_clock, TURN_SECONDS)
	for event in _pending:
		totals[event] = int(totals[event]) + 1
	_pending.clear()


func total(event: int) -> float:
	return float(totals.get(event, 0))


func set_angle_sound(native: int, enabled: bool) -> void:
	# Native285 and348 control the same feedback channel with different input
	# sources (rotation and pitch). Disabling either stops that channel.
	angle_sound_axis = (ROTATE_EVENT if native == 285 else PITCH_EVENT) if enabled else 0
