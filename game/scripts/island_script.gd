# Parses a Black & White island script (Scripts/LandN.txt) from the player's game folder.
class_name IslandScript
extends RefCounted

const Data := preload("res://scripts/data.gd")
var commands: Array[Dictionary] = []


func load_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		var open := line.find("(")
		if open <= 0 or not line.ends_with(")"):
			continue
		commands.append({"cmd": line.substr(0, open), "args": _split(line.substr(open + 1, line.length() - open - 2))})
	return true


func _split(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	for ch in s:
		if ch == "\"":
			quoted = not quoted
		elif ch == "," and not quoted:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
	out.append(cur.strip_edges())
	return out


static func pos(arg: String) -> Vector2:
	var p := arg.split(",")
	return Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.ZERO


static func placement(rule: String, args: PackedStringArray) -> Dictionary:
	if not Data.PLACEMENT_RULES.has(rule):
		return {}
	var row: Dictionary = Data.PLACEMENT_RULES[rule]
	var ai: int = row["angle_index"]
	var si: int = row["scale_index"]
	if ai < 0 or si < 0 or ai >= args.size() or si >= args.size() or not args[ai].is_valid_float() or not args[si].is_valid_float():
		return {}
	var angle := float(args[ai]) / float(row["angle_divisor"])
	var scale := float(args[si]) / float(row["scale_divisor"])
	if not is_finite(angle) or not is_finite(scale) or scale <= 0.0:
		return {}
	return {"angle":angle,"scale":scale}


func all(cmd: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in commands:
		if c["cmd"] == cmd:
			out.append(c)
	return out
