# Reads a Black & White landscape (.lnd) from the player's own game folder.
class_name LndReader
extends RefCounted

const CELL := 10.0
const HEIGHT_UNIT := 0.67
const GRID := 513 # 32 blocks * 16 cells + 1

var heights := PackedFloat32Array()
var cells := PackedByteArray() # 8 bytes per grid vertex, copied from the blocks
var has_cell := PackedByteArray()
var countries: Array[PackedInt32Array] = []
var material_images: Array[Image] = []
var sea_level := 2.6 * HEIGHT_UNIT


func load_file(path: String) -> bool:
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 2000:
		return false
	var block_count := d.decode_u32(0)
	var p := 4 + 1024
	var mat_count := d.decode_u32(p)
	var country_count := d.decode_u32(p + 4)
	var block_size := d.decode_u32(p + 8)
	var mat_size := d.decode_u32(p + 12)
	var country_size := d.decode_u32(p + 16)
	var lowres_count := d.decode_u32(p + 20)
	p += 24
	for i in lowres_count:
		p += 16 + d.decode_u32(p + 16)
	heights.resize(GRID * GRID)
	cells.resize(GRID * GRID * 8)
	has_cell.resize(GRID * GRID)
	for b in block_count - 1:
		var o := p + b * block_size
		var meta := o + 289 * 8
		var bx := int(round(d.decode_float(meta + 4) / (16.0 * CELL)))
		var bz := int(round(d.decode_float(meta + 8) / (16.0 * CELL)))
		for r in 17:
			for c in 17:
				var gx := bx * 16 + c
				var gz := bz * 16 + r
				if gx >= GRID or gz >= GRID:
					continue
				var src := o + (c * 17 + r) * 8 # cells are stored x-major
				var gi := gz * GRID + gx
				for k in 8:
					cells[gi * 8 + k] = d[src + k]
				heights[gi] = d[src + 4] * HEIGHT_UNIT
				has_cell[gi] = 1
	p += (block_count - 1) * block_size
	for ci in country_count:
		var arr := PackedInt32Array()
		arr.resize(768)
		for a in 256:
			arr[a * 3] = d.decode_u32(p + 4 + a * 12)
			arr[a * 3 + 1] = d.decode_u32(p + 8 + a * 12)
			arr[a * 3 + 2] = d.decode_u32(p + 12 + a * 12)
		countries.append(arr)
		p += country_size
	for m in mat_count:
		var px := PackedByteArray()
		px.resize(256 * 256 * 3)
		var base := p + 2
		for i in 65536:
			var v := d.decode_u16(base + i * 2)
			px[i * 3] = ((v >> 10) & 31) << 3
			px[i * 3 + 1] = ((v >> 5) & 31) << 3
			px[i * 3 + 2] = (v & 31) << 3
		var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGB8, px)
		img.generate_mipmaps()
		material_images.append(img)
		p += mat_size
	return true


# Height in B&W world coordinates (x, z).
func height_at(x: float, z: float) -> float:
	var fx := x / CELL
	var fz := z / CELL
	if fx < 0.0 or fz < 0.0 or fx >= GRID - 1 or fz >= GRID - 1:
		return 0.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var gi := iz * GRID + ix
	if has_cell[gi] == 0 or has_cell[gi + 1] == 0 or has_cell[gi + GRID] == 0 or has_cell[gi + GRID + 1] == 0:
		return 0.0
	var h00 := heights[gi]
	var h10 := heights[gi + 1]
	var h01 := heights[gi + GRID]
	var h11 := heights[gi + GRID + 1]
	# Objects and the Hand must stand on the same triangles build_mesh renders.
	# Bilinear interpolation bends a quad between its vertices and can put feet
	# above or below the visible ground, especially on the coast and steep slopes.
	if (cells[gi * 8 + 6] & 0x10) != 0:
		if tx >= tz:
			return h00 + (h10 - h00) * tx + (h11 - h10) * tz
		return h00 + (h11 - h01) * tx + (h01 - h00) * tz
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func _corner(gx: int, gz: int) -> Vector3:
	# material pair and blend for one grid vertex: (material a, material b, a weight)
	var gi := gz * GRID + gx
	var props := cells[gi * 8 + 6]
	var country := props & 0x0F
	if country >= countries.size():
		country = 0
	var alt := cells[gi * 8 + 4]
	var arr := countries[country]
	return Vector3(arr[alt * 3], arr[alt * 3 + 1], arr[alt * 3 + 2] / 255.0)


# Builds the island terrain mesh. Godot position = (x, h, -z) so the island is not mirrored.
func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	for gz in GRID - 1:
		for gx in GRID - 1:
			var gi := gz * GRID + gx
			if has_cell[gi] == 0 or has_cell[gi + 1] == 0 or has_cell[gi + GRID] == 0 or has_cell[gi + GRID + 1] == 0:
				continue
			var split := (cells[gi * 8 + 6] & 0x10) != 0
			var q := [Vector2i(gx, gz), Vector2i(gx + 1, gz), Vector2i(gx + 1, gz + 1), Vector2i(gx, gz + 1)]
			var tris := [[0, 2, 1], [0, 3, 2]] if split else [[0, 3, 1], [1, 3, 2]] # front faces up in Godot
			for t in tris:
				var corners: Array[Vector3] = []
				for k in 3:
					var g: Vector2i = q[t[k]]
					corners.append(_corner(g.x, g.y))
				for k in 3:
					var g: Vector2i = q[t[k]]
					var x := g.x * CELL
					var z := g.y * CELL
					verts.append(Vector3(x, heights[g.y * GRID + g.x], -z))
					normals.append(_normal(g.x, g.y))
					c0.append_array([corners[0].x, corners[1].x, corners[2].x, 0.0])
					c1.append_array([corners[0].y, corners[1].y, corners[2].y, 0.0])
					c2.append_array([corners[0].z, corners[1].z, corners[2].z, 0.0])
					var bary := [0.0, 0.0, 0.0, 1.0]
					bary[k] = 1.0
					c3.append_array(bary)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_CUSTOM2] = c2
	arrays[Mesh.ARRAY_CUSTOM3] = c3
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh


func _normal(gx: int, gz: int) -> Vector3:
	var hl := heights[gz * GRID + maxi(gx - 1, 0)]
	var hr := heights[gz * GRID + mini(gx + 1, GRID - 1)]
	var hd := heights[maxi(gz - 1, 0) * GRID + gx]
	var hu := heights[mini(gz + 1, GRID - 1) * GRID + gx]
	# z is negated in Godot space
	return Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized()


func material_array() -> Texture2DArray:
	var arr := Texture2DArray.new()
	arr.create_from_images(material_images)
	return arr
