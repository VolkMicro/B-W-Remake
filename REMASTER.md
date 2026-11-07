# Preservation target

Current product direction (2026-11-06): a noncommercial fan remake on Godot,
with recognizable original play followed by modern presentation and deeper
systems. Original data files may remain required in the finished game.
Observable fidelity and playability are the target; bit-exact reproduction of
every internal calculation is not required. See PROJECT_RU.md and
TASK_CLAUDE_RU.md. New clean-room work follows CLEAN_ROOM_RU.md; legacy code
does not acquire clean-room provenance retrospectively.

The creator's explicit target is a full Black & White remaster: to feel like playing the original childhood game. The port must keep the original story, behaviour, atmosphere and content, rather than turn the original landscape into an unrelated sandbox. Modern-PC support is the purpose of moving to Godot. Full scope is not satisfied by one island; island one is the first complete playable milestone.

## First milestone acceptance

- The original first-island story runs in its original order, including its quests, creature selection and training, adviser guidance and narrative transitions. Indexing CHL names or showing a quest list is not execution.
- Ape, Cow and Tiger use the player's original models, skins and animation data. Upbringing, rewards, punishment, needs, learning and moral consequences must reproduce the original systems. The current two-action teaching loop is temporary.
- The Good and Evil consciences retain original appearance, speech, reactions and guidance. Current animated models alone do not meet this requirement.
- Hand controls, picking up, carrying, dropping, throwing, physical reactions and miracle interactions should feel like the original. Current gravity, throwing, and belief values are reconstructed prototype parameters, not verified original physics.
- Villagers animate and perform original activities and roles. Villages need their original economy, worship and reactions. Wandering, gifts and scare behaviour alone do not meet this requirement.
- Island one uses all required original landscape, objects, creatures, animations, speech, music and sounds from the player's installation. Missing original object mappings must be recovered. No substitute content, bundled original assets or copied original game files.
- Camera, timing, sounds, light and feedback should support the original experience. New UI must not falsely imply campaign completion; village conversion is not a replacement for the original story ending.
- A full first-island playthrough and fresh one-click Melty installation must pass, with real footage. Numerical/unit checks supplement this, never replace it.

## Current honest status

The experimental `--story-preview` mode starts the original `LandControl1`, including its concurrent singing-stone scripts and `FollowUs` opening. It uses separate development behavior and skips loading or writing the preservation save. Normal launch still starts the tested `SetupLand1` path. The preview is incomplete and can stop at the first unsupported original command.

The opening now reads the original camera and route data, family close-up rigs, script animations, narrator voice, intro music, singing-stone audio and sprite frames, shark models, and rescue Hand assets from the installed game. The original Bink movie is converted asynchronously by FFmpeg and cached locally for Godot's Theora player. The preview needs FFmpeg available on `PATH` to create that cache. Shark path interpolation, game lighting, adviser flight, and some cinematic effects are approximations that still need side-by-side visual verification.

Development example on Windows (replace the original install path as needed):

```powershell
godot --path game -- '--bw=C:/Games/Black and White Complete Collection' --story-preview
godot --headless --path game --script res://tests/verify_landmark_spawn.gd -- '--bw=C:/Games/Black and White Complete Collection' --probe=LandControl1 --simulate --ticks=1600
```

The probe can advance movement and camera state off-tree. It checks the installed original data but skips real player input, rendering, and playback timing. A successful probe alone is insufficient for release.

The preview now drives the opening with the original LHVM, including family movement,
original dialogue, welcome choreography, village membership, the temple construction,
camera tutorials, and the recorded resource-handling demonstration. Prototype creature
selection and alignment panels stay hidden during the opening. Campaign completion,
full economy, miracles, complete creature learning and later quests remain unfinished.
This is not ready to publish as a complete remaster.

Scripted influence falloff reads the original installed settings and was checked
against the installed executable. Town influence still uses a provisional radius;
this is not yet the complete original influence system.

## Engine evaluation and intro fixes (2026-11-05)

