# Black & White: instructions for Claude

Default role in this checkout: **coordinator/integrator**. It contains legacy
reverse-engineering notes. It is not an isolated implementation room.

Read in order: `CLEAN_ROOM_RU.md`, `TASK_CLAUDE_RU.md`, `PROJECT_RU.md`,
`AGENTS.md`, `HANDOFF_RU.md`, `BUGS_RU.md`. An isolated implementer must instead
receive only the approved packet and separate instructions defined in the
clean-room protocol; do not give it this checkout or conversation history.

## Product target

- Noncommercial fan remake on native Godot. Requiring the player's original
  Black & White files is acceptable in the finished game.
- First preserve a recognizable, complete campaign and its atmosphere, music,
  advisers, Hand, creature and freedom. Then develop the 2026 remake: modern
  presentation, reliable interaction, meaningful learning and a reactive world.
- Prioritize observable gameplay and a working game. Bit-exact replication of
  every internal algorithm is not a product acceptance criterion.
- Do not substitute a generic sandbox, an AI chat, or a launcher for the old exe.

## Immediate assignment

Deliver **Preview 10 fixing BW-001 through BW-004**, then continue the first
island according to `TASK_CLAUDE_RU.md`. BW-001/002/004 remain open. Preview9.1
fixes five reproduced contact regressions; the user's exact case still needs
verification. See current `BUGS_RU.md` and `cleanroom/STATUS.md`.

Use Ghidra for the requested binary research, with its headless mode when a GUI
is unavailable. Keep research, specification review and independent new
implementation separated as described in `CLEAN_ROOM_RU.md`. Do not certify
legacy code retrospectively or confuse a subagent with an OS access boundary.

## Execution

1. Inspect actual code and reproduce relevant behavior. Start implementation
   work; a plan, research report or installation guide alone is not delivery.
2. Keep a short active plan in `cleanroom/STATUS.md`: completed work, evidence,
   next concrete step and any actual blocker. Preserve progress across restarts.
3. Research only what resolves the current uncertainty. Produce a reviewed
   behavioral packet, independent new modules, integration and tests. Do not
   decompile the entire game before attempting a local bug fix.
4. Preserve user changes and the latest passing preview. Use small reviewable
   changes. Avoid unrelated rewrites or silently changing the assignment.
5. Ordinary installation, read-only research, local builds and reversible fixes
   are part of the task. Ask only for genuinely missing access/files, a material
   design choice or permissions required by the actual execution environment.
6. Treat new messages as steering unless the user explicitly replaces the task.
   After compaction, re-read the active status and continue instead of restarting.

## Evidence required before completion

- A process running, a green counter, decompiler output, synthetic clicks or an
  increasing resource number do not establish the requested gameplay behavior.
- Never fabricate quest flags, stock, tests, screenshots, isolation or Ghidra
  runs. Do not weaken checks or hide an unresolved report to obtain PASS.
- Exercise real input and rendered scenes. Inspect engine/script logs as well
  as exit codes. Unit checks supplement visual gameplay verification.
- Build a new executable and check that exact file. Update the normal launcher
  only after relevant checks pass. Record source revision, executable hash,
  commands, results, visual evidence and remaining approximations.
- Update `BUGS_RU.md`, `HANDOFF_RU.md`, `cleanroom/STATUS.md`, commit and push.
  An unfinished item stays open with a concrete next step.
- If credentials, tools or usage limits truly prevent progress, preserve the
  work and identify the exact limitation. Do not report the task as complete.

These instructions guide work; they do not override tool permissions or enforce
filesystem isolation. The acceptance matrix is in `TASK_CLAUDE_RU.md`.
