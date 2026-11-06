extends Node3D

const CLIP := "rescue_hand"
var rig := L3dRig.new()
var animations := AnmReader.new()
var elapsed := 0.0
var playing := false


func configure(folder: String) -> bool:
	if not animations.load_standalone(folder.path_join("hand_intro.anm"), CLIP):
		return false
	var model := rig.load_file(folder.path_join("hand_intro.l3d"))
	if model == null:
		return false
	if rig.bone_count != int(animations.clips[CLIP]["bones"]):
		model.free()
		return false
	add_child(model)
	position = Vector3(1494.379, -2.5, -2091.474)
	scale = Vector3.ONE * 0.008
	_apply()
	return true


func trigger() -> void:
	if playing:
		elapsed = 2.379
	else:
		playing = true
	_apply()


func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	_apply()
	if elapsed >= float(animations.clips[CLIP]["duration"]):
		hide()


func _apply() -> void:
	var pose := animations.sample(CLIP, elapsed, 0, false, true)
	if pose.size() == rig.bone_count:
		rig.apply_local_pose(pose)
