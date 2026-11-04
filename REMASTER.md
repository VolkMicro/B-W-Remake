# Preservation target

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

The current local development build has the real island, basic interactions, real creature/adviser models and animations, initial reconstructed creature teaching, original animated villager state changes, selected original creature-choice dialogue, and provisional original alignment music. A Godot 4 skeletal-pose error affecting villagers, creatures, advisers and landmarks was corrected and checked against actual bone transforms; rendered appearance remains unverified. The island loads four previously missing cave and gate landmarks and uses original house and feature placement scales. Their original animation clips play by explicit request in off-tree tests; the campaign events that trigger them are not connected. Wildlife models and default animations can be read and validated from the original data, but animals are not spawned yet. The isolated story VM bridge has twelve queries and helpers under test, some narrowly scoped, but it is not driving gameplay. Original campaign execution, complete learning AI, original economy/miracles, complete audio timing and fidelity comparisons remain unfinished. Not ready to publish as a remaster. Existing 0.1.0 Melty test evidence does not cover this work.

The original 1.2 settings and one scripted-object influence falloff calculation are now read and evaluated in isolation, with an independent comparison against the installed original. Influence sources, the Hand's access rules and the campaign still are not connected; this is not a complete influence system.

## Permission state

The creator renewed permission to launch and test the build and use the mouse and keyboard. An isolated 0.3.4 showcase started on 2026-11-04, but computer-use access to its window was not approved. The showcase process is no longer running and did not produce its expected images. No interaction or visual result was verified, and no attempt was made to bypass the restriction. Existing user processes were not closed or restarted. Window/gameplay verification is pending.
