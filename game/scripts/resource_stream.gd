extends Node3D
## ResourceStream - cosmetic pickup/putdown particle paths for SPEC-RESOURCE-HAND-001 v1.
## Exact original particle trajectories are UNKNOWN. This bounded arc is a new
## remake presentation policy, not a decoding of any original particle system.
## Owns no economic quantity. Coordinates are view-local. There is no automatic
## processing: the caller advances once per frame.

const MAX_PARTICLES: int = 64
const ARC_MIN: float = 0.4
const ARC_MAX: float = 4.0
const ARC_DISTANCE_FACTOR: float = 0.12


class Particle extends RefCounted:
	var node: MeshInstance3D = null
	var origin: Vector3 = Vector3.ZERO
	var endpoint: Vector3 = Vector3.ZERO
	var destination: Callable = Callable()
	var arc: float = 0.4
	var seconds: float = 1.0
	var progress: float = 0.0


var _particles: Array[Particle] = []
var _busy: bool = false


func burst(mesh: Mesh, origin: Vector3, destination: Callable, scale_factor: float, seconds: float = 0.35) -> bool:
	if _busy:
		return false
	_prune_invalid()
	if _particles.size() >= MAX_PARTICLES:
		return false
	if not _mesh_is_usable(mesh):
		return false
	if not origin.is_finite():
		return false
	if not is_finite(scale_factor) or scale_factor <= 0.0:
		return false
	if not is_finite(seconds) or seconds <= 0.0:
		return false
	var uniform_scale: Vector3 = Vector3.ONE * scale_factor
	if not uniform_scale.is_finite():
		return false
	if uniform_scale.x <= 0.0 or uniform_scale.y <= 0.0 or uniform_scale.z <= 0.0:
		return false
	if not destination.is_valid():
		return false
	_busy = true
	var sampled: Variant = destination.call()
	_busy = false
	if typeof(sampled) != TYPE_VECTOR3:
		return false
	var endpoint: Vector3 = sampled
	if not endpoint.is_finite():
		return false
	var arc: float = _arc_for(origin, endpoint)
	if not is_finite(arc):
		return false
	if not _path_is_finite(origin, endpoint, arc):
		return false
	if not _mesh_is_usable(mesh) or _particles.size() >= MAX_PARTICLES:
		return false
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = uniform_scale
	instance.position = origin
	add_child(instance)
	var particle: Particle = Particle.new()
	particle.node = instance
	particle.origin = origin
	particle.endpoint = endpoint
	particle.destination = destination
	particle.arc = arc
	particle.seconds = seconds
	particle.progress = 0.0
	_particles.append(particle)
	return true


func advance(delta: float) -> void:
	if _busy:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	_busy = true
	var survivors: Array[Particle] = []
	for particle: Particle in _particles:
		if not is_instance_valid(particle.node):
			continue
		_refresh_endpoint(particle)
		if not is_instance_valid(particle.node):
			continue
		var progress: float = particle.progress
		if delta > 0.0:
			var step: float = delta / particle.seconds
			if not is_finite(step) or step >= 1.0 - progress:
				progress = 1.0
			else:
				progress += step
		if progress >= 1.0:
			_release_node(particle.node)
			particle.node = null
			continue
		particle.progress = progress
		var place: Vector3 = _position_on_path(particle.origin, particle.endpoint, particle.arc, progress)
		if place.is_finite():
			particle.node.position = place
		survivors.append(particle)
	_particles = survivors
	_busy = false


func active_count() -> int:
	_prune_invalid()
	return _particles.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_particles.clear()


func _mesh_is_usable(mesh: Mesh) -> bool:
	if mesh == null or not is_instance_valid(mesh):
		return false
	if mesh.get_surface_count() < 1:
		return false
	var bounds: AABB = mesh.get_aabb()
	if not bounds.position.is_finite() or not bounds.size.is_finite():
		return false
	if bounds.size.y <= 0.0:
		return false
	if bounds.size == Vector3.ZERO:
		return false
	return true


func _arc_for(origin: Vector3, endpoint: Vector3) -> float:
	var distance: float = endpoint.distance_to(origin)
	if not is_finite(distance):
		return NAN
	return minf(ARC_MAX, maxf(ARC_MIN, distance * ARC_DISTANCE_FACTOR))


func _path_is_finite(origin: Vector3, endpoint: Vector3, arc: float) -> bool:
	if not is_finite(arc):
		return false
	var offset: Vector3 = endpoint - origin
	if not offset.is_finite():
		return false
	if not is_finite(endpoint.distance_to(origin)):
		return false
	var midpoint: Vector3 = _position_on_path(origin, endpoint, arc, 0.5)
	return midpoint.is_finite()


func _position_on_path(origin: Vector3, endpoint: Vector3, arc: float, t: float) -> Vector3:
	return origin.lerp(endpoint, t) + Vector3.UP * (arc * 4.0 * t * (1.0 - t))


func _refresh_endpoint(particle: Particle) -> void:
	if not particle.destination.is_valid():
		return
	var sampled: Variant = particle.destination.call()
	if typeof(sampled) != TYPE_VECTOR3:
		return
	var candidate: Vector3 = sampled
	if not candidate.is_finite():
		return
	if not _path_is_finite(particle.origin, candidate, particle.arc):
		return
	particle.endpoint = candidate


func _release_node(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


func _prune_invalid() -> void:
	var kept: Array[Particle] = []
	for particle: Particle in _particles:
		if is_instance_valid(particle.node) and particle.node.get_parent() == self:
			kept.append(particle)
	if kept.size() != _particles.size():
		_particles = kept
