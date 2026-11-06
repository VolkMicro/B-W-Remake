extends SceneTree

const Data := preload("res://scripts/data.gd")
var passed := 0
var failed := 0


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok:
		passed += 1
	else:
		failed += 1


func vertex_count(mesh: ArrayMesh) -> int:
	var total := 0
	if mesh != null:
		for surface in mesh.get_surface_count():
			total += mesh.surface_get_array_len(surface)
	return total


func _initialize() -> void:
	var host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	if host.is_empty():
		printerr("Original Black & White folder required")
		quit(2)
		return
	var reader := G3dReader.new()
	if not reader.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h")):
		check(false, "open original mesh archive")
		quit(1)
		return
	for abode_type in Data.ABODES:
		if abode_type.ends_with("GRAVEYARD"):
			continue
		var mesh_name: String = Data.ABODES[abode_type]
		var whole := reader.mesh(mesh_name)
		var finished := reader.mesh(mesh_name, PackedInt32Array([0]))
		var scaffold := reader.mesh(mesh_name, PackedInt32Array([1]))
		check(whole != null and finished != null and scaffold != null and vertex_count(finished) > 0 and vertex_count(scaffold) > 0 and vertex_count(whole) == vertex_count(finished) + vertex_count(scaffold), "original finished %s excludes its scaffold geometry" % abode_type)
	var whole := reader.mesh("MSH_B_NORS_1")
	var finished := reader.mesh("MSH_B_NORS_1", PackedInt32Array([0]))
	var scaffold := reader.mesh("MSH_B_NORS_1", PackedInt32Array([1]))
	check(whole != finished and whole != scaffold and finished != scaffold and finished.get_surface_count() == 4 and scaffold.get_surface_count() == 1, "Norse house keeps separate complete and construction mesh resources")
	check(reader.mesh("MSH_B_NORS_1") == whole and reader.mesh("MSH_B_NORS_1", PackedInt32Array([0])) == finished, "filtered cache does not overwrite the default mesh")
	var index := int(reader.name_to_index["MSH_B_NORS_1"])
	var by_index := reader.mesh_index(index, PackedInt32Array([0]))
	check(vertex_count(by_index) == vertex_count(finished) and reader.mesh_index(index).get_surface_count() == whole.get_surface_count() and reader.mesh_index(index, PackedInt32Array([0])) == by_index, "indexed API filters and caches construction states independently")
	check(reader.mesh("MSH_B_NORS_1", PackedInt32Array([0, 1])) == reader.mesh("MSH_B_NORS_1", PackedInt32Array([1, 0])), "state filter order shares the same mesh cache entry")
	check(reader.mesh("MSH_B_NORS_1", PackedInt32Array([63])) == null and reader.mesh("MSH_B_NORS_1") == whole, "absent state returns no geometry without poisoning the default cache")
	for mesh_name in ["MSH_B_NORS_GRAVEYARD", "MSH_B_AZTC_GRAVEYARD"]:
		var graveyard := reader.mesh(mesh_name)
		var base := reader.mesh(mesh_name, PackedInt32Array([0]))
		check(graveyard != null and base != null and graveyard.get_surface_count() > base.get_surface_count() and vertex_count(graveyard) > vertex_count(base), "default %s preserves its extra grave components" % mesh_name)
	reader.close()
	print("RESULT ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
