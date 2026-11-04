# Research: which composition of original CBN rotations with the L3D rest pose keeps creatures' feet planted.
extends SceneTree

const Data := preload("res://scripts/data.gd")
var host := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	call_deferred("_run")


func globals_of(rig: L3dRig, local: Array) -> Array:
	var g := []
	for bi in rig.bone_count:
		var p: int = rig.parents[bi]
		g.append(g[p] * local[bi] if p >= 0 else local[bi])
	return g


func _run() -> void:
	var orders := {"XYZ":EULER_ORDER_XYZ,"XZY":EULER_ORDER_XZY,"YXZ":EULER_ORDER_YXZ,"YZX":EULER_ORDER_YZX,"ZXY":EULER_ORDER_ZXY,"ZYX":EULER_ORDER_ZYX}
	var total_scores := {}
	for id in Data.CREATURES:
		var row: Dictionary = Data.CREATURES[id]
		var rig := L3dRig.new()
		rig.load_file(host.path_join(row["mesh_file"]))
		var morph := MorphReader.new()
		morph.load_file(host.path_join(row["animation_file"]), host.path_join("Data"))
		var rest_g := globals_of(rig, rig.rests)
		var size := 0.0
		for t in rest_g:
			size = maxf(size, t.origin.length())
		var has_child := {}
		for bi in rig.bone_count:
			has_child[rig.parents[bi]] = true
		var leaves := []
		for bi in rig.bone_count:
			if not has_child.has(bi):
				leaves.append([rest_g[bi].origin.y, bi])
		leaves.sort()
		var feet := []
		for k in mini(2 if id == "ape" else 4, leaves.size()):
			feet.append(leaves[k][1])
		print(id, " feet ", feet, " lowest leaves ", leaves.slice(0, 5), " root rest y ", rest_g[0].origin.y)
		var scores := {}
		for clipname in ["move/stand", "move/walk", "move/run"]:
			if not morph.clips.has(clipname):
				continue
			var clip: Dictionary = morph.clips[clipname]
			var rids: PackedInt32Array = clip["rids"]
			var tids: PackedInt32Array = clip["tids"]
			var stride: int = (rids.size() + tids.size()) * 12
			var nf: int = clip["frames"]
			for oname in orders:
				for sign in [1.0, -1.0]:
					for refl in [true, false]:
						var key := "%s s%d r%s" % [oname, sign, refl]
						var mins := []
						var spread := 0.0
						for f in nf:
							var local: Array = rig.rests.duplicate()
							for i in rids.size():
								var idx := rids[i]
								var e: Vector3 = morph._vec(clip["offset"] + f * stride + i * 12) * sign
								var b: Basis = Basis.from_euler(e, orders[oname])
								if refl:
									b = L3dRig.reflected(Transform3D(b, Vector3.ZERO)).basis
								var rest: Transform3D = rig.rests[idx]
								local[idx] = Transform3D(rest.basis * b, rest.origin)
							var g := globals_of(rig, local)
							var ys := []
							for ft in feet:
								ys.append(g[ft].origin.y - g[0].origin.y)
							ys.sort()
							mins.append(ys[0])
							if clipname == "move/stand":
								spread += (ys[-1] - ys[0]) / size
						var mean := 0.0
						for m in mins:
							mean += m
						mean /= mins.size()
						var var_ := 0.0
						for m in mins:
							var_ += (m - mean) * (m - mean)
						var sc: float = sqrt(var_ / mins.size()) / size + spread / nf
						scores[key] = scores.get(key, 0.0) + sc
		var res := []
		for k in scores:
			res.append([scores[k], k])
			total_scores[k] = total_scores.get(k, 0.0) + scores[k]
		res.sort_custom(func(a, b): return a[0] < b[0])
		for k in 8:
			print("  ", "%.4f" % res[k][0], " ", res[k][1])
	var all := []
	for k in total_scores:
		all.append([total_scores[k], k])
	all.sort_custom(func(a, b): return a[0] < b[0])
	print("TOTAL")
	for k in 10:
		print("  ", "%.4f" % all[k][0], " ", all[k][1])
	quit(0)
