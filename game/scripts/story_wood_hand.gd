class_name StoryWoodHand
extends RefCounted

const Data := preload("res://scripts/data.gd")
# BW1 1.2 serializes GPotInfo without its 16-byte GBaseInfo header.
# The eleventh pot row is POT_INFO_HAND_WOOD, used by PileWood's locked pickup.
const HAND_WOOD_OFFSET := 288460
const HAND_WOOD_SIZE := 308
const GAME_TURN_SECONDS := 0.1

var error := ""
var amount := 0
var initial_amount := 0
var amount_per_turn := 0
var amount_per_turn_end := 0
var maximum_amount := 0
var ramp_seconds := 0.0
var collecting := false
var _configured := false
var _take := Callable()
var _elapsed := 0.0
var _turn := 0


func configure(path: String) -> bool:
	error = ""
	_configured = false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_buffer(8).get_string_from_ascii() != "LiOnHeAd":
		return _fail("Original hand resource settings are unavailable")
	while file.get_position() + 36 <= file.get_length():
		var raw_name := file.get_buffer(32)
		var end := raw_name.find(0)
		var name := raw_name.slice(0, end if end >= 0 else 32).get_string_from_ascii()
		var size := file.get_32()
		var start := file.get_position()
		if size > file.get_length() - start:
			return _fail("Original hand resource settings are truncated")
		if name == "Info":
			var supported := false
			for format in Data.HOST_INFO_FORMATS.values():
				if format["id"] == "bw_1_2" and int(format["info_size"]) == size:
					supported = true
			if not supported or HAND_WOOD_OFFSET + HAND_WOOD_SIZE > size:
				return _fail("Unsupported original hand resource settings version")
			file.seek(start + HAND_WOOD_OFFSET)
			return _configure_row(file.get_buffer(HAND_WOOD_SIZE))
		file.seek(start + size)
	return _fail("Original hand resource settings block is missing")


func _configure_row(row: PackedByteArray) -> bool:
	if row.size() != HAND_WOOD_SIZE or row.slice(8, 17).get_string_from_ascii() != "Hand Wood" or row.decode_u32(0x108) != 1:
		return _fail("Original hand wood record is invalid")
	# GPotInfo +0x130..0x140: initial, starting/ending per-turn amount,
	# pickup maximum and ramp duration. MaxResource (+0x11c) is a mesh scale
	# setting; ProcessInInteract caps at MaxAmountCanBePickedUp instead.
	initial_amount = row.decode_u32(0x120)
	amount_per_turn = row.decode_u32(0x124)
	amount_per_turn_end = row.decode_u32(0x128)
	maximum_amount = row.decode_u32(0x12c)
	ramp_seconds = row.decode_float(0x130)
	if initial_amount <= 0 or amount_per_turn <= 0 or amount_per_turn_end < amount_per_turn or maximum_amount < initial_amount or maximum_amount > 1000000 or not is_finite(ramp_seconds) or ramp_seconds <= 0.0:
		return _fail("Original hand wood pickup limits are invalid")
	_configured = true
	return true


func begin(take: Callable) -> bool:
	if not _configured or not take.is_valid() or collecting or amount > 0:
		return false
	_take = take
	_elapsed = 0.0
	_turn = 0
	collecting = true
	_collect(initial_amount)
	if amount == 0:
		release()
		return false
	return true


func advance(delta: float) -> void:
	if not collecting or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	var turns := floori((_elapsed + 0.0000001) / GAME_TURN_SECONDS)
	var ramp_turns := maxi(1, int((1.0 / GAME_TURN_SECONDS) * ramp_seconds))
	while collecting and _turn < turns:
		_turn += 1
		var weight := clampf(float(_turn) / ramp_turns, 0.0, 1.0)
		# GPotInfo's original 0x66cd30 uses a quadratic ramp and truncates
		# the positive float result before removing resources from the pile.
		var requested := int(amount_per_turn + (amount_per_turn_end - amount_per_turn) * weight * weight)
		if _collect(requested) == 0:
			release()


func _collect(requested: int) -> int:
	requested = mini(requested, maxi(maximum_amount - amount, 0))
	if requested <= 0 or not _take.is_valid():
		return 0
	var taken := clampi(int(_take.call(requested)), 0, requested)
	amount += taken
	return taken


func release() -> void:
	collecting = false
	_take = Callable()


func take_all() -> int:
	var result := amount
	release()
	amount = 0
	return result


func _fail(message: String) -> bool:
	error = message
	return false
