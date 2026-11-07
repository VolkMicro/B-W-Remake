extends SceneTree
## Verification for StockPilesView. Run: godot --headless --script res://verify_stock_piles_view.gd

const ViewScript = preload("res://scripts/stock_piles_view.gd")

var _raw: Variant = Vector2i.ZERO
var _checks: int = 0
var _failures: int = 0
var _views: Array[Node] = []


func _reader() -> Variant:
	return _raw


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)


func _near(a: float, b: float, msg: String, eps: float = 1e-5) -> void:
	_check(absf(a - b) <= eps, "%s (got %f, expected %f)" % [msg, a, b])


func _box(height: float, mat: Material = null) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(1.0, height, 1.0)
	if mat != null:
		m.material = mat
	return m


func _tri_mesh(h: float) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, h, 0), Vector3(0, h, 1)])
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _def(resource: int, mesh: Mesh, nominal: int, anchor: Vector3 = Vector3.ZERO, heading: float = 0.0, sc: float = 1.0) -> Dictionary:
	return {"resource": resource, "mesh": mesh, "nominal": nominal, "anchor": anchor, "heading": heading, "scale": sc}


func _make(defs: Array[Dictionary], stock: Vector2i, duration: float = 1.0) -> ViewScript:
	_raw = stock
	var v: ViewScript = ViewScript.new()
	_views.append(v)
	var ok: bool = v.configure(_reader, defs, duration)
	_check(ok, "configure succeeds")
	return v


func _simple_defs() -> Array[Dictionary]:
	var defs: Array[Dictionary] = [_def(0, _box(4.0), 10), _def(1, _box(4.0), 10)]
	return defs


func _initialize() -> void:
	_test_zero()
	_test_allocation()
	_test_proportions()
	_test_transition()
	_test_retarget()
	_test_same_target_no_restart()
	_test_transforms()
	_test_shared_material()
	_test_subdivision()
	_test_deltas()
	_test_invalid_snapshot_later()
	_test_invalid_configure()
	_test_inspection()
	for v: Node in _views:
		v.free()
	_views.clear()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_zero() -> void:
	var defs: Array[Dictionary] = [_def(0, _tri_mesh(2.0), 100), _def(1, _box(1.0), 10), _def(1, _box(1.0), 10)]
	var v: ViewScript = _make(defs, Vector2i(0, 0))
	for i: int in 3:
		var st: Dictionary = v.state(i)
		_check(not bool(st["visible"]), "zero snapshot pile %d invisible" % i)
		_check(not v.pile(i).visible, "zero snapshot node %d invisible" % i)
	_check(_raw == Vector2i(0, 0), "zero snapshot not mutated")


func _test_allocation() -> void:
	var defs: Array[Dictionary] = [_def(0, _box(1.0), 100), _def(1, _box(1.0), 10), _def(1, _box(1.0), 10), _def(1, _box(1.0), 10)]
	var v: ViewScript = _make(defs, Vector2i(150, 45))
	var expected: Array[int] = [150, 10, 10, 25]
	for i: int in 4:
		var st: Dictionary = v.state(i)
		_check(int(st["amount"]) == expected[i], "allocation amount %d" % i)
		_near(float(st["proportion"]), 1.0, "allocation full %d" % i)
		_check(bool(st["visible"]), "allocation visible %d" % i)
	_raw = Vector2i(150, 15)
	v.sync(true)
	var exp2: Array[int] = [150, 10, 5, 0]
	for i: int in 4:
		_check(int(v.state(i)["amount"]) == exp2[i], "reduced allocation amount %d" % i)
	_check(not bool(v.state(3)["visible"]), "empty last entry invisible after snap")
	var one: Array[Dictionary] = [_def(0, _box(1.0), 100), _def(1, _box(1.0), 10)]
	var w: ViewScript = _make(one, Vector2i(0, 2000000000))
	_check(int(w.state(1)["amount"]) == 2000000000, "single wood entry receives whole quantity")


func _test_proportions() -> void:
	var a_defs: Array[Dictionary] = [_def(0, _box(1.0), 100), _def(1, _box(1.0), 10)]
	var a: ViewScript = _make(a_defs, Vector2i(50, 5))
	_near(float(a.state(0)["proportion"]), 0.774375, "food half p")
	_near(float(a.state(0)["uv_v"]), 0.05640625, "food half uv_v")
	_near(float(a.state(1)["proportion"]), 0.525, "wood half p")
	_near(float(a.state(1)["uv_v"]), 0.0, "wood uv_v zero")
	var b_defs: Array[Dictionary] = [_def(0, _box(1.0), 100), _def(1, _box(1.0), 20)]
	var b: ViewScript = _make(b_defs, Vector2i(25, 5))
	_near(float(b.state(0)["proportion"]), 0.49234375, "food quarter p")
	_near(float(b.state(1)["proportion"]), 0.2875, "wood quarter p")


