extends RefCounted
## ResourceHand - remake implementation of SPEC-RESOURCE-HAND-001 v1 (DRAFT).
## Holds integer units of one resource (0 food, 1 wood). Quantities move only
## through synchronous caller callbacks. The moved signal is a notification only
## and never owns economic quantity.
## Public properties resource/amount/collecting are read-only by convention.
## The 25 initial, 8 to 70 quadratic gather, 0.1 s turn, 6 s ramp and 20000
## capacity examples come from static expectations, not from measurements.
## Robustness limits (256 turns per advance, 1000000 pending turns, reentrancy
## rejection) are explicit remake policies.

signal moved(direction: String, resource: int, amount: int)

const RESOURCE_NONE: int = -1
const RESOURCE_FOOD: int = 0
const RESOURCE_WOOD: int = 1
const MAX_UNITS: int = 20000
const MIN_TURN_SECONDS: float = 0.001
const MAX_TURN_SECONDS: float = 1.0
const MAX_RAMP_QUOTIENT: float = 1000000.0
const MAX_TURNS_PER_ADVANCE: int = 256
const MAX_PENDING_TURNS: int = 1000000
const TURN_EPSILON_SECONDS: float = 0.000000001
const RAMP_RELATIVE_EPSILON: float = 0.000000001
const DIRECTION_PICKUP: String = 'pickup'
const DIRECTION_PUTDOWN: String = 'putdown'

var resource: int = RESOURCE_NONE
var amount: int = 0
var collecting: bool = false

var _configured: bool = false
var _profiles: Array[Dictionary] = []
var _turn_seconds: float = 0.1
var _take: Callable = Callable()
var _turns_elapsed: int = 0
var _pending_seconds: float = 0.0
var _busy: bool = false


## Configure once. Both profiles are validated before anything is committed.
func configure(profiles: Array[Dictionary], turn_seconds: float = 0.1) -> bool:
	if _busy or _configured:
		return false
	if profiles.size() != 2:
		return false
	if not is_finite(turn_seconds):
		return false
	if turn_seconds < MIN_TURN_SECONDS or turn_seconds > MAX_TURN_SECONDS:
		return false
	var validated: Array[Dictionary] = []
	for entry: Dictionary in profiles:
		var normalized: Dictionary = _validated_profile(entry, turn_seconds)
		if normalized.is_empty():
			return false
		validated.append(normalized)
	_profiles = validated
	_turn_seconds = turn_seconds
	_configured = true
	return true


## Start holding resource_id. take(requested:int)->int debits its own source.
func begin(resource_id: int, take: Callable) -> bool:
	if _busy or not _configured:
		return false
	if amount != 0 or collecting:
		return false
	if resource_id != RESOURCE_FOOD and resource_id != RESOURCE_WOOD:
		return false
	if not take.is_valid():
		return false
	var profile: Dictionary = _profiles[resource_id]
	var initial: int = profile['initial']
	var maximum: int = profile['maximum']
	var request: int = mini(initial, maximum)
	_busy = true
	var got: int = _sanitize(take.call(request), request)
	if got <= 0:
		resource = RESOURCE_NONE
		amount = 0
		collecting = false
		_take = Callable()
		_pending_seconds = 0.0
		_busy = false
		return false
	resource = resource_id
	amount = got
	_turns_elapsed = 0
	_pending_seconds = 0.0
	if amount < maximum:
		collecting = true
		_take = take
	else:
		collecting = false
		_take = Callable()
	moved.emit(DIRECTION_PICKUP, resource_id, got)
	_busy = false
	return true


## Stop collecting: discards pending time, releases the source, keeps quantity.
func stop() -> void:
	if _busy:
		return
	_halt_collection()


## Accumulate elapsed time and process at most 256 turns per call.
func advance(delta: float) -> void:
	if _busy or not collecting:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	var cap_seconds: float = float(MAX_PENDING_TURNS) * _turn_seconds
	var room: float = cap_seconds - _pending_seconds
	if delta >= room:
		_pending_seconds = cap_seconds
	else:
		_pending_seconds += delta
	var available_float: float = floorf((_pending_seconds + TURN_EPSILON_SECONDS) / _turn_seconds)
	var available: int = int(clampf(available_float, 0.0, float(MAX_PENDING_TURNS)))
	if available <= 0:
		return
	var budget: int = mini(available, MAX_TURNS_PER_ADVANCE)
	var processed: int = 0
	_busy = true
	while processed < budget and collecting:
		processed += 1
		_run_turn()
	_busy = false
	if collecting:
		_pending_seconds = maxf(0.0, _pending_seconds - float(processed) * _turn_seconds)
	else:
		_pending_seconds = 0.0


