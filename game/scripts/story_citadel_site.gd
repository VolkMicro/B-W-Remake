extends Node3D

var progress := 0.0
var forced_desire := 0.0
var model: Node3D
var mesh_height := 0.0
var _finished: Node3D
var _scaffold: Node3D
var _finished_material: ShaderMaterial
var _scaffold_material: ShaderMaterial
var _base_y := 0.0
var entrance_bounds := AABB()
var _entrance_faces := PackedVector3Array()

# InitTemple starts with Level=0 and Alignment=.5. ProcessAlignement blends
# B_FIRST_TEMPLE's vertices/UVs/normals to stage 0, alignment 2, B_TEMPLE02.
# The files share their topology and construction-state flags. Showing the raw
# B_FIRST_TEMPLE geometry instead leaves the evil temple's tall outer spikes.
const INITIAL_GEOMETRY := "b_temple02_l3d.zzz"

const BUILD_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin : source_color, filter_linear_mipmap;
uniform float cut_height = 100000.0;
varying float original_height;
void vertex() { original_height = VERTEX.y; }
void fragment() {
    if (original_height > cut_height) { discard; }
    vec4 texel = texture(skin, UV);
    ALBEDO = texel.rgb;
    ALPHA = texel.a;
    ALPHA_SCISSOR_THRESHOLD = 0.2;
    ROUGHNESS = 1.0;
}
"""


func configure(folder: String) -> bool:
	var bytes := _initial_mesh_bytes(folder)
	if bytes.is_empty():
		return false
	var texture := _load_skin(folder.path_join("neutral0.16B"))
	if texture == null:
		return false
	var shader := Shader.new()
	shader.code = BUILD_SHADER
	_finished_material = ShaderMaterial.new()
	_finished_material.shader = shader
	_finished_material.set_shader_parameter("skin", texture)
	_scaffold_material = _finished_material.duplicate()
	var rig := L3dRig.new()
	_finished = rig.load_bytes(bytes, func(_texture_id: int, _argb: int): return _finished_material, PackedInt32Array([0]))
	if _finished == null:
		return false
	mesh_height = rig.bounds.size.y
	_base_y = rig.bounds.position.y
	var scaffold_rig := L3dRig.new()
	_scaffold = scaffold_rig.load_bytes(bytes, func(_texture_id: int, _argb: int): return _scaffold_material, PackedInt32Array([1]))
	if _scaffold == null:
		_finished.free()
		return false
	# In the original this mesh is registered by AddJustForCollide, not drawn.
	# Its actual vertices locate the doorway on the front of the neutral temple.
	var entrance_rig := L3dRig.new()
	var entrance := entrance_rig.load_bytes(_load_mesh_bytes(folder.path_join("Entrance_l3d.zzz")))
	if entrance == null:
		_finished.free()
		_scaffold.free()
		return false
	entrance_bounds = entrance_rig.bounds
	for child in entrance.get_children():
		if child is MeshInstance3D:
			_entrance_faces.append_array(child.mesh.get_faces())
	entrance.free()
	model = Node3D.new()
	model.add_child(_finished)
	model.add_child(_scaffold)
	add_child(model)
	set_progress(0.0)
	return true


func entrance_position() -> Vector3:
	return global_transform * entrance_bounds.get_center()


func set_forced_desire(value: float) -> void:
	# BUILD_BUILDING changes the village's desire to build, not completion.
	if is_finite(value):
		forced_desire = maxf(value, 0.0)


func entrance_hit(ray_origin: Vector3, ray_direction: Vector3) -> bool:
	if progress < 1.0:
		return false
	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := (inverse.basis * ray_direction).normalized()
	for i in range(0, _entrance_faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(local_origin, local_direction, _entrance_faces[i], _entrance_faces[i + 1], _entrance_faces[i + 2]) != null:
			return true
	return false


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	_finished_material.set_shader_parameter("cut_height", _base_y + mesh_height * progress)
	# Original construction geometry rises during 0..0.2 and disappears
	# behind a descending clipping plane during 0.8..1.0.
	_scaffold.position.y = -mesh_height * (1.0 - clampf(progress / 0.2, 0.0, 1.0))
	_scaffold_material.set_shader_parameter("cut_height", _base_y + mesh_height * (1.0 - clampf((progress - 0.8) / 0.2, 0.0, 1.0)))
	_scaffold.visible = progress < 1.0
	model.visible = progress > 0.0


static func _load_mesh_bytes(path: String) -> PackedByteArray:
	var compressed := FileAccess.get_file_as_bytes(path)
	if compressed.size() < 6:
		return PackedByteArray()
	var size := compressed.decode_u32(0)
	if size < 76 or size > 16777216:
		return PackedByteArray()
	var bytes := compressed.slice(4).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	return bytes if bytes.size() == size else PackedByteArray()


static func _initial_mesh_bytes(folder: String) -> PackedByteArray:
	# Shape variants reference the first temple's texture, so retain its skin
	# storage and metadata while applying the selected original vertex records.
	var bytes := _load_mesh_bytes(folder.path_join("b_first_temple_l3d.zzz"))
	var shape := _load_mesh_bytes(folder.path_join(INITIAL_GEOMETRY))
	if bytes.is_empty() or shape.is_empty() or bytes.decode_u32(12) != shape.decode_u32(12):
		return PackedByteArray()
	for submesh in bytes.decode_u32(12):
		var base_sub := bytes.decode_u32(bytes.decode_u32(16) + submesh * 4)
		var shape_sub := shape.decode_u32(shape.decode_u32(16) + submesh * 4)
		if bytes.decode_u32(base_sub + 4) != shape.decode_u32(shape_sub + 4):
			return PackedByteArray()
		for primitive in bytes.decode_u32(base_sub + 4):
			var base_primitive := bytes.decode_u32(bytes.decode_u32(base_sub + 8) + primitive * 4)
			var shape_primitive := shape.decode_u32(shape.decode_u32(shape_sub + 8) + primitive * 4)
			var count := bytes.decode_u32(base_primitive + 16)
			if count != shape.decode_u32(shape_primitive + 16):
				return PackedByteArray()
			var base_vertices := bytes.decode_u32(base_primitive + 20)
			var shape_vertices := shape.decode_u32(shape_primitive + 20)
			if base_vertices + count * 32 > bytes.size() or shape_vertices + count * 32 > shape.size():
				return PackedByteArray()
			for byte in count * 32:
				bytes[base_vertices + byte] = shape[shape_vertices + byte]
	return bytes


static func _load_skin(path: String) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != 16 + 256 * 256 * 2 or bytes.decode_u32(4) != 256 or bytes.decode_u32(8) != 256:
		return null
	# Citadel skins retain A4R4G4B4 (LH3DCitadel's 0xf00/0xf0/0xf
	# alignment blend). Treating this file as RGB565 produces neon scaffolding.
	var rgba := PackedByteArray()
	rgba.resize(256 * 256 * 4)
	for i in 256 * 256:
		var pixel := bytes.decode_u16(16 + 2 * i)
		rgba[i * 4] = ((pixel >> 8) & 15) * 17
		rgba[i * 4 + 1] = ((pixel >> 4) & 15) * 17
		rgba[i * 4 + 2] = (pixel & 15) * 17
		rgba[i * 4 + 3] = ((pixel >> 12) & 15) * 17
	var image := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, rgba)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
