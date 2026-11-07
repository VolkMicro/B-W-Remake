# SPEC-STOCK-PILES-VIEW-001 v1 — quantity-driven pile presentation

Status: DRAFT until separately reviewed by SHA256. This is a new presentation
API implementing a bounded static behavior model. It is not original source
code, a game parser or a claim of a measured original playthrough.

## Inputs and boundary

Implement `stock_piles_view.gd`, `class_name StockPilesView`, `extends Node3D`.
It displays caller-supplied Mesh resources at caller-supplied anchors. It never
loads assets, reads a repository, modifies stock, handles input or moves items.
Only a read-only Callable supplies a Vector2i snapshot of two resource totals.
Coordinate/terrain/version conversion belongs to the external adapter.

```gdscript
func configure(read_stock: Callable, definitions: Array[Dictionary], transition_seconds: float = 1.0) -> bool
func sync(immediate: bool = false) -> void
func advance(delta: float) -> void
func pile(index: int) -> MeshInstance3D
func state(index: int) -> Dictionary
```

No automatic process callback: the caller advances it once per game frame.
Allow configure once; on invalid input or repeated configure return false and
leave any previous configuration/children unchanged. Validate before creating
children. Do not overwrite Node/Object built-in methods or properties.

Definitions are ordered: exactly one resource0 first, then one or more resource1
entries. Each has `resource` int, `mesh` valid Mesh with positive finite AABB
height, `nominal` positive int, `anchor` finite Vector3 in view-local space,
`heading` finite radians and `scale` positive finite scalar. All fields are
required. The mesh AABB position and size must be finite. Effective height H,
the uniform scale Vector3 and full/empty root positions must remain finite in
Godot's transform representation; otherwise fail configuration. Materials on
the supplied mesh surfaces can be StandardMaterial3D or null. Other material classes
are outside this packet and should fail configuration before creating children.
The Callable must be valid and initially return a nonnegative Vector2i. Duration
must be finite and positive, and each H/duration must be finite so the reported
vertical speed is representable. Copy definition values so caller Dictionary/Array
mutations cannot change configured bindings. Mesh resources may remain shared.

Read and validate the initial Callable result once during configure; use that
same snapshot to initialize all piles immediately. Do not call it again between
validation and initialization. The caller must not mutate shared Mesh/material
resources after configure; such external resource changes are outside this API.
The caller owns this Node's lifetime. If the Callable later becomes invalid or
returns invalid data, treat the snapshot as zero for presentation only; never
write to it, fabricate resources or repeatedly log engine errors.

## Allocation for this aggregate view

Resource0 uses its single entry and can exceed its visual nominal. Resource1
fills entries in order: every entry except the last receives up to its nominal;
the last receives all remaining quantity, even above its nominal. Empty entries
receive zero. This is a canonical aggregate presentation, not persistent
per-pile accounting or a definition of selecting a particular pile with a Hand.
Totals are preserved in state outputs, including overflow. With one wood entry,
it receives the whole resource1 quantity. Do not sum quantities in narrow ints.

## Stable presentation

For amount q=0, target proportion p=0. For positive q define
r=min(1,q/nominal), using a floating-point ratio, a=.05+.95*r. Resource1 has p=a; resource0 has
p=1-(1-a)^2. Source observation IDs BW001-STATIC-20261107-A/B/C and
BW001-DATA-20261107-B motivate these numerical fixtures; actual originals and
their implementation are not part of this packet.

H = supplied mesh AABB height * supplied scale. A pile's root position is
anchor + Vector3.UP * ((p-1)*H), rotation.y=heading and uniform scale=scale.
Quantity never changes mesh size. Anchors and heading do not animate.

The food pile gets additional UV V offset .25*(1-clamp(p,0,1)); U is unchanged.
Duplicate its StandardMaterial3D surfaces for that instance and apply the offset
relative to their original uv1_offset. Do not modify shared Mesh/materials or
other instances. Null surfaces require no fabricated material. Wood material
UVs stay unchanged. All piles use the original supplied meshes, not proxies.

At settled zero the pile is invisible. While moving toward zero it remains
visible until the transition finishes. A positive stock must be visible,
including when it is rising from a previously invisible zero.

## One-second transitions

sync reads the current snapshot and updates targets. A changed quantity with the
same target proportion must update its amount but must not restart an existing
transition. sync(true) snaps to the stable target and clears velocity.

advance(delta) first syncs, then advances in seconds. Zero delta may sync but
does not move. Negative/nonfinite delta does nothing. A large finite step ends
at the target without iteration loops. Target changes preserve current position
and velocity; the new target is reached after transition_seconds, with zero end
velocity and acceleration. Never teleport to an old start/target on retarget.

An independently derived interpolation can use these functional constraints:
over normalized time t in[0,1], the displacement from rest covers
F(t)=6t^2-8t^3+3t^4 of the distance. Initial velocity v contributes
v*duration*t*(1-t)^3. This defines observable results, not implementation layout.
These interpolation equations may use proportion as their displacement unit;
then v is in proportion/second. Convert that derivative by H for the vertical
velocity exposed by state. Use the current animated proportion, not the final
target, for position and UV.
Clamp the displayed proportion to[0,1] if a retarget mathematically overshoots;
preserve internal continuity. This clamp is a remake presentation policy.

## Inspection API and metadata

pile returns the corresponding MeshInstance3D or null for an invalid index.
Each pile has metadata `resource_index` (0/1) and `pile_slot` (its overall
definition index). The adapter will use these to associate future cursor hits.

state returns a fresh Dictionary (empty for invalid index) containing at least
`resource`, `amount`, `nominal`, `proportion` (displayed), `target`,
`y_offset`, `velocity`, `visible` and `uv_v`. The offset uses displayed/clamped
proportion. Velocity is the unclamped animation's vertical derivative in
units/second, including while the displayed position is clamped. `uv_v` is the
additional food V shift, not a surface's final UV offset; for wood it is zero.
Reading/mutating that Dictionary must not change live animation or stock.

## Acceptance examples

Use synthetic BoxMesh/ArrayMesh fixtures and a local snapshot Callable only.

- Zero snapshot: all invisible, no stock mutation.
- Food nominal100 and wood nominals10,10,10; totals(150,45): amounts
  [150,10,10,25], all full, no truncation.
- Reduce resource1 to15: amounts[10,5,0], food150 unchanged.
- Resource1 half-full has p=.525. Resource0 half-full has p=.774375,
  UV V=.05640625. Quarter-full values: wood .2875, food .49234375.
- H=4 full→zero from rest: after0.5s Y offset=-2.75; after1s=-4,
  invisible and velocity0. An unchanged snapshot across advances does not reset.
- Retarget in flight: state position and velocity are unchanged at sync time,
  new endpoint reached after one duration. A single step2s settles exactly.
- Mesh transforms retain supplied scale/heading, including scale2. Two views
  sharing food mesh/material can have different food fill/UV without modifying
  each other or the caller's original material.
- Different time-step subdivisions produce the same settled state. Negative,
  zero and nonfinite dt behave as specified. Inspection calls cannot debit stock.
- Invalid definitions or repeated configure do not leak/create partial children.
- Use metadata/pile output and a fresh state Dictionary as specified.

## Delivery

Return only JSON `files` entries {path,content}, allowed paths
`stock_piles_view.gd` and `verify_stock_piles_view.gd`. Tests are a SceneTree
using preload("res://stock_piles_view.gd"). They print results and exit nonzero
on failure. You have no execution tools: do not claim to have run them.
Use explicit types wherever Godot Variant expressions prevent safe inference.
No filesystem/network/shell access or original assets belong in the module.
