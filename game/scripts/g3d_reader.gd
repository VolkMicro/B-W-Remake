# Reads meshes (L3D) and their textures from Black & White's Data/AllMeshes.g3d in the player's game folder.
class_name G3dReader
extends RefCounted

var data := PackedByteArray()
var meshes_base := -1
var mesh_offsets := PackedInt32Array()
var tex_chunks := {}
var name_to_index := {}
var _tex_cache := {}
var _mat_cache := {}
var _mesh_cache := {}
var _rig_cache: Dictionary = {}


func open(g3d_path: String, header_path: String) -> bool:
	data = FileAccess.get_file_as_bytes(g3d_path)
	if data.size() < 64:
		return false
	var p := 8
	while p + 36 <= data.size():
		var nm := _cstr(p, 32)
		var sz := data.decode_u32(p + 32)
		if nm == "MESHES":
			meshes_base = p + 36
		elif nm.is_valid_hex_number():
			tex_chunks[nm.hex_to_int()] = p + 36
		p += 36 + sz
	if meshes_base < 0:
		return false
	var n := data.decode_u32(meshes_base + 4)
	mesh_offsets.resize(n)
	for i in n:
		mesh_offsets[i] = data.decode_u32(meshes_base + 8 + i * 4)
	var rx := RegEx.create_from_string("(MSH_[A-Z0-9_]+)\\s*=\\s*(\\d+)")
	for m in rx.search_all(FileAccess.get_file_as_string(header_path)):
		name_to_index[m.get_string(1)] = int(m.get_string(2))
	return true


func _cstr(p: int, n: int) -> String:
	var e := p
	while e < p + n and data[e] != 0:
		e += 1
	return data.slice(p, e).get_string_from_ascii()


func texture(id: int) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var tex: Texture2D = null
	if tex_chunks.has(id):
		var t: int = tex_chunks[id]
		var dd := t + 16
		var h := data.decode_u32(dd + 8)
		var w := data.decode_u32(dd + 12)
		var four := data.slice(dd + 80, dd + 84).get_string_from_ascii()
		var fmt := Image.FORMAT_DXT1
		var bytes := w * h / 2
		if four == "DXT3":
			fmt = Image.FORMAT_DXT3
			bytes = w * h
		elif four == "DXT5":
			fmt = Image.FORMAT_DXT5
			bytes = w * h
		var img := Image.create_from_data(w, h, false, fmt, data.slice(dd + 124, dd + 124 + bytes))
		img.decompress()
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_tex_cache[id] = tex
	return tex


func _material(tex_id: int, argb: int) -> Material:
	var key := "%d_%d" % [tex_id, argb]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	var tex := texture(tex_id)
	if tex:
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.albedo_color = Color8((argb >> 16) & 255, (argb >> 8) & 255, argb & 255)
	_mat_cache[key] = m
	return m


func has_mesh(mesh_name: String) -> bool:
	return name_to_index.has(mesh_name)


func mesh(mesh_name: String) -> ArrayMesh:
	if _mesh_cache.has(mesh_name):
		return _mesh_cache[mesh_name]
	var am: ArrayMesh = null
	if name_to_index.has(mesh_name):
		am = _build(meshes_base + mesh_offsets[name_to_index[mesh_name]])
	_mesh_cache[mesh_name] = am
	return am


func mesh_index(index: int) -> ArrayMesh:
	if index < 0 or index >= mesh_offsets.size():
		return null
	var key := "index:%d" % index
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _build(meshes_base + mesh_offsets[index])
	return _mesh_cache[key]


func rig(mesh_name: String) -> L3dRig:
	if not _rig_cache.has(mesh_name):
		if not name_to_index.has(mesh_name):
			return null
		var start: int = meshes_base + mesh_offsets[name_to_index[mesh_name]]
		var end := data.size()
		for off in mesh_offsets:
			if meshes_base + off > start:
				end = mini(end, meshes_base + off)
		var blueprint := L3dRig.new()
		if blueprint.load_bytes(data.slice(start, end), _material) == null:
			push_error("Original rig %s: %s" % [mesh_name, blueprint.error])
			return null
		_rig_cache[mesh_name] = blueprint
	return (_rig_cache[mesh_name] as L3dRig).instantiate()


func rig_index(index: int) -> L3dRig:
	for mesh_name in name_to_index:
		if int(name_to_index[mesh_name]) == index:
			return rig(mesh_name)
	return null


func close() -> void:
	for blueprint in _rig_cache.values():
		if is_instance_valid(blueprint.root):
			blueprint.root.free()
	_rig_cache.clear()


func _build(q: int) -> ArrayMesh:
	if data.slice(q, q + 4).get_string_from_ascii() != "L3D0":
		return null
	var nsub := data.decode_u32(q + 12)
	var sub_oo := data.decode_u32(q + 16)
	var am := ArrayMesh.new()
	for s in nsub:
		var so := q + data.decode_u32(q + sub_oo + s * 4)
		var sflags := data.decode_u32(so)
		if (sflags & 0x20000000) == 0:
			continue # lower detail levels and collision hulls
		var nprim := data.decode_u32(so + 4)
		var primo := data.decode_u32(so + 8)
		var nb := data.decode_u32(so + 12)
		var bo := data.decode_u32(so + 16)
		var bones: Array[Transform3D] = []
		for b in nb:
			var bp := q + bo + b * 60
			var parent := data.decode_u32(bp)
			var f := []
			for k in 12:
				f.append(data.decode_float(bp + 12 + k * 4))
			var local := Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])), Vector3(f[9], f[10], f[11]))
			if parent < b:
				bones.append(bones[parent] * local)
			else:
				bones.append(local)
		for pi in nprim:
			var pp := q + data.decode_u32(q + primo + pi * 4)
			var tex_id := data.decode_u32(pp + 8)
			var argb := data.decode_u32(pp + 12)
			var nv := data.decode_u32(pp + 16)
			var vo := data.decode_u32(pp + 20)
			var nt := data.decode_u32(pp + 24)
			var to := data.decode_u32(pp + 28)
			var ng := data.decode_u32(pp + 32)
			var go := data.decode_u32(pp + 36)
			if nv == 0 or nt == 0:
				continue
			var vbone := PackedInt32Array()
			vbone.resize(nv)
			vbone.fill(-1)
			if nb > 0 and ng > 0:
				var vi := 0
				for g in ng:
					var e := data.decode_u32(q + go + g * 4)
					var cnt := e & 0xFFFF
					var bone := e >> 16
					for k in cnt:
						if vi < nv:
							vbone[vi] = bone
						vi += 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var uvs := PackedVector2Array()
			for v in nv:
				var vp := q + vo + v * 32
				var pos := Vector3(data.decode_float(vp), data.decode_float(vp + 4), data.decode_float(vp + 8))
				var nrm := Vector3(data.decode_float(vp + 20), data.decode_float(vp + 24), data.decode_float(vp + 28))
				var bi := vbone[v]
				if bi >= 0 and bi < bones.size():
					pos = bones[bi] * pos
					nrm = bones[bi].basis * nrm
				verts.append(Vector3(pos.x, pos.y, -pos.z))
				norms.append(Vector3(nrm.x, nrm.y, -nrm.z).normalized())
				uvs.append(Vector2(data.decode_float(vp + 12), data.decode_float(vp + 16)))
			var idx := PackedInt32Array()
			for t in nt * 3:
				idx.append(data.decode_u16(q + to + t * 2))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = idx
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, _material(tex_id if tex_id != 0xFFFFFFFF else -1, argb))
	if am.get_surface_count() == 0:
		return null
	return am
