extends RefCounted

## Generic presentation clock for a Godot host.
## The caller owns time and drives the clock through advance().
## The module never selects animations, poses or movement; the host samples its
## clip with `position` and holds its last frame while `completed` is true.
## No signals, callbacks, processing, randomness, filesystem or engine clock.

const INFINITE_REPEATS: int = -1
const MAX_CLIP_COUNT: int = 512
const MAX_NAME_LENGTH: int = 128
const MIN_DURATION: float = 0.000001
const MAX_DURATION: float = 36000.0
const MAX_REPEATS: int = 1000000
const MAX_DELTA: float = 36000.0
const MAX_INFINITE_AGE: float = 1.0e12

var _configured: bool = false
var _durations: Dictionary = {}

var _active: bool = false
var _clip_name: String = ""
var _clip_duration: float = 0.0
var _repeats: int = 0
var _total: float = 0.0
var _age: float = 0.0
var _position: float = 0.0
var _playing: bool = false
var _completed: bool = false


## Accepts exactly one successful configuration. Validates every entry before
## storing anything, so a rejected map leaves the module untouched.
func configure(durations: Dictionary) -> bool:
	if _configured:
		return false
	var count: int = durations.size()
	if count < 1 or count > MAX_CLIP_COUNT:
		return false
	var copy: Dictionary = {}
	for key: Variant in durations.keys():
		if typeof(key) != TYPE_STRING:
			return false
		var key_text: String = key
		var key_length: int = key_text.length()
		if key_length < 1 or key_length > MAX_NAME_LENGTH:
			return false
		var raw: Variant = durations[key]
		var raw_type: int = typeof(raw)
		if raw_type != TYPE_INT and raw_type != TYPE_FLOAT:
			return false
		var seconds: float = float(raw)
		if not is_finite(seconds):
			return false
		if seconds < MIN_DURATION or seconds > MAX_DURATION:
			return false
		copy[key_text] = seconds
	_durations = copy
	_configured = true
	_clear_request()
	return true


## Replaces the active request. Always resets age and position, even when the
## name and repeat count are unchanged.
func start(clip_name: String, repeats: int) -> bool:
	if not _configured:
		return false
	if not _durations.has(clip_name):
		return false
	if repeats != INFINITE_REPEATS and (repeats < 1 or repeats > MAX_REPEATS):
		return false
	var seconds: float = _durations[clip_name]
	_active = true
	_clip_name = clip_name
	_clip_duration = seconds
	_repeats = repeats
	if repeats == INFINITE_REPEATS:
		_total = 0.0
	else:
		_total = seconds * float(repeats)
	_age = 0.0
	_position = 0.0
	_playing = true
	_completed = false
	return true


## Advances the active request by a caller-supplied delta in seconds.
func advance(delta: float) -> bool:
	if not _configured:
		return false
	if not is_finite(delta):
		return false
	if delta < 0.0 or delta > MAX_DELTA:
		return false
	if not _active or _completed:
		return true
	var next_age: float = _age + delta
	if _repeats == INFINITE_REPEATS:
		if next_age > MAX_INFINITE_AGE:
			return false
		_age = next_age
		_position = fmod(_age, _clip_duration)
		return true
	if next_age >= _total:
		_age = _total
		_position = _clip_duration
		_playing = false
		_completed = true
	else:
		_age = next_age
		_position = fmod(_age, _clip_duration)
	return true


## Returns to idle while keeping the configured durations.
func stop() -> bool:
	if not _configured:
		return false
	_clear_request()
	return true


## Returns a fresh dictionary; no internal reference is exposed.
func snapshot() -> Dictionary:
	return {
		"name": _clip_name,
		"age": _age,
		"position": _position,
		"duration": _clip_duration,
		"repeats": _repeats,
		"playing": _playing,
		"completed": _completed,
	}


func _clear_request() -> void:
	_active = false
	_clip_name = ""
	_clip_duration = 0.0
	_repeats = 0
	_total = 0.0
	_age = 0.0
	_position = 0.0
	_playing = false
	_completed = false
