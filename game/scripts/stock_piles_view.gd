class_name StockPilesView
extends Node3D
## Quantity-driven pile presentation (SPEC-STOCK-PILES-VIEW-001 v1).
## Displays caller-supplied meshes at caller-supplied anchors. Never modifies stock.
## No automatic processing: the caller calls advance(delta) once per game frame.

const _FIELDS: Array[String] = ["resource", "mesh", "nominal", "anchor", "heading", "scale"]

var _configured: bool = false
var _read_stock: Callable = Callable()
var _duration: float = 1.0

var _resources: Array[int] = []
var _nominals: Array[int] = []
var _anchors: Array[Vector3] = []
var _headings: Array[float] = []
var _scales: Array[float] = []
var _heights: Array[float] = []
var _piles: Array[MeshInstance3D] = []

var _amounts: Array[int] = []
var _targets: Array[float] = []
var _start_p: Array[float] = []
var _start_v: Array[float] = []
var _elapsed: Array[float] = []
var _active: Array[bool] = []

var _food_materials: Array[StandardMaterial3D] = []
var _food_base_offsets: Array[Vector3] = []


func configure(read_stock: Callable, definitions: Array[Dictionary], transition_seconds: float = 1.0) -> bool:
	if _configured:
		return false
	if not is_finite(transition_seconds) or transition_seconds <= 0.0:
		return false
	if not read_stock.is_valid():
		return false
	var count: int = definitions.size()
	if count < 2:
		return false

	var res: Array[int] = []
	var meshes: Array[Mesh] = []
	var noms: Array[int] = []
	var anchors: Array[Vector3] = []
	var headings: Array[float] = []
	var scales: Array[float] = []
	var heights: Array[float] = []

	for i: int in count:
		var d: Dictionary = definitions[i]
		for f: String in _FIELDS:
			if not d.has(f):
				return false
		var rv: Variant = d["resource"]
		if typeof(rv) != TYPE_INT:
			return false
		var resource: int = int(rv)
		if i == 0 and resource != 0:
			return false
		if i > 0 and resource != 1:
			return false

		var mv: Variant = d["mesh"]
		if typeof(mv) != TYPE_OBJECT or not is_instance_valid(mv) or not (mv is Mesh):
			return false
		var mesh: Mesh = mv as Mesh
		var aabb: AABB = mesh.get_aabb()
		if not aabb.position.is_finite() or not aabb.size.is_finite():
			return false
		if aabb.size.y <= 0.0:
			return false
		for s: int in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if mat != null and not (mat is StandardMaterial3D):
				return false

		var nv: Variant = d["nominal"]
		if typeof(nv) != TYPE_INT:
			return false
		var nominal: int = int(nv)
		if nominal <= 0:
			return false

		var av: Variant = d["anchor"]
		if typeof(av) != TYPE_VECTOR3:
			return false
		var anchor: Vector3 = av
		if not anchor.is_finite():
			return false

		var hv: Variant = d["heading"]
		if not _is_finite_number(hv):
			return false
		var heading: float = float(hv)

		var sv: Variant = d["scale"]
		if not _is_finite_number(sv):
			return false
		var sc: float = float(sv)
		if sc <= 0.0:
			return false
		var scale_vec: Vector3 = Vector3(sc, sc, sc)
		if not scale_vec.is_finite() or scale_vec.x <= 0.0:
			return false

		var h: float = aabb.size.y * sc
		if not is_finite(h) or h <= 0.0:
			return false
		var h_vec: Vector3 = Vector3(0.0, h, 0.0)
		if not h_vec.is_finite() or h_vec.y <= 0.0:
			return false
		var full_root: Vector3 = anchor
		var empty_root: Vector3 = anchor + Vector3.UP * (-h)
		if not full_root.is_finite() or not empty_root.is_finite():
			return false
		var speed: float = h / transition_seconds
		if not is_finite(speed):
			return false

		res.append(resource)
		meshes.append(mesh)
		noms.append(nominal)
		anchors.append(anchor)
		headings.append(heading)
		scales.append(sc)
		heights.append(h)

	# Single read of the initial snapshot; reused for initialization.
	var raw: Variant = read_stock.call()
	if not _is_valid_snapshot(raw):
		return false
	var snapshot: Vector2i = raw

	# All validation passed: commit configuration and create children.
	_read_stock = read_stock
	_duration = transition_seconds
	_resources = res
	_nominals = noms
	_anchors = anchors
	_headings = headings
	_scales = scales
	_heights = heights
	_piles.clear()
	_amounts.clear()
	_targets.clear()
	_start_p.clear()
	_start_v.clear()
	_elapsed.clear()
	_active.clear()
	_food_materials.clear()
	_food_base_offsets.clear()

	for i: int in count:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Pile%d" % i
		mi.mesh = meshes[i]
		mi.rotation = Vector3(0.0, _headings[i], 0.0)
		mi.scale = Vector3(_scales[i], _scales[i], _scales[i])
		mi.position = _anchors[i]
		mi.set_meta("resource_index", _resources[i])
		mi.set_meta("pile_slot", i)
		if _resources[i] == 0:
			var m: Mesh = meshes[i]
			for s: int in m.get_surface_count():
				var mat: Material = m.surface_get_material(s)
				if mat is StandardMaterial3D:
					var orig: StandardMaterial3D = mat as StandardMaterial3D
					var dup: StandardMaterial3D = orig.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(s, dup)
					_food_materials.append(dup)
					_food_base_offsets.append(orig.uv1_offset)
		_piles.append(mi)
		_amounts.append(0)
		_targets.append(0.0)
		_start_p.append(0.0)
		_start_v.append(0.0)
		_elapsed.append(0.0)
		_active.append(false)
		add_child(mi)

	_configured = true
	_apply_snapshot(snapshot, true)
	return true


