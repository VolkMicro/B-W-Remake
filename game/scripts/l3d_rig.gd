# Independent reader for original L3D geometry. All bytes stay in memory.
class_name L3dRig
extends RefCounted

const Data := preload("res://scripts/data.gd")
var error := ""
var bone_count := 0
var surface_count := 0
var texture_count := 0
var parents := PackedInt32Array()
var rests: Array[Transform3D] = []
var global_rests: Array[Transform3D] = []
var skeleton: Skeleton3D
var root: Node3D
var bounds := AABB()
var _bytes := PackedByteArray()
var _skins: Dictionary = {}


static func reflected(t: Transform3D) -> Transform3D:
	var flip := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	return Transform3D(flip * t.basis * flip, flip * t.origin)


func load_file(path: String) -> Node3D:
	return load_bytes(FileAccess.get_file_as_bytes(path))


func load_bytes(bytes: PackedByteArray, external_material := Callable(), submesh_states := PackedInt32Array()) -> Node3D:
	error = ""
	_bytes = bytes
	if _bytes.size() < 76:
		return _fail("Cannot read model")
	var offset := _bytes.find(76) # find L3D0, including an embedded adviser model
	while offset >= 0:
		if offset + 4 <= _bytes.size() and _bytes.slice(offset, offset + 4).get_string_from_ascii() == "L3D0":
			break
		offset = _bytes.find(76, offset + 1)
	if offset < 0:
		return _fail("No L3D0 model")
	_bytes = _bytes.slice(offset)
	var nsub := _u(12)
	var sub_table := _u(16)
	# The original main temple room contains 263 static submeshes.
	if nsub < 1 or nsub > 1024 or not _fits(sub_table, nsub * 4):
		return _fail("Invalid submesh table")
	# Embedded RGBA4 skins have their own id before the 256x256 texels.
	var skin_count := _u(56)
	var skin_table := _u(60)
	if skin_count > 32 or (skin_count > 0 and not _fits(skin_table, skin_count * 4)):
		return _fail("Invalid skin table")
	for i in skin_count:
		var sp := _u(skin_table + i * 4)
		if not _fits(sp, 4 + 256 * 256 * 2):
			return _fail("Truncated embedded skin")
		var rgba := PackedByteArray()
		rgba.resize(256 * 256 * 4)
		for pixel in 256 * 256:
			var v := _bytes.decode_u16(sp + 4 + pixel * 2)
			rgba[pixel * 4] = ((v >> 8) & 15) * 17
			rgba[pixel * 4 + 1] = ((v >> 4) & 15) * 17
			rgba[pixel * 4 + 2] = (v & 15) * 17
			rgba[pixel * 4 + 3] = ((v >> 12) & 15) * 17
		var image := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, rgba)
		image.generate_mipmaps()
		_skins[_u(sp)] = ImageTexture.create_from_image(image)
	texture_count = _skins.size()
	root = Node3D.new()
	skeleton = Skeleton3D.new()
	skeleton.name = "OriginalSkeleton"
	root.add_child(skeleton)
	var mesh := ArrayMesh.new()
	var mesh_parts: Array[ArrayMesh] = []
	for si in nsub:
		var so := _u(sub_table + si * 4)
		if not _fits(so, 20):
			return _fail("Truncated submesh")
		if (_u(so) & 0x20000000) == 0:
			continue
		if not submesh_states.is_empty() and not submesh_states.has(int((_u(so) >> 4) & 63)):
			continue
		var nb := _u(so + 12)
		var bo := _u(so + 16)
		if nb > 256 or (nb > 0 and not _fits(bo, nb * 60)):
			return _fail("Invalid bones")
		# Creature/adviser files each have one skinned high-detail submesh.
		if nb > 0 and bone_count > 0:
			return _fail("Multiple independent skeletons are not supported")
		for bi in nb:
			var bp := bo + bi * 60
			var parent := _u(bp)
			if parent != 0xFFFFFFFF and parent >= bi:
				return _fail("Invalid bone parent order")
			var local := reflected(_transform(bp + 12))
			parents.append(parent if parent < bi else -1)
			rests.append(local)
			global_rests.append(global_rests[parent] * local if parent < bi else local)
			skeleton.add_bone("bone_%d" % bi)
			if parent < bi:
				skeleton.set_bone_parent(bi, parent)
			skeleton.set_bone_rest(bi, local)
		bone_count = nb
		var np := _u(so + 4)
		var pt := _u(so + 8)
		if np > 256 or not _fits(pt, np * 4):
			return _fail("Invalid primitive table")
		for pi in np:
			var pp := _u(pt + pi * 4)
			if not _fits(pp, 48):
				return _fail("Invalid primitive")
			var nv := _u(pp + 16)
			var vo := _u(pp + 20)
			var nt := _u(pp + 24)
			var to := _u(pp + 28)
			var ng := _u(pp + 32)
			var go := _u(pp + 36)
			if nv > 100000 or nt > 100000 or not _fits(vo, nv * 32) or not _fits(to, nt * 6) or not _fits(go, ng * 4):
				return _fail("Invalid vertex ranges")
			if nv == 0 or nt == 0:
				continue
			var groups := PackedInt32Array()
			groups.resize(nv)
			groups.fill(0)
			var vi := 0
			for gi in ng:
				var count := _bytes.decode_u16(go + gi * 4)
				var bone := _bytes.decode_u16(go + gi * 4 + 2)
				if bone >= maxi(1, nb) or vi + count > nv:
					return _fail("Invalid vertex bone group")
				for v in count:
					groups[vi + v] = bone
				vi += count
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var indices := PackedInt32Array()
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			for v in nv:
				var vp := vo + v * 32
				var p := _vec(vp)
				var normal := _vec(vp + 20)
				p.z = -p.z
				normal.z = -normal.z
				if nb > 0:
					var bind: Transform3D = global_rests[groups[v]]
					p = bind * p
					normal = bind.basis * normal
				vertices.append(p)
				normals.append(normal.normalized())
				uvs.append(Vector2(_bytes.decode_float(vp + 12), _bytes.decode_float(vp + 16)))
				for influence in 4:
					bones.append(groups[v] if influence == 0 else 0)
					weights.append(1.0 if influence == 0 else 0.0)
			for ti in nt * 3:
				var idx := _bytes.decode_u16(to + ti * 2)
				if idx >= nv:
					return _fail("Triangle vertex out of range")
				indices.append(idx)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			if nb > 0:
				arrays[Mesh.ARRAY_BONES] = bones
				arrays[Mesh.ARRAY_WEIGHTS] = weights
			# Rooms can exceed Godot's 256-surface limit for one ArrayMesh.
			if mesh.get_surface_count() >= 256:
				mesh_parts.append(mesh)
				mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := StandardMaterial3D.new()
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 1.0
			var tex_id := _u(pp + 8)
			if external_material.is_valid():
				mesh.surface_set_material(mesh.get_surface_count() - 1, external_material.call(tex_id, _u(pp + 12)))
				continue
			elif _skins.has(tex_id):
				material.albedo_texture = _skins[tex_id]
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.2
			else:
				var col := _u(pp + 12)
				material.albedo_color = Color8((col >> 16) & 255, (col >> 8) & 255, col & 255)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	if mesh.get_surface_count() == 0:
		return _fail("Model has no supported surfaces")
	mesh_parts.append(mesh)
	var skin := Skin.new()
	for bi in bone_count:
		skin.add_bind(bi, global_rests[bi].affine_inverse())
	for part in mesh_parts:
		var instance := MeshInstance3D.new()
		instance.mesh = part
		root.add_child(instance)
		if bone_count > 0:
			instance.skin = skin
			instance.skeleton = NodePath("../OriginalSkeleton")
		bounds = part.get_aabb() if surface_count == 0 else bounds.merge(part.get_aabb())
		surface_count += part.get_surface_count()
	if bone_count > 0 and Data.PORT_RULES["skeleton_pose"]["initial_pose"] == "model_rest":
		apply_local_pose(rests)
	_bytes.clear()
	return root


