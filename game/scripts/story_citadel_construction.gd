# The first temple's bounded supply/build loop. Work consumes original resources
# at completed original animation cycles; no elapsed-time completion shortcut.
class_name StoryCitadelConstruction
extends RefCounted

const WORK_CLIPS := [276, 354, 380]
const INTO_CLIPS := [284, 292, 293]
const CARRY_CLIP := 214
const INFO_SIZE := 582022
const CITADEL_ROW := 71060
const FEMALE_ROW := 186084
const MALE_ROW := 187000
# Progress accumulates fractions of the whole wood cost. Roundoff must not turn
# an integral remainder such as 2500.000000000001 into a 2501-wood reservation.
# One thousandth of a wood unit also covers the original VM's float32 progress
# writes (.9 becomes .899999976158). Whole-unit costs and work rates are intact.
const WOOD_ROUNDING_EPSILON := 0.001
const ROUTE_CELL := 5.0

var error := ""
var wood := 0
var wood_consumed := 0
var wood_cost := 0.0
var max_builders := 0
var completion_prevented := true
var animations := AnmReader.new()
var jobs: Array[Dictionary] = []
var _world: Node
var _site: Node3D
var _town := 0
var _storages: Array[Node3D] = []
var _work_points := PackedVector3Array()
var _profiles := {}
var _failed_routes := {}


func configure(world: Node, site: Node3D, town: int) -> bool:
	_world = world
	_site = site
	_town = town
	var info := _read_info(world.bw_dir.path_join("Scripts/info.dat"))
	if info.size() != INFO_SIZE:
		error = "Unsupported original construction information"
		return false
	wood_cost = float(info.decode_u32(CITADEL_ROW + 0x5c)) * site.scale.x
	max_builders = info.decode_u32(CITADEL_ROW + 0x100)
	for entry in [["male", MALE_ROW], ["female", FEMALE_ROW]]:
		_profiles[entry[0]] = {"capacity": info.decode_u32(entry[1] + 0x258),
			"per_cycle": info.decode_float(entry[1] + 0x26c)}
	if wood_cost <= 0.0 or max_builders < 1 or max_builders > 100:
		error = "Invalid original temple cost or builder limit"
		return false
	var indices := PackedInt32Array(WORK_CLIPS + INTO_CLIPS + [CARRY_CLIP])
	if not animations.load_file(world.bw_dir.path_join("Data/AllAnims.anm"), [], indices):
		error = animations.error
		return false
	for command in world.island.all("CREATE_ABODE"):
		var args: PackedStringArray = command["args"]
		if args.size() < 7 or int(args[0]) != town or not args[2].ends_with("STORAGE_PIT"):
			continue
		var point: Vector3 = world.to_world(IslandScript.pos(args[1]))
		for landmark in world.story_landmarks:
			if landmark is Node3D and landmark.get_meta("original_type", "") == args[2] and landmark.position.distance_to(point) < 0.1:
				if world.has_method("story_bind_storage"):
					if world.story_bind_storage(landmark, Vector2i(int(args[5]), int(args[6]))) == null:
						error = "Invalid source storage resource ledger"
						return false
				if not landmark.has_meta("story_wood_stock"):
					landmark.set_meta("story_wood_stock", int(args[6]))
				_storages.append(landmark)
				break
	# Original building jobs use ground positions on the building's perimeter.
	# The general original clearance/path solver is not yet ported; use actual
	# neutral temple base vertices, rather than an invented radius or teleport.
	for child in site._finished.get_children():
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if vertex.y < 0.5 and Vector2(vertex.x, vertex.z).length() > 10.0:
						_work_points.append(vertex)
	return not _work_points.is_empty()


func set_forced_desire(value: float) -> void:
	_site.set_forced_desire(value)


func add_wood(amount: int) -> int:
	if amount < 0:
		return 0
	wood += amount
	return amount


func storage_wood() -> int:
	var result := 0
	for storage in _storages:
		if is_instance_valid(storage):
			result += int(storage.get_meta("story_wood_stock", 0))
	return result


