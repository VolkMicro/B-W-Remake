extends RefCounted
## Shared, native BVHs for cursor surfaces and continuous item contacts.
## Terrain still uses the landscape triangles; these are the actual object meshes.
var entries: Array[Dictionary] = []
var _mesh_cache := {}
var _instances := {}
var _synced_frame := -1
var _prepared_entries: Array[Dictionary] = []

func register_node(node: Node3D, target: Node3D = null, rig: L3dRig = null, clip := Callable(), include_hidden := false) -> void:
	if target == null: target = node
	if node is MeshInstance3D and node.mesh != null:
		var id := node.get_instance_id()
		if not _instances.has(id):
			var mesh_id: int = node.mesh.get_instance_id()
			if not _mesh_cache.has(mesh_id):
				var tree := TriangleMesh.new()
				if not tree.create_from_faces(node.mesh.get_faces()): return
				_mesh_cache[mesh_id] = {"tree":tree,"bounds":node.mesh.get_aabb()}
			var cached: Dictionary = _mesh_cache[mesh_id]
			entries.append({"visual":weakref(node),"target":weakref(target),"tree":cached["tree"],
				"bounds":cached["bounds"],"rig":rig,"version":-1,"clip":clip,"mesh_id":mesh_id,"include_hidden":include_hidden})
			_instances[id] = true
			_synced_frame = -1
	for child in node.get_children():
		if child is Node3D: register_node(child, target, rig, clip, include_hidden)