func instantiate() -> L3dRig:
	var copy := L3dRig.new()
	copy.bone_count = bone_count
	copy.surface_count = surface_count
	copy.texture_count = texture_count
	copy.parents = parents
	copy.rests = rests
	copy.global_rests = global_rests
	copy.bounds = bounds
	copy.root = root.duplicate()
	copy.skeleton = copy.root.get_node("OriginalSkeleton")
	return copy


func apply_local_pose(pose: Array[Transform3D]) -> void:
	if pose.size() != bone_count:
		return
	for bi in bone_count:
		# Godot 4's local bone pose already includes the bone's rest transform.
		# The original readers also produce a parent-local absolute pose, so
		# applying the inverse rest here would distort the entire hierarchy.
		var local := pose[bi]
		skeleton.set_bone_pose_position(bi, local.origin)
		skeleton.set_bone_pose_rotation(bi, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bi, local.basis.get_scale())


func _transform(p: int) -> Transform3D:
	return Transform3D(Basis(_vec(p), _vec(p + 12), _vec(p + 24)), _vec(p + 36))


func _vec(p: int) -> Vector3:
	return Vector3(_bytes.decode_float(p), _bytes.decode_float(p + 4), _bytes.decode_float(p + 8))


func _u(p: int) -> int:
	return _bytes.decode_u32(p) if _fits(p, 4) else 0


func _fits(p: int, size: int) -> bool:
	return p >= 0 and size >= 0 and p + size <= _bytes.size()


func _fail(message: String) -> Node3D:
	error = message
	if is_instance_valid(root):
		root.free()
	root = null
	_bytes.clear()
	return null
