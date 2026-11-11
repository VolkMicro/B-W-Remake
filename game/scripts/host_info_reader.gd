# Read the player's own original object registry; no original table is shipped.
class_name HostInfoReader
extends RefCounted

const Data := preload("res://scripts/data.gd")
var error := ""
var version := ""
var mobile_statics: Array[Dictionary] = []
var animated_statics: Dictionary = {}
var animals: Array[Dictionary] = []
var influence_settings: Dictionary = {}
var highlights: Array[Dictionary] = []
var villagers: Array[Dictionary] = []
var storage_piles: Array[Dictionary] = []
var hand_resources: Array[Dictionary] = []


func load_file(path: String, mesh_count: int) -> bool:
	error = ""
	version = ""
	mobile_statics.clear()
	animated_statics.clear()
	animals.clear()
	influence_settings.clear()
	highlights.clear()
	villagers.clear()
	storage_piles.clear()
	hand_resources.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Original object information is unavailable")
	while f.get_position() + 36 <= f.get_length():
		var raw := f.get_buffer(32)
		var end := raw.find(0)
		var name := raw.slice(0, end if end >= 0 else 32).get_string_from_ascii()
		var length := f.get_32()
		var start := f.get_position()
		if length > f.get_length() - start:
			return _fail("Original object information is truncated")
		if name == "Info":
			return _read_info(f.get_buffer(length), mesh_count)
		f.seek(start + length)
	return _fail("Original object registry is missing")


