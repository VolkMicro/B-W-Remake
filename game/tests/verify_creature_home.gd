extends "res://tests/verify_creature_glade.gd"
## Focused continuation after genuine three-key delivery and creature choice.
## The parent fixture does not run LandControl1. Start its next source scene
## explicitly, without changing quest flags, ownership, actor position or fade.
var following_home := false

func source_step(world: Node) -> void:
	await super.source_step(world)
	# This off-main-loop fixture advances its clocks in fixed 0.1s steps.
	if following_home and world.story_fade_tween != null and world.story_fade_tween.is_valid():
		world.story_fade_tween.custom_step(0.1)


func verify_third_stone(world: Node, quarry: Thing) -> void:
	await super.verify_third_stone(world, quarry)
	if failed > 0 or glade_ready_only: return
	check(world.story_fade_rect != null and world.story_fade_rect.color.a >= 0.99, "source choice leaves a covered transition for LandControl1's next scene")
	if failed > 0: return
	world.story_vm.strict_scripts.append_array(PackedStringArray(["CreatureDevSeeHome", "CreatureDevelopmentTrainerLeaveCitadel"]))
	following_home = true
	world.story_vm.start("CreatureDevSeeHome")
	var revealed := false
	for i in 3000:
		await source_step(world)
		if not world.story_vm.error.is_empty():
			check(false, "next original scene remains pending: " + str(world.story_vm.error))
			return
		for task in world.story_vm.tasks.values():
			if task["script"] == "CreatureDevSeeHome" and task["pc"] >= 6136 and world.story_fade_rect.color.a <= 0.01:
				revealed = true
		if revealed: break
	check(revealed, "original home scene removes the black cover through its own fade-in")
	check(world.creature.story_fatigue == 1.0 and world.creature._story_sleep_phase == "sleeping", "original home scene makes the actual selected creature sleep")
	print("HOME RESULT revealed=", revealed, " fade=", world.story_fade_rect.color.a, " pending=", world.story_vm.error)
	if revealed and not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-home.png")
