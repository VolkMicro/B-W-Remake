extends SceneTree

var passed := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run_test")


func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
		print("PASS ", description)
	else:
		failures += 1
		printerr("FAIL ", description)


func mesh_height_error(land: LndReader, stride := 1) -> float:
	var mesh := land.build_mesh()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	# Compare with points on the actual rendered triangles, including interiors
	# off the diagonal where bilinear interpolation gives a different surface.
	for i in range(0, vertices.size(), 3 * stride):
		for weights in [Vector3(0.2, 0.3, 0.5), Vector3(0.6, 0.25, 0.15)]:
			var point: Vector3 = vertices[i] * weights.x + vertices[i + 1] * weights.y + vertices[i + 2] * weights.z
			worst = maxf(worst, absf(point.y - land.height_at(point.x, -point.z)))
	return worst


func run_test() -> void:
	var land := LndReader.new()
	land.heights.resize(LndReader.GRID * LndReader.GRID)
	land.has_cell.resize(LndReader.GRID * LndReader.GRID)
	land.cells.resize(LndReader.GRID * LndReader.GRID * 8)
	var materials := PackedInt32Array()
	materials.resize(768)
	land.countries.append(materials)
	var origin := 20 * LndReader.GRID + 20
	for offset in [0, 1, LndReader.GRID, LndReader.GRID + 1]:
		land.has_cell[origin + offset] = 1
	land.heights[origin] = 2.0
	land.heights[origin + 1] = 11.0
	land.heights[origin + LndReader.GRID] = 5.0
	land.heights[origin + LndReader.GRID + 1] = 30.0
	for split in [false, true]:
		land.cells[origin * 8 + 6] = 0x10 if split else 0
		var error := mesh_height_error(land)
		check(error < 0.0001, "ground sampler matches both rendered triangles, split=%s (error %.6f)" % [split, error])
	check(land.height_at(-1.0, 200.0) == 0.0 and land.height_at(200.0, -1.0) == 0.0, "outside landscape returns sea bed")
	land.has_cell[origin + 1] = 0
	check(land.height_at(205.0, 205.0) == 0.0, "missing terrain quad does not create invisible ground")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bw="):
			var original := LndReader.new()
			var loaded := original.load_file(argument.substr(5).path_join("Data/Landscape/Land1.lnd"))
			check(loaded, "load original first island")
			if loaded:
				var error := mesh_height_error(original, 17)
				check(error < 0.002, "original first island ground matches rendered triangles (max error %.6f)" % error)
	print("TERRAIN ", passed, " passed, ", failures, " failed")
	quit(0 if failures == 0 else 1)
