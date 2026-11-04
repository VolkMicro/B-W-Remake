# Development-only: prints a readable listing of one original script from the player's CHL (in memory).
extends SceneTree

const NAMES := ["end","jz","push","pop","add","sys","sub","neg","mul","div","mod","not","and","or","eq","neq","geq","leq","gt","lt","jmp","sleep","except","cast","call","yield","endexcept","retexcept","iterexcept","swap","line"]


func _initialize() -> void:
	var host := ""
	var root := "SetupLand1"
	var natives := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
		elif arg.begins_with("--root="):
			root = arg.substr(7)
		elif arg.begins_with("--names="):
			for line in FileAccess.get_file_as_string(arg.substr(8)).split("\n"):
				var cols := line.split("\t")
				if cols.size() >= 2:
					natives[int(cols[0])] = cols[1]
	var source := ChlReader.new()
	source.load_file(host.path_join("Scripts/Quests/challenge.chl"))
	var ordered: Array = source.scripts.values()
	ordered.sort_custom(func(a, b): return int(a["address"]) < int(b["address"]))
	var by_id := {}
	for e in ordered:
		by_id[int(e["id"])] = e
	var entry: Dictionary = source.scripts[root]
	var start: int = entry["address"]
	var end := source.instruction_count
	for e in ordered:
		if int(e["address"]) > start:
			end = int(e["address"])
			break
	print("SCRIPT ", root, " ", start, "-", end, " ", entry)
	for a in range(start, end):
		var ins := source.instruction(a)
		var op: int = ins["opcode"]
		var arg := ""
		if op == 5:
			arg = str(natives.get(int(ins["bits"]), ins["bits"]))
		elif op == 24:
			arg = str(by_id[int(ins["bits"])]["name"]) if by_id.has(int(ins["bits"])) else str(ins["bits"])
		elif op == 2 and int(ins["mode"]) == 0 and int(ins["type"]) in [2, 4]:
			var b := PackedByteArray()
			b.resize(4)
			b.encode_u32(0, int(ins["bits"]))
			arg = str(snappedf(b.decode_float(0), 0.001))
		elif (op == 2 or op == 3) and int(ins["mode"]) == 1:
			arg = "var" + str(ins["bits"])
		else:
			arg = str(ins["bits"])
		print("%6d %-8s m%d t%d %s" % [a, NAMES[op] if op < NAMES.size() else str(op), ins["mode"], ins["type"], arg])
	quit(0)
