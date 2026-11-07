# SPEC-RESOURCE-STORE-001 v1 — two-resource store

Status: DRAFT until a separate review approves this exact file SHA256.
Origin: new remake requirements, not a transcription of a legacy algorithm.
This packet contains no original binary, source, asset or implementation.

## Purpose

Implement an independently written Godot 4 GDScript resource store. It is a
small reusable accounting component. A caller supplies the owner, metadata key
names, initial values and optional limits. No game-file parsing, rendering,
input handling, threading, filesystem/network access or timers belong here.

The owner's metadata is authoritative. Do not keep a second copy of stock.
Existing code can update that metadata; subsequent reads must reflect it.
The component must not keep the owner alive after it is freed.

## Public contract

File `resource_store.gd`, `class_name ResourceStore`, `extends RefCounted`.

```gdscript
signal changed(resource: int, before: int, after: int)
func bind(owner: Node, keys: PackedStringArray, initial: Vector2i, limits: Vector2i = Vector2i(-1, -1)) -> bool
func stock(resource: int) -> int
func take(resource: int, requested: int) -> int
func add(resource: int, offered: int) -> int
func snapshot() -> Vector2i
```

Resources are indexed 0 and 1. Metadata values, initial values and finite limits
are integers in [0, 2147483647]. Limit -1 means unbounded within that range.
Requests/offers are GDScript int values; negative and zero amounts are no-ops.
Invalid indices are no-ops/read as zero. There is no implicit conversion of
strings, floats, booleans or missing values into an existing stock value.

## Binding

- Owner must be a valid Node. Exactly two nonempty, distinct keys are required;
  each must pass Godot String.is_valid_identifier() before any metadata access.
  Initial values must be nonnegative. Limits must be -1 or nonnegative.
- For each existing metadata key, preserve its current integer value. Do not
  reset it to the caller's initial value. Existing values outside the valid
  integer range make binding fail.
- Missing keys are initialized from the corresponding supplied initial value.
  Initial/existing stock above a configured limit is allowed and preserved.
  Limits constrain future additions, not already-owned resources.
- Validate everything before writing either key or replacing a prior binding.
  Failed bind returns false and leaves the owner and previous binding untouched.
- Successful bind returns true and does not emit changed. Rebinding to the same
  owner/keys must not reset stock; successful binding to another owner is allowed.
- Keep an immutable copy of the key names: later mutation of the caller's array
  must not redirect the store. Hold the owner weakly.

## Reading and mutation

- stock reads the metadata at call time. If unbound, owner freed, index invalid,
  or current metadata missing/invalid, return 0 without mutating anything.
- take returns min(requested, current stock) for a valid positive request and
  valid binding/current metadata. Subtract exactly that returned amount.
- add accepts up to the available limit and the integer ceiling. If current
  stock is already at/above a finite limit, accept 0. Never clamp away existing
  over-limit stock. Avoid overflow even if offered is the largest positive int.
- Missing/invalid current metadata makes take/add fail safely: return 0 and
  leave it untouched; do not manufacture a valid empty store in its place.
- Mutating one resource must not change the other. Read/write happen in a
  single-threaded caller context; locks and cross-store transactions are out
  of scope.
- For an actual positive change, write metadata first, then emit exactly one
  changed event containing resource/before/after. A no-op emits no event.
  Observers must see the committed value when the signal fires. Reentrant
  observers may perform additional valid operations; do not overwrite their
  result after emitting the original event.
- snapshot returns the two current stock readings, with the same safe-read
  behavior. No internal timer or polling is required.

## Acceptance cases

Use synthetic Node fixtures with keys unrelated to any existing game code.

| ID | Setup/action | Required result |
| --- | --- | --- |
| A1 | Bind fresh owner, initial(37,91), no limits | Metadata and snapshot equal(37,91); no event |
| A2 | Take12 of resource0, then request100 | Return12 then25; stock0=0, stock1=91; two events |
| A3 | Add9 of resource0, then add0/negative or invalid index | Return9 then0; only one event |
| A4 | Initial(37,91), limits(20,40) | Preserve both counts; additions accept0; withdrawals still work |
| A5 | Stock14, limit20, offer100 | Return6; final20, exactly one event |
| A6 | One key exists with11, other missing; initial(37,91) | Preserve11; create other91 |
| A7 | Bind with an invalid existing value or duplicate keys | No partial metadata writes and no loss of previous valid binding |
| A8 | Mutate caller's keys array after bind | Store still targets the original two keys |
| A9 | External valid metadata write | stock/snapshot reflect the new value immediately |
| A10 | External invalid metadata write | Safe reads0; mutations return0; invalid value unchanged |
| A11 | Free owner while store still exists | Safe reads0 and mutations0, no engine errors |
| A12 | Add to2147483646 with offer9223372036854775807 | Accept1; final2147483647 without overflow |
| A13 | Signal observer reads stock and performs another take | Observer sees committed state; original mutation does not overwrite nested result |
| A14 | Bind with 'bad key', '1stock', punctuation or empty key | Return false without engine error, partial writes or loss of previous binding |

Also run deterministic sequences of additions and withdrawals and assert
the conservation equation: final = initial + accepted additions - actual takes.
No originals or repository files are needed for these checks.

## Delivery

Return JSON with a `files` array containing `path` and `content`. Allowed paths:
`resource_store.gd` and `verify_resource_store.gd`. The test is an independent
SceneTree script using preload("res://resource_store.gd"), prints a result and
exits nonzero on failure. Tests run later by the coordinator in a minimal Godot
project. Do not claim you ran them when no execution tool is supplied.

Use explicit types where Godot cannot infer values returned from metadata,
weak references or Dictionary access. Provide source code only in the JSON,
without Markdown fences or instructions to run arbitrary external commands.