The test launcher targets the latest `GodotIsland-village-preview*.exe` in
`build/story-preview`; the shortcut and CMD launcher are updated together.
The shark sequence now renders from above the sea, with a downward view of at
least 45 degrees for its underwater shots. This is an explicit presentation
adjustment requested during testing, not an exact recreation of the original
camera. It does not modify the LHVM camera state or arrival conditions. Water
rendering remains approximate; a four-corner ocean stays level, with per-pixel
surface detail instead of moving the entire plane.

`FollowUs` leaves a black fade in place before its Bink movie and contains no
subsequent fade-in. Movie completion now removes that covering layer. Both the
natural end of the installed 66.7-second video and the Escape completion path
passed six regression assertions using the actual converted video. Island
checks passed 45/45 and story checks 95/95. This does not constitute a full
first-island playthrough.

OpenBlack checkout `744c0febf53b128bebc82ba3782dac7be08ee3e6` was evaluated as an
alternative engine. Its `src/CHLApi.cpp` registers 464 functions including NONE;
441 of the other 463 contain explicit unimplemented diagnostics. Replacing
this port with that checkout would not unlock the campaign. Its separate
ScriptLibrary can execute bytecode, but engine natives still need implementing.
Keep the existing Godot implementation while consulting OpenBlack's camera
constraints, recorded original camera scenarios, file readers and reflected
ocean renderer. Direct reuse of its source requires preserving its GPLv3 terms.
The immediate development priority remains continuous original-story progression
and rendered transition tests; changing VM or renderer alone does not provide
missing campaign behavior.

## Earlier showcase permissions

The creator renewed permission to launch and test the build and use the mouse and keyboard. An isolated 0.3.4 showcase started on 2026-11-04, but computer-use access to its window was not approved. The showcase process is no longer running and did not produce its expected images. No interaction or visual result was verified, and no attempt was made to bypass the restriction. Existing user processes were not closed or restarted. Window/gameplay verification is pending.

## Village and adviser milestone (2026-11-05)

- Camera clearance now applies to scripted views as well as player views. Low
  camera handover no longer multiplies the terrain clearance by eight.
- Adviser SPIRIT_EJECT now reveals and flies in the original actor; SPIRIT_HOME
  flies out. Body hover and sparse speech channels combine. Advisers render in
  an independent depth buffer, preserving their self-occlusion while avoiding
  clipping by terrain. A real original movement-instruction voice was decoded
  and observed playing with the correct mouth-animation selection.
- The citadel skin is A4R4G4B4 with cutout alpha, rather than RGB565. Its wood
  construction frame and stone texture have been visually inspected.
- Double-clicking the original entrance after the guide invitation opens the
  original main room, floor and water meshes, with all 150 recorded entry-camera
  frames. Escape returns to the island. Other temple rooms and their gameplay
  are not implemented. Large rooms are split across ArrayMeshes to retain all
  surfaces beyond Godot's 256-surface limit.
- The recorded givewood demonstration includes its original pickup/drop timing
  and a visual carried-wood prop. Resource quantity/economy remains approximate.

Checks currently cover original story100, island53, port199, skeleton52,
crowd/dance14, camera-input16, advisers12 and temple-entry7 assertions. The
ordinary-speed runtime run reached the temple guide at approximately 8m40s with
full original voice and video timing; it exposed the inside-temple binding now
implemented. The latest full runtime rehearsal uses the scene tree, physics and
input handlers but skips media and accelerates time, explicitly as a test fixture.
It must not be presented as a recorded, ordinary-speed ten-minute playthrough.

To observe a new ordinary-speed run with original media:

```powershell
godot --path game --script res://tests/verify_opening_runtime.gd -- '--bw=C:/Games/Black and White Complete Collection' --story-preview --runtime-seconds=660 --runtime-input-only
```

The `--runtime-input-only` option drives mouse handlers in the test. Normal
`--story-preview` launch never enables an automatic player or skips media.

The preview isolates unimplemented later quests at their exact native call and
retains their stack and waiting parents. It never reports those quests complete.
The opening/camera/temple-guide scripts still use strict failure reporting. In
current rehearsals ThrowingStones and TheLostFlock remain suspended; their
remaining gameplay is not implemented. Five VM regressions verify suspension,
independent-script progress, parent waiting, real resumption, and strict intro
errors. This preview policy is opt-in; isolated VM tests keep strict defaults.

