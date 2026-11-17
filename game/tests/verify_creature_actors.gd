extends SceneTree
## Installed assets and bridge integration, separate from campaign progression.
class ActorWorld extends "res://scripts/main.gd":
	func _ready() -> void: pass

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if ok: passed += 1
	else: failed += 1

func run() -> void:
	var world := ActorWorld.new()
	world.bw_dir = "C:/Games/Black and White Complete Collection"
	world.story_preview = true
	root.add_child(world)
	world.add_child(world.cam)
	world._build_hud()
	check(world.lnd.load_file(world.bw_dir.path_join(world.Data.SOURCES["landscape"])), "actor fixture reads installed first-island ground")
	check(world.g3d.open(world.bw_dir.path_join("Data/AllMeshes.g3d"),world.bw_dir.path_join("Data/AllMeshes.h")) and world.host_info.load_file(world.bw_dir.path_join("Scripts/info.dat"),world.g3d.mesh_offsets.size()),"actor fixture reads installed development masks")
	var bridge := StoryNatives.new()
	bridge.configure(world)
	bridge.camera = world.story_camera
	world.story_bridge = bridge
	var absent := bridge.invoke(197,[StoryVm.number(1)],{})
	check(absent.get("ok",false) and absent["push"]==[StoryVm.integer(0,StoryVm.OBJECT)],"player-creature query returns NULL before an actual choice")
	var actors: Array[IslandCreature] = []
	var handles: Array[Dictionary] = []
	for subtype in 3:
		var request := [StoryVm.integer(12),StoryVm.integer(subtype),StoryVm.number(1750.0+subtype*20.0),StoryVm.number(35.0),StoryVm.number(2810.0)]
		var response := bridge.invoke(27,request,{})
		check(response.get("ok",false) and response.get("push",[]).size()==1,"CREATE12 returns a source creature handle for subtype%d" % subtype)
		if not response.get("ok",false): continue
		var handle: Dictionary = response["push"][0]
		var actor := bridge._object(handle) as IslandCreature
		actor.set_physics_process(false)
		actors.append(actor)
		handles.append(handle)
		check(actor.species==["ape","cow","tiger"][subtype] and actor.rig.bone_count==[76,48,51][subtype],"actor loads the correct original model and skeleton")
		check(actor.story_actor and actor.story_player_id==-1 and world.creature==null and not bridge.profile_has_creature,"creation does not choose or own a creature")
		check(actor.morph.names_by_index.get(72,"")=="individual/friendly_wave","source animation index72 resolves through the installed specification")
		var before: Array[Transform3D] = []
		for bone in actor.rig.bone_count: before.append(actor.rig.skeleton.get_bone_pose(bone))
		check(bridge.invoke(20,[handle,StoryVm.integer(72),StoryVm.integer(1)],{}).get("ok",false) and bridge.invoke(17,[handle,StoryVm.integer(200)],{}).get("ok",false),"source ScriptPlayAnim starts its real CBN clip")
		var duration := float(actor.morph.clips["individual/friendly_wave"]["duration"])
		actor.advance_story(duration*0.4)
		var changed := false
		for bone in actor.rig.bone_count: changed = changed or not before[bone].is_equal_approx(actor.rig.skeleton.get_bone_pose(bone))
		check(changed and StoryVm.as_int(bridge.invoke(64,[handle],{})["push"][0])==0,"actual bones move while PLAYED remains false")
		actor.advance_story(duration*2.0)
		var terminal: Array[Transform3D] = []
		for bone in actor.rig.bone_count: terminal.append(actor.rig.skeleton.get_bone_pose(bone))
		actor.advance_story(duration)
		var retained := true
		for bone in actor.rig.bone_count: retained = retained and terminal[bone].is_equal_approx(actor.rig.skeleton.get_bone_pose(bone))
		check(retained and StoryVm.as_int(bridge.invoke(64,[handle],{})["push"][0])==1,"completed finite animation retains its terminal pose")
		var position := actor.position
		var hunger := actor.hunger
		actor.advance_story(30.0)
		check(actor.position==position and actor.hunger==hunger and not actor.following,"source actor does not run prototype hunger, following or autonomous learning")
		var state: Dictionary = actor._story_clock.snapshot()
		check(not bridge.invoke(20,[handle,StoryVm.integer(99999),StoryVm.integer(1)],{}).get("ok",false) and actor._story_clock.snapshot()==state,"unknown installed animation remains unsupported without losing the current request")
	check(world.story_creatures.size()==3 and actors.size()==3,"three original species coexist as separate scene actors")
	if actors.size()==3:
		var marker := Node3D.new()
		marker.position = actors[0].position+Vector3(10,0,10)
		var marker_handle := StoryVm.integer(bridge.register_object(marker,1),StoryVm.OBJECT)
		check(bridge.invoke(75,[handles[0],StoryVm.integer(189),marker_handle,StoryVm.integer(0,StoryVm.OBJECT)],{}).get("ok",false),"LookForever accepts a real source marker outside the scene tree")
		actors[0].advance_story(0.1)
		check(is_finite(actors[0].rotation.y),"marker look advances without querying an orphan global transform")
		var state: Dictionary = actors[0]._story_clock.snapshot()
		check(not bridge.invoke(75,[handles[0],StoryVm.integer(9999),marker_handle,StoryVm.integer(0)],{}).get("ok",false) and actors[0]._story_clock.snapshot()==state,"unimplemented creature actions remain pending without changing animation")
		marker.free()
		actors[0].advance_story(0.1)
		check(bridge.invoke(83,[handles[1]],{}).get("ok",false) and world.creature==actors[1] and actors[1].story_player_id==1 and bridge.profile_has_creature,"source ownership selects the existing cow actor")
		var query := bridge.invoke(197,[StoryVm.number(1)],{})
		check(query.get("ok",false) and query["push"]==[handles[1]],"player query returns the stable handle of the actual selected actor")
		check(not bridge.invoke(197,[StoryVm.number(2)],{}).get("ok",false),"unported other-player queries do not return the player's creature")
		check(actors[0].story_player_id==-1 and actors[2].story_player_id==-1,"ownership does not silently select the alternatives")
		check(bridge.invoke(223,[handles[1],StoryVm.number(1800),StoryVm.number(30),StoryVm.number(2500)],{}).get("ok",false) and actors[1].story_home==Vector3(1800,30,-2500),"source creature home preserves mirrored coordinates")
		check(not bridge.invoke(223,[handles[1],StoryVm.number(NAN),StoryVm.number(30),StoryVm.number(2500)],{}).get("ok",false) and actors[1].story_home==Vector3(1800,30,-2500),"invalid home does not overwrite the selected creature's home")
		check(bridge.invoke(159,[handles[1]],{}).get("ok",false) and not actors[1].story_script_controlled,"source release changes control without activating the sandbox")
		check(bridge.invoke(205,[StoryVm.integer(1)],{}).get("ok",false) and actors[1].story_development_phase==0 and actors[1].story_desires.size()==40 and actors[1].story_desires[5] and not actors[1].story_desires[0],"DEV_FUNCTION1 initializes forty actual desire gates from the installed phase0 record")
		check(actors[1].story_tether_radius==12.0 and actors[1].story_tether_center==actors[1].story_home,"development initialization sets the source home anchor and twelve-unit tether")
		var home: Vector3=actors[1].story_home
		check(bridge.invoke(24,[handles[1],StoryVm.number(home.x+20),StoryVm.number(home.y),StoryVm.number(-home.z)],{}).get("ok",false),"declared movement fixture uses real SET_POSITION for its out-of-tether precondition")
		actors[1].advance_story(5.0)
		check(Vector2(actors[1].position.x-home.x,actors[1].position.z-home.z).length()<=12.0,"initialized tether has an observable movement effect")
		check(not bridge.invoke(205,[StoryVm.integer(2)],{}).get("ok",false) and actors[1].story_development_phase==0,"other development/debug commands remain unsupported")
		check(bridge.invoke(208,[handles[1],StoryVm.integer(0)],{}).get("ok",false) and not bridge.invoke(208,[handles[1],StoryVm.integer(1)],{}).get("ok",false),"stage0 uses the installed mask while later training stages remain unsupported")
		check(bridge.invoke(282,[StoryVm.integer(1,StoryVm.BOOL),handles[1]],{}).get("ok",false) and actors[1].story_in_development_script,"source training flag gates ordinary tether movement")
		bridge.invoke(24,[handles[1],StoryVm.number(home.x+20),StoryVm.number(home.y),StoryVm.number(-home.z)],{})
		actors[1].advance_story(1.0)
		check(is_equal_approx(actors[1].position.x,home.x+20),"active training preserves its authored out-of-tether setup")
		check(bridge.invoke(282,[StoryVm.integer(0,StoryVm.BOOL),handles[1]],{}).get("ok",false) and not actors[1].story_in_development_script,"source can release the training control gate")
		check(bridge.invoke(22,[StoryVm.integer(31),handles[1],StoryVm.number(1)],{}).get("ok",false) and bridge.invoke(75,[handles[1],StoryVm.integer(17),handles[1],StoryVm.integer(0,StoryVm.OBJECT)],{}).get("ok",false),"source property31 and SleepAtHome start the installed sleep sequence")
		actors[1].advance_story(4.0)
		check(actors[1]._story_clock.snapshot()["name"]=="static/sleep" and actors[1]._story_sleep_phase=="sleeping" and StoryVm.as_float(bridge.invoke(21,[StoryVm.integer(31),handles[1]],{})["push"][0])==1.0,"sleep enters its real looping CBN clip with the configured fatigue")
		check(bridge.invoke(22,[StoryVm.integer(31),handles[1],StoryVm.number(0)],{}).get("ok",false),"source can clear fatigue to request waking")
		actors[1].advance_story(4.0)
		check(actors[1]._story_sleep_phase=="" and not actors[1].story_animation_playing(),"wake animation completes and restores ordinary standing")
		check(bridge.invoke(48,[handles[0],StoryVm.integer(0)],{}).get("ok",false) and bridge._object(handles[0])==null and world.story_creatures.size()==2 and world.creature==actors[1],"source cleanup deletes an actual alternative while retaining the selected actor")
	world._hand_surface = Vector3(12,34,-56)
	var hand := bridge.invoke(42,[],{})
	check(hand.get("ok",false) and hand["push"]==[StoryVm.number(12,StoryVm.VECTOR),StoryVm.number(34,StoryVm.VECTOR),StoryVm.number(56,StoryVm.VECTOR)],"hand-position native returns current mirrored contact as three VECTOR cells")
	world.story_camera.eye = Vector3(0,20,0)
	world.story_camera.focus = Vector3.ZERO
	var shake := [StoryVm.number(0),StoryVm.number(20),StoryVm.number(0),StoryVm.number(20),StoryVm.number(0.1),StoryVm.number(7)]
	check(bridge.invoke(201,shake,{}).get("ok",false),"source earthquake starts a visible presentation request")
	world.story_camera.advance(0.1)
	check(not world.story_camera.visual_shake_offset().is_zero_approx() and world.story_camera.eye==Vector3(0,20,0),"shake affects presentation without changing logical camera position")
	world.story_camera.advance(7.0)
	check(world.story_camera.visual_shake_offset()==Vector3.ZERO,"visual shake expires without a permanent camera offset")
	bridge.clear_created()
	world.g3d.close()
	for property in ["hand_ring","hand_pivot","ambience","sea_player"]:
		var node: Node = world.get(property)
		if node.get_parent()==null: world.add_child(node)
	world.free()
	await process_frame
	print("CREATURE ACTORS %d passed; %d failed" % [passed,failed])
	quit(0 if failed==0 else 1)
