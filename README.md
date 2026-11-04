# Black & White: Godot Island

**Мы восстанавливаем Black & White на Godot, чтобы в неё можно было играть на современных компьютерах и вновь пережить знакомую историю.** Первая цель — полностью работающий первый остров: сюжет, добрый и злой советники, существо и его воспитание, жители, чудеса и привычные взаимодействия рукой. В дальнейшем цель — остальные острова оригинальной игры.

Проект находится в разработке. Есть ранний прототип острова и часть его систем, но оригинальный сюжет, полноценное поведение существ и точная физика ещё не готовы. Текущая сборка не проверена полноценным прохождением и не готова к публикации как ремастер. Подробности и ближайшие задачи — в [описании проекта](PROJECT_RU.md).

Игра рассчитана на одного игрока и требует собственную установленную копию Black & White: модели, остров, звук и другие материалы читаются из неё во время работы. Исходные файлы самой игры в этот проект не включены. Это неофициальный проект сохранения игры.

---

An unfinished preservation port of Black & White's first island in Godot. Single player. Requires the player's own installed Black & White (tested data source: Complete Collection). Melty supplies its folder at launch. No original game assets are distributed.

## Direction
The creator wants a full preservation remaster: the feeling and gameplay of the original childhood game, rather than a new sandbox with its appearance. The first island is the first milestone, with original story and quests, both conscience advisers, Ape/Cow/Tiger creature choice, creature teaching, physical interaction with the Hand, and the original island. Later islands are part of the overall remaster direction. These are the project goal, not a claim that the entire campaign already works. Do not publish a reduced sandbox as the requested remaster.

## Existing prototype
Runtime terrain/material loading, original villages and static models, wandering villagers, gift/preacher/scare belief rules, alignment sky, and SAD ambience. The development build resolves the original island's 16 mobile-object types, model IDs, positions, rotations and scales from each player's own 1.2-compatible object information table. It also creates the four previously missing cave and gate landmarks using their original model records and placement, and preserves original building and landscape-feature sizes and angles. Their original animation clips can be played by a controller, but the story events that trigger them are not wired yet. Other table versions are rejected until verified. Gameplay and physics rules are reconstructions and have not been matched to the original engine.

The original wildlife registry is now readable from the player's installation, including model IDs, default animations, age scales and flying altitude data. Wildlife does not yet appear in the world: its behaviour and age-based scaling still need to be restored.

## Preservation work
The local 0.2.0 development build adds three original skinned creature models, their CBN animations, Good/Evil appearance variants, both original skinned/animated conscience advisers, the original Hand model, basic action-specific teaching, grain feeding, creature state saves, and fixed-step swept throwing/collision physics. All assets are read in memory from the required host folder. The learning and physics rules are reconstructions, not yet verified equivalents of Lionhead's implementation.

Original story scripts are compiled LHVM bytecode. An experimental compatibility engine now executes original instructions in isolation, with twelve world operations and helpers, some narrowly scoped. In a focused test of the real first-island setup, after a test-only bypass of the missing virtual-influence operation, it finds the original cave and house, creates position markers, then stops at another missing influence operation. The engine is not enabled in the game: story quests, cinematics, original creature AI, economy, miracles and physical fidelity remain unfinished.

## Local story and audio work

Selected original adviser lines, captions and speech animations play at creature choice. Neutral, good and evil music is decoded from the player's original music banks using a supplied helper. Original game audio remains in the player's own installation and is decoded in memory. Dialogue timing and alignment-based music selection are provisional: these do not constitute the original campaign or music director.

Automated checks cover all 31 instruction types in isolation, twelve script helpers with explicit limits, original creature-choice voices, all three complete original alignment soundtracks, and asynchronous playback. A real adviser line's decoded samples matched an independent decoder. A separate non-running scene check constructs the original houses, features, gates and caves at their original positions, plays their original animations by request, and connects the story test to the actual landmark instances. These checks do not replace a playthrough. The current build has not been visually or audibly verified in a game window and has not been tested through Melty. Prior 0.1.0 tests do not cover it.

The executable `bw_audio_decode.exe` must remain beside `GodotIsland.exe`. It is included in the package; no additional audio software is required. Do not publish this development build as a completed remaster.

Earlier 0.2.0 automated tests checked model/animation data, feedback, saving and physics without a game window. They do not prove campaign playability.

Controls: choose Ape/Cow/Tiger with 1/2/3 or buttons; C toggles following; R praises the last act; F punishes it. Deliver original grain from storage pits to feed the creature. F5/F9 save/load creature upbringing and village beliefs in the port's own profile. H toggles adviser visibility. Existing mouse camera and Hand controls remain available.

## Local 0.2.1 animation fix
Villagers now instantiate their original 22-bone skeletons and play the original ANM idle, male/female walk, panic, held, thrown and dead clips instead of moving a frozen mesh. Animations blend across state changes and share meshes/materials. Signed scales are preserved during matrix interpolation: the original uses reflected bone frames; discarding the reflection in quaternion interpolation inverts limbs. All eight villager types pass regression checks for original poses, moving gait joints, and hands below shoulder height when idle.

156 automated checks passed at that stage. After the creator renewed permission, a 0.3.4 showcase process was started on 2026-11-04, but computer-use access to its window was not approved. The process is no longer running, no showcase images were produced, and its visual result is unknown. No new Melty release test has occurred. The Windows package remains a local development build.

## 0.3.5 skeleton correction

The previous rig applied an inverse rest transform as if Godot 4 bone poses were rest-relative. Godot 4 expects the parent-local pose including rest, so this distorted villagers, creatures, advisers and animated landmarks. The rig now initializes the skeleton from the original rest pose and applies the decoded parent-local poses directly, retaining signed scale. New automated checks compare the actual Godot bone poses and hierarchy against the original data for all eight villager types, three creatures and both advisers. The source matrices include small amounts of shear in some rest poses, which Godot's rotation-and-scale pose representation approximates. This fixes a confirmed transform error, but its appearance and any remaining T-pose problems still require a real visual check.

## 0.3.6 original scripted influence research

The original 1.2 influence settings are now read directly from the player's `info.dat`. A separate function reproduces the specific distance falloff used by script-created influence objects; 39 points were compared against the original installed executable in an isolated x86 emulator. It preserves the original curve, including its abrupt changes at boundaries. This is only one calculation: influence sources are not yet connected to the world, player interactions or the campaign, and the first-island story remains disabled. The research emulator is a development dependency and is not included in the release.

## Credits and permissions
Original game: Lionhead Studios, published by Electronic Arts. Original content stays in each player's own game installation. Godot Engine: MIT, https://godotengine.org/license/. Audio decoder: minimp3 by lieff and contributors, CC0-1.0, https://github.com/lieff/minimp3; its source and license are included. Original file format research: openblack contributors' public documentation and format definitions. No openblack implementation is bundled. This port's original code: all rights reserved; creator permits Melty remixes. Third party components keep their own licenses. Created with AI assistance.
