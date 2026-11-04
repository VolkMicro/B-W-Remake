# Compare original gate/cave rig shapes to their original animation records.
extends SceneTree


func _initialize() -> void:
	var host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	if host.is_empty():
		quit(2)
		return
	var models := G3dReader.new()
	var anims := AnmReader.new()
	var names: Array[String] = ["M_NORS_GATE", "M_Gate_Totem_Plinthe", "M_mine_entrance"]
	if not models.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h")) or not anims.load_file(host.path_join("Data/AllAnims.anm"), names):
		printerr("Original landmark archives are unavailable: ", anims.error)
		quit(1)
		return
	var entries := [["MSH_B_NORS_GATE", names[0]], ["MSH_O_GATE_TOTEM_PLINTHE", names[1]], ["MSH_B_MINE_ENTRANCE", names[2]]]
	var errors := 0
	for entry in entries:
		var rig := models.rig(entry[0])
		var clip: Dictionary = anims.clips[entry[1]]
		var ok := rig != null and rig.bone_count == int(clip["bones"])
		print(entry[0], " bones=", rig.bone_count if rig else 0, " clip_bones=", clip["bones"], " compatible=", ok)
		if not ok: errors += 1
		if rig: rig.root.free()
	models.close()
	quit(1 if errors else 0)
