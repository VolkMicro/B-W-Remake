# Cursor lag, LR/FB controls and state blend — observations0.1

**Research draft, not a product implementation or approved API packet.**

Research/review role `/root/hand_packet_review`, 11November2026. The role has
coordinator/legacy context. Actual input executable SHA256:
`525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054`.
Original code was not executed; no original-frame or mouse recording was made.

Ghidra12.1.4/JDK21, existing HandMotionCoordinator project, process/noanalysis.
Three bounded instruction exports succeeded and the project was saved. The
normal-state instruction trace was reused from the previous corrected-ABI
investigation. Claude's read-only followup was treated as a set of hypotheses;
its earlier raw decompile has missing parameters and is not an exact API.

Private evidence remains under Research/HandMotionCoordinator, outside Git:

- `HP-LAG-20261111-A`: per-frame hand-controller instructions and lag state.
- `HP-POWER-20261111-A`: x87 power-call arguments and adapter body.
- `HP-CONSTANTS-20261111-A`: hash-guarded original float/double reads.
- `HP-SLIDERS-20261111-A`: normal-state LR/FB difference, clamp and clip phase.
- `HP-BLEND-20261111-A`: transition buffer exchange, timer and raw matrix blend.
- `HP-FIXTURES-20261111-A`: independent arithmetic, not original execution.

## Absolute cursor response

The source updates once per accepted hand frame from absolute screen pixel
coordinates. It does not feed individual mouse-event deltas directly to the
authored pose controls. A special path can reuse a cached cursor position;
the complete camera/input ownership predicates are outside this result.

On first initialization, lag position equals current cursor position and both
velocity components are zero. For each axis of a subsequent accepted frame,
the externally relevant recurrence in seconds is:

1. Advance lag position by its previous velocity times dt.
2. Limit that advanced position to within80pixels on either side of the current
   cursor coordinate.
3. Add `(cursor - limited_lag) * 20 * dt` to velocity.
4. Multiply the resulting velocity by `pow(0.03, dt)`.

This order is observable: the positional limit applies before the spring-force
term, and there is no separate velocity cap in this bounded path. The two axes
have independent state and identical numerical constants. Lag can overshoot
the cursor and then oscillate; replacing this with an exponential interpolation
of per-event relative motion changes the response.

The stored time conversion is approximately0.001 times integer frame ticks.
The actual caller routes the same converted frame time into the active hand
state update. The update is gated by visibility/state, interface and an active
object condition. When this branch is skipped, the bounded source path does
not reset the lag state. A complete port ownership/cancellation policy still
needs its own explicit contract.

The damping base is approximately0.02999999933, not the nearby0.7 constant.
The caller places that base and dt on the x87 stack; the actual power adapter
exchanges them and writes a conventional double base/exponent pair before its
shared power implementation. No division by0.03 or nominal frame interval is
present at these call sites. Thus0.03 is the per-second velocity multiplier
when all other terms are held aside; it is not a duration.

Original constants checked directly with correct widths:

| Meaning | Stored value |
| --- | ---: |
| X/Y lag positional limit | float32 80 / 80 |
| Spring gain | float32 20 |
| Velocity damping base | float32 ≈0.03 |
| Frame tick conversion | float32 ≈0.001 |
| LR/FB clip difference limit | float32 80 / 80 |
| Small comparison threshold | float64 ≈0.00009999999747 |
| State transition duration | float32 ≈0.1299999952s |

The threshold is stored as a **double**. Interpreting only its first four bytes
as a float yields an unrelated large negative number and invalid conclusions.

## Authored LR/FB slider phases

The normal state requests the authored main clip and its following two control
entries: main+1 for LR, main+2 for FB. The old decompiler's uninitialized clip
indices were ABI artifacts; the machine instruction trace has a coherent
main-clip value returned by the required-position path.

