class_name ResourceStore
extends RefCounted

## Two-resource accounting store.
## The owner's metadata is the single authoritative copy of stock.
## The owner is held weakly and never kept alive by this store.

signal changed(resource: int, before: int, after: int)

const MAX_STOCK: int = 2147483647
const RESOURCE_COUNT: int = 2
const INVALID: int = -1

var _owner_ref: WeakRef = null
var _keys: PackedStringArray = PackedStringArray()
var _limits: Vector2i = Vector2i(-1, -1)
var _bound: bool = false


func bind(owner: Node, keys: PackedStringArray, initial: Vector2i, limits: Vector2i = Vector2i(-1, -1)) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if keys.size() != RESOURCE_COUNT:
		return false
	# Build an independent copy of the key names and validate them before any metadata access.
	var key_copy: PackedStringArray = PackedStringArray()
	for i in RESOURCE_COUNT:
		var key: String = String(keys[i])
		if key.is_empty() or not key.is_valid_identifier():
			return false
		key_copy.append(key)
	if key_copy[0] == key_copy[1]:
		return false
	if initial.x < 0 or initial.y < 0:
		return false
	if not _is_valid_limit(limits.x) or not _is_valid_limit(limits.y):
		return false
	# Validate existing metadata without writing anything.
	var missing: Array[bool] = [false, false]
	for i in RESOURCE_COUNT:
		var meta_name: StringName = StringName(key_copy[i])
		if owner.has_meta(meta_name):
			var existing: Variant = owner.get_meta(meta_name)
			if not _is_valid_stock(existing):
				return false
		else:
			missing[i] = true
	# Everything validated: commit missing keys, then replace the binding.
	var initial_values: Array[int] = [initial.x, initial.y]
	for i in RESOURCE_COUNT:
		if missing[i]:
			owner.set_meta(StringName(key_copy[i]), initial_values[i])
	_owner_ref = weakref(owner)
	_keys = key_copy
	_limits = limits
	_bound = true
	return true


func stock(resource: int) -> int:
	var node: Node = _current_owner()
	if node == null:
		return 0
	var value: int = _read(node, resource)
	if value == INVALID:
		return 0
	return value


func take(resource: int, requested: int) -> int:
	if requested <= 0:
		return 0
	var node: Node = _current_owner()
	if node == null:
		return 0
	var before: int = _read(node, resource)
	if before == INVALID:
		return 0
	var amount: int = mini(requested, before)
	if amount <= 0:
		return 0
	var after: int = before - amount
	node.set_meta(StringName(_keys[resource]), after)
	changed.emit(resource, before, after)
	return amount


func add(resource: int, offered: int) -> int:
	if offered <= 0:
		return 0
	var node: Node = _current_owner()
	if node == null:
		return 0
	var before: int = _read(node, resource)
	if before == INVALID:
		return 0
	var ceiling: int = MAX_STOCK
	var limit: int = _limits.x if resource == 0 else _limits.y
	if limit >= 0:
		ceiling = mini(limit, MAX_STOCK)
	if before >= ceiling:
		return 0
	var room: int = ceiling - before
	var accepted: int = mini(offered, room)
	if accepted <= 0:
		return 0
	var after: int = before + accepted
	node.set_meta(StringName(_keys[resource]), after)
	changed.emit(resource, before, after)
	return accepted


func snapshot() -> Vector2i:
	return Vector2i(stock(0), stock(1))


func _current_owner() -> Node:
	if not _bound or _owner_ref == null:
		return null
	var obj: Variant = _owner_ref.get_ref()
	if obj == null:
		return null
	if not is_instance_valid(obj):
		return null
	var node: Node = obj as Node
	return node


func _read(node: Node, resource: int) -> int:
	if resource < 0 or resource >= RESOURCE_COUNT:
		return INVALID
	if _keys.size() != RESOURCE_COUNT:
		return INVALID
	var meta_name: StringName = StringName(_keys[resource])
	if not node.has_meta(meta_name):
		return INVALID
	var value: Variant = node.get_meta(meta_name)
	if not _is_valid_stock(value):
		return INVALID
	var result: int = value
	return result


func _is_valid_stock(value: Variant) -> bool:
	if typeof(value) != TYPE_INT:
		return false
	var n: int = value
	return n >= 0 and n <= MAX_STOCK


func _is_valid_limit(value: int) -> bool:
	return value == -1 or (value >= 0 and value <= MAX_STOCK)