func take_storage_wood(point: Vector3, amount: int, radius := 12.0) -> int:
	if amount <= 0:
		return 0
	var nearest: Node3D
	var distance := radius
	for storage in _storages:
		if not is_instance_valid(storage):
			continue
		var offset := Vector2(point.x - storage.position.x, point.z - storage.position.z).length()
		if offset <= distance:
			nearest = storage
			distance = offset
	if nearest == null:
		return 0
	return _take_from(nearest, amount)


func advance() -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_site):
		return
	var limit := 0.9 if completion_prevented else 1.0
	if _site.forced_desire <= 0.0 or _site.progress >= 1.0:
		_release_all()
		return
	if completion_prevented and maxf(limit - _site.progress, 0.0) * wood_cost <= WOOD_ROUNDING_EPSILON:
		_pause_at_cap()
		return
	for job in jobs.duplicate():
		var builder := job["builder"] as Thing
		if not _available(builder, true):
			_release(job)
			continue
		var target: Vector3 = job["target"]
		var distance := Vector2(builder.position.x - target.x, builder.position.z - target.z).length()
		match job["state"]:
			"paused":
				if job["resume_state"] == "storage" and builder.story_resources.y == 0:
					_get_supplies(job)
				else:
					_to_site(job)
			"storage":
				# A real Hand delivery can cover an already scheduled pickup.
				# Cancel that reservation before an unnecessary empty round trip.
				if _wood_needed(job) == 0:
					job["reserved_wood"] = 0
					_to_site(job)
					continue
				if distance > 0.25:
					_maintain_route(job)
					continue
				var profile: Dictionary = _profiles[builder.animation_profile]
				var amount := _take_from(job["storage"], mini(int(profile["capacity"]) - builder.story_resources.y, _wood_needed(job)))
				job["reserved_wood"] = 0
				builder.add_story_resource(1, amount)
				_to_site(job)
			"site":
				if distance > 0.25:
					_maintain_route(job)
					continue
				if builder.story_resources.y > 0:
					add_wood(builder.story_resources.y)
					builder.story_resources.y = 0
				builder.set_script_focus(_site.position)
				if wood <= 0:
					_get_supplies(job)
				else:
					_start_work(job)
			"waiting":
				# ADD_RESOURCE can give a waiting villager real wood while the
				# tutorial is running. That carried wood counts in _wood_needed(),
				# so waiting for a positive need here deadlocks its own delivery.
				if builder.story_resources.y > 0:
					_to_site(job)
				elif wood > 0:
					_start_work(job)
				elif _wood_needed(job) > 0 and storage_wood() > 0:
					_get_supplies(job)
			"into":
				if _cycle_finished(job):
					job["entered"] = true
					if _play(job, WORK_CLIPS[job["work_type"]]):
						job["state"] = "build"
			"build":
				if distance > 0.25 or not _cycle_finished(job):
					continue
				var per_cycle := float(_profiles[builder.animation_profile]["per_cycle"])
				# MapCoords alignment is -1..1; the port's alignment is -100..100.
				var alignment: float = clampf(float(_world.alignment) / 100.0, -1.0, 1.0)
				var used := mini(wood, int(per_cycle * clampf(1.0 - alignment * 0.2, 1.0, 1.2)))
				used = mini(used, _whole_wood_cost(maxf(limit - _site.progress, 0.0) * wood_cost))
				if used > 0:
					wood -= used
					wood_consumed += used
					var next_progress: float = _site.progress + used / wood_cost
					if maxf(limit - next_progress, 0.0) * wood_cost <= WOOD_ROUNDING_EPSILON:
						next_progress = limit
					_site.set_progress(minf(limit, next_progress))
				if _site.progress >= limit:
					if completion_prevented:
						_pause_at_cap()
					else:
						_release_all()
					return
				if wood > 0:
					_play(job, WORK_CLIPS[job["work_type"]])
				else:
					_get_supplies(job)
	for candidate in _world.things:
		var builder := candidate as Thing
		if jobs.size() >= max_builders:
			break
		if not _available(builder) or _has_job(builder):
			continue
		if _failed_routes.has(builder.get_instance_id()) and builder.position.distance_to(_failed_routes[builder.get_instance_id()]) < 1.0:
			continue
		if builder.story_resources.y == 0 and wood == 0 and storage_wood() == 0:
			continue
		# Do not recruit another empty carrier after existing deliveries and
		# reserved pickups already cover everything still needed by the temple.
		if builder.story_resources.y == 0 and wood == 0 and _wood_needed() == 0:
			continue
		var point := _work_point(builder.position)
		var job := {"builder":builder, "state":"", "target":point, "work_point":point,
			"work_type":randi_range(0, 2), "original_hold":builder.story_hold_position,
			"entered":false, "reserved_wood":0}
		jobs.append(job)
		builder.story_hold_position = true
		if builder.story_resources.y > 0 or wood > 0:
			_to_site(job)
		else:
			_get_supplies(job)


