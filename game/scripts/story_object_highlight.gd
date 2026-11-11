extends Node3D
## Provisional outline presentation for source effect 34 HIGHLIGHT_ON_OBJECT.
## Lifetime/attachment use the actual source request; original particles remain.
var elapsed := 0.0
var duration := -1.0
var _meshes: Array[WeakRef] = []
var _previous: Array[Material] = []
var _material: ShaderMaterial

func configure(target: Thing, seconds: float) -> bool:
	duration = seconds
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never;
void vertex() { VERTEX += NORMAL * 0.09; }
void fragment() { ALBEDO = vec3(1.0, 0.78, 0.12); ALPHA = 0.55 + 0.2 * sin(TIME * 3.0); }
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	# Overlay the actual rendered mesh so the outline receives the same skin
	# and bone animation. A copied static mesh cannot highlight a rigged actor.
	for child in target.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null: continue
		_meshes.append(weakref(child))
		_previous.append(child.material_overlay)
		child.material_overlay = _material
	return not _meshes.is_empty()


func _exit_tree() -> void:
	for i in _meshes.size():
		var mesh := _meshes[i].get_ref() as MeshInstance3D
		if is_instance_valid(mesh) and mesh.material_overlay == _material:
			mesh.material_overlay = _previous[i]

func _process(delta: float) -> void:
	elapsed += delta
	if duration >= 0.0 and elapsed >= duration: queue_free()
