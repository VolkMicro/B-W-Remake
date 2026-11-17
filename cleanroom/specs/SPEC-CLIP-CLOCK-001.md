# SPEC-CLIP-CLOCK-001

Version: 2. Status: draft until exact-hash independent review.
Role: generic presentation scheduler for a Godot host. This is a new port
policy, not a recovered original game algorithm. No game data is supplied.

## Deliverables and boundary

Return JSON with `files`, each containing `path` and `content`, for exactly
`clip_clock.gd`, `test_clip_clock.gd`, and `clip_clock_notes.md`. Do not use
tools or claim to have run the code. Coordinator will run the standalone tests.
Module extends RefCounted, no class_name, filesystem, network, scene, clock,
signals, callbacks, randomness or processing. Caller owns time. No imports.
Tests extend SceneTree, load the sibling module, run after tree entry, print
checks and quit0/1. Include a deadline guard; synthetic data only. Keep tests
focused on boundary/transition behavior rather than a large generated matrix.

## API and domain

- `configure(durations: Dictionary) -> bool`: one successful configuration.
  Accept 1..512 entries. Every key must be String, length1..128, and every value
  int or float (not bool), finite, 0.000001..36000 seconds inclusive. Reject
  empty/invalid map and later configure requests atomically. Copy the input so
  later host dictionary changes cannot change the module's behavior.
- `start(name: String, repeats: int) -> bool`: requires configuration and a
  known name. Repeats is -1 for infinite, or 1..1000000. Reject other requests
  atomically. A success replaces the active request and resets age/position0,
  playing=true and completed=false, including when name/repeats are unchanged.
- `advance(delta: float) -> bool`: requires configuration. Delta must be finite
  and 0..36000 inclusive. Invalid calls preserve all state. When idle or already
  completed, valid calls return true without changing state. Otherwise advance
  by delta. Infinite-request age is cumulative, capped domain1e12 seconds; if
  age+delta would exceed1e12, reject atomically. Finite requests clamp age to
  total duration (duration * repeats, at most3.6e10) and never reject solely
  because the unclamped age+delta exceeds their total.
- `stop() -> bool`: false without configuration. Otherwise return to idle,
  preserving the configured durations. Repeated stop in idle succeeds.
- `snapshot() -> Dictionary`: fresh dictionary containing exactly name:String,
  age:float, position:float, duration:float, repeats:int, playing:bool,
  completed:bool. Modifying the returned dictionary must not mutate the module.
  Do not expose the durations map or any other mutable internal reference.

Unconfigured and idle snapshot:
`{name:"", age:0.0, position:0.0, duration:0.0, repeats:0,
playing:false, completed:false}`.

## Observable scheduling

While active and not completed, position is the nonnegative remainder of age
divided by duration. An exact internal repeat boundary therefore has position0.
Infinite requests remain playing, never completed. For a finite request,
age >= duration*repeats completes it: age becomes exactly that product,
position becomes exactly duration, playing=false, completed=true. The terminal
position remains duration on later valid advances until start or stop.
The host uses position to sample its clip and completed to hold its last frame;
the module never selects animations, poses or movement itself.

Examples, using duration2:

| Request/input | age | position | playing | completed |
| --- | --- | --- | --- | --- |
| start("a",2) | 0 | 0 | true | false |
| advance(2) | 2 | 0 | true | false |
| advance(1) | 3 | 1 | true | false |
| advance(9) | 4 | 2 | false | true |
| advance(0.5) | 4 | 2 | false | true |
| start("a",-1), advance(5) | 5 | 1 | true | false |
| stop() | 0 | 0 | false | false |

All calculations use Godot float (64-bit GDScript float). No epsilon-based
completion: compare the cumulative age with the computed total directly.
Fixtures use exactly representable durations2,0.5 for exact boundaries. For
nonbinary durations compare outputs within 1e-9 absolute or 1e-12 relative,
whichever is larger. Different delta partitions may differ by floating-point
rounding; they must agree within that tolerance away from repeat/end boundaries.
No requirement of partition independence exactly at an inexact rounded boundary.

## Required checks

Exercise failed-then-successful configuration, immutable input/snapshot,
unconfigured operations, duplicate configure, unknown clip, invalid repeats,
NaN/infinity/negative/oversize delta, zero delta, finite one/multiple repeats,
infinite looping, large clamping step, terminal pose retention, restart while
playing/after completion, stop while playing/after completion, nonbinary timing,
and independent instances. Demonstrate an invalid start/advance cannot lose a
running request. Include bounded-duration/count/repeat limits. Age-limit
coverage may use repeated valid advance calls (about28 million would be slow);
do not run millions of calls or modify private state to fabricate acceptance.
Instead explain that bound in notes and cover near boundaries achievable with
a small number of calls. No nondeterministic sleeps in the tests.

## Explicit API/harness clarifications

Target engine: Godot4.7.2, standalone `--headless --script`. Every rejection
returns false and changes no state; every acceptance returns true. Unconfigured
start/advance return false. Invalid deltas are rejected even while idle or
completed. Atomicity includes retaining the entire completed terminal request
on an invalid start/advance, as well as retaining a running request.

During an active or completed request, snapshot name is the exact requested
name, duration is that clip's configured float duration (not the total), and
repeats is the requested integer including -1. Completion retains those three
fields until a successful start or stop.

Keys require TYPE_STRING; StringName is rejected. Length means String.length()
in Unicode code points. start matches exact case-sensitive keys. Numeric map
values are converted to float before the inclusive direct duration bounds are
compared and stored. Wrong argument types to the typed API (such as String for
delta or Node for name) are outside the contract and must not be tested as
false-return cases. An int passed to advance is permitted by normal numeric
conversion to float. Negative zero delta is valid and compares equal to zero;
no negative-zero bit-pattern requirement is imposed on snapshots.

The test SceneTree _initialize defers its run using call_deferred. Locate the
sibling module with get_script().resource_path.get_base_dir().path_join(...).
Install a SceneTreeTimer deadline of20 seconds, ending quit(1) if not finished.
Return one JSON object of the exact shape
`{"files":[{"path":"clip_clock.gd","content":"..."}, ...]}`, all paths bare
filenames from the three-file allowlist, with no prose outside JSON. Notes must
explain age-limit test coverage and the floating-point partition caveat.
