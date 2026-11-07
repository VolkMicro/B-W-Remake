extends SceneTree

const ResourceStoreScript = preload("res://scripts/resource_store.gd")
const MAX_STOCK: int = 2147483647
const BIG: int = 9223372036854775807
const KEY_A: String = "fx_alpha"
const KEY_B: String = "fx_beta"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_a1()
	_test_a2()
	_test_a3()
	_test_a4()
	_test_a5()
	_test_a6()
	_test_a7()
	_test_a8()
	_test_a9()
	_test_a10()
	_test_a11()
	_test_a12()
	_test_a13()
	_test_a14()
	_test_conservation()
	if _failures == 0:
		print("RESOURCE_STORE_VERIFY PASS checks=%d" % _checks)
		quit(0)
	else:
		print("RESOURCE_STORE_VERIFY FAIL failures=%d checks=%d" % [_failures, _checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _keys(a: String, b: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	result.append(a)
	result.append(b)
	return result


func _new_store() -> ResourceStoreScript:
	var store: ResourceStoreScript = ResourceStoreScript.new()
	return store


func _record(store: ResourceStoreScript, events: Array[Vector3i]) -> Callable:
	var cb: Callable = func(r: int, b: int, a: int) -> void:
		events.append(Vector3i(r, b, a))
	store.changed.connect(cb)
	return cb


func _meta_int(node: Node, key: String) -> int:
	if not node.has_meta(StringName(key)):
		return -999
	var v: Variant = node.get_meta(StringName(key))
	if typeof(v) != TYPE_INT:
		return -998
	var n: int = v
	return n


func _bound_store(node: Node, initial: Vector2i, limits: Vector2i = Vector2i(-1, -1)) -> ResourceStoreScript:
	var store: ResourceStoreScript = _new_store()
	var ok: bool = store.bind(node, _keys(KEY_A, KEY_B), initial, limits)
	_check(ok, "setup bind")
	return store


func _test_a1() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _new_store()
	var events: Array[Vector3i] = []
	_record(store, events)
	var ok: bool = store.bind(node, _keys(KEY_A, KEY_B), Vector2i(37, 91))
	_check(ok, "A1 bind returns true")
	_check(_meta_int(node, KEY_A) == 37, "A1 meta alpha 37")
	_check(_meta_int(node, KEY_B) == 91, "A1 meta beta 91")
	_check(store.snapshot() == Vector2i(37, 91), "A1 snapshot")
	_check(events.size() == 0, "A1 no event")
	node.free()


func _test_a2() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	var events: Array[Vector3i] = []
	_record(store, events)
	_check(store.take(0, 12) == 12, "A2 take 12")
	_check(store.take(0, 100) == 25, "A2 take remaining 25")
	_check(store.stock(0) == 0, "A2 stock0 zero")
	_check(store.stock(1) == 91, "A2 stock1 untouched")
	_check(events.size() == 2, "A2 two events")
	if events.size() == 2:
		_check(events[0] == Vector3i(0, 37, 25), "A2 first event")
		_check(events[1] == Vector3i(0, 25, 0), "A2 second event")
	_check(store.take(0, 5) == 0, "A2 take from empty")
	_check(events.size() == 2, "A2 empty take no event")
	node.free()


func _test_a3() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	var events: Array[Vector3i] = []
	_record(store, events)
	_check(store.add(0, 9) == 9, "A3 add 9")
	_check(store.add(0, 0) == 0, "A3 add 0")
	_check(store.add(0, -5) == 0, "A3 add negative")
	_check(store.add(2, 5) == 0, "A3 add invalid index 2")
	_check(store.add(-1, 5) == 0, "A3 add invalid index -1")
	_check(store.take(0, 0) == 0, "A3 take 0")
	_check(store.take(0, -3) == 0, "A3 take negative")
	_check(store.take(5, 1) == 0, "A3 take invalid index")
	_check(store.stock(7) == 0, "A3 stock invalid index")
	_check(store.stock(-1) == 0, "A3 stock negative index")
	_check(events.size() == 1, "A3 only one event")
	_check(store.snapshot() == Vector2i(46, 91), "A3 snapshot")
	node.free()


func _test_a4() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91), Vector2i(20, 40))
	var events: Array[Vector3i] = []
	_record(store, events)
	_check(store.snapshot() == Vector2i(37, 91), "A4 over-limit preserved")
	_check(store.add(0, 5) == 0, "A4 add0 accepts 0")
	_check(store.add(1, 1) == 0, "A4 add1 accepts 0")
	_check(events.size() == 0, "A4 no event for rejected adds")
	_check(store.take(0, 7) == 7, "A4 withdraw works")
	_check(store.take(1, 50) == 50, "A4 withdraw resource1")
	_check(store.snapshot() == Vector2i(30, 41), "A4 snapshot after takes")
	_check(store.add(1, 1) == 0, "A4 still at/over limit")
	_check(store.take(1, 2) == 2, "A4 drop below limit")
	_check(store.add(1, 10) == 1, "A4 add up to limit")
	_check(store.stock(1) == 40, "A4 at limit")
	_check(events.size() == 4, "A4 event count")
	node.free()


func _test_a5() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(14, 0), Vector2i(20, -1))
	var events: Array[Vector3i] = []
	_record(store, events)
	_check(store.add(0, 100) == 6, "A5 accept 6")
	_check(store.stock(0) == 20, "A5 final 20")
	_check(events.size() == 1, "A5 exactly one event")
	if events.size() == 1:
		_check(events[0] == Vector3i(0, 14, 20), "A5 event payload")
	node.free()


