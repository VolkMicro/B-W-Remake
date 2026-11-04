# Compare the port against values independently produced by the original
# installed executable in an isolated x86 emulator; no host data is exported.
extends SceneTree

const Data := preload("res://scripts/data.gd")
var host := ""
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(label)
		printerr("FAIL ", label)


func _run() -> void:
	var models := G3dReader.new()
	var info := HostInfoReader.new()
	var opened := not host.is_empty() and models.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and info.load_file(host.path_join("Scripts/info.dat"), models.mesh_offsets.size())
	check(opened and info.influence_settings.size() == 3, "read original influence settings from the player's installation")
	var oracle = JSON.parse_string(OS.get_environment("BW_INFLUENCE_ORACLE"))
	check(oracle is Array and oracle.size() >= 30, "original executable provides independent comparison cases")
	if opened and oracle is Array:
		for sample in oracle:
			var result := InfluenceMath.strength(float(sample["distance"]), float(sample["radius"]), info.influence_settings)
			check(absf(result - float(sample["strength"])) < 0.00002, "match original falloff at " + str(sample["distance"]) + "/" + str(sample["radius"]))
		var from := Vector3(10, 2, -20)
		var to := Vector3(13, 500, -24)
		check(is_equal_approx(InfluenceMath.strength_at(from, to, 30, info.influence_settings), InfluenceMath.strength(5, 30, info.influence_settings)), "height does not change the original horizontal distance")
		check(InfluenceMath.strength(-1, 30, info.influence_settings) < 0 and InfluenceMath.strength(1, 0, info.influence_settings) < 0, "invalid distances and radii are rejected")
		check(InfluenceMath.strength(1, 30, {}) < 0, "missing original settings are rejected")
		var file := FileAccess.open(host.path_join("Scripts/info.dat"), FileAccess.READ)
		file.seek(8)
		var bytes := PackedByteArray()
		while file.get_position() + 36 <= file.get_length():
			var name_bytes := file.get_buffer(32)
			var end := name_bytes.find(0)
			var name := name_bytes.slice(0, end if end >= 0 else 32).get_string_from_ascii()
			var length := file.get_32()
			if name == "Info":
				bytes = file.get_buffer(length)
				break
			file.seek(file.get_position() + length)
		file.close()
		var format: Dictionary = Data.HOST_INFO_FORMATS[info.version]
		if bytes.size() == int(format["info_size"]):
			bytes.encode_float(int(format["influence_offset"]), NAN)
			var invalid := HostInfoReader.new()
			check(not invalid._read_info(bytes, models.mesh_offsets.size()) and invalid.influence_settings.is_empty(), "corrupt influence settings are rejected and cleared")
		else:
			check(false, "load original settings for corruption test")
	models.close()
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)