func sync(immediate: bool = false) -> void:
	if not _configured:
		return
	_apply_snapshot(_read_snapshot(), immediate)


func advance(delta: float) -> void:
	if not _configured:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	sync(false)
	if delta == 0.0:
		return
	for i: int in _piles.size():
		if not _active[i]:
			continue
		_elapsed[i] += delta
		if _elapsed[i] >= _duration:
			_settle(i)
		_present(i)


func pile(index: int) -> MeshInstance3D:
	if index < 0 or index >= _piles.size():
		return null
	return _piles[index]


func state(index: int) -> Dictionary:
	if index < 0 or index >= _piles.size():
		return {}
	var disp: float = clampf(_anim_p(index), 0.0, 1.0)
	var uv: float = 0.0
	if _resources[index] == 0:
		uv = 0.25 * (1.0 - disp)
	return {
		"resource": _resources[index],
		"pile_slot": index,
		"amount": _amounts[index],
		"nominal": _nominals[index],
		"proportion": disp,
		"target": _targets[index],
		"y_offset": (disp - 1.0) * _heights[index],
		"velocity": _anim_v(index) * _heights[index],
		"visible": _is_shown(index),
		"uv_v": uv,
		"transitioning": _active[index],
	}


# --- internals ---

func _is_finite_number(v: Variant) -> bool:
	var t: int = typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	return is_finite(float(v))


func _is_valid_snapshot(raw: Variant) -> bool:
	if typeof(raw) != TYPE_VECTOR2I:
		return false
	var v: Vector2i = raw
	return v.x >= 0 and v.y >= 0


func _read_snapshot() -> Vector2i:
	if not _read_stock.is_valid():
		return Vector2i.ZERO
	var raw: Variant = _read_stock.call()
	if not _is_valid_snapshot(raw):
		return Vector2i.ZERO
	var v: Vector2i = raw
	return v


func _allocate(snapshot: Vector2i) -> Array[int]:
	var out: Array[int] = []
	var count: int = _piles.size()
	var remaining: int = int(snapshot.y)
	for i: int in count:
		if _resources[i] == 0:
			out.append(int(snapshot.x))
		elif i == count - 1:
			out.append(remaining)
			remaining = 0
		else:
			var amt: int = mini(remaining, _nominals[i])
			out.append(amt)
			remaining -= amt
	return out


func _target_for(i: int, q: int) -> float:
	if q <= 0:
		return 0.0
	var r: float = minf(1.0, float(q) / float(_nominals[i]))
	var a: float = 0.05 + 0.95 * r
	if _resources[i] == 1:
		return a
	var b: float = 1.0 - a
	return 1.0 - b * b


func _apply_snapshot(snapshot: Vector2i, immediate: bool) -> void:
	var amounts: Array[int] = _allocate(snapshot)
	for i: int in _piles.size():
		_amounts[i] = amounts[i]
		var tgt: float = _target_for(i, amounts[i])
		if immediate:
			_targets[i] = tgt
			_settle(i)
		elif tgt != _targets[i]:
			var p: float = _anim_p(i)
			var v: float = _anim_v(i)
			_start_p[i] = p
			_start_v[i] = v
			_targets[i] = tgt
			_elapsed[i] = 0.0
			_active[i] = true
		_present(i)


func _settle(i: int) -> void:
	_start_p[i] = _targets[i]
	_start_v[i] = 0.0
	_elapsed[i] = 0.0
	_active[i] = false


## Unclamped animated proportion.
func _anim_p(i: int) -> float:
	if not _active[i]:
		return _targets[i]
	var t: float = clampf(_elapsed[i] / _duration, 0.0, 1.0)
	var u: float = 1.0 - t
	var f: float = 6.0 * t * t - 8.0 * t * t * t + 3.0 * t * t * t * t
	var g: float = t * u * u * u
	return _start_p[i] + (_targets[i] - _start_p[i]) * f + _start_v[i] * _duration * g


## Unclamped animated derivative in proportion/second.
func _anim_v(i: int) -> float:
	if not _active[i]:
		return 0.0
	var t: float = clampf(_elapsed[i] / _duration, 0.0, 1.0)
	var u: float = 1.0 - t
	var df: float = 12.0 * t * u * u
	var dg: float = u * u * (1.0 - 4.0 * t)
	return ((_targets[i] - _start_p[i]) * df) / _duration + _start_v[i] * dg


func _is_shown(i: int) -> bool:
	return _active[i] or _targets[i] > 0.0


func _present(i: int) -> void:
	var mi: MeshInstance3D = _piles[i]
	var disp: float = clampf(_anim_p(i), 0.0, 1.0)
	var y: float = (disp - 1.0) * _heights[i]
	mi.position = _anchors[i] + Vector3.UP * y
	mi.visible = _is_shown(i)
	if _resources[i] == 0:
		var uv: float = 0.25 * (1.0 - disp)
		for k: int in _food_materials.size():
			_food_materials[k].uv1_offset = _food_base_offsets[k] + Vector3(0.0, uv, 0.0)
