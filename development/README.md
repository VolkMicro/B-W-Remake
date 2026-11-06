# Development snapshots

The current source handoff is Preview 9; see `HANDOFF_RU.md`, `BUGS_RU.md` and
`preview9-verification.json`. Build it with `tools/build_preview.ps1`. The
archives below are historical 0.x snapshots and are not the current preview.

`GodotIsland-0.3.6-development.zip` is the latest unfinished Windows development snapshot, preserved here with the source. It includes the 0.3.5 Godot 4 skeleton-pose fix and an isolated original influence falloff calculation, with automated checks. Its appearance has not been visually verified; the calculation is not connected to gameplay. It is not a playable first-island campaign and has not passed a fresh Melty installation test. Versions 0.3.4 and 0.3.5 are retained as earlier snapshots. The documentation inside each archive reflects the moment it was created; the project-level README and PROJECT_RU.md have the current status.

The archive requires a player's own installed Black & White. Melty's draft recipe provides its location at launch. The archive contains the Godot runtime, the project's own files and the credited minimp3 decoder; it does not contain original Black & White game assets. It is not a Melty publication or an approved release.

The `package-*.json` files record package contents and checksums. The `recipe-*-draft.json` files record draft setups that passed static checks; they have not been tested as installations. These recipes are kept here as development documentation and are not active release configurations.
