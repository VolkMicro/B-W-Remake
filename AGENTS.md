# Continuing the restoration

Read `HANDOFF_RU.md`, then `BUGS_RU.md`, before editing. `REMASTER.md` records
verified milestones. The older 0.x descriptions in README/development archives
are historical; they are not the current campaign status.

The goal is the original Black & White campaign on native Godot, preserving its
story, atmosphere, controls and content. Do not substitute a sandbox or mark
quests complete to bypass an unimplemented native. Keep pending source bytecode
and report the actual unsupported operation.

Use the player's installed files in memory; never add original game archives,
extracted assets, credentials, local research checkouts, caches or recordings to
Git. The current preview still needs that installation. Standalone import is
planned, not implemented. Generated Godot builds belong in ignored `build/`.

Use the current checkout. Keep changes scoped and preserve unrelated work.
On Windows use PowerShell without its interactive profile for tool commands.
Use `godot_console.exe` for synchronous checks. Run checks appropriate to the
change, inspect engine/script errors as well as exit status, and retain honest
limits on what they establish. A passing unit test is not a manual playthrough.

Do not update the normal launcher or verification report until an exported
executable passes startup checks and relevant scene tests. Record bug status and
reproduction details in `BUGS_RU.md`; update the handoff when the state changes.
