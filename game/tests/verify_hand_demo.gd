extends SceneTree

const HandDemo := preload("res://scripts/story_hand_demo.gd")
var passed := 0
var failed := 0


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok:
		passed += 1
	else:
		failed += 1


func _initialize() -> void:
	var host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	if host.is_empty():
		printerr("Original Black & White folder required")
		quit(2)
		return
	for name in ["drag", "rotate", "pitch", "zoom", "zoomreminder", "givewood"]:
		var demo := HandDemo.new()
		check(demo.start(FileAccess.get_file_as_bytes(host.path_join("Data/HandDemo/%s.hnd" % name))), "parse original %s hand recording" % name)
	var demo := HandDemo.new()
	var bytes := FileAccess.get_file_as_bytes(host.path_join("Data/HandDemo/givewood.hnd"))
	if not demo.start(bytes):
		quit(1)
		return
	var actions: Array[Dictionary] = []
	var triggers := 0
	for i in 1000:
		if not demo.playing:
			break
		demo.advance(0.05)
		for action in demo.take_actions():
			actions.append(action)
			check(action["button_down"] == (action["event"] == "action_pressed"), "recorded input transition updates Action Button state")
		if demo.consume_trigger():
			triggers += 1
	check(not demo.playing and triggers == 4, "original GiveFood demonstration consumes all four dialogue sync markers")
	check(actions.size() == 4 and demo.action_press_count == 2 and demo.action_release_count == 2 and not demo.action_button_down, "givewood contains two Action Button presses and releases")
	if actions.size() == 4:
		check(actions[0]["event"] == "action_pressed" and actions[1]["event"] == "action_released" and actions[2]["event"] == "action_pressed" and actions[3]["event"] == "action_released", "recorded press/release order supports collection, carry, then drop")
		check(absf(float(actions[1]["held_seconds"]) - 4.4) < 0.001 and absf(float(actions[3]["held_seconds"]) - 0.311) < 0.001, "recorded collection lasts 4.4 seconds and final drop press lasts 0.311 seconds")
		var binding: Dictionary = actions[0]["binding"]
		check(binding.get("type") == 16 and binding.get("subtype") == 5 and binding["position"].distance_to(Vector3(1830.11597, 0.0, -2642.61475)) < 0.001, "pickup binds the original STORE/WOOD_PILE_3 at its recorded map position")
		check(actions[1]["binding"]["position"] == binding["position"] and float(actions[1]["binding"]["distance"]) > 1e30 and actions[2]["binding"].is_empty() and actions[3]["binding"].is_empty(), "release retains store binding and the final drop invents no new resource source")
	check(demo.take_actions().is_empty() and demo.action_button_held_seconds() == 0.0, "action queue drains once and released button has no hold duration")
	check(demo.start(bytes) and demo.action_press_count == 0 and demo.action_release_count == 0 and not demo.action_button_down, "restarting demonstration resets all button counters")
	demo.advance(100.0)
	check(demo.trigger_pending and demo.action_press_count == 0, "dialogue sync pauses before pickup instead of skipping input transitions")
	print("RESULT ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