func _available(builder: Thing, assigned := false) -> bool:
	return is_instance_valid(builder) and not builder.is_queued_for_deletion() and builder.kind == "villager" and builder.town == _town and builder.state == Thing.State.IDLE \
		and builder.story_age >= 16 and not builder.has_meta("story_villager_subtype") \
		and not is_instance_valid(builder.story_flock) and _profiles.has(builder.animation_profile) \
		and (assigned or (not builder.story_hold_position and not builder._script_move_active and not builder.is_script_animation_playing()))


func _has_job(builder: Thing) -> bool:
	for job in jobs:
		if job["builder"] == builder:
			return true
	return false


func _wood_needed(exclude_reservation := {}) -> int:
	var carried := 0
	var reserved := 0
	for job in jobs:
		var builder := job["builder"] as Thing
		if is_instance_valid(builder):
			carried += builder.story_resources.y
			if job != exclude_reservation:
				reserved += int(job.get("reserved_wood", 0))
	return maxi(0, _whole_wood_cost((1.0 - _site.progress) * wood_cost) - wood - carried - reserved)


static func _whole_wood_cost(remaining: float) -> int:
	return maxi(0, int(ceil(remaining - WOOD_ROUNDING_EPSILON)))


func diagnostics() -> Dictionary:
	var states := {}
	var reserved := 0
	var carried := 0
	var details: Array[Dictionary] = []
	for job in jobs:
		var builder := job["builder"] as Thing
		if not is_instance_valid(builder):
			continue
		var state: String = job["state"]
		var next_step := builder.position.move_toward(builder._script_move_target, 0.5)
		states[state] = int(states.get(state, 0)) + 1
		reserved += int(job.get("reserved_wood", 0))
		carried += builder.story_resources.y
		details.append({"id":builder.get_instance_id(), "state":state,
			"reserved":job.get("reserved_wood", 0), "carried":builder.story_resources.y,
			"distance":_horizontal_distance(builder.position, job["target"]),
			"move_active":builder._script_move_active, "speed_per_turn":builder.story_speed_per_turn,
			"clip":builder._script_clip, "clip_age":builder._script_clip_age,
			"position":builder.position, "target":job["target"], "move_target":builder._script_move_target,
			"next_ground":_world.ground_y(next_step), "sea":_world.sea_y,
			"in_tree":builder.is_inside_tree(), "physics":builder.is_physics_processing()})
	return {"states":states, "reserved":reserved, "carried":carried, "needed":_wood_needed(), "jobs":details}


func _take_from(storage: Node3D, amount: int) -> int:
	if not is_instance_valid(storage) or amount <= 0:
		return 0
	if _world.has_method("story_resource_store"):
		var store: RefCounted = _world.story_resource_store(storage)
		if store != null: return store.take(1, amount)
	var stock := int(storage.get_meta("story_wood_stock", 0))
	var taken := mini(stock, amount)
	storage.set_meta("story_wood_stock", stock - taken)
	return taken


func _get_supplies(job: Dictionary) -> void:
	var builder := job["builder"] as Thing
	job["reserved_wood"] = 0
	var needed := _wood_needed(job)
	if builder.story_resources.y > 0:
		_to_site(job)
		return
	var nearest: Node3D
	var distance := INF
	for storage in _storages:
		if is_instance_valid(storage) and int(storage.get_meta("story_wood_stock", 0)) > 0:
			var offset := storage.position.distance_to(builder.position)
			if offset < distance:
				nearest = storage
				distance = offset
	if nearest == null or needed == 0:
		if _horizontal_distance(builder.position, job["work_point"]) > 0.25:
			_to_site(job)
		else:
			_wait_at_site(job)
		return
	job["reserved_wood"] = mini(needed, int(_profiles[builder.animation_profile]["capacity"]))
	job["storage"] = nearest
	job["state"] = "storage"
	job["target"] = nearest.position
	_start_walk(job, nearest.position)
	job["entered"] = false


