extends RefCounted
## Coordinator adapter: original profiles/meshes, world selection and new pure
## controllers. This integration file has legacy context, not clean provenance.

var world: Node3D
var hand: RefCounted
var stream: Node3D
var visual: MeshInstance3D
var _pickup_point := Vector3.ZERO
var _release_point := Vector3.ZERO
var _transfer_origin := Vector3.ZERO
var _drop_velocity := Vector3.ZERO
var _release_clock := 0.0
var _ready := false

func configure(owner: Node3D) -> bool:
	if _ready: return false
	world = owner
	if world.host_info.hand_resources.size() != 2: return false
	hand = load("res://scripts/resource_hand.gd").new()
	var profiles: Array[Dictionary] = world.host_info.hand_resources
	if not hand.configure(profiles): return false
	stream = load("res://scripts/resource_stream.gd").new()
	world.add_child(stream)
	visual = MeshInstance3D.new()
	visual.name = "HeldResource"
	world.add_child(visual)
	visual.hide()
	hand.connect("moved", _moved)
	_ready = true
	return true

func amount() -> int:
	return int(hand.amount) if _ready else 0

func resource() -> int:
	return int(hand.resource) if _ready else -1

func collecting() -> bool:
	return _ready and hand.collecting

func action() -> String:
	if amount() > 0: return "hold_side"
	return "release" if _release_clock > 0.0 else ""

func stop() -> void:
	if _ready: hand.stop()

func begin(selection: Dictionary) -> bool:
	if not _ready or amount() > 0: return false
	var target := selection.get("target") as Node3D
	var resource_index := int(selection.get("resource", -1))
	if not is_instance_valid(target) or resource_index not in [0, 1]: return false
	var store: RefCounted = world.story_resource_store(target)
	if store == null or not world.has_influence(selection["point"]): return false
	_pickup_point = selection["point"]
	visual.mesh = world.g3d.mesh_index(world.host_info.hand_resources[resource_index]["mesh_id"])
	if visual.mesh == null: return false
	if world.hand_rig != null:
		world._hand_action = "hold_side"
		world._update_hand_pose(0.016, selection)
	var taken := bool(hand.begin(resource_index, func(requested: int) -> int:
		var actual: int = store.take(resource_index, requested)
		if is_instance_valid(target) and target.get_meta("loose_resource", false) and store.stock(resource_index) == 0:
			world.things.erase(target)
			world.resource_stores.erase(target.get_instance_id())
			target.state = Thing.State.DEAD
			target.hide()
			target.queue_free()
		return actual))
	if taken: update_visual()
	return taken

func release(selection: Dictionary, velocity := Vector3.ZERO) -> int:
	if not _ready or amount() == 0: return 0
	stop()
	var target := selection.get("target") as Node3D
	var index := resource()
	_transfer_origin = visual.global_position
	_drop_velocity = velocity
	_release_point = selection["point"]
	if not world.has_influence(_release_point): return 0
	var store: RefCounted = world.story_resource_store(target)
	var accepted := 0
	if not velocity.is_zero_approx():
		accepted = hand.give(func(offered: int) -> int: return _drop_pile(index, offered))
	elif store != null and (not target.get_meta("loose_resource", false) or int(target.get_meta("resource_index", -1)) == index):
		accepted = hand.give(func(offered: int) -> int: return store.add(index, offered))
	elif index == 1 and world.story_construction != null and world.story_citadel != null and (target == world.story_citadel or _release_point.distance_to(world.story_citadel.global_position) < 30.0):
		accepted = hand.give(func(offered: int) -> int: return world.story_construction.add_wood(offered))
	elif _release_point.y > world.sea_y + 0.05:
		# A dropped quantified original mesh is a real source, not a second
		# particle wallet. Credit it only inside the controller's give callback.
		accepted = hand.give(func(offered: int) -> int: return _drop_pile(index, offered))
	if accepted > 0: _release_clock = 0.3
	update_visual()
	return accepted

func _drop_pile(index: int, quantity: int) -> int:
	var mesh_id: int = world.host_info.hand_resources[index]["mesh_id"]
	var size := model_scale(index, visual.mesh, quantity, false)
	var pile: Thing = world._place_mesh(mesh_id, _transfer_origin, 0.0, size, "resource_pile")
	if pile == null: return 0
	pile.set_meta("loose_resource", true)
	pile.set_meta("resource_index", index)
	var initial := Vector2i.ZERO
	initial[index] = quantity
	if world.story_bind_storage(pile, initial) == null:
		pile.queue_free()
		return 0
	world.things.append(pile)
	world.world_physics.register_node(pile)
	pile.velocity = _drop_velocity
	pile.launch_from = pile.position
	pile.thrown = not _drop_velocity.is_zero_approx()
	pile.state = Thing.State.FLYING
	return quantity

func advance(delta: float) -> void:
	if not _ready: return
	_release_clock = maxf(0.0, _release_clock - maxf(delta, 0.0))
	hand.advance(delta)

func update_visual() -> void:
	if not _ready: return
	visual.visible = amount() > 0
	if not visual.visible: return
	visual.global_position = grip_point()
	visual.scale = Vector3.ONE * model_scale(resource(), visual.mesh, amount())
	visual.rotation.y = world.yaw

func model_scale(index: int, mesh: Mesh, quantity: int, follow_hand := true) -> float:
	var row: Dictionary = world.host_info.hand_resources[index]
	# Exact original hand-pot scale is still unknown; this adapter preserves
	# its original mesh and uses a bounded size relative to the current hand.
	var hand_size := 6.0
	if world.hand_rig != null:
		var unit_scale: float = world.hand_rig.root.global_transform.basis.get_scale().abs().x
		if not follow_hand: unit_scale = 3.2 / world._hand_bind_span
		hand_size = unit_scale * world.hand_rig.bounds.get_longest_axis_size()
	var fill := clampf(pow(float(quantity) / maxf(float(row["nominal"]), 1.0), 1.0 / 3.0), 0.2, 1.0)
	return hand_size * 0.48 * fill / maxf(mesh.get_aabb().get_longest_axis_size(), 0.001)

func grip_point() -> Vector3:
	if world.hand_rig != null:
		return world.hand_rig.root.global_transform * world.hand_pose.geometry(Basis.IDENTITY)["grip"]
	return world._hand_surface + Vector3.UP * float(world.cfg_hand["hold_height"])

func advance_visuals(delta: float) -> void:
	if not _ready: return
	update_visual()
	stream.advance(delta)

func _moved(direction: String, index: int, quantity: int) -> void:
	if quantity <= 0: return
	if direction == "pickup":
		show_transfer(index, _pickup_point, func() -> Vector3: return grip_point())
	else:
		var endpoint := _release_point
		show_transfer(index, _transfer_origin, func() -> Vector3: return endpoint)

func show_transfer(index: int, origin: Vector3, destination: Callable) -> void:
	if not _ready or index not in [0, 1]: return
	var mesh: Mesh = world.g3d.mesh_index(world.host_info.hand_resources[index]["mesh_id"])
	if mesh == null: return
	var hand_size := 6.0
	if world.hand_rig != null:
		hand_size = world.hand_rig.root.global_transform.basis.get_scale().abs().x * world.hand_rig.bounds.get_longest_axis_size()
	var scale_factor := maxf(hand_size * 0.16 / maxf(mesh.get_aabb().get_longest_axis_size(), 0.001), 0.0001)
	stream.burst(mesh, origin, destination, scale_factor)
