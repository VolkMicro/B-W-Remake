extends RefCounted
## Script controls for daylight and the simulation clock.

const SECONDS_PER_GAME_HOUR := 60.0

var hour := 12.0
var daylight_started := false
var daylight_advances := true
var speed := 1.0
var speed_owner := 0
var _move_target := 12.0
var _move_rate := 0.0
var _move_left := 0.0


func advance(delta: float) -> void:
	if _move_left > 0.0:
		var step := minf(delta, _move_left)
		_move_left -= step
		hour = _move_target if _move_left <= 0.0 else fposmod(hour + step * _move_rate, 24.0)
	elif daylight_started and daylight_advances:
		hour = fposmod(hour + delta / SECONDS_PER_GAME_HOUR, 24.0)


func release_speed() -> void:
	speed_owner = 0
	speed = 1.0


func invoke(id: int, stack: Array, context: Dictionary) -> Dictionary:
	var task := int(context.get("task", 0))
	match id:
		66: # SET_GAMESPEED
			var requested := StoryVm.as_float(stack.back())
			if not is_finite(requested) or requested <= 0.0:
				return {"ok": false}
			if task > 0 and task == speed_owner:
				speed = requested
			return {"ok": true, "pop": 1, "push": []}
		112: # SET_GAME_TIME
			var requested := StoryVm.as_float(stack.back())
			if not is_finite(requested):
				return {"ok": false}
			hour = fposmod(requested, 24.0)
			_move_left = 0.0
			daylight_started = true
			return {"ok": true, "pop": 1, "push": []}
		113: # GET_GAME_TIME
			return {"ok": true, "pop": 0, "push": [StoryVm.number(hour)]}
		128: # START_GAME_SPEED
			if task <= 0:
				return {"ok": false}
			if speed_owner == 0:
				speed_owner = task
			return {"ok": true, "pop": 0, "push": []}
		129: # END_GAME_SPEED
			if task == speed_owner:
				release_speed()
			return {"ok": true, "pop": 0, "push": []}
		288: # GAME_TIME_ON_OFF
			daylight_advances = StoryVm.as_int(stack.back()) != 0
			daylight_started = true
			return {"ok": true, "pop": 1, "push": []}
		289: # MOVE_GAME_TIME
			var requested := StoryVm.as_float(stack[stack.size() - 2])
			var seconds := StoryVm.as_float(stack.back())
			if not is_finite(requested) or not is_finite(seconds) or seconds <= 0.0:
				return {"ok": false}
			_move_target = fposmod(requested, 24.0)
			_move_rate = (fposmod(_move_target - hour + 12.0, 24.0) - 12.0) / seconds
			_move_left = seconds
			daylight_started = true
			return {"ok": true, "pop": 2, "push": []}
	return {"ok": false}
