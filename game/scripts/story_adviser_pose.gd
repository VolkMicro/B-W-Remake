extends RefCounted

# Original HelpDude composition: stand -> hover -> additive mouth -> additive
# point/head controls. All action parameters are poses, not looping animations.
# Source: CC0 bw1-decomp HelpDude::Update1/ApplyVoiceKey/ApplyHeadMovement.
var _clock := 0.0
var _point_weight := 0.0
var _stable_weight := 0.0
var _point_left := false
var _point_direction := 0.5
var _mouth := 0.0
var _look := Vector2.ZERO
var _last_pose: Array[Transform3D] = []
var _voice_stream: AudioStreamWAV
var _voice_bytes := PackedByteArray()
var _cling_time := 0.0
var camera: Camera3D


static func facing_yaw(screen: Vector2, clinging := false) -> float:
	# HelpDude::Update1 rotates Y by HoverX * -0.8; reflecting its row
	# matrix into Godot retains this angle. Bottom-edge clinging disables yaw.
	return 0.0 if clinging else -(screen.x * 2.0 - 1.0) * 0.8


func sample(animation: MorphReader, rig: L3dRig, id: String, delta: float, anchor_screen: Vector2, point_screen := Vector2.INF, look_screen := Vector2.INF, voice: AudioStreamPlayer = null, clinging := false) -> Array[Transform3D]:
	if delta <= 0.0 and not _last_pose.is_empty():
		return _last_pose.duplicate()
	_clock += maxf(delta, 0.0)
	_cling_time = _cling_time + maxf(delta, 0.0) if clinging else 0.0
	var prefix := "adviser/Yogi_" if id == "good" else "adviser/Demon_"
	var pointing := point_screen.is_finite()
	var desired_left := point_screen.x < anchor_screen.x if pointing else _point_left
	var changing_side := pointing and desired_left != _point_left and _point_weight > 0.0
	_point_weight = move_toward(_point_weight, 0.0 if not pointing or changing_side else 1.0, delta * 4.0)
	if _point_weight == 0.0:
		_point_left = desired_left
	# The original blends to stable hovering over one second when pointing.
	_stable_weight = move_toward(_stable_weight, 1.0 if pointing else 0.0, delta)
	var pose := animation.sample_adviser(prefix + "Hover", _clock, rig)
	var stable := animation.sample_adviser(prefix + "Hover_Stable", _clock, rig)
	for bone in pose.size():
		pose[bone] = pose[bone].interpolate_with(stable[bone], _stable_weight)
	if clinging:
		# CLING_SPIRIT uses the authored edge pose, not a flying hover. The
		# original subtracts the root's hold-position displacement from its
		# world transform so the sprite remains attached to the screen edge.
		pose = animation.sample_adviser("move/stand", 0.0, rig)
		var clip := prefix + "ClingD"
		if animation.clips.has(clip):
			var hold: float = animation.adviser_metadata.get("loop_ends", {}).get(68, 0.5)
			var position := minf(_cling_time / float(animation.clips[clip]["duration"]), hold)
			animation.apply_adviser_difference(clip, position, 0.0, pose, rig)
			pose[0].origin -= animation.adviser_root_motion(clip, hold)
	var aperture := _voice_aperture(voice)
	_mouth = lerpf(_mouth, aperture, 1.0 - exp(-delta * (35.0 if aperture > _mouth else 16.0)))
	animation.apply_adviser_difference(prefix + "Speak_AAA", _mouth, 0.0, pose, rig)
	if _point_weight > 0.0:
		var side := ("L" if _point_left else "R") if id == "good" else ("Left" if _point_left else "Right")
		var pointing_prefix := prefix + "Point_" + side
		animation.apply_adviser_difference(pointing_prefix + "_In", _point_weight, 0.0, pose, rig)
		if pointing:
			var difference := anchor_screen - point_screen
			_point_direction = clampf(atan2(difference.y, absf(difference.x)) / deg_to_rad(100.0) + 0.5, 0.0, 1.0)
		animation.apply_adviser_difference(pointing_prefix + "_UD", lerpf(0.5, _point_direction, _point_weight), 0.5, pose, rig)
	# Look L/R and U/D are slider poses centred at 0.5 in the source. Running
	# them as cyclic clips makes the adviser repeatedly swing its head.
	var desired_look := Vector2.ZERO
	if is_instance_valid(camera) and rig.root.is_inside_tree():
		# HelpDude::CalcHeadPos evaluates the camera in the animated head's
		# local frame. Screen displacement alone has the wrong sign when an
		# adviser is near either side of a perspective view.
		var head: int = animation.adviser_metadata.get("head_bone", -1)
		if head >= 0 and head < pose.size():
			var globals: Array[Transform3D] = []
			for bone in pose.size():
				globals.append(globals[rig.parents[bone]] * pose[bone] if rig.parents[bone] >= 0 else pose[bone])
			var head_world := rig.root.global_transform * globals[head]
			var target := camera.global_position
			if look_screen.is_finite():
				var depth := maxf(absf(camera.to_local(head_world.origin).z) * 0.8, 0.1)
				target = camera.project_position(look_screen * camera.get_viewport().get_visible_rect().size, depth)
			var local := head_world.affine_inverse() * target
			if local.y > 0.0:
				local = local.normalized()
				desired_look = Vector2(atan2(-local.z, local.y), asin(clampf(local.x, -1.0, 1.0))) / (2.0 * PI / 3.0)
				desired_look = desired_look.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	elif look_screen.is_finite():
		desired_look = (look_screen - anchor_screen).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	var turn_speed := 1.35 if id == "good" else 4.5
	_look = _look.move_toward(desired_look, delta * turn_speed)
	var slots: Dictionary = animation.adviser_metadata.get("slots", {})
	var look_lr: String = slots.get(70 if pointing else 18, "")
	var look_ud: String = slots.get(71 if pointing else 19, "")
	animation.apply_adviser_difference(look_lr, 0.5 + _look.x, 0.5, pose, rig)
	animation.apply_adviser_difference(look_ud, 0.5 + _look.y, 0.5, pose, rig)
	# Retargeted sparse controls can enter on different render frames. A short
	# 50 ms pose filter prevents a single-frame discontinuity at their boundary.
	if _last_pose.size() == pose.size() and delta > 0.0:
		var blend := 1.0 - exp(-20.0 * delta)
		for bone in pose.size():
			pose[bone] = _last_pose[bone].interpolate_with(pose[bone], blend)
	# Sampling and control state use separate clocks. No speech-start reset may
	# jump the body pose; retain the result for the next render frame.
	_last_pose = pose
	return pose


func _voice_aperture(voice: AudioStreamPlayer) -> float:
	if voice == null or not voice.playing or not voice.stream is AudioStreamWAV:
		return 0.0
	var stream := voice.stream as AudioStreamWAV
	if stream != _voice_stream:
		_voice_stream = stream
		_voice_bytes = stream.data
	if stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return 0.0
	var channels := 2 if stream.stereo else 1
	var first := maxi(0, int(voice.get_playback_position() * stream.mix_rate) * channels)
	var count := mini(int(stream.mix_rate * 0.025) * channels, _voice_bytes.size() / 2 - first)
	if count <= 0:
		return 0.0
	var power := 0.0
	for sample_index in range(first, first + count, 4):
		var amplitude := float(_voice_bytes.decode_s16(sample_index * 2)) / 32768.0
		power += amplitude * amplitude
	return clampf(sqrt(power / maxf(float(count) / 4.0, 1.0)) * 5.0, 0.0, 1.0)
