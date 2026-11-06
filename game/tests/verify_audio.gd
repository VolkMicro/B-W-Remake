extends SceneTree

const Data := preload("res://scripts/data.gd")
var passed := 0
var failures: Array[String] = []
var host := ""
var played_lines: Array[Dictionary] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bw="):
			host = arg.substr(5)
	call_deferred("run_tests")


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failures.append(label)
		printerr("FAIL ", label)


func run_tests() -> void:
	if host == "":
		printerr("Original Black & White folder required")
		quit(2)
		return
	var bank := SoundBank.new()
	check(bank.open(host.path_join(Data.AUDIO_SOURCES["adviser_bank"]["path"])), "open original adviser voice bank: " + bank.error)
	check(bank.entries.size() > 1000, "index original voice entries without extracting files")
	var dialogue := OriginalDialogue.new()
	check(dialogue.configure(host), "read actual original dialogue text: " + dialogue.error)
	check(dialogue.has_text_enum(4411) and not dialogue.has_text_enum(-1), "resolve the original opening narration by LHVM text enum")
	for id in Data.STORY_DIALOGUE:
		check(bank.entries.has(id) and dialogue.captions.has(id), "original voice and caption exist: " + id)
	var good: Dictionary = dialogue.captions.get("HELP_TEXT_NEWEST_GET_CREATURE_05", {})
	var evil: Dictionary = dialogue.captions.get("HELP_TEXT_NEWEST_GET_CREATURE_06", {})
	check(good.get("speaker", "") == "HELP_TEXT_NARRATOR_GOOD_SPIRIT" and evil.get("speaker", "") == "HELP_TEXT_NARRATOR_EVIL_SPIRIT", "original dialogue preserves both speakers")
	var sample := bank.sample("HELP_TEXT_NEWEST_GET_CREATURE_05")
	check(sample.get("ok", false) and sample.get("format", "") == "mpeg", "read original compressed voice into memory")
	if sample.get("ok", false):
		var decoded := MpegAudio.decode(sample["payload"])
		check(decoded.get("ok", false), "decode original adviser voice through in-memory pipe: " + str(decoded.get("error", "")))
		if decoded.get("ok", false):
			var pcm: PackedByteArray = decoded["pcm"]
			check(decoded["sample_rate"] == 22050 and decoded["channels"] == 1 and pcm.size() > 44000, "decoded original voice has expected rate, channels and duration")
			var peak := 0
			for i in range(0, pcm.size(), 2):
				peak = maxi(peak, absi(pcm.decode_s16(i)))
			check(peak > 100, "decoded original voice is not silence")
	check(not bank.sample("not-a-game-sound").get("ok", false), "missing original sound fails explicitly")
	check(not MpegAudio.decode(PackedByteArray()).get("ok", false), "empty compressed audio is rejected")
	check(not MpegAudio.decode(PackedByteArray([0,1,2,3,4])).get("ok", false), "invalid compressed audio is rejected")
	var samples: Dictionary = {}
	for mode in Data.MUSIC_MODES:
		var row: Dictionary = Data.MUSIC_MODES[mode]
		var path: String = host.path_join(Data.AUDIO_SOURCES[row["source"]]["path"])
		var track := OriginalMusic.decode_track(path, row["section_prefix"], MpegAudio.executable_path(), 3)
		check(track.get("ok", false) and track.get("sections", 0) == 3, "decode original " + mode + " music segments in memory")
		if track.get("ok", false):
			samples[mode] = track["pcm"]
			check(track["sample_rate"] == 22050 and track["channels"] == 2 and track["pcm"].size() > 100000, "original " + mode + " music has valid stereo PCM")
	check(samples.size() == 3 and samples.get("good", PackedByteArray()) != samples.get("evil", PackedByteArray()), "good and evil use distinct original recordings")
	for mode in ["neutral","good","evil"]:
		var source_id: String = Data.MUSIC_MODES[mode]["source"]
		var path: String = host.path_join(Data.AUDIO_SOURCES[source_id]["path"])
		var whole := OriginalMusic.decode_track(path, "SECT", MpegAudio.executable_path(), 0)
		check(whole.get("ok", false) and whole.get("sections", 0) == 430 and whole.get("pcm", PackedByteArray()).size() > 40000000, "decode complete ordered original " + mode + " soundtrack in memory")
	for cue in [54, 61]:
		var whole := OriginalMusic.decode_track(host.path_join(OriginalMusic.STORY_CUES[cue]), "SECT", MpegAudio.executable_path(), 0)
		var expected_sections := 177 if cue == 54 else 29
		var expected_seconds := 193.567 if cue == 54 else 31.660
		check(whole.get("ok", false) and whole.get("sections", 0) == expected_sections, "decode every original story music section for cue %d: %s" % [cue, whole.get("error", "")])
		if whole.get("ok", false):
			var pcm: PackedByteArray = whole["pcm"]
			var seconds := float(pcm.size()) / (2 * int(whole["channels"]) * int(whole["sample_rate"]))
			var peak := 0
			for i in range(0, pcm.size(), 2048):
				peak = maxi(peak, absi(pcm.decode_s16(i)))
			check(whole["sample_rate"] == 22050 and whole["channels"] == 2 and absf(seconds - expected_seconds) < 0.1 and peak > 100, "complete original cue %d has audible stereo audio and expected duration (%.3f s)" % [cue, seconds])
	var music := OriginalMusic.new()
	check(music.configure(host), "configure original alignment music: " + music.error)
	music.set_alignment(50.0)
	check(music._requested == "good", "good alignment requests original good music")
	music.set_alignment(-50.0)
	check(music._requested == "evil", "evil alignment requests original evil music")
	music.set_alignment(0.0)
	check(music._requested == "neutral", "neutral alignment requests original neutral music")
	root.add_child(music)
	root.add_child(dialogue)
	dialogue.line_started.connect(func(speaker: String, text: String): played_lines.append({"speaker":speaker,"text":text}))
	for i in 300:
		if music._current == "neutral": break
		await create_timer(0.025).timeout
	check(music._current == "neutral" and music._player.playing, "full original neutral music starts through asynchronous player")
	music.set_alignment_enabled(false)
	check(music._player.stream_paused and music.start_story_cue(54), "script cue 54 takes over from the alignment soundtrack")
	for i in 300:
		if music._current == "54": break
		await create_timer(0.025).timeout
	check(music._current == "54" and music._player.playing and not music._player.stream_paused, "original intro music decodes and plays while alignment music is disabled")
	check(music._player.volume_db == OriginalMusic.STORY_VOLUME_DB, "cinematic score uses the audible story mix")
	music._player.seek(30.0)
	check(not music.start_story_cue(-1) and music._story_cue == 54, "unsupported music cue fails explicitly without interrupting the current score")
	check(music.start_story_cue(61), "temple reveal requests the original Epic01 cue")
	for i in 300:
		if music._current == "61": break
		await create_timer(0.025).timeout
	check(music._current == "61" and music._player.playing and not music._player.stream_paused and music._player.get_playback_position() < 1.0, "Epic01 starts at its beginning after the previous cue was at 30 seconds")
	check(music.error.is_empty() and music._player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and absf(music._player.stream.get_length() - 31.660) < 0.1, "complete Epic01 plays once and clears previous cue errors")
	var epic_stream := music._player.stream
	music.set_alignment_enabled(true)
	music.set_alignment(50.0)
	music.set_alignment_enabled(false)
	check(music._current == "61" and music._player.playing and not music._player.stream_paused and music._player.stream == epic_stream, "alignment controls do not pause or replace the foreground Epic01 cue")
	check(dialogue.play_text_enum(4411), "start original foreground narration over Epic01")
	for i in 200:
		if not played_lines.is_empty(): break
		await create_timer(0.025).timeout
	var epic_position := music._player.get_playback_position()
	await create_timer(0.15).timeout
	check(not played_lines.is_empty() and dialogue._player.playing and music._current == "61" and music._player.playing and not music._player.stream_paused and music._player.stream == epic_stream and music._player.get_playback_position() > epic_position, "foreground narration plays while the original Epic01 cue continues")
	dialogue.stop()
	check(music._current == "61" and music._player.playing and music._player.stream == epic_stream, "clearing foreground dialogue leaves Epic01 playing")
	played_lines.clear()
	music._player.seek(20.0)
	check(music.start_story_cue(2), "original neutral cue follows the temple reveal")
	for i in 300:
		if music._current == "2": break
		await create_timer(0.025).timeout
	check(music._current == "2" and music._player.playing and music._player.get_playback_position() < 1.0 and absf(music._player.stream.get_length() - 471.667) < 0.1, "full original neutral story cue begins at zero after Epic01")
	check(music.start_story_cue(67), "keeper requests the original CreatureGuide score")
	for i in 300:
		if music._current == "67": break
		await create_timer(0.025).timeout
	check(music._current == "67" and music._player.playing and music._player.get_playback_position() < 1.0 and absf(music._player.stream.get_length() - 154.958) < 0.1, "complete CreatureGuide score plays from its beginning")
	music.stop_story_cue()
	check(not music._player.playing, "stop music stops the original story cue")
	music.free()
	check(dialogue.play_text_enum(4411), "start original opening narration")
	for i in 200:
		if not played_lines.is_empty(): break
		await create_timer(0.025).timeout
	check(not played_lines.is_empty() and played_lines[0]["speaker"] == "HELP_TEXT_NARRATOR_BIG_VOICE", "original opening narration plays with the original narrator caption")
	# Match RUN_TEXT's false/false mode: a later line waits for the current
	# original recording rather than cancelling it as a background quest speaks.
	dialogue.stop()
	check(dialogue.play_text_enum(4411, false), "start original queued narration")
	for i in 200:
		if dialogue._player.playing: break
		await create_timer(0.025).timeout
	var voice_stream := dialogue._player.stream
	var voice_generation := dialogue._generation
	check(dialogue.play_text_enum(5128, false) and dialogue._player.stream == voice_stream and dialogue._player.playing and dialogue._generation == voice_generation and dialogue._queue.size() == 1, "ordinary RUN_TEXT preserves the current voice and queues the next line")
	check(dialogue.play_text_enum(5128, true) and dialogue._generation > voice_generation and dialogue._queue.is_empty(), "single-line RUN_TEXT explicitly replaces queued speech")
	dialogue.stop()
	played_lines.clear()
	check(dialogue.play_event("creature_choice"), "start original creature choice dialogue")
	for i in 200:
		if not played_lines.is_empty(): break
		await create_timer(0.025).timeout
	check(played_lines.size() >= 1 and played_lines[0]["text"] == dialogue.captions["HELP_TEXT_NEWEST_GET_CREATURE_05"]["text"], "first actual original line starts with its caption")
	check(dialogue.play_event("creature_chosen"), "selection interrupts previous conversation")
	for i in 200:
		if played_lines.size() >= 2: break
		await create_timer(0.025).timeout
	check(played_lines.size() >= 2 and played_lines[1]["text"] == dialogue.captions["HELP_TEXT_NEWEST_GET_CREATURE_16"]["text"], "choice plays matching original response")
	dialogue.stop()
	dialogue.free()
	await create_timer(0.15).timeout
	print("RESULT ", passed, " passed; ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)
