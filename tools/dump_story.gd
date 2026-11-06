extends SceneTree
## Read-only disassembly of the owner's original CHL for restoration research.
func _initialize() -> void:
	var host := "C:/Games/Black and White Complete Collection"
	var names: Array[String] = []
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="): host = arg.substr(5)
		elif arg.begins_with("--output="): output = arg.substr(9)
		else: names.append(arg)
	var program := ChlReader.new()
	if not program.load_file(host.path_join("Scripts/Quests/challenge.chl")):
		printerr(program.error)
		quit(1)
		return
	var native_names := {}
	var table := ProjectSettings.globalize_path("res://").get_base_dir().path_join("../scratch/native_ids.tsv").simplify_path()
	for line in FileAccess.get_file_as_string(table).split("\n"):
		var columns := line.split("\t")
		if columns.size() >= 2: native_names[int(columns[0])] = columns[1]
	var rows := PackedStringArray()
	for script in names:
		if not program.scripts.has(script):
			rows.append("MISSING " + script)
			continue
		var entry: Dictionary = program.scripts[script]
		var stop := program.instruction_count
		for candidate in program.scripts.values():
			if candidate["address"] > entry["address"]: stop = mini(stop, candidate["address"])
		rows.append("SCRIPT " + str(entry))
		for index in range(entry["address"], stop):
			var instruction := program.instruction(index)
			var value := str(instruction["bits"])
			if instruction["opcode"] == 5:
				value += " " + str(native_names.get(instruction["bits"], "?"))
			elif instruction["opcode"] == 2 and instruction["mode"] == 0 and instruction["type"] in [2, 3]:
				value = str(program.code.decode_float(index * 20 + 12))
			elif instruction["opcode"] == 24:
				value = str(program.scripts_by_id.get(instruction["bits"], {}).get("name", value))
			rows.append("%d %s m%d t%d %s" % [index, preload("res://scripts/data.gd").STORY_OPCODES[str(instruction["opcode"])]["name"], instruction["mode"], instruction["type"], value])
	var text := "\n".join(rows)
	if output.is_empty(): print(text)
	else:
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(text)
	quit()