`build/story-preview/Launch-Village-Test.cmd` runs the local Godot project with
the test driver. It advances the original opening and input handlers, skips
introductory media, then disables automation and restores ordinary speed when
the original script creates the village temple. It is a review convenience, not
a saved game or a claim that the introductory scenes were manually completed.

Final rehearsal: `scratch/opening-acceptance.log` completed 660 seconds of
game time with PASS. It completed TeachRotate, TeachPitch, TeachZoom and
GiveFood, entered and exited the actual temple room, and retained a minimum
outside-camera clearance of 2.999986 units. Media was skipped only by the test
fixture. This validates progression and camera safety, not full visual or
ordinary-speed playthrough equivalence. The quick village-review handoff also
reported VILLAGE_TEST_READY.

## Restoration corrections: preview 6 (2026-11-05)

The first temple now uses the original neutral B_TEMPLE02 geometry, not the
unmorphed spiked first-temple mesh. Planned citadel angles are radians times
1000: Land1's 36000 means +36 radians after the coordinate reflection. Static
abodes and animated landmarks use that same positive rotation convention.
Finished abodes render state 0 without the state-1 scaffolding; graveyard
components retain their separate states. Both CREATE_TOWN_CENTRE objects load.

The temple door uses the installed Entrance collision triangles. Cinematic
look-at targets retain their authored height, including the below-ground
look-through target in CitadelGuideCinema. The eye remains above terrain.
Player control resumes from the rendered camera, retaining its framing and
elevated pivot. Tutorial hints show the original HelpProfile progress and
confirmed completion, without changing objective state.

Advisers now use the original YXZ animation matrices, additive speech and
pointing controls, noncyclic pointing introductions, and the ClingD edge pose.
Head controls face the actual camera, including the demon's original Head_Turn
clips. Speaking changes the mouth from decoded PCM amplitude and never resets
the body's animation clock. Good defaults to the right and evil to the left;
original script anchors still take precedence.

Music starts each new story cue at zero. Original story and alignment tracks
use -10 dB, while added countryside sounds use -26 dB with gaps and pause
during cinematics and adviser speech. Original RUN_TEXT queue/single-line
semantics prevent queued narration from replacing an ongoing recording.

BUILD_BUILDING now sets forced desire instead of instantly completing a
temple. A bounded construction controller uses actual adult villagers, the
original storage-pit inventory, visible carried wood, and completed original
work animations. It reads the first temple's 6500-wood cost and villager
carry/cycle settings from info.dat. The original 90% tutorial cap remains.
General town desire arbitration and the complete original building path and
clearance solver are still not implemented.

GiveFood is an original recorded givewood demonstration, rather than a new
mandatory player objective. HND action 3/4 means button press/release. The first
release retains the wood; the next press delivers it to the actual site.
Collection uses the installed HAND_WOOD settings and a 100 ms game turn.
The recording transfers 860 wood with exact inventory conservation in focused
tests. Village 0 already has 30000 wood in the original Land1 storage pit.

New checks cover source temple shape/door19, completed mesh states28,
adviser poses27, resource construction and main demo integration29,
HND events19, wood collection17 and camera handover/ambience6. Updated audio
checks66, island54, story100, port199, adviser runtime12 and temple interior7
also pass. Runtime logs distinguish accelerated media-skipping rehearsal from
ordinary-speed input-driven playback. No complete campaign or manual
ten-minute playthrough is claimed.

Preview 6 acceptance: `scratch/opening-full6.log` and the rendered
`scratch/opening-render-final6.log` report PASS for 800 seconds of game time.
Both completed the three camera lessons, delivered the recorded wood, finished
the temple with 4063 additional wood consumed after its scripted 37.5% starting
state, waited 30 seconds at the door without camera movement, and entered and
exited the actual main room. These two runs use the accelerated media-skipping
test fixture. The release executable also passed its independent startup check.
`scratch/opening-voiced6.log` separately reports PASS for 800 seconds with
ordinary-speed original voice/video playback and test-driven mouse input.
It also completed the lessons, conserved the recorded wood delivery, entered
and exited the main room, and retained a stable camera during the 30-second
door wait. The two still-suspended quests remain incomplete in every run.

