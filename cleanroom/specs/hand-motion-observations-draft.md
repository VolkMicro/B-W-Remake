# Normal hand motion — bounded static observations 0.2

**DRAFT. Research input, not an approved implementation packet.**

Research/review role: `/root/hand_packet_review`, 11 November2026. The role has
legacy/coordinator access and writes no product implementation in this step.
Original executable/input loop was not run. These are byte observations,
manually derived scalar properties and explicitly bounded inferences, not
captured original gameplay or a complete hand/camera solver.

## Inputs and evidence

Installed executable SHA256:
`525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054`.
Private project: Research/HandMotionCoordinator, Ghidra12.1.4/JDK21.0.12.1+1.
It is separate from the older storage project. Original files and all addressed
disassembly/decompiler output stay outside Git. Public evidence IDs:

- `HM-ABI-20261111-A`: caller instruction trace proves nine stack arguments
  and caller cleanup for the required-position helper. The normal-state method
  itself uses a `this` register and one elapsed-time argument.
- `HM-DEPTH-20261111-A`: typed position helper, terrain-depth sampler,
  instruction trace and scalar values; bounded ordinary terrain path only.
- `HM-SCALE-20261111-A`: scale-setting instructions plus independently read,
  hash-guarded executable float/double constants.
- `HM-RESPONSE-20261111-A`: scalar target/update instructions, local endpoint
  matrix construction, continuous state fields and independent arithmetic.
- `HM-FACING-20261111-A`: independent facing components and final normalization;
  terrain-normal path and separate object/interfacing branches.
- `HM-ANCHOR-20261111-A`: normal caller, required helper and orientation matrix
  builder; root placement relative to later skeletal animation.
- `HM-FIXTURES-20261111-A`: independent scalar calculations, not execution of
  original machine functions and not a frame comparison.
- `HM-MODEL-NORMALIZATION-20261111-A`: model-load, bind transform return and
  matrix-scale instructions, plus independent bone-table calculation and a
  Godot data-reader probe against the installed hand model.

The first inspection script did not compile (`Memory.getFloat` is unavailable
in this Ghidra API), although headless process exit was0. It produced no usable
analysis. Corrected inspection then exported10 bounded instruction bodies and
scalars successfully. A subsequent bounded pass assigned explicit prototypes
and produced7 corrected decompiles, with project save success. Additional
bounded instruction exports checked constructor/size/matrix/model-loading
links. No whole-program
autoanalysis was requested. Exit status alone did not establish script success.

The old one-argument helper decompile has uninitialized-stack artifacts and must
not be used as the behavioral law. Explicit stack/register storage and helper
cleanup sizes were checked before using the corrected representation. Some
untyped subordinate geometry calls remain; their inferred C local variables
are not independent evidence of geometry semantics.

## Ordinary terrain depth and scale

For a valid ordinary terrain sample, the initial distance query has this
functional effect:

`L = clamp(camera_to_sample_distance - 3.2 * previous_scale * base_scale,
           2, maximum_hand_distance)`.

Here camera distance is Euclidean/radial, not merely camera-space forward Z.
The nominal size/radius query constant is approximately3.2. `previous_scale` is the hand scale
already present when this initial query starts; it is not a new self-consistent
solution using the final scale. `base_scale` and maximum distance are separate
hand instance fields. A subsequent constructor/MorphInit instruction pass
confirms default maximum distance1800, initial depth scale1 and initial
base/user size1; LoadBinary also requests SetSize(1) after loading/selecting.
These are defaults of the checked path, not a promise that all later states
leave those values unchanged.
The ordinary normal-state caller enables this radius offset. Missed terrain,
special state and exceptional interface paths have additional handling.

The required-position helper initially evaluates scale at L and places a
candidate on the current screen ray. With no selected object or special
interface distance, its normal depth target is L. It then advances a persistent
scalar following response toward that target. The rendered depth is capped by
the current unfiltered L before being passed through the scale setter's
minimum/maximum clamp. Consequently a newly nearer surface can immediately
limit the visible root even while the internal response retains its previous
position/velocity. Do not replace internal state with that visible cap.

The final scale is evaluated at the final rendered/clamped radial distance d:

- For2<=d<10, scale is `(d/10)^0.8`.
- For10<=d<=150, scale is1.
- Ford>150, multiply the base scale above by
  `(1 - 0.3*(d-150)/(1800-150)) * (d/150)`.

Stored constants are float32 approximations; exponent is stored as a double
approximately0.8000000119.1800 is a scale-law breakpoint; a separate constructor
write independently confirms the default instance maximum1800. The scale setter clamps to minimum2
and its instance maximum first. This bounded law differs from forcing the hand
to a fixed pixel width at every camera distance.

Independent decimal arithmetic fixtures, assuming the supplied instance maximum
does not clamp the stated input:

| d | scale |
| ---: | ---: |
| 2 | 0.2759459323 |
| 5 | 0.5743491775 |
| 10 | 1 |
| 100 | 1 |
| 150 | 1 |
| 300 | 1.9454545455 |
| 1000 | 5.6363636364 |
| 1800 | 8.4 |

These expected numerical values permit ordinary source float/x87 rounding.

### Converting raw hand-model units

The depth scale above is **not** the direct scale factor for raw L3D vertices.
The hand matrix initializer computes a uniform factor

`model_factor = 3.2 / normalization_span * depth_scale * user_size`,

then applies its separate left/right reflection. The same factor is stored as
the drawable hand size. This is verified in actual matrix-setting instructions;
using depth_scale directly would make the roughly639-unit raw model enormous.

