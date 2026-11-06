extends Node3D
## Actual AnimatedStatic gate-stone slots, not campaign completion flags.
const KEY_BITS := {362: 1, 364: 4, 366: 2}
var meshes: G3dReader
var landmark: OriginalLandmark
var installed_meshes: Array[int] = []
var _faces := PackedVector3Array()

func configure(owner_landmark: OriginalLandmark, source: G3dReader) -> void:
	landmark = owner_landmark
	meshes = source
	for child in landmark.rig.root.get_children():
		if child is MeshInstance3D:
			_faces.append_array(child.mesh.get_faces())

func info_bits() -> int:
	# Installed AnimatedStatic::GetInfoBits, 0x422df0, sums the three mesh IDs.
	var bits := 0
	for mesh_id in installed_meshes: bits += KEY_BITS[mesh_id]
	return bits

func can_accept(record: Dictionary) -> bool:
	# MobileStatic::ValidToApplyThisToObject checks category 49 and plinth type 1.
	return installed_meshes.size() < 3 and record.get("category", -1) == 49 and KEY_BITS.has(int(record.get("mesh_id", -1)))

func accept(record: Dictionary) -> bool:
	if not can_accept(record): return false
	var mesh_id: int = record["mesh_id"]
	var mesh := meshes.mesh_index(mesh_id)
	if mesh == null: return false
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	# Original Draw 0x42298f: first GetMesh is the KEY, second (0x4229b1)
	# is the PLINTH. The first key starts at plinthHeight, not keyHeight.
	var key_height := mesh.get_aabb().size.y
	if not is_finite(key_height) or key_height <= 0.0:
		visual.free()
		return false
	visual.position.y = landmark.rig.bounds.size.y + key_height * installed_meshes.size() - 0.2
	add_child(visual)
	installed_meshes.append(mesh_id)
	return true

func ray_hit(origin: Vector3, direction: Vector3) -> Variant:
	var inverse := landmark.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	var closest: Variant = null
	var distance := INF
	for i in range(0, _faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, _faces[i], _faces[i + 1], _faces[i + 2])
		if hit != null:
			var point: Vector3 = landmark.global_transform * hit
			var travelled := origin.distance_squared_to(point)
			if travelled < distance:
				distance = travelled
				closest = point
	return closest

func drop_hit(camera: Camera3D, screen: Vector2) -> Variant:
	var hit: Variant = ray_hit(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit != null: return hit
	# Small screen-space forgiveness around the physical pedestal. The same
	# target is shown by the hand and used when releasing the carried key.
	var centre: Vector3 = landmark.global_transform * landmark.rig.bounds.get_center()
	if camera.is_position_behind(centre): return null
	if camera.unproject_position(centre).distance_to(screen) > 30.0: return null
	return ray_hit(camera.project_ray_origin(camera.unproject_position(centre)), camera.project_ray_normal(camera.unproject_position(centre)))