## Restoration continuation: preview 7 (2026-11-05)

Original script highlights now read all four installed info.dat records and use
their real DYK, silver and gold meshes, active states, source height offsets,
rotation and depth scaling. A mouse click selects the actual scroll without
placing it in the Hand. The gold scroll starts the original ChooseYourCreature
keeper introduction, with its real 22-bone trainer, separate sable.l3d close-up,
source animations, voice and complete CreatureGuide music (cue 67, 154.958 s).
Camera focus-follow tracks the actor's centre independently of eye movement.
Low cinematics retain valid authored heights; a 0.5-unit floor prevents a buried
eye. Free-player camera clearance remains three units. The three-unit cinematic
floor previously placed the keeper below the image.

The counted original SNAPSHOT operation records the keeper event and captures a
rendered frame. The story-book UI and UPDATE_SNAPSHOT remain unimplemented.
The source one-metre CALL tolerance, original rock/pillar lookup and reveal
command allow ThrowingStones to prepare its actual scene and await its scroll.
Its complete challenge and TheLostFlock still remain unfinished. Gate-key
protection can suspend on native 53; collecting all three keys, opening the
gate and original creature selection are not playable yet. No completed quest
flags are fabricated to bypass these gaps.

Preview 7 checks: story100, island54, port199, audio68, camera37, camera-handover7,
and rendered scroll/keeper16 pass. The rendered full-scene input-driven rehearsal
in scratch/opening-render7-fast.log completes the three camera lessons, recorded
wood delivery, resource-backed construction, a stable 30-second door wait,
temple visit and keeper introduction. This is an accelerated media-skipping
fixture, not an ordinary-speed playthrough. Its minimum cinematic clearance is
0.5 units and player clearance 6.9029. The exported executable separately loads
the original island, story and soundtrack with exit code zero.

## Key delivery continuation: preview 8 (2026-11-06)

The first tiger key can now be picked up, carried and applied to the actual gate
plinth through mouse input. Category 49 is an interactive key, while the blank
quarry stone remains distinct. The plinth uses the installed key meshes, three
source slots, original height stacking and source mesh identity values (ape 1,
tiger 2, cow 4). OBJECT_INFO_BITS reads the physical slots; no campaign flags
are set by the hand or plinth. The original ChooseYourCreature reacts to the
first delivery, sets only its own tiger-key flag, brings back the keeper and
starts LostBrother. Other keys and the original creature choice remain pending.

The source counted UPDATE_SNAPSHOT updates progress and text without replacing
the captured camera/image. The existing SNAPSHOT record now stores HelpText and
ScriptName with their correct source meanings. The keeper reward uses sound
174 from the installed InGame bank, independently of ScriptSfx sound IDs.
Key protection can respawn real mobile objects with the requested transform,
create its indefinite attached highlight and remove its actual influence node.
The object highlight currently uses a provisional outline; its original particle
presentation is not yet reproduced. Key flight parameters remain approximate.

Closed-gate and plinth triangles now stop swept flying items and report real
contact to CLEAR_HIT_OBJECT/GAME_THING_HIT. An impact never inserts a key.
Animated collision poses and general original object physics remain unfinished.

Checks: gate/key lifecycle, invalid deliveries, physical contacts and counted
snapshot updates24, rendered keeper/key sequence28, port199, island54,
story100 and audio68 pass. scratch/opening-key8.log reports PASS for the rendered
input-driven opening, temple visit, stable door wait and first key delivery with
the keeper's reaction. The test accelerates time and skips media. It is not an
ordinary-speed or manual full playthrough.

Launch-Key-Test.cmd drives the actual opening to the keeper and then disables
automation, restores ordinary speed and leaves the key for manual pickup. It
uses local Godot and sources, without creating a fabricated campaign save.