The normalization field is populated during base loading from the return of
the bind-transform routine. That routine does **not** return the mesh AABB
half-diagonal: it composes bone bind matrices, compares their world Y
translations with min/max initially both0, and returns maxY-minY. Thus0 must
be included even if every bone lies below it. The independent mesh bounding-box
routine does calculate a half-diagonal, but that is a different quantity and
must not be substituted merely because a field was provisionally called radius.

For the installed Hand_Boned_Base2 model (one submesh,22bones), independent
raw-bone affine composition and the Godot rest-reader probe agree:
minY=-555.294372558594, maxY=0 including the zero seed,
normalization_span=555.294372558594. At depth_scale1,user_size1,
model_factor≈0.005762709218996. The mesh AABB height≈638.969604492188 and
half-diagonal≈390.380279541016 are **not** this normalization span.
The model's serialized bounding-box fields are zero; do not read that empty
header as a valid denominator. This is a data-reader/static-law check, not
execution of the original renderer. Asset SHA256:
`cb0be5f1959aa4e23767f49308cf42958db65c777567d08a03f40a495d044b06`.

## Following response

The scalar target setter preserves current scalar position and velocity and
constructs a finite-duration polynomial with target position, target velocity0
and terminal acceleration0. It is called again on each normal update even when
the desired scalar target did not change; it is not a one-shot animation
started only on target change. A separate time advance evaluates that new
trajectory. This distinction affects the feel of continuous cursor following.

For normalized time t in[0,1], its endpoint-system/evaluation yields the derived
zero-end-velocity functional family:

`F(t)=6*t^2-8*t^3+3*t^4`, `G(t)=t*(1-t)^3`;

`position(t)=p0 + (target-p0)*F(t) + v0*T*G(t)`.

The velocity is its time derivative. At or beyond T it settles to target with
velocity0. Duration below approximately0.001s takes the immediate-setting branch.
The source's repeated target-setting retains current velocity but does not
promise continuous acceleration across retargets. This derived arithmetic is
not a claim that an entire original render sequence has been measured.

The ordinary depth response chooses duration approximately0.28s while target
is at least the current internal distance, and0.1s when target is nearer.
A separate conditional outward branch uses2.0s. Its predicates involve
interface/camera state and current velocity; their complete user-facing meaning
has not been established here. A future limited API can accept that branch as
an explicit caller choice; it must not claim to have restored all predicates.
The internal depth is separately constrained to at least1; scale/output then
applies its own minimum2 and instance maximum.

The normal caller passes elapsed seconds to the depth response. Facing scalar
updates use the stored frame-millisecond counter multiplied by0.001. Exact
update scheduling and pause/camera takeover behavior still need integration
tests; do not invent a universal render-FPS invariance claim for repeated
retargeting.

Single transition from rest expected fractions:
F(0.25)=0.26171875, F(0.5)=0.6875, F(0.75)=0.94921875.
For an isolated target20→100, initial velocity0,T0.28 and step1/60s, derived
internal position21.56871847 and velocity180.50927854. Repeating the target
setter at each1/60s, with the ordinary nearer/farther duration switch, gives
internal position51.30883736 after6frames and82.86689845 after12frames.
These are fixtures of the stated static arithmetic convention, not original
runtime samples; visible output remains subject to L and instance clamps.

## Facing, root and authored animation

Facing X/Y/Z are separate persistent scalar responses. When the source path
retargets them, duration is **0.4s** (the instruction immediate decodes to
approximately0.400000006), with target velocity0, followed by component time
updates and final vector normalization. It is not an exponential0.13s filter.
Not every path retargets facing: a source instance condition or a nonzero
additional orientation argument gates that operation. Initial component state
is up `(0,1,0)`.

The ordinary terrain branch obtains terrain-normal information through a
separate geometry helper; object collision normals, selected/held-object
clearances and icon/camera branches can produce other facing targets. Do not
apply an invented universal blend of ground normal, view ray and up and call
it the exact source rule. A limited response component should take a supplied
facing target; the adapter must identify the appropriate branch separately.

For the bounded normal path, the final root point is placed along the current
screen ray at its final radial distance. The normal caller passes this position
directly to the hand orientation-matrix builder. That matrix's translation is
the supplied root point; skeletal animation is sampled/applied afterward.
There is no query of the animated fingertip/pinch-bone or subtraction of its
position in this required-position/matrix path. Therefore the current port's
per-frame animated-fingertip subtraction can cancel authored root/body motion
and is not established as original behavior by these observations.

The separate `0.5 * 3.2 * scale` expression is used in an orientation/contact
decision. It must not replace the full radius offset in the initial depth
sampler. Mesh collision and held-object radius branches are broader than this
ordinary terrain result and remain separate work.

## Unknowns and implementation boundary

- Later modifications to default maximum distance/user size in special states.
- Full multi-skeleton/multi-submesh normalization outside the single-submesh
  checked hand asset; do not silently reuse a visible-vertex AABB as fallback.
- Exact complete selected/held-object, special interface and camera predicates.
- Cursor lag coordinates driving authored LR/FB animation sliders: existing
  per-event relative motion is not proved equivalent by this analysis.
- HND recorded hand-point producer identity; do not declare it fingertip/root
  merely because a visual fit seems good.
- Actual binary camera horizontal/vertical FOV default and resize convention.
  A separate legacy-source hint suggests horizontal70deg, but that is not
  approved by this motion pass alone.
- Original runtime comparison at normal speed and exact x87 edge behavior.
- Cancellation/reset, nonfinite input, huge delta and ownership transitions for
  a new Godot component are explicit remake robustness policy, not source facts.

A future packet should contain only reviewed functional inputs/outputs and
synthetic fixtures. Raw addressed files, corrected decompilation, this full
checkout and its conversation are not inputs for the clean implementation
worker. This draft does not close the user's hand-motion report on its own.
