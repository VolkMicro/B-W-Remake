# Read-only compatibility probe for original wildlife rigs and default clips.
extends SceneTree


func _initialize() -> void:
	var host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	if host.is_empty():
		quit(2)
		return
	var pairs := [
		["MSH_A_TORTOISE_1", "M_A_Tortoise_stand"],
		["MSH_A_COW_1", "M_A_Cow_Stand"],
		["MSH_A_HORSE_1", "M_A_horse_stand"],
		["MSH_A_PIG_1", "M_A_pig_walk"],
		["MSH_A_DOVE_1", "M_dove_flap"],
		["MSH_A_SWALLOW_1", "M_swallow_flap"],
		["MSH_A_SEAGULL_1", "M_seagull_flap"],
		["MSH_A_BAT_1", "M_bat_flap"]
	]
	var species := [6, 8, 9, 10, 12, 13, 15, 16]
	var default_animations := [171, 42, 57, 128, 8, 27, 18, 1]
	var clips: Array[String] = []
	for pair in pairs:
		clips.append(pair[1])
	var anims := AnmReader.new()
	if not anims.load_file(host.path_join("Data/AllAnims.anm"), clips):
		printerr("Animation archive: ", anims.error)
		quit(1)
		return
	var models := G3dReader.new()
	if not models.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h")):
		printerr("Model archive unavailable")
		quit(1)
		return
	var info := HostInfoReader.new()
	if not info.load_file(host.path_join("Scripts/info.dat"), models.mesh_offsets.size()):
		printerr("Wildlife information: ", info.error)
		models.close()
		quit(1)
		return
	var failures := 0
	for i in pairs.size():
		var pair: Array = pairs[i]
		var rig := models.rig(pair[0])
		var clip: Dictionary = anims.clips[pair[1]]
		var original := info.animal(species[i])
		var good: bool = rig != null and rig.bone_count == int(clip["bones"]) and int(original["mesh_id"]) == int(models.name_to_index[pair[0]]) and int(original["animation_id"]) == default_animations[i]
		if not good: failures += 1
		print(pair[0], " model bones=", rig.bone_count if rig else 0, " animation bones=", clip["bones"], " compatible=", good)
		if rig: rig.root.free()
	models.close()
	quit(1 if failures else 0)
