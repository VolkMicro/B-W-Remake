extends Node3D
## Installed ScriptHighlight meshes, including DYK, silver and gold scrolls.
var highlight_type := 0
var challenge := 0
var active := false
var draw_height := 0.0
var ground_height := 0.0
var visual := MeshInstance3D.new()
var _normal_mesh: ArrayMesh
var _active_mesh: ArrayMesh
var _clock := 0.0
var _hover_material: StandardMaterial3D


func configure(g3d: G3dReader, info: Dictionary, type: int, script_id: int, base_height: float) -> bool:
	if info.is_empty():
		return false
	_normal_mesh = g3d.mesh_index(info["mesh_id"])
	_active_mesh = g3d.mesh_index(info["active_mesh_id"])
	if _normal_mesh == null or _active_mesh == null:
		return false
	highlight_type = type
	challenge = script_id
	ground_height = base_height
	set_meta("highlight_type", type)
	set_meta("challenge", script_id)
	visual.mesh = _normal_mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_hover_material = StandardMaterial3D.new()
	_hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_material.albedo_color = Color(0.35, 0.25, 0.1, 0.25)
	return true

func set_hovered(value: bool) -> void:
	visual.material_overlay = _hover_material if value else null


func set_active(value: bool) -> void:
	active = value
	visual.mesh = _active_mesh if active else _normal_mesh


func set_draw_height(value: float) -> void:
	draw_height = value
	set_meta("property_24", value)
	position.y = ground_height + value


func advance(delta: float, camera: Camera3D) -> void:
	_clock += delta
	# ScriptHighlight::Draw rotates scrolls by time * PI/1000. DYK signs
	# face the camera and retain their own scale; other scrolls scale by
	# clamp(camera-space depth,10,30)/30 (installed 0x709c60).
	if highlight_type == 1:
		var towards := camera.global_position - global_position
		visual.rotation.y = atan2(towards.x, towards.z)
		visual.scale = Vector3.ONE
	else:
		visual.rotation.y = _clock * PI
		var depth := -camera.to_local(global_position).z
		visual.scale = Vector3.ONE * clampf(floorf(depth), 10.0, 30.0) / 30.0


func screen_hit(camera: Camera3D, screen: Vector2) -> bool:
	if not visible or camera.is_position_behind(global_position):
		return false
	var origin := visual.global_transform.affine_inverse() * camera.project_ray_origin(screen)
	var direction := visual.global_basis.inverse() * camera.project_ray_normal(screen)
	var bounds := visual.mesh.get_aabb()
	if bounds.intersects_ray(origin, direction) != null:
		return true
	# Use the full projected scroll plus a forgiving cursor area. This remains
	# a scroll selection; the world checks occlusion before accepting it.
	var centre := visual.global_transform * bounds.get_center()
	var radius := clampf(camera.get_viewport().get_visible_rect().size.y / 900.0 * 28.0, 28.0, 38.0)
	var rect := Rect2(camera.unproject_position(centre), Vector2.ZERO)
	for i in 8:
		var point := visual.global_transform * bounds.get_endpoint(i)
		if not camera.is_position_behind(point): rect = rect.expand(camera.unproject_position(point))
	return rect.grow(14.0).has_point(screen) or camera.unproject_position(centre).distance_to(screen) <= radius
