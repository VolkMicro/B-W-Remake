# One original cave/gate rig. The story driver may request its original clip;
# campaign triggers are not wired yet, so the initial pose remains the bind pose.
class_name OriginalLandmark
extends Node3D

signal animation_finished

const Data := preload("res://scripts/data.gd")
var rig: L3dRig
var animations: AnmReader
var clip := ""
var playing := false
var elapsed := 0.0


func configure(models: G3dReader, original: Dictionary, animation_reader: AnmReader) -> bool:
	var animation_id := int(original.get("animation_id", -1))
	if not animation_reader.names_by_index.has(animation_id):
		return false
	clip = animation_reader.names_by_index[animation_id]
	if not animation_reader.clips.has(clip):
		return false
	rig = models.rig_index(int(original.get("mesh_id", -1)))
	if rig == null:
		return false
	if rig.bone_count != int(animation_reader.clips[clip]["bones"]):
		rig.root.free()
		rig = null
		return false
	animations = animation_reader
	add_child(rig.root)
	return true


func play_original() -> bool:
	if rig == null or animations == null:
		return false
	elapsed = 0.0
	playing = true
	_apply_pose()
	return true


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not playing or delta < 0.0 or not is_finite(delta):
		return
	var rules: Dictionary = Data.LANDMARK_ANIMATION_RULES["scripted"]
	var duration: float = animations.clips[clip]["duration"]
	elapsed = minf(elapsed + delta * float(rules["speed"]), duration)
	_apply_pose()
	if elapsed >= duration:
		playing = false
		animation_finished.emit()


func _apply_pose() -> void:
	var preserve_root := Data.LANDMARK_ANIMATION_RULES["scripted"]["root_translation"] == "preserve"
	var pose := animations.sample(clip, elapsed, 0, false, preserve_root)
	if pose.size() == rig.bone_count:
		rig.apply_local_pose(pose)