## Offer the whole held amount. accept(offered:int)->int credits its destination.
func give(accept: Callable) -> int:
	if _busy:
		return 0
	_halt_collection()
	if amount <= 0:
		return 0
	if not accept.is_valid():
		return 0
	var offered: int = amount
	var transferred_resource: int = resource
	_busy = true
	var got: int = _sanitize(accept.call(offered), offered)
	if got > 0:
		amount -= got
		if amount <= 0:
			amount = 0
			resource = RESOURCE_NONE
		moved.emit(DIRECTION_PUTDOWN, transferred_resource, got)
	_busy = false
	return got


func snapshot() -> Dictionary:
	return {'resource': resource, 'amount': amount, 'collecting': collecting}


func _run_turn() -> void:
	if not _take.is_valid():
		_halt_collection()
		return
	if resource != RESOURCE_FOOD and resource != RESOURCE_WOOD:
		_halt_collection()
		return
	var profile: Dictionary = _profiles[resource]
	var maximum: int = profile['maximum']
	var free_space: int = maximum - amount
	if free_space <= 0:
		_halt_collection()
		return
	_turns_elapsed += 1
	var request: int = mini(_rate_for_turn(profile, _turns_elapsed), free_space)
	var got: int = _sanitize(_take.call(request), request)
	if got <= 0:
		_halt_collection()
		return
	var transferred_resource: int = resource
	amount += got
	if amount >= maximum:
		_halt_collection()
	moved.emit(DIRECTION_PICKUP, transferred_resource, got)


## Exact integer evaluation of int(start + (end - start) * clamp(n / ramp, 0, 1)^2).
@warning_ignore('integer_division')
func _rate_for_turn(profile: Dictionary, turn: int) -> int:
	var start_rate: int = profile['rate_start']
	var end_rate: int = profile['rate_end']
	var ramp: int = profile['ramp_turns']
	var n: int = clampi(turn, 0, ramp)
	var extra: int = ((end_rate - start_rate) * n * n) / (ramp * ramp)
	return start_rate + extra


func _halt_collection() -> void:
	collecting = false
	_take = Callable()
	_pending_seconds = 0.0


func _sanitize(value: Variant, limit: int) -> int:
	if typeof(value) != TYPE_INT:
		return 0
	var number: int = value
	if number < 0 or number > limit:
		return 0
	return number


func _validated_profile(source_profile: Dictionary, turn_seconds: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ['initial', 'rate_start', 'rate_end', 'maximum']:
		if not source_profile.has(key):
			return {}
		var value: Variant = source_profile[key]
		if typeof(value) != TYPE_INT:
			return {}
		var number: int = value
		if number <= 0 or number > MAX_UNITS:
			return {}
		result[key] = number
	var initial: int = result['initial']
	var maximum: int = result['maximum']
	var start_rate: int = result['rate_start']
	var end_rate: int = result['rate_end']
	if initial > maximum or start_rate > end_rate:
		return {}
	if not source_profile.has('ramp_seconds'):
		return {}
	var ramp_value: Variant = source_profile['ramp_seconds']
	var ramp_type: int = typeof(ramp_value)
	if ramp_type != TYPE_INT and ramp_type != TYPE_FLOAT:
		return {}
	var ramp_seconds: float = float(ramp_value)
	if not is_finite(ramp_seconds) or ramp_seconds <= 0.0:
		return {}
	var quotient: float = ramp_seconds / turn_seconds
	if not is_finite(quotient) or quotient > MAX_RAMP_QUOTIENT:
		return {}
	result['ramp_seconds'] = ramp_seconds
	result['ramp_turns'] = _derive_ramp_turns(quotient)
	return result


## max(1, int(quotient)) without truncating a mathematically integral
## quotient (for example 0.3 / 0.1) below its value because of roundoff.
func _derive_ramp_turns(quotient: float) -> int:
	var nearest: float = roundf(quotient)
	var whole: float = floorf(quotient)
	if absf(quotient - nearest) <= RAMP_RELATIVE_EPSILON * maxf(1.0, absf(quotient)):
		whole = nearest
	return maxi(1, int(whole))