func _to_site(job: Dictionary) -> void:
	var builder := job["builder"] as Thing
	# A pickup reservation only exists while the actor is going to storage.
	# Any return to the work site cancels that promise, including externally
	# granted carried wood and routes resumed after the 90% tutorial cap.
	job["reserved_wood"] = 0
	job["state"] = "site"
	job["target"] = job["work_point"]
	if not _start_walk(job, job["target"]):
		return
	if builder.story_resources.y > 0:
		builder.override_script_move_animation(animations, CARRY_CLIP)


func _start_walk(job: Dictionary, target: Vector3) -> bool:
	var builder := job["builder"] as Thing
	var path := _land_route(builder.position, target)
	if path.is_empty():
		# An unreachable worker must not reserve the remaining supply forever.
		# Reconsider it after the Hand or another real action changes its position.
		_failed_routes[builder.get_instance_id()] = builder.position
		_release(job)
		return false
	_failed_routes.erase(builder.get_instance_id())
	if path.size() == 1:
		return builder.set_script_move(target, 0.1)
	return builder.set_script_path(path)


func _maintain_route(job: Dictionary) -> void:
	var builder := job["builder"] as Thing
	if builder.is_script_animation_playing():
		return
	var direction := builder._script_move_target - builder.position
	direction.y = 0.0
	var next := builder.position + direction.normalized() * minf(2.0, direction.length())
	if not builder._script_move_active or not _walkable_segment(builder.position, next):
		_start_walk(job, job["target"])


func _walkable_segment(from: Vector3, to: Vector3) -> bool:
	var steps := maxi(1, int(ceil(_horizontal_distance(from, to) / 2.0)))
	for i in range(steps + 1):
		if _world.ground_y(from.lerp(to, float(i) / steps)) <= _world.sea_y + 0.2:
			return false
	return true


func _land_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _walkable_segment(from, to):
		return PackedVector3Array([to])
	# Original villagers use footpaths/MoveToWithHug. The port's straight walk
	# rejects water but cannot turn around it. Route only through actual dry
	# terrain cells and retain the existing physical walking/animation speed.
	for margin in [80.0, 160.0, 320.0]:
		var low := Vector2i(floori((minf(from.x, to.x) - margin) / ROUTE_CELL), floori((minf(from.z, to.z) - margin) / ROUTE_CELL))
		var high := Vector2i(ceili((maxf(from.x, to.x) + margin) / ROUTE_CELL), ceili((maxf(from.z, to.z) + margin) / ROUTE_CELL))
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(low, high - low + Vector2i.ONE)
		grid.cell_size = Vector2.ONE * ROUTE_CELL
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				var point := Vector3(x * ROUTE_CELL, 0.0, z * ROUTE_CELL)
				if _world.ground_y(point) <= _world.sea_y + 0.2:
					grid.set_point_solid(Vector2i(x, z))
		var start: Variant = _route_connection(grid, from)
		var finish: Variant = _route_connection(grid, to)
		if start == null or finish == null:
			continue
		var points := grid.get_point_path(start, finish)
		if points.is_empty():
			continue
		var path := PackedVector3Array()
		for point in points:
			var position := Vector3(point.x, 0.0, point.y)
			position.y = _world.ground_y(position)
			path.append(position)
		path.append(to)
		var simplified := PackedVector3Array()
		var current := from
		var index := 0
		while index < path.size():
			var reachable := -1
			for i in range(path.size() - 1, index - 1, -1):
				if _walkable_segment(current, path[i]):
					reachable = i
					break
			if reachable < 0:
				simplified.clear()
				break
			simplified.append(path[reachable])
			current = path[reachable]
			index = reachable + 1
		if not simplified.is_empty():
			return simplified
	return PackedVector3Array()


