extends SceneTree

class MovieWorld extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var source := ""
	var full_playback := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			source = arg.substr(5)
		elif arg == "--full-playback":
			full_playback = true
	var world := MovieWorld.new()
	world.bw_dir = source
	root.add_child(world)
	world._build_hud()
	# This is the real FollowUs transition: SET_FADE black, SET_AVI_SEQUENCE.
	# FollowUs has no SET_FADE_IN after this movie.
	world.story_fade(true, Color.BLACK, 0.0)
	check(world.story_fade_rect.color.a == 1.0, "original movie begins over an opaque story fade")
	check(world.story_play_intro_movie(), "start player's original Bink intro through local movie cache")
	var movie = world.story_intro_movie
	if movie != null:
		var deadline := Time.get_ticks_msec() + 120000
		var played := false
		while movie.active and Time.get_ticks_msec() < deadline:
			if movie.player.is_playing() and movie.player.stream_position >= 0.25:
				played = true
				if not full_playback:
					movie.finish() # Same completion path as the user's Escape key.
			await create_timer(0.1).timeout
		check(played and movie.error.is_empty(), "original movie decodes and advances")
		check(not movie.active and not movie.visible, "movie releases its fullscreen layer on completion")
		check(world.story_fade_rect.color.a == 0.0, "movie completion uncovers island without requiring an absent fade-in command")
		world.story_fade(true, Color.BLACK, 0.0)
		movie.finish()
		check(world.story_fade_rect.color.a == 1.0, "duplicate completion does not cancel a later scripted fade")
	for property in ["cam", "hand_ring", "hand_pivot", "hud", "align_bar", "align_label", "towns_label", "msg_label", "help_label", "dialogue_caption", "ambience", "sea_player", "creature_panel", "creature_status", "campaign_status", "choice_row"]:
		var node: Variant = world.get(property)
		if node is Node and is_instance_valid(node) and node.get_parent() == null:
			world.add_child(node)
	world.free()
	print("MOVIE failures=", failures)
	quit(0 if failures == 0 else 1)
