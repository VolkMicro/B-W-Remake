# Read the player's own original object registry; no original table is shipped.
class_name HostInfoReader
extends RefCounted

const Data := preload("res://scripts/data.gd")
var error := ""
var version := ""
var mobile_statics: Array[Dictionary] = []
var animated_statics: Dictionary = {}
var animals: Array[Dictionary] = []


func load_file(path: String, mesh_count: int) -> bool:
	error = ""
	version = ""
	mobile_statics.clear()
	animated_statics.clear()
	animals.clear()
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
	version = format["id"]
	return true


func record(index: int) -> Dictionary:
	return mobile_statics[index] if index >= 0 and index < mobile_statics.size() else {}


func animated_static(name: String) -> Dictionary:
	var records: Array = animated_statics.get(name, [])
	return records[0] if records.size() == 1 else {}


func animal(index: int) -> Dictionary:
	return animals[index] if index >= 0 and index < animals.size() else {}


func _fail(message: String) -> bool:
	error = message
	version = ""
	mobile_statics.clear()
	animated_statics.clear()
	animals.clear()
	return false
