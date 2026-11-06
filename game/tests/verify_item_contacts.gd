extends SceneTree

class ContactWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func on_landed(_thing: Thing) -> void: pass

var failures := 0
var passed := 0
var host := "C:/Games/Black and White Complete Collection"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failures += 1

func run() -> void:
	var world := ContactWorld.new()
	world.bw_dir = host
	root.add_child(world)
	var opened := world.lnd.load_file(host.path_join("Data/Landscape/Land1.lnd"))
	opened = opened and world.g3d.open(host.path_join("Data/AllMeshes.g3d"), host.path_join("Data/AllMeshes.h"))
	opened = opened and world.host_info.load_file(host.path_join("Scripts/info.dat"), world.g3d.mesh_offsets.size())
	check(opened, "load original landscape triangles and mobile meshes")
	if not opened:
		quit(1)
		return
	world.sea_y = world.lnd.sea_level
	for kind in ["rock", "gate_key"]:
		var record: Dictionary = world.host_info.record(5 if kind == "rock" else 52)
		var below := 0
		var worst := 0.0
		for i in 12:
			var start: Vector3 = world.to_world(Vector2(1652.78 + (i % 3) * 3.0, 2323.02 + (i / 3) * 3.0))
			var actor: Thing = world._place_mesh(record["mesh_id"], start + Vector3.UP * 12.0, i * 0.37, 1.0, kind)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.rotation.x = i * 0.19
			actor.rotation.z = i * 0.28
			actor.state = Thing.State.FLYING
			actor.velocity = Vector3(8.0 if i % 2 == 0 else -8.0, -100.0, 3.0)
			for step in 600:
				if actor.state == Thing.State.FLYING: actor._fly(1.0 / 60.0)
			var clearance := minimum_clearance(actor, world)
			worst = minf(worst, clearance)
			if clearance < -0.03: below += 1
			actor.free()
		check(below == 0, "%s at tiger key has no mesh below rendered terrain after settling (%d penetrations, minimum %.4f)" % [kind, below, worst])
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "creature_panel", "creature_status", "campaign_status", "choice_row", "ambience", "sea_player"]:
		var node: Node = world.get(property)
		if is_instance_valid(node) and node.get_parent() == null: world.add_child(node)
	world.free()
	print("ITEM CONTACTS ", passed, " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)

func minimum_clearance(actor: Thing, world: Node) -> float:
	var minimum := INF
	for child in actor.get_children():
		if not child is MeshInstance3D or child.mesh == null: continue
		var transform: Transform3D = actor.transform * child.transform
		var faces: PackedVector3Array = child.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			for point in [faces[i], faces[i + 1], faces[i + 2], (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0]:
				var positioned: Vector3 = transform * point
				minimum = minf(minimum, positioned.y - world.ground_y(positioned))
	return minimum
