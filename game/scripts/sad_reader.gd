# Pulls the WAV sounds out of a Black & White sound bank (.sad) in the player's game folder.
class_name SadReader
extends RefCounted


static func load_waves(path: String, max_count := 64) -> Array[AudioStreamWAV]:
	var out: Array[AudioStreamWAV] = []
	var d := FileAccess.get_file_as_bytes(path)
	var p := 0
	while out.size() < max_count:
		p = _find_riff(d, p)
		if p < 0:
			break
		var size := d.decode_u32(p + 4) + 8
		if size < 64 or p + size > d.size():
			p += 4
			continue
		if d.decode_u16(p + 20) != 1: # only plain PCM; MPEG-in-WAV sounds are skipped
			p += size
			continue
		var wav := AudioStreamWAV.load_from_buffer(d.slice(p, p + size))
		if wav:
			out.append(wav)
		p += size
	return out


static func _find_riff(d: PackedByteArray, from: int) -> int:
	var i := from
	var n := d.size() - 12
	while i < n:
		i = d.find(0x52, i) # 'R'
		if i < 0 or i >= n:
			return -1
		if d[i + 1] == 0x49 and d[i + 2] == 0x46 and d[i + 3] == 0x46 and d[i + 8] == 0x57 and d[i + 9] == 0x41:
			return i
		i += 1
	return -1