func _read_info(bytes: PackedByteArray, mesh_count: int) -> bool:
	var format: Dictionary = {}
	for entry in Data.HOST_INFO_FORMATS.values():
		if int(entry["info_size"]) == bytes.size():
			format = entry
			break
	if format.is_empty():
		return _fail("Unsupported Black & White object information version")
	var influence_offset: int = format["influence_offset"]
	if int(format["influence_float_count"]) != 3 or influence_offset < 0 or influence_offset + 12 > bytes.size():
		return _fail("Original influence settings are truncated")
	var full := bytes.decode_float(influence_offset)
	var gradient := bytes.decode_float(influence_offset + 4)
	var small := bytes.decode_float(influence_offset + 8)
	if not is_finite(full) or not is_finite(gradient) or not is_finite(small) or full <= 0.0 or gradient <= 0.0 or full + gradient >= 1.0 or small < 0.0 or small > 1.0:
		return _fail("Original influence settings are invalid")
	influence_settings = {"full":full,"gradient":gradient,"small":small}
	var start: int = format["mobile_static_offset"]
	var count: int = format["record_count"]
	var size: int = format["record_size"]
	if start < 0 or count < 1 or start + count * size > bytes.size():
		return _fail("Invalid original object table")
	for i in count:
		var p := start + i * size
		var object_type := bytes.decode_u32(p + int(format["object_type_offset"]))
		var mesh := bytes.decode_u32(p + int(format["mesh_id_offset"]))
		var max_scale := bytes.decode_float(p + int(format["max_scale_offset"]))
		var category := bytes.decode_u32(p + int(format["category_offset"]))
		if object_type != int(format["expected_object_type"]) or mesh >= mesh_count or not is_finite(max_scale) or max_scale <= 0.0:
			return _fail("Invalid original object record %d" % i)
		mobile_statics.append({"mesh_id":mesh,"category":category,"max_scale":max_scale})
	var animated_start: int = format["animated_static_offset"]
	var animated_count: int = format["animated_record_count"]
	var animated_size: int = format["animated_record_size"]
	var name_offset: int = format["animated_name_offset"]
	var name_limit: int = format["animated_name_limit"]
	if animated_start < 0 or animated_count < 1 or animated_start + animated_count * animated_size > bytes.size() or name_offset + name_limit > animated_size:
		return _fail("Invalid original animated object table")
	for i in animated_count:
		var p := animated_start + i * animated_size
		var object_type := bytes.decode_u32(p + int(format["animated_type_offset"]))
		var mesh := bytes.decode_u32(p + int(format["animated_mesh_offset"]))
		var animation := bytes.decode_u32(p + int(format["animated_animation_offset"]))
		var raw_name := bytes.slice(p + name_offset, p + name_offset + name_limit)
		var end := raw_name.find(0)
		if object_type != int(format["animated_expected_type"]) or mesh >= mesh_count or end <= 0:
			return _fail("Invalid original animated object record %d" % i)
		var name := raw_name.slice(0, end).get_string_from_ascii()
		if not animated_statics.has(name):
			animated_statics[name] = []
		animated_statics[name].append({"mesh_id":mesh,"animation_id":animation})
	var animal_start: int = format["animal_offset"]
	var animal_count: int = format["animal_record_count"]
	var animal_size: int = format["animal_record_size"]
	var age_start: int = format["animal_age_scale_offset"]
	var age_count: int = format["animal_age_scale_count"]
	if animal_start < 0 or animal_count < 1 or animal_start + animal_count * animal_size > bytes.size() or age_start < 0 or age_count < 1 or age_start + age_count * 4 > animal_size:
		return _fail("Invalid original animal information table")
	for i in animal_count:
		var p := animal_start + i * animal_size
		var object_type := bytes.decode_u32(p + int(format["animal_type_offset"]))
		var subtype := bytes.decode_u32(p + int(format["animal_subtype_offset"]))
		var mesh := bytes.decode_u32(p + int(format["animal_mesh_offset"]))
		var animation := bytes.decode_u32(p + int(format["animal_animation_offset"]))
		var altitude := bytes.decode_float(p + int(format["animal_altitude_normal_offset"]))
		if object_type != int(format["animal_expected_type"]) or mesh >= mesh_count or animation >= 10000 or not is_finite(altitude):
			return _fail("Invalid original animal record %d" % i)
		var age_scales := PackedFloat32Array()
		for j in age_count:
			var value := bytes.decode_float(p + age_start + j * 4)
			if not is_finite(value) or value <= 0.0:
				return _fail("Invalid original animal age scale %d" % i)
			age_scales.append(value)
		animals.append({"subtype":subtype,"mesh_id":mesh,"animation_id":animation,"normal_altitude":altitude,"age_scales":age_scales})
	for i in int(format["highlight_record_count"]):
		var p := int(format["highlight_offset"]) + i * int(format["highlight_record_size"])
		if p < 0 or p + 256 > bytes.size() or bytes.decode_u32(p) != 35:
			return _fail("Invalid original highlight record")
		var mesh := bytes.decode_u32(p + 0xf0)
		var active := bytes.decode_u32(p + 0xf4)
		if mesh >= mesh_count or active >= mesh_count:
			return _fail("Invalid original scroll meshes")
		highlights.append({"mesh_id":mesh,"active_mesh_id":active,"effect":bytes.decode_u32(p + 0xf8),"active_effect":bytes.decode_u32(p + 0xfc)})
	for i in int(format["villager_record_count"]):
		var p := int(format["villager_offset"]) + i * int(format["villager_record_size"])
		if p < 0 or p + 916 > bytes.size() or bytes.decode_u32(p) != 2:
			return _fail("Invalid original villager record")
		var mesh := bytes.decode_u32(p + 0x204)
		var high := bytes.decode_u32(p + 0x200)
		if mesh >= mesh_count or high >= mesh_count:
			return _fail("Invalid original villager meshes")
		var scales := PackedFloat32Array()
		for age in 20:
			scales.append(bytes.decode_float(p + 0x2d4 + age * 4))
		villagers.append({"mesh_id":mesh,"high_mesh_id":high,"child_mesh_id":bytes.decode_u32(p + 0x1f4),"sex":bytes.decode_u32(p + 0x1e8),"age_scales":scales})
	var pot_start: int = format["storage_pile_offset"]
	var pot_size: int = format["storage_pile_record_size"]
	var pot_count: int = format["storage_pile_record_count"]
	if pot_start < 0 or pot_size < 272 or pot_count != 6 or pot_start + pot_size * pot_count > bytes.size():
		return _fail("Invalid original storage pile table")
	for i in pot_count:
		var p := pot_start + i * pot_size
		var resource := bytes.decode_u32(p + 264)
		var mesh := bytes.decode_u32(p + 248)
		var nominal := bytes.decode_u32(p + 268)
		if resource != (0 if i == 0 else 1) or mesh >= mesh_count or nominal < 1 or nominal > 2147483647:
			return _fail("Invalid original storage pile record %d" % i)
		storage_piles.append({"resource":resource,"mesh_id":mesh,"nominal":nominal})
	# Original GPotInfo11/12 are HandWood/HandFood, not MagicFood10.
	# This adapter only reads data; the new controller receives plain profiles.
	hand_resources.resize(2)
	for i in 2:
		var p: int = int(format["hand_pile_offset"]) + i * pot_size
		if p < 0 or p + 308 > bytes.size(): return _fail("Original hand resource settings are truncated")
		var resource := bytes.decode_u32(p + 264)
		var mesh := bytes.decode_u32(p + 248)
		var row := {"mesh_id":mesh,"nominal":bytes.decode_u32(p + 268),
			"initial":bytes.decode_u32(p + 288),"rate_start":bytes.decode_u32(p + 292),
			"rate_end":bytes.decode_u32(p + 296),"maximum":bytes.decode_u32(p + 300),
			"ramp_seconds":bytes.decode_float(p + 304)}
		if resource != 1 - i or mesh >= mesh_count or int(row["nominal"]) < 1:
			return _fail("Original hand resource record is invalid")
		hand_resources[resource] = row
	version = format["id"]
	return true


func record(index: int) -> Dictionary:
	return mobile_statics[index] if index >= 0 and index < mobile_statics.size() else {}


func animated_static(name: String) -> Dictionary:
	var records: Array = animated_statics.get(name, [])
	return records[0] if records.size() == 1 else {}


func animal(index: int) -> Dictionary:
	return animals[index] if index >= 0 and index < animals.size() else {}


func highlight(index: int) -> Dictionary:
	return highlights[index] if index >= 0 and index < highlights.size() else {}


func villager(index: int) -> Dictionary:
	return villagers[index] if index >= 0 and index < villagers.size() else {}


func _fail(message: String) -> bool:
	error = message
	version = ""
	mobile_statics.clear()
	animated_statics.clear()
	animals.clear()
	influence_settings.clear()
	highlights.clear()
	villagers.clear()
	storage_piles.clear()
	hand_resources.clear()
	return false
