extends Node3D
## Provisional outline presentation for source effect 34 HIGHLIGHT_ON_OBJECT.
## Lifetime/attachment use the actual source request; original particles remain.
var elapsed := 0.0
var duration := -1.0

func configure(target: Thing, seconds: float) -> bool:
	duration = seconds
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never;
void vertex() { VERTEX += NORMAL * 0.09; }
void fragment() { ALBEDO = vec3(1.0, 0.78, 0.12); ALPHA = 0.55 + 0.2 * sin(TIME * 3.0); }
"""
	for child in target.get_children():
		if child is MeshInstance3D:
			var outline := MeshInstance3D.new()
			outline.mesh = child.mesh
			outline.transform = child.transform
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := ShaderMaterial.new()
			material.shader = shader
			outline.material_override = material
			add_child(outline)
	return get_child_count() > 0

func _process(delta: float) -> void:
	elapsed += delta
	if duration >= 0.0 and elapsed >= duration: queue_free()
