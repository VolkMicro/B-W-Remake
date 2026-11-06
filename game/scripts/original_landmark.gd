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
var gate_open := false
var _collision_faces := PackedVector3Array()


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
	for child in rig.root.get_children():
		if child is MeshInstance3D: _collision_faces.append_array(child.mesh.get_faces())
	return true


func play_original() -> bool:
	if rig == null or animations == null:
		return false
	elapsed = 0.0
	gate_open = true
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


func segment_contact(from: Vector3, to: Vector3) -> Dictionary:
	# Closed gate/plinth geometry. Animated collision poses are not yet ported.
	if elapsed > 0.0 or from.is_equal_approx(to): return {}
	var inverse := global_transform.affine_inverse()
	var start := inverse * from
	var finish := inverse * to
	if not rig.bounds.intersects_segment(start, finish): return {}
	var direction := (finish - start).normalized()
	var closest := INF
	var contact := {}
	for i in range(0, _collision_faces.size(), 3):
		var a := _collision_faces[i]
		var b := _collision_faces[i + 1]
		var c := _collision_faces[i + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(start, direction, a, b, c)
		if hit == null: continue
		var distance: float = start.distance_to(hit)
		if distance > start.distance_to(finish) + 0.0001 or distance >= closest: continue
		closest = distance
		var normal := (global_basis.inverse().transposed() * (b - a).cross(c - a)).normalized()
		if normal.dot(to - from) > 0.0: normal = -normal
		contact = {"target":self,"point":global_transform * hit,"normal":normal}
	return contact