## Hand, plinth and construction fixes: preview 9 (2026-11-06)

The ordinary Hand now decodes the player's original hh.HBN and hndspec5.txt:
25 clips in 69 source slots, with idle/motion sliders, pointing, pickup, holding
and camera gestures on the original 22-bone rig. The original default negative-X
reflection restores the right hand. Mesh-derived fingertip/grip anchors remain
aligned with the selected screen point while terrain/object clearance moves the
hand toward the camera. Cursor size stays stable with camera distance. Visible
static meshes, including houses, trees, rocks and animated landmarks, use shared
native triangle BVHs. Held objects are excluded from their own cursor surface.
Scroll selection includes the projected scroll and a padded area, respects world
occlusion and shows a hover overlay without prematurely setting source ACTIVE.
The prototype ground torus and village light pillar are absent in story mode.

The plinth's first installed stone uses the plinth height minus the source 0.2
overlap; subsequent stones add their actual mesh height. Previously the first
stone was placed mostly inside the pedestal. Flying-item support now uses the
original solid collision hull: plinth 336/337/338 and gate 219/220 according to
the persistent original slot/open state. Swept footprint contacts prevent fast
stones from passing through the platform. An impact still does not install a
key or complete its quest. Cursor landmarks use their current animated pose.
General original physics, GJK and the complete Hand controller remain unfinished.

Construction keeps its actual workers/resources at the scripted 90% cap rather
than sending everyone home and back. Reservations avoid unnecessary supply
trips, source ADD_RESOURCE deliveries wake waiting carriers, and float rounding
cannot reserve an extra whole wood unit. Water-blocked supply routes use bounded
land A* and normal walking; unreachable reservations are released. This is a
limited land route solver, not the original full footpath/Hug/economy system.

Checks: hand pose30, rendered hand/world18, construction38, village workflow10
and source-tutorial workflow11 across the recorded seeds, gate/key24, mouse
scroll/keeper/key27, port199, story100 and island54 pass. The final rendered
input-driven rehearsal in scratch/opening-key9-final.log reaches completed
construction, a stable thirty-second temple-door wait, the temple interior,
keeper and first key reward without engine/script errors. It accelerates time
and skips media; it is not an ordinary-speed manual playthrough. The exported
Preview9 separately passes headless and rendered startup checks. The launcher
and local shortcut select this executable. Full campaign and remaining quests
are still pending.

## Collision maintenance checkpoint: preview 9.1 (2026-11-07)

An audit found no new remote code after the Claude handoff at7c7358f.
The contact probe was extended to inspect flight frames and final roll,
use an actual larger rotated rock, detect self-sweep, and drop onto a real
nearby boulder. Against the original checkpoint it reports7PASS/5FAIL:
the resting rock penetrates LND by0.1555m, another trajectory has three
penetrating frames, self-sweep hits, and a drop passes through the boulder.

Physics now recalculates support after rotation and landing actions, includes
actual mesh vertices in terrain support, and resolves terrain after an object
contact. Movable rocks/keys/food/toys participate in object contacts, with the
swept body excluded from its own query. Headless and rendered contact checks
now report12PASS; viewed captures show final ground support and the first
actual boulder contact. These are legacy geometry repairs, not independent
clean-room modules or a complete original/GJK/dynamic-pair solver.

Checks repeated for this checkpoint: hand/world18, gate/key24, keeper/key27,
port199, rendered opening through first key, exported headless/rendered
startup and a fresh Git-source build. The original user-specific case still
needs confirmation. Storage, resource transfer and gesture throwing remain
open; this is not the complete Preview10 delivery. See its verification JSON.

## Optional standalone packaging

The user now accepts requiring original files in the finished remake. A one-time
import into the port's data directory is optional future packaging work. Replacing
engine code does not replace the terrain, models, music, voices, videos and
campaign data which still define the original game. Current previews read those
resources directly from the original folder. An importer, versioned resource
manifest and clean launch test with that folder unavailable would be required
before claiming that dependency was removed. Keep the original installation for
the current preview; importer work does not block the next gameplay milestone.