func raycast(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	_sync()
	return _cast(_prepared_entries, origin, origin + direction.normalized() * distance, true)

func _sync() -> void:
	if _synced_frame != Engine.get_process_frames():
		_prepared_entries.clear()
		for entry in entries:
			if _prepare(entry): _prepared_entries.append(entry)
		_synced_frame = Engine.get_process_frames()

func vertical_clearance(bounds: AABB) -> float:
	# One broad-phase lookup for all eight hand corners. A village contains
	# hundreds of trees; scanning every object once per corner is unnecessary.
	_sync()
	var height := bounds.size.y + 1.0
	var region := AABB(bounds.position - Vector3.UP * height, bounds.size + Vector3.UP * height * 2.0).grow(0.01)
	var candidates: Array[Dictionary] = []
	for entry in _prepared_entries:
		if region.intersects(entry["world_bounds"]): candidates.append(entry)
	var raise := 0.0
	for i in 8:
		var point := bounds.get_endpoint(i)
		var hit := _cast(candidates, point + Vector3.UP * height, point - Vector3.UP * height, true)
		if not hit.is_empty(): raise = maxf(raise, hit["point"].y + 0.04 - point.y)
	return raise

func sweep(from: Vector3, to: Vector3, body: Node3D) -> Dictionary:
	if from.is_equal_approx(to): return {}
	var offsets := body_offsets(body)
	var radius := 0.0
	for offset in offsets: radius = maxf(radius, offset.length())
	var candidates: Array[Dictionary] = []
	for entry in entries:
		# A released object can remain registered as a visible solid. Its own
		# triangles must never stop its first movement or make it bounce inside.
		if entry["target"].get_ref() == body: continue
		if not _prepare(entry): continue
		var bounds: AABB = entry["world_bounds"]
		if bounds.grow(radius + 0.02).intersects_segment(from, to) != null:
			candidates.append(entry)
	var closest := INF
	var result := {}
	for offset in offsets:
		var contact := _cast(candidates, from + offset, to + offset, true)
		if contact.is_empty(): continue
		var distance := (from + offset).distance_to(contact["point"])
		if distance < closest:
			closest = distance
			result = contact
			result["root"] = contact["point"] - offset
	return result

func _cast(candidates: Array[Dictionary], from: Vector3, to: Vector3, prepared := false) -> Dictionary:
	var closest := from.distance_to(to) + 0.0001
	var result := {}
	for entry in candidates:
		if not is_instance_valid(entry["target"].get_ref()): continue
		if not prepared and not _prepare(entry): continue
		var bounds: AABB = entry["world_bounds"]
		if bounds.intersects_segment(from, to) == null: continue
		var transform: Transform3D = entry["transform"]
		var inverse := transform.affine_inverse()
		var local_from := inverse * from
		var local_to := inverse * to
		var tree: TriangleMesh = entry["tree"]
		var clip: Callable = entry["clip"]
		for layer in 8:
			var hit := tree.intersect_segment(local_from, local_to)
			if hit.is_empty(): break
			if clip.is_valid() and hit["position"].y > float(clip.call()) + 0.001:
				local_from = hit["position"] + (local_to - local_from).normalized() * 0.01
				continue
			var point: Vector3 = transform * hit["position"]
			var distance := from.distance_to(point)
			if distance < closest:
				closest = distance
				var normal: Vector3 = (transform.basis.inverse().transposed() * hit["normal"]).normalized()
				if normal.dot(to - from) > 0.0: normal = -normal
				result = {"target":entry["target"].get_ref(),"visual":entry["visual"].get_ref(),"point":point,"normal":normal}
			break
	return result

func _prepare(entry: Dictionary) -> bool:
	var visual := entry["visual"].get_ref() as MeshInstance3D
	var target := entry["target"].get_ref() as Node3D
	if not is_instance_valid(visual) or not is_instance_valid(target): return false
	if target.get_meta("story_deleted", false): return false
	if target is Thing and target.state in [Thing.State.HELD, Thing.State.DEAD]: return false
	if not entry["include_hidden"] and visual.is_inside_tree() and not visual.is_visible_in_tree(): return false
	if target.is_inside_tree() and not target.is_visible_in_tree(): return false
	var mesh_id := visual.mesh.get_instance_id()
	if mesh_id != entry["mesh_id"]:
		if not _mesh_cache.has(mesh_id):
			var tree := TriangleMesh.new()
			if not tree.create_from_faces(visual.mesh.get_faces()): return false
			_mesh_cache[mesh_id] = {"tree":tree,"bounds":visual.mesh.get_aabb()}
		entry["tree"] = _mesh_cache[mesh_id]["tree"]
		entry["bounds"] = _mesh_cache[mesh_id]["bounds"]
		entry["mesh_id"] = mesh_id
	var rig: L3dRig = entry["rig"]
	if rig != null and target is OriginalLandmark:
		var version := floori(target.elapsed * 20.0) + 1 if target.playing or target.elapsed > 0.0 else 0
		if version != entry["version"] and version > 0:
			var faces := _posed_faces(visual.mesh, rig)
			var tree := TriangleMesh.new()
			if not tree.create_from_faces(faces): return false
			var bounds := AABB(faces[0], Vector3.ZERO)
			for point in faces: bounds = bounds.expand(point)
			entry["tree"] = tree
			entry["bounds"] = bounds
		entry["version"] = version
	entry["transform"] = node_transform(visual)
	entry["world_bounds"] = entry["transform"] * entry["bounds"]
	return true

static func _posed_faces(mesh: Mesh, rig: L3dRig) -> PackedVector3Array:
	var transforms: Array[Transform3D] = []
	for i in rig.bone_count:
		transforms.append(rig.skeleton.get_bone_global_pose(i) * rig.global_rests[i].affine_inverse())
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if arrays[Mesh.ARRAY_BONES] != null:
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for i in vertices.size(): vertices[i] = transforms[bones[i * 4]] * vertices[i]
		if indices.is_empty(): faces.append_array(vertices)
		else:
			for index in indices: faces.append(vertices[index])
	return faces

static func node_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree(): return node.global_transform
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		transform = parent.transform * transform
		parent = parent.get_parent()
	return transform

static func body_offsets(body: Node3D) -> PackedVector3Array:
	var offsets := PackedVector3Array([Vector3.ZERO])
	var bounds := AABB()
	var found := false
	var rig: L3dRig = body.get("rig")
	if rig != null:
		bounds = rig.bounds
		found = true
	else:
		for child in body.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var child_bounds: AABB = child.transform * child.mesh.get_aabb()
				bounds = bounds.merge(child_bounds) if found else child_bounds
				found = true
	if found:
		for i in 8: offsets.append(body.basis * bounds.get_endpoint(i))
		# Centre-bottom catches a small platform beneath a larger object's base.
		offsets.append(body.basis * Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z))
	return offsets
