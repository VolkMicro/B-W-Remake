extends SceneTree

class CrowdWorld extends Node:
	var bw_dir := ""
	var g3d := G3dReader.new()
	var cam := Camera3D.new()
	var animation_clock := 0.0
	var story_camera = preload("res://scripts/story_camera.gd").new()
	var villager_anims := AnmReader.new()

var failures := 0

func _initialize() -> void:
	call_deferred("run_test")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func run_test() -> void:
	var world := CrowdWorld.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			world.bw_dir = arg.substr(5)
	world.add_child(world.cam)
	var data = preload("res://scripts/data.gd")
	var opened := world.g3d.open(world.bw_dir.path_join(data.SOURCES["meshes"]), world.bw_dir.path_join("Data/AllMeshes.h"))
	check(opened, "open installed original villager archive")
	if not opened:
		world.free()
		quit(1)
		return
	var actor := Thing.new()
	actor.kind = "villager"
	actor.world = world
	actor.rig = world.g3d.rig("MSH_P_NORS_M_A_1")
	actor.add_child(actor.rig.root)
	actor.position = Vector3(20, 5, -40)
	world.add_child(actor)
	var crowd := StoryFlock.new()
	world.add_child(crowd)
	crowd.attach(actor, false)
	crowd.crowd_mode = true
	crowd._physics_process(0.1)
	check(actor.is_script_animation_playing() and crowd._crowd_animations != null, "ScriptInCrowd starts the original finite state animation")
	var clips := crowd._crowd_animations.names_by_index.values()
	check(actor._script_clip in clips and actor._script_clip_end < INF, "crowd uses the installed original gesture pool without an infinite loop")
	actor._process(0.1)
	var age := actor._script_clip_age
	crowd._physics_process(0.1)
	check(actor._script_clip_age == age, "crowd does not restart an unfinished gesture on every game turn")
	var original_position := actor.position
	actor._physics_process(0.1)
	check(actor.position == original_position, "standing crowd stays at its original spot")
	actor._process(actor._script_clip_end + 0.1)
	check(not actor.is_script_animation_playing(), "finite original crowd clip finishes")
	crowd._physics_process(0.1)
	check(actor.is_script_animation_playing() and actor._script_clip_age == 0.0, "crowd picks another original state animation after completion")
	crowd.detach(actor)
	check(actor.story_flock == null and not actor.is_script_animation_playing(), "leaving the crowd releases its animation and movement")
	verify_welcome_dance(world, actor)
	world.g3d.close()
	world.free()
	print("CROWD failures=", failures)
	quit(0 if failures == 0 else 1)


func verify_welcome_dance(world: CrowdWorld, male: Thing) -> void:
	var female := Thing.new()
	female.kind = "villager"
	female.world = world
	female.animation_profile = "female"
	female.rig = world.g3d.rig("MSH_P_NORS_F_A_1")
	female.add_child(female.rig.root)
	world.add_child(female)
	var dance := preload("res://scripts/story_welcome_dance.gd").new()
	world.add_child(dance)
	dance.focus_actor = male
	check(dance.load_choreography(FileAccess.get_file_as_bytes(world.bw_dir.path_join("Scripts/Dance/NewDanceAroundPerson"))), "load installed welcome dance timeline")
	dance.attach(male, false)
	dance.attach(female, false)
	dance.advance(20.0)
	male.position = dance.follow_position(male)
	female.position = dance.follow_position(female)
	dance._physics_process(0.0)
	check(male._script_clip == dance._dance_animations.names_by_index[314] and female._script_clip == dance._dance_animations.names_by_index[265], "welcome slot zero uses the original male and female Dance A clips")
	male._process(0.1)
	var age := male._script_clip_age
	dance._physics_process(0.0)
	check(male._script_clip_age == age, "welcome animation continues between choreography keys")
	dance.advance(30.0)
	dance._physics_process(0.0)
	check(male._script_clip == dance._dance_animations.names_by_index[236] and female._script_clip == dance._dance_animations.names_by_index[266], "turn fifty applies original independent group animation slots")
	male.position += Vector3(2, 0, 0)
	dance._physics_process(0.0)
	check(not male.is_script_animation_playing(), "a dancer outside its formation releases animation so walking can resume")
	dance.disband()
	check(not female.is_script_animation_playing() and male.story_flock == null and female.story_flock == null, "welcome dance disband releases both animation and group control")
