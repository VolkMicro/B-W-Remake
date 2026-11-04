# Development-only inventory of the player's campaign dependencies.
# Reads the installed bytecode in memory; never exports original game data.
extends SceneTree


func _initialize() -> void:
	var host := ""
	var root_script := "LandControlAll"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
		elif arg.begins_with("--root="):
			root_script = arg.substr(7)
	if host.is_empty():
		printerr("Supply the installed game with --bw=<folder>")
		quit(1)
		return
	var source := ChlReader.new()
	if not source.load_file(host.path_join("Scripts/Quests/challenge.chl")):
		printerr(source.error)
		quit(1)
		return
	if not source.scripts.has(root_script):
		printerr("Script not found: ", root_script)
		quit(1)
		return
	var ordered: Array = source.scripts.values()
	ordered.sort_custom(func(a, b): return int(a["address"]) < int(b["address"]))
	var by_id := {}
	for i in ordered.size():
		var entry: Dictionary = ordered[i]
		var end: int = ordered[i + 1]["address"] if i + 1 < ordered.size() else source.instruction_count
		var natives := {}
		var children := {}
		for address in range(entry["address"], end):
			var ins := source.instruction(address)
			if ins["opcode"] == 5:
				natives[ins["bits"]] = true
			elif ins["opcode"] == 24:
				children[ins["bits"]] = true
		by_id[entry["id"]] = {"name": entry["name"], "natives": natives, "children": children}
	var pending := [int(source.scripts[root_script]["id"])]
	var visited := {}
	var used_natives := {}
	var missing_scripts := {}
	while not pending.is_empty():
		var id: int = pending.pop_back()
		if visited.has(id):
			continue
		visited[id] = true
		if not by_id.has(id):
			missing_scripts[id] = true
			continue
		for native in by_id[id]["natives"]:
			used_natives[native] = true
		for child in by_id[id]["children"]:
			pending.append(int(child))
	var implemented := preload("res://scripts/data.gd").STORY_NATIVES
	var bound := 0
	var unbound: Array[int] = []
	for native in used_natives:
		if implemented.has(str(native)):
			bound += 1
		else:
			unbound.append(native)
	unbound.sort()
	print("Root: ", root_script)
	print("Potentially reachable scripts: ", visited.size())
	print("Distinct world functions: ", used_natives.size(), "; implemented: ", bound)
	print("Unimplemented function IDs: ", unbound)
	print("Unresolved script IDs: ", missing_scripts.keys())
	print("Note: this is a conservative static call graph; runtime branches may differ.")
	quit(0 if missing_scripts.is_empty() else 1)