func _test_transition() -> void:
	var v: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	_near(float(v.state(1)["y_offset"]), 0.0, "full start offset")
	_raw = Vector2i(0, 0)
	v.advance(0.25)
	v.advance(0.25)
	var st: Dictionary = v.state(1)
	_near(float(st["y_offset"]), -2.75, "half-second offset")
	_near(float(st["velocity"]), -6.0, "half-second velocity")
	_check(bool(st["visible"]), "visible while moving to zero")
	_near(v.pile(1).position.y, -2.75, "node position half", 1e-4)
	v.advance(0.5)
	st = v.state(1)
	_near(float(st["y_offset"]), -4.0, "one-second offset")
	_near(float(st["velocity"]), 0.0, "one-second velocity")
	_check(not bool(st["visible"]), "invisible at settled zero")
	_check(not v.pile(1).visible, "node invisible at settled zero")
	_raw = Vector2i(0, 10)
	v.sync()
	_check(v.pile(1).visible, "visible when rising from zero")


func _test_retarget() -> void:
	var v: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	_raw = Vector2i(0, 0)
	v.advance(0.5)
	var before: Dictionary = v.state(1)
	_raw = Vector2i(0, 5)
	v.sync()
	var after: Dictionary = v.state(1)
	_near(float(after["proportion"]), float(before["proportion"]), "retarget keeps position")
	_near(float(after["velocity"]), float(before["velocity"]), "retarget keeps velocity")
	_near(float(after["target"]), 0.525, "retarget new target")
	v.advance(0.5)
	_check(bool(v.state(1)["transitioning"]), "still moving mid retarget")
	v.advance(0.5)
	var fin: Dictionary = v.state(1)
	_near(float(fin["proportion"]), 0.525, "retarget reached after one duration")
	_near(float(fin["velocity"]), 0.0, "retarget end velocity")
	var w: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	_raw = Vector2i(0, 5)
	w.advance(2.0)
	_check(float(w.state(1)["proportion"]) == 0.525, "single 2s step settles exactly")
	_check(float(w.state(1)["velocity"]) == 0.0, "single 2s step zero velocity")


func _test_same_target_no_restart() -> void:
	var v: ViewScript = _make(_simple_defs(), Vector2i(0, 0))
	_raw = Vector2i(0, 10)
	v.advance(0.5)
	var p_before: float = float(v.state(1)["proportion"])
	_raw = Vector2i(0, 20)
	v.sync()
	_check(int(v.state(1)["amount"]) == 20, "amount updated with same target")
	_near(float(v.state(1)["proportion"]), p_before, "same target keeps position")
	v.advance(0.5)
	_near(float(v.state(1)["proportion"]), 1.0, "same target not restarted")
	_check(not bool(v.state(1)["transitioning"]), "same target settled on schedule")


func _test_transforms() -> void:
	var defs: Array[Dictionary] = [_def(0, _box(4.0), 10, Vector3(1, 2, 3), 0.3, 1.0), _def(1, _box(4.0), 10, Vector3(-1, 0, 5), 0.7, 2.0)]
	var v: ViewScript = _make(defs, Vector2i(10, 5))
	var mi: MeshInstance3D = v.pile(1)
	_near(mi.scale.x, 2.0, "scale x", 1e-4)
	_near(mi.scale.y, 2.0, "scale y", 1e-4)
	_near(mi.rotation.y, 0.7, "heading", 1e-4)
	_near(mi.position.y, (0.525 - 1.0) * 8.0, "scaled H offset", 1e-4)
	_near(mi.position.x, -1.0, "anchor x", 1e-4)
	_near(mi.position.z, 5.0, "anchor z", 1e-4)
	_near(v.pile(0).position.y, 2.0, "full food at anchor", 1e-4)
	_near(v.pile(0).rotation.y, 0.3, "food heading", 1e-4)