func _test_a6() -> void:
	var node: Node = Node.new()
	node.set_meta(StringName(KEY_A), 11)
	var store: ResourceStoreScript = _new_store()
	var events: Array[Vector3i] = []
	_record(store, events)
	var ok: bool = store.bind(node, _keys(KEY_A, KEY_B), Vector2i(37, 91))
	_check(ok, "A6 bind")
	_check(_meta_int(node, KEY_A) == 11, "A6 preserve 11")
	_check(_meta_int(node, KEY_B) == 91, "A6 create 91")
	_check(store.take(0, 4) == 4, "A6 take")
	var ok2: bool = store.bind(node, _keys(KEY_A, KEY_B), Vector2i(37, 91))
	_check(ok2, "A6 rebind same owner")
	_check(store.snapshot() == Vector2i(7, 91), "A6 rebind does not reset")
	_check(events.size() == 1, "A6 binds emit no event")
	node.free()


func _test_a7() -> void:
	var node1: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node1, Vector2i(37, 91))
	var node2: Node = Node.new()
	node2.set_meta(StringName(KEY_A), 11)
	node2.set_meta(StringName(KEY_B), "12")
	_check(not store.bind(node2, _keys(KEY_A, KEY_B), Vector2i(1, 2)), "A7 string meta fails")
	_check(_meta_int(node2, KEY_A) == 11, "A7 node2 alpha untouched")
	var sv: Variant = node2.get_meta(StringName(KEY_B))
	_check(typeof(sv) == TYPE_STRING and String(sv) == "12", "A7 node2 beta untouched")
	var node3: Node = Node.new()
	node3.set_meta(StringName(KEY_B), 3.5)
	_check(not store.bind(node3, _keys(KEY_A, KEY_B), Vector2i(1, 2)), "A7 float meta fails")
	_check(not node3.has_meta(StringName(KEY_A)), "A7 no partial write")
	var node4: Node = Node.new()
	node4.set_meta(StringName(KEY_B), -4)
	_check(not store.bind(node4, _keys(KEY_A, KEY_B), Vector2i(1, 2)), "A7 negative meta fails")
	_check(not node4.has_meta(StringName(KEY_A)), "A7 negative no partial write")
	var node5: Node = Node.new()
	node5.set_meta(StringName(KEY_A), 2147483648)
	_check(not store.bind(node5, _keys(KEY_A, KEY_B), Vector2i(1, 2)), "A7 over-range meta fails")
	_check(not node5.has_meta(StringName(KEY_B)), "A7 over-range no partial write")
	var node6: Node = Node.new()
	_check(not store.bind(node6, _keys(KEY_A, KEY_A), Vector2i(1, 2)), "A7 duplicate keys fail")
	_check(not store.bind(node6, _keys(KEY_A, KEY_B), Vector2i(-1, 2)), "A7 negative initial fails")
	_check(not store.bind(node6, _keys(KEY_A, KEY_B), Vector2i(1, 2), Vector2i(-2, -1)), "A7 bad limit fails")
	_check(not store.bind(null, _keys(KEY_A, KEY_B), Vector2i(1, 2)), "A7 null owner fails")
	_check(node6.get_meta_list().size() == 0, "A7 node6 untouched")
	_check(store.snapshot() == Vector2i(37, 91), "A7 previous binding intact")
	_check(store.take(1, 1) == 1, "A7 previous binding usable")
	_check(_meta_int(node1, KEY_B) == 90, "A7 previous owner mutated")
	node1.free()
	node2.free()
	node3.free()
	node4.free()
	node5.free()
	node6.free()


