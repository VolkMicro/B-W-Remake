extends SceneTree

const WoodHand := preload("res://scripts/story_wood_hand.gd")
const HandDemo := preload("res://scripts/story_hand_demo.gd")
var passed := 0
var failed := 0


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok:
		passed += 1
	else:
		failed += 1


func withdraw(storage: Dictionary, requested: int) -> int:
	var taken := mini(requested, int(storage["wood"]))
	storage["wood"] -= taken
	storage["calls"] += 1
	return taken


func _initialize() -> void:
	var host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	if host.is_empty():
		printerr("Original Black & White folder required")
		quit(2)
		return
	var path := host.path_join("Scripts/info.dat")
	var hand := WoodHand.new()
	check(hand.configure(path), "read actual original HAND_WOOD settings: " + hand.error)
	check(hand.initial_amount == 25 and hand.amount_per_turn == 8 and hand.amount_per_turn_end == 70 and hand.maximum_amount == 20000 and hand.ramp_seconds == 6.0, "original hand pickup uses 25 initially, 8 to 70 per turn, 6 second ramp and 20000 limit")
	var storage := {"wood":30000, "calls":0}
	check(not hand.begin(Callable()) and hand.amount == 0, "invalid withdrawal callback cannot create wood")
	check(hand.begin(func(requested: int) -> int: return withdraw(storage, requested)) and hand.amount == 25 and storage["wood"] == 29975, "first Action Button press withdraws exactly the initial real wood")
	check(not hand.begin(func(requested: int) -> int: return withdraw(storage, requested)), "repeated begin cannot debit a second initial pickup")
	hand.advance(0.099)
	check(hand.amount == 25, "pickup waits for an original 100 ms game turn")
	hand.advance(0.001)
	check(hand.amount == 33 and storage["wood"] == 29967, "first completed game turn takes the original 8 wood")
	hand.advance(4.3)
	check(hand.amount == 860 and storage["wood"] + hand.amount == 30000, "4.4 seconds of original quadratic pickup conserves 860 transferred wood")
	hand.release()
	var calls: int = storage["calls"]
	hand.advance(30.0)
	hand.release()
	check(hand.amount == 860 and storage["calls"] == calls and not hand.collecting, "first button release freezes collection and keeps the wood in hand")
	check(hand.take_all() == 860 and hand.amount == 0 and hand.take_all() == 0 and storage["calls"] == calls, "drop transfers held wood exactly once without another withdrawal")
	var partial := {"wood":17, "calls":0}
	check(hand.begin(func(requested: int) -> int: return withdraw(partial, requested)) and hand.amount == 17 and partial["wood"] == 0, "pickup respects a partially depleted storage pit")
	hand.advance(1.0)
	check(hand.amount == 17 and not hand.collecting and hand.take_all() == 17, "empty storage stops collection without manufacturing resource")
	check(not hand.begin(func(requested: int) -> int: return withdraw(partial, requested)) and hand.amount == 0, "empty storage cannot start a phantom held pile")
	var plentiful := {"wood":30000, "calls":0}
	check(hand.begin(func(requested: int) -> int: return withdraw(plentiful, requested)), "start another original pickup after dropping")
	hand.advance(100.0)
	check(hand.amount == 20000 and plentiful["wood"] == 10000 and not hand.collecting, "original 20000 pickup maximum caps actual withdrawals")
	hand.take_all()
	var demo := HandDemo.new()
	var demo_storage := {"wood":30000, "calls":0}
	demo.start(FileAccess.get_file_as_bytes(host.path_join("Data/HandDemo/givewood.hnd")))
	var previous_time := 0.0
	var holding_after_first_release := 0
	var delivered := 0
	for i in 1000:
		if not demo.playing:
			break
		demo.advance(0.05)
		var interval_start := previous_time
		for action in demo.take_actions():
			hand.advance(maxf(float(action["time"]) - interval_start, 0.0))
			interval_start = float(action["time"])
			if action["event"] == "action_pressed":
				if hand.amount == 0:
					hand.begin(func(requested: int) -> int: return withdraw(demo_storage, requested))
				else:
					delivered += hand.take_all()
			else:
				hand.release()
				if int(action["release_count"]) == 1:
					holding_after_first_release = hand.amount
		hand.advance(maxf(demo.elapsed - interval_start, 0.0))
		previous_time = demo.elapsed
		demo.consume_trigger()
	check(holding_after_first_release == 860 and delivered == 860 and hand.amount == 0 and demo_storage["wood"] == 29140, "actual givewood recording carries its collected supply until the second press and delivers once")
	check(not WoodHand.new().configure(host.path_join("Scripts/missing-info.dat")), "missing resource settings fail explicitly")
	print("RESULT ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