func _test_shared_material() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.uv1_offset = Vector3(0.1, 0.2, 0.0)
	var food: BoxMesh = _box(1.0, mat)
	var d1: Array[Dictionary] = [_def(0, food, 100), _def(1, _box(1.0), 10)]
	var v1: ViewScript = _make(d1, Vector2i(100, 0))
	var d2: Array[Dictionary] = [_def(0, food, 100), _def(1, _box(1.0), 10)]
	var v2: ViewScript = _make(d2, Vector2i(50, 0))
	var m1: Material = v1.pile(0).get_surface_override_material(0)
	var m2: Material = v2.pile(0).get_surface_override_material(0)
	_check(m1 is StandardMaterial3D and m2 is StandardMaterial3D, "food override materials exist")
	_check(m1 != mat and m2 != mat and m1 != m2, "override materials distinct")
	if m1 is StandardMaterial3D and m2 is StandardMaterial3D:
		var s1: StandardMaterial3D = m1 as StandardMaterial3D
		var s2: StandardMaterial3D = m2 as StandardMaterial3D
		_near(s1.uv1_offset.y, 0.2, "full food uv unchanged from base")
		_near(s2.uv1_offset.y, 0.2 + 0.05640625, "half food uv offset")
		_near(s2.uv1_offset.x, 0.1, "food U unchanged")
	_near(mat.uv1_offset.y, 0.2, "original material untouched")
	_check(food.material == mat, "shared mesh keeps original material")
	_check(v1.pile(0).mesh == food and v2.pile(0).mesh == food, "original mesh used")
	_check(v1.pile(1).get_surface_override_material(0) == null, "wood has no override")


func _test_subdivision() -> void:
	var a: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	var b: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	var c: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	_raw = Vector2i(0, 3)
	a.advance(1.0)
	for k: int in 4:
		b.advance(0.25)
	for k: int in 7:
		c.advance(0.15)
	var sa: Dictionary = a.state(1)
	var sb: Dictionary = b.state(1)
	var sc: Dictionary = c.state(1)
	_check(float(sa["proportion"]) == float(sb["proportion"]) and float(sa["proportion"]) == float(sc["proportion"]), "subdivisions same proportion")
	_check(float(sb["velocity"]) == 0.0 and float(sc["velocity"]) == 0.0, "subdivisions settled")
	_check(bool(sa["visible"]) == bool(sc["visible"]), "subdivisions same visibility")


func _test_deltas() -> void:
	var v: ViewScript = _make(_simple_defs(), Vector2i(0, 10))
	_raw = Vector2i(0, 5)
	v.advance(0.0)
	_check(int(v.state(1)["amount"]) == 5, "zero dt syncs amount")
	_near(float(v.state(1)["target"]), 0.525, "zero dt updates target")
	_near(float(v.state(1)["proportion"]), 1.0, "zero dt does not move")
	_raw = Vector2i(0, 0)
	v.advance(-1.0)
	v.advance(NAN)
	v.advance(INF)
	_check(int(v.state(1)["amount"]) == 5, "invalid dt does not sync")
	_near(float(v.state(1)["proportion"]), 1.0, "invalid dt does not move")


func _test_invalid_snapshot_later() -> void:
	var v: ViewScript = _make(_simple_defs(), Vector2i(10, 10))
	_raw = "bad"
	v.sync(true)
	_check(int(v.state(0)["amount"]) == 0 and int(v.state(1)["amount"]) == 0, "invalid data treated as zero")
	_check(not v.pile(0).visible, "invalid data hides piles")
	_raw = Vector2i(-5, 3)
	v.sync(true)
	_check(int(v.state(1)["amount"]) == 0, "negative data treated as zero")
	_raw = Vector2i(0, 0)


func _expect_invalid(defs: Array[Dictionary], stock: Variant, duration: float, msg: String, reader: Callable = Callable()) -> void:
	_raw = stock
	var v: ViewScript = ViewScript.new()
	_views.append(v)
	var r: Callable = reader if reader.is_valid() or reader != Callable() else _reader
	if reader == Callable():
		r = _reader
	var ok: bool = v.configure(r, defs, duration)
	_check(not ok, "invalid rejected: " + msg)
	_check(v.get_child_count() == 0, "no children: " + msg)