func _test_a8() -> void:
	var node: Node = Node.new()
	var ks: PackedStringArray = _keys(KEY_A, KEY_B)
	var store: ResourceStoreScript = _new_store()
	_check(store.bind(node, ks, Vector2i(37, 91)), "A8 bind")
	ks[0] = "fx_gamma"
	ks[1] = "fx_delta"
	ks.append("fx_epsilon")
	_check(store.take(0, 5) == 5, "A8 take")
	_check(store.add(1, 4) == 4, "A8 add")
	_check(_meta_int(node, KEY_A) == 32, "A8 original key A used")
	_check(_meta_int(node, KEY_B) == 95, "A8 original key B used")
	_check(not node.has_meta(&"fx_gamma"), "A8 no redirected key gamma")
	_check(not node.has_meta(&"fx_delta"), "A8 no redirected key delta")
	node.free()


func _test_a9() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	node.set_meta(StringName(KEY_A), 55)
	_check(store.stock(0) == 55, "A9 stock reflects external write")
	_check(store.snapshot() == Vector2i(55, 91), "A9 snapshot reflects external write")
	_check(store.take(0, 5) == 5, "A9 take from external value")
	_check(_meta_int(node, KEY_A) == 50, "A9 meta after take")
	node.free()


func _test_a10() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	var events: Array[Vector3i] = []
	_record(store, events)
	node.set_meta(StringName(KEY_A), "abc")
	_check(store.stock(0) == 0, "A10 string reads 0")
	_check(store.snapshot() == Vector2i(0, 91), "A10 snapshot safe")
	_check(store.take(0, 1) == 0, "A10 take 0")
	_check(store.add(0, 1) == 0, "A10 add 0")
	var v: Variant = node.get_meta(StringName(KEY_A))
	_check(typeof(v) == TYPE_STRING and String(v) == "abc", "A10 string unchanged")
	node.set_meta(StringName(KEY_A), 5.0)
	_check(store.stock(0) == 0, "A10 float reads 0")
	_check(store.add(0, 3) == 0, "A10 float add 0")
	var fv: Variant = node.get_meta(StringName(KEY_A))
	_check(typeof(fv) == TYPE_FLOAT, "A10 float unchanged")
	node.set_meta(StringName(KEY_A), true)
	_check(store.take(0, 1) == 0, "A10 bool take 0")
	node.set_meta(StringName(KEY_A), -7)
	_check(store.stock(0) == 0, "A10 negative reads 0")
	_check(store.add(0, 10) == 0, "A10 negative add 0")
	_check(_meta_int(node, KEY_A) == -7, "A10 negative unchanged")
	node.remove_meta(StringName(KEY_A))
	_check(store.stock(0) == 0, "A10 missing reads 0")
	_check(store.add(0, 10) == 0, "A10 missing add 0")
	_check(store.take(0, 10) == 0, "A10 missing take 0")
	_check(not node.has_meta(StringName(KEY_A)), "A10 missing not recreated")
	_check(events.size() == 0, "A10 no events")
	_check(store.take(1, 1) == 1, "A10 other resource still works")
	_check(events.size() == 1, "A10 one event from other resource")
	node.free()


func _test_a11() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	var events: Array[Vector3i] = []
	_record(store, events)
	node.free()
	_check(store.stock(0) == 0, "A11 stock0 0")
	_check(store.stock(1) == 0, "A11 stock1 0")
	_check(store.take(0, 5) == 0, "A11 take 0")
	_check(store.add(1, 5) == 0, "A11 add 0")
	_check(store.snapshot() == Vector2i(0, 0), "A11 snapshot 0")
	_check(events.size() == 0, "A11 no events")
	var node2: Node = Node.new()
	_check(store.bind(node2, _keys(KEY_A, KEY_B), Vector2i(3, 4)), "A11 rebind to another owner")
	_check(store.snapshot() == Vector2i(3, 4), "A11 new owner snapshot")
	node2.free()


func _test_a12() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(2147483646, 5))
	_check(store.add(0, BIG) == 1, "A12 accept 1")
	_check(store.stock(0) == MAX_STOCK, "A12 final max")
	_check(store.add(0, BIG) == 0, "A12 at ceiling accepts 0")
	_check(store.take(1, BIG) == 5, "A12 huge take bounded")
	_check(store.add(1, BIG) == MAX_STOCK, "A12 add huge from zero")
	_check(store.stock(1) == MAX_STOCK, "A12 resource1 max")
	node.free()