- LR displacement is `lagX - cursorX`, limited to[-80,80].
- FB displacement is `cursorY - lagY`, also limited to[-80,80]. The signs differ.
- Each limited displacement maps to normalized phase `(displacement+80)/160`.
  The source multiplies this phase by the clip duration and converts to integer
  animation time before applying the corresponding difference.

The bounded LR branch applies only above the small absolute-displacement
threshold. The FB branch actually tests the absolute lagged Y coordinate
against the threshold. That asymmetry is present in the instruction trace,
not evidence that FB lacks the80pixel clamp. A pure dynamics API can expose
phases; it should not silently claim to reproduce every native clip-application
predicate unless those predicates are part of its contract.

The difference reference is selected by the authored middle-key index
`floor((key_count-1)/2)`. It is not automatically proof that a normalized-time
sample at0.5 is the same reference for every clip. Asset key spacing and the
existing reader must be checked before substituting one definition for another.

The hand's movement flag controlling another facing path compares previous
and current X only in this source block; a Y-only change does not set that
flag. This is separate from updating both lag axes.

## State transitions

On transition initialization, the source exchanges current/previous pose
buffers, resets the transition timer to zero, and retains the previous position
triple. Each ordinary active state still produces its new authored pose.

While accumulated transition time is strictly below the stored approximately
0.13s duration, the blend factor is the plain ratio elapsed/duration. It is
**linear**, without smoothstep or another easing function. Each of the twelve
floats of every pose matrix is blended independently, as is the position
triple. Quaternion interpolation or orthonormalizing the interpolated basis
is not the same operation: an intermediate basis can have determinant below1.

The temporal wrapper has distinct branches when a frame crosses the duration:
the current authored pose is then left unblended; the stored position triple
write follows its own source branch. A pure matrix-blend function accepting
explicit progress can reproduce the in-range interpolation, but does not by
itself certify that every original buffer-write/ownership timing is restored.

This approximately0.13s state blend is separate from the0.4s facing-component
response and the near/far depth response described in
hand-motion-observations-draft.md.

## Independent numerical fixtures

The following use decimal constants and float64 arithmetic for clarity; allow
ordinary float32/source rounding. They are not captured original frames.

Initialize lag=(400,300), velocity=(0,0). Set cursor=(500,340), dt0.02:

| Frame | Lag | Velocity | LR/FB phases |
| --- | --- | --- | --- |
| 1 | (420,300) | (29.83268919,14.91634459) | (0,0.75) |
| 2, same cursor | (420.59665378,300.29832689) | (57.42235885,28.71117943) | (0.00372908615,0.74813545693) |

The damping multiplier at dt0.02 is approximately0.9322715371. At initialization
with a stationary cursor the phases are(0.5,0.5). Input event count between
frames must not create extra accepted frame updates.

For a pose scalar0→10 at progress0.25, the source component blend gives2.5;
smoothstep would give1.5625. For a transform from identity to a90degree Y
rotation with origin(4,8,12), quarter progress gives basis columns
(0.75,0,-0.25),(0,1,0),(0.25,0,0.75), origin(1,2,3), determinant0.625.
These distinguish component interpolation from quaternion interpolation.

## Bounds and unknowns

- No original game execution, pixel comparison or measured cursor trace.
- Exact original behavior under a huge/negative/nonfinite delta is not given
  by these regular-frame observations. A new API must label defensive input
  limits, maximum step size and reset/cancel policies as remake choices.
- Different accepted timestep subdivisions need not yield identical results;
  this is a discrete per-frame recurrence, not an analytic frame-rate invariant.
- Full state/interface gating, cached cursor ownership and source tick scheduling
  across menus/cutscenes are not reconstructed in full.
- Detailed blend-clip keyframe reference and engine skeleton application remain
  integration checks. Matching matrix interpolation alone does not certify
  every original skeletal rendering detail.

Use a separately reviewed functional packet for an isolated implementer. This
draft, raw addressed output and the legacy checkout are not its implementation
inputs. No product code was changed during this research.