func _test_invalid_configure() -> void:
	var empty: Array[Dictionary] = []
	_expect_invalid(empty, Vector2i.ZERO, 1.0, "empty")
	var only_food: Array[Dictionary] = [_def(0, _box(1.0), 10)]
	_expect_invalid(only_food, Vector2i.ZERO, 1.0, "no wood")
	var wood_first: Array[Dictionary] = [_def(1, _box(1.0), 10), _def(0, _box(1.0), 10)]
	_expect_invalid(wood_first, Vector2i.ZERO, 1.0, "order")
	var missing: Dictionary = _def(1, _box(1.0), 10)
	missing.erase("heading")
	var miss_defs: Array[Dictionary] = [_def(0, _box(1.0), 10), missing]
	_expect_invalid(miss_defs, Vector2i.ZERO, 1.0, "missing field")
	var null_mesh: Array[Dictionary] = [_def(0, _box(1.0), 10), {"resource": 1, "mesh": null, "nominal": 10, "anchor": Vector3.ZERO, "heading": 0.0, "scale": 1.0}]
	_expect_invalid(null_mesh, Vector2i.ZERO, 1.0, "null mesh")
	var zero_nom: Array[Dictionary] = [_def(0, _box(1.0), 10), _def(1, _box(1.0), 0)]
	_expect_invalid(zero_nom, Vector2i.ZERO, 1.0, "zero nominal")
	var bad_scale: Array[Dictionary] = [_def(0, _box(1.0), 10), _def(1, _box(1.0), 10, Vector3.ZERO, 0.0, -1.0)]
	_expect_invalid(bad_scale, Vector2i.ZERO, 1.0, "negative scale")
	var inf_anchor: Array[Dictionary] = [_def(0, _box(1.0), 10), _def(1, _box(1.0), 10, Vector3(INF, 0, 0))]
	_expect_invalid(inf_anchor, Vector2i.ZERO, 1.0, "infinite anchor")
	var shader: Array[Dictionary] = [_def(0, _box(1.0, ShaderMaterial.new()), 10), _def(1, _box(1.0), 10)]
	_expect_invalid(shader, Vector2i.ZERO, 1.0, "unsupported material")
	_expect_invalid(_simple_defs(), Vector2i.ZERO, 0.0, "zero duration")
	_expect_invalid(_simple_defs(), Vector2i.ZERO, NAN, "nan duration")
	_expect_invalid(_simple_defs(), Vector2i(-1, 0), 1.0, "negative snapshot")
	_expect_invalid(_simple_defs(), "nope", 1.0, "non-vector snapshot")
	var v: ViewScript = _make(_simple_defs(), Vector2i(1, 1))
	var first: MeshInstance3D = v.pile(0)
	var again: bool = v.configure(_reader, _simple_defs(), 1.0)
	_check(not again, "repeated configure rejected")
	_check(v.get_child_count() == 2, "repeated configure keeps children")
	_check(v.pile(0) == first, "repeated configure keeps pile")
	var caller_defs: Array[Dictionary] = _simple_defs()
	var w: ViewScript = _make(caller_defs, Vector2i(0, 10))
	caller_defs[1]["nominal"] = 1000
	caller_defs[1]["anchor"] = Vector3(50, 50, 50)
	caller_defs.clear()
	w.sync(true)
	_check(int(w.state(1)["nominal"]) == 10, "definitions copied")
	_near(w.pile(1).position.x, 0.0, "anchor copied")


func _test_inspection() -> void:
	var defs: Array[Dictionary] = [_def(0, _box(1.0), 100), _def(1, _box(1.0), 10), _def(1, _box(1.0), 10), _def(1, _box(1.0), 10)]
	var v: ViewScript = _make(defs, Vector2i(150, 45))
	_check(v.pile(-1) == null and v.pile(4) == null, "invalid pile index returns null")
	_check(v.state(-1).is_empty() and v.state(9).is_empty(), "invalid state index empty")
	_check(int(v.pile(0).get_meta("resource_index")) == 0, "food resource_index")
	_check(int(v.pile(2).get_meta("resource_index")) == 1, "wood resource_index")
	_check(int(v.pile(3).get_meta("pile_slot")) == 3, "pile_slot")
	var st: Dictionary = v.state(3)
	for key: String in ["resource", "amount", "nominal", "proportion", "target", "y_offset", "velocity", "visible", "uv_v"]:
		_check(st.has(key), "state has " + key)
	st["amount"] = 0
	st["proportion"] = 0.0
	var again: Dictionary = v.state(3)
	_check(int(again["amount"]) == 25, "state dictionary is fresh")
	_near(float(again["proportion"]), 1.0, "state mutation does not affect view")
	_check(_raw == Vector2i(150, 45), "inspection does not debit stock")