func _test_a13() -> void:
	var node: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node, Vector2i(37, 91))
	var events: Array[Vector3i] = []
	var rec: Callable = _record(store, events)
	var state: Dictionary = {"done": false, "seen": -1, "meta": -1, "nested": -1}
	var observer: Callable = func(r: int, _b: int, _a: int) -> void:
		if bool(state["done"]):
			return
		state["done"] = true
		state["seen"] = store.stock(r)
		state["meta"] = _meta_int(node, KEY_A)
		state["nested"] = store.take(r, 5)
	store.changed.connect(observer)
	_check(store.take(0, 10) == 10, "A13 original take returns 10")
	_check(int(state["seen"]) == 27, "A13 observer sees committed stock")
	_check(int(state["meta"]) == 27, "A13 observer sees committed meta")
	_check(int(state["nested"]) == 5, "A13 nested take 5")
	_check(store.stock(0) == 22, "A13 nested result not overwritten")
	_check(_meta_int(node, KEY_A) == 22, "A13 meta 22")
	_check(events.size() == 2, "A13 two events")
	if events.size() == 2:
		_check(events[0] == Vector3i(0, 37, 27), "A13 first event")
		_check(events[1] == Vector3i(0, 27, 22), "A13 nested event")
	store.changed.disconnect(observer)
	store.changed.disconnect(rec)
	node.free()


func _test_a14() -> void:
	var node1: Node = Node.new()
	var store: ResourceStoreScript = _bound_store(node1, Vector2i(37, 91))
	var node2: Node = Node.new()
	var bad: Array[String] = ["bad key", "1stock", "fx-alpha", "fx.alpha", "fx!", "", " "]
	for b: String in bad:
		_check(not store.bind(node2, _keys(b, KEY_B), Vector2i(1, 2)), "A14 reject first '" + b + "'")
		_check(not store.bind(node2, _keys(KEY_A, b), Vector2i(1, 2)), "A14 reject second '" + b + "'")
	var one: PackedStringArray = PackedStringArray()
	one.append(KEY_A)
	_check(not store.bind(node2, one, Vector2i(1, 2)), "A14 reject single key")
	var three: PackedStringArray = _keys(KEY_A, KEY_B)
	three.append("fx_gamma")
	_check(not store.bind(node2, three, Vector2i(1, 2)), "A14 reject three keys")
	_check(not store.bind(node2, PackedStringArray(), Vector2i(1, 2)), "A14 reject empty array")
	_check(node2.get_meta_list().size() == 0, "A14 no partial writes")
	_check(store.snapshot() == Vector2i(37, 91), "A14 previous binding intact")
	_check(store.add(0, 3) == 3, "A14 previous binding usable")
	_check(_meta_int(node1, KEY_A) == 40, "A14 previous owner mutated")
	node1.free()
	node2.free()


func _test_conservation() -> void:
	var node: Node = Node.new()
	var initial: Vector2i = Vector2i(100, 250)
	var limits: Vector2i = Vector2i(500, -1)
	var store: ResourceStoreScript = _bound_store(node, initial, limits)
	var events: Array[Vector3i] = []
	_record(store, events)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261107
	var added: Array[int] = [0, 0]
	var taken: Array[int] = [0, 0]
	var model: Array[int] = [initial.x, initial.y]
	var model_limits: Array[int] = [limits.x, limits.y]
	var nonzero: int = 0
	var ok_model: bool = true
	for i in 400:
		var r: int = rng.randi_range(0, 1)
		var amount: int = rng.randi_range(-3, 80)
		var op: int = rng.randi_range(0, 1)
		if op == 0:
			var expected_add: int = 0
			if amount > 0:
				var ceiling: int = MAX_STOCK
				if model_limits[r] >= 0:
					ceiling = model_limits[r]
				if model[r] < ceiling:
					expected_add = mini(amount, ceiling - model[r])
			var got: int = store.add(r, amount)
			if got != expected_add:
				ok_model = false
			added[r] += got
			model[r] += expected_add
			if got > 0:
				nonzero += 1
		else:
			var expected_take: int = 0
			if amount > 0:
				expected_take = mini(amount, model[r])
			var got_t: int = store.take(r, amount)
			if got_t != expected_take:
				ok_model = false
			taken[r] += got_t
			model[r] -= expected_take
			if got_t > 0:
				nonzero += 1
	_check(ok_model, "CONS per-step results match model")
	_check(store.stock(0) == initial.x + added[0] - taken[0], "CONS resource0 equation")
	_check(store.stock(1) == initial.y + added[1] - taken[1], "CONS resource1 equation")
	_check(store.snapshot() == Vector2i(model[0], model[1]), "CONS snapshot matches model")
	_check(store.stock(0) <= 500, "CONS limit respected")
	_check(events.size() == nonzero, "CONS one event per actual change")
	var delta: Array[int] = [0, 0]
	var chained: bool = true
	var last: Array[int] = [initial.x, initial.y]
	for e: Vector3i in events:
		delta[e.x] += e.z - e.y
		if e.y != last[e.x]:
			chained = false
		last[e.x] = e.z
	_check(chained, "CONS event before values chain")
	_check(delta[0] == added[0] - taken[0], "CONS event delta0")
	_check(delta[1] == added[1] - taken[1], "CONS event delta1")
	node.free()