func _route_connection(grid: AStarGrid2D, point: Vector3) -> Variant:
	var centre := Vector2i(roundi(point.x / ROUTE_CELL), roundi(point.z / ROUTE_CELL))
	var best: Variant = null
	var distance := INF
	for x in range(centre.x - 2, centre.x + 3):
		for z in range(centre.y - 2, centre.y + 3):
			var cell := Vector2i(x, z)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
				continue
			var position := Vector3(x * ROUTE_CELL, 0.0, z * ROUTE_CELL)
			position.y = _world.ground_y(position)
			if point.distance_squared_to(position) < distance and _walkable_segment(point, position):
				best = cell
				distance = point.distance_squared_to(position)
	return best


func _start_work(job: Dictionary) -> void:
	if job["entered"]:
		if _play(job, WORK_CLIPS[job["work_type"]]):
			job["state"] = "build"
	elif _play(job, INTO_CLIPS[job["work_type"]]):
		job["state"] = "into"


func _wait_at_site(job: Dictionary) -> void:
	var builder := job["builder"] as Thing
	job["state"] = "waiting"
	job["target"] = job["work_point"]
	builder.story_hold_position = true
	builder._script_move_active = false
	builder._script_move_clip = ""
	if builder._script_animations == animations:
		builder._script_clip = ""


func _pause_at_cap() -> void:
	# Keep the workforce and its real carried/site resources in place while
	# PreventCitadelCompletion holds at 90%. Releasing everyone to wander home
	# imposed another complete walking leg after the tutorial lifted the cap.
	for job in jobs.duplicate():
		var builder := job["builder"] as Thing
		if not _available(builder, true):
			_release(job)
			continue
		if job["state"] == "paused":
			continue
		job["resume_state"] = job["state"]
		job["state"] = "paused"
		builder.story_hold_position = true
		builder._script_move_active = false
		builder._script_move_clip = ""
		if builder._script_animations == animations:
			builder._script_clip = ""


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _play(job: Dictionary, animation: int) -> bool:
	var builder := job["builder"] as Thing
	if not builder.prepare_script_animation(animations, animation, 1) or not builder.play_script_animation():
		_release(job)
		return false
	job["clip"] = animations.names_by_index[animation]
	return true


func _cycle_finished(job: Dictionary) -> bool:
	var builder := job["builder"] as Thing
	var clip: String = job["clip"]
	if builder._script_animations != animations or builder._prepared_script_clip != clip:
		_release(job)
		return false
	if builder.is_script_animation_playing():
		if builder._script_clip != clip:
			_release(job)
		return false
	if builder._script_clip_age + 0.00001 < float(animations.clips[clip]["duration"]):
		_release(job)
		return false
	return true


func _work_point(from: Vector3) -> Vector3:
	var best := _site.entrance_position() as Vector3
	var distance := INF
	for local in _work_points:
		var direction := Vector3(local.x, 0, local.z).normalized()
		var point: Vector3 = _site.global_transform * (local + direction * 1.5)
		point.y = _world.ground_y(point)
		var occupied := false
		for job in jobs:
			if point.distance_to(job["work_point"]) < 2.0:
				occupied = true
				break
		if not occupied and point.distance_to(from) < distance:
			best = point
			distance = point.distance_to(from)
	return best


func _release(job: Dictionary) -> void:
	var builder := job["builder"] as Thing
	if is_instance_valid(builder):
		builder.story_hold_position = job["original_hold"]
		builder._script_move_active = false
		builder._script_move_clip = ""
		if builder._script_animations == animations:
			builder._script_clip = ""
	jobs.erase(job)


func _release_all() -> void:
	for job in jobs.duplicate():
		_release(job)


static func _read_info(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_buffer(8).get_string_from_ascii() != "LiOnHeAd":
		return PackedByteArray()
	while file.get_position() + 36 <= file.get_length():
		var raw := file.get_buffer(32)
		var end := raw.find(0)
		var name := raw.slice(0, end if end >= 0 else 32).get_string_from_ascii()
		var length := file.get_32()
		var start := file.get_position()
		if length > file.get_length() - start:
			return PackedByteArray()
		if name == "Info":
			return file.get_buffer(length)
		file.seek(start + length)
	return PackedByteArray()
