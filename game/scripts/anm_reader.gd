# Original packed ANM matrix keyframes, read directly from AllAnims.anm.
class_name AnmReader
extends RefCounted

var error := ""
var clips: Dictionary = {}
var names_by_index: Dictionary = {}
var _cache: Dictionary = {}
var _cache_tick := -1


func load_file(path: String, wanted: Array[String], wanted_indices := PackedInt32Array()) -> bool:
	error = ""
	clips.clear()
	names_by_index.clear()
	_cache.clear()
	var data := FileAccess.get_file_as_bytes(path)
	if data.size() < 44 or data.slice(0, 8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Invalid original animation archive")
	var blocks := {}
	var p := 8
	while p + 36 <= data.size():
		var end := data.find(0, p)
		var name := data.slice(p, mini(end, p + 32)).get_string_from_ascii()
		var size := data.decode_u32(p + 32)
		if p + 36 + size > data.size():
			return _fail("Truncated animation block")
		blocks[name] = Vector2i(p + 36, size)
		p += 36 + size
	if not blocks.has("Body"):
		return _fail("Original animation headers missing")
	var body: Vector2i = blocks["Body"]
	var count := data.decode_u32(body.x + 4)
	if count > 10000 or 8 + count * 8 > body.y:
		return _fail("Invalid original animation index")
	for i in count:
		var q := body.x + data.decode_u32(body.x + 8 + i * 8)
		if q < body.x or q + 84 > body.x + body.y:
			return _fail("Invalid original animation header")
		var name_end := data.find(0, q)
		var name := data.slice(q, mini(name_end, q + 32)).get_string_from_ascii()
		if name not in wanted and not wanted_indices.has(i):
			continue
		names_by_index[i] = name
		var block_name := "Julien%d" % i
		if not blocks.has(block_name):
			return _fail("Original animation frames missing")
		var chunk: Vector2i = blocks[block_name]
		var bytes := data.slice(q, q + 84)
		bytes.append_array(data.slice(chunk.x, chunk.x + chunk.y))
		if not _decode(name, bytes):
			return false
	for name in wanted:
		if not clips.has(name):
			return _fail("Missing original clip: " + name)
	for index in wanted_indices:
		if not names_by_index.has(index):
			return _fail("Missing original animation index: " + str(index))
	return true


func _decode(name: String, bytes: PackedByteArray) -> bool:
	var count := bytes.decode_u32(56)
	var table := bytes.decode_u32(76)
	if count < 1 or count > 10000 or table + count * 4 > bytes.size():
		return _fail("Invalid ANM frame table")
	var frames: Array = []
	var bones := -1
	for i in count:
		var p := bytes.decode_u32(table + i * 4)
		for dereference in 2:
			if p + 4 > bytes.size():
				return _fail("Invalid ANM frame pointer")
			p = bytes.decode_u32(p)
		if p + 8 > bytes.size():
			return _fail("Invalid ANM bone block")
		var nb := bytes.decode_u32(p)
		# +4 is a pointer to the matrix data, not elapsed animation time.
		var matrices := bytes.decode_u32(p + 4)
		if nb < 1 or nb > 256 or matrices + nb * 48 > bytes.size() or (bones >= 0 and bones != nb):
			return _fail("Invalid ANM skeleton frame")
		bones = nb
		var pose: Array[Transform3D] = []
		for bi in nb:
			var off := matrices + bi * 48
			var raw := Transform3D(Basis(_vec(bytes, off), _vec(bytes, off + 12), _vec(bytes, off + 24)), _vec(bytes, off + 36))
			pose.append(L3dRig.reflected(raw))
		frames.append(pose)
	# +0x20 is the duration in milliseconds; +0x40 is serialized size.
	clips[name] = {"frames":frames,"bones":bones,"duration":maxf(bytes.decode_u32(32) / 1000.0, 0.1)}
	return true


func sample(name: String, seconds: float, phase := 0, loop := true, preserve_root_translation := false) -> Array[Transform3D]:
	var empty: Array[Transform3D] = []
	if not clips.has(name):
		return empty
	var now := int(seconds * 20.0)
	if now != _cache_tick:
		_cache_tick = now
		_cache.clear()
	var key := "%s:%d:%s:%s" % [name, phase, loop, preserve_root_translation]
	if _cache.has(key):
		return _cache[key]
	var clip: Dictionary = clips[name]
	var frames: Array = clip["frames"]
	var duration: float = clip["duration"]
	var normalized := fposmod(seconds / duration + phase / 8.0, 1.0) if loop else clampf(seconds / duration, 0.0, 1.0)
	var index := normalized * float(frames.size() - 1)
	var a := int(index)
	var b := mini(a + 1, frames.size() - 1)
	var fraction := index - float(a)
	var result: Array[Transform3D] = []
	for bi in int(clip["bones"]):
		var ta: Transform3D = frames[a][bi]
		var tb: Transform3D = frames[b][bi]
		var qa := ta.basis.orthonormalized().get_rotation_quaternion()
		var qb := tb.basis.orthonormalized().get_rotation_quaternion()
		var scale_a := ta.basis.get_scale()
		var scale_b := tb.basis.get_scale()
		var p := ta.origin.lerp(tb.origin, fraction)
		# Actor movement is driven by the world, not accumulated root motion.
		if bi == 0 and not preserve_root_translation:
			p.x = frames[0][0].origin.x
			p.z = frames[0][0].origin.z
		# Several original bones use reflected coordinate frames (det < 0).
		# Quaternion-only interpolation discards that reflection and turns
		# shoulders/limbs upside down. Preserve the signed scale as well.
		result.append(Transform3D(Basis(qa.slerp(qb, fraction)).scaled_local(scale_a.lerp(scale_b, fraction)), p))
	_cache[key] = result
	return result


func _vec(bytes: PackedByteArray, p: int) -> Vector3:
	return Vector3(bytes.decode_float(p), bytes.decode_float(p + 4), bytes.decode_float(p + 8))


func _fail(message: String) -> bool:
	error = message
	clips.clear()
	names_by_index.clear()
	return false
