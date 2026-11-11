# SPEC-HAND-MOMENTUM-001 v1

DRAFT pending hash review. New remake policy for estimating release velocity
from caller-supplied world positions and game-time seconds. This is not a claim
of original smoothing constants or aftertouch, and contains no original code.
No input/physics/parser/filesystem/network access. Pure GDScript RefCounted.

`hand_momentum.gd` methods:
configure(max_speed:float=180.0, window:float=0.12, stale:float=0.1, minimum:float=2.0)->bool
begin(point:Vector3, time:float)->bool
sample(point:Vector3, time:float)->void
finish(time:float)->Vector3
cancel()->void

Configure once, all finite: max_speed>0,0<window<=1,0<=stale<=1,
0<=minimum<=max_speed. Invalid/repeated configure leaves existing state.
The positive max_speed must also remain finite and nonzero when represented
as a Vector3 component; otherwise reject configuration without mutation.
begin valid only configured, finite point/time>=0. A valid begin replaces any
old gesture with this single sample; invalid begin leaves old state unchanged.
sample only while active; finite point/time>=0, time>=last timestamp. Older/
invalid samples ignored. Same timestamp replaces last position. Keep at most64
newest samples, removing oldest first. Discard timestamps strictly less than
newest-window (the exact boundary stays), retaining at least newest.
No auto-clock or scene access. Caller cancels on camera gestures/scene handoff.

finish always consumes gesture, including invalid finish time. Return zero if
inactive, fewer than2samples, invalid/time<last, last sample older than stale,
or last-first time<=1e-6. Finish uses its time only for validity/staleness: it
does not append a still sample or re-window the retained samples. Equality at
the stale limit is valid. Otherwise velocity=(last point-first point)/(time span).
If derived displacement or velocity becomes nonfinite return zero. Cap vector
magnitude to max_speed, and zero if resulting magnitude<minimum. Use finite
stable magnitude arithmetic for large finite float32 vectors. No destination
or auto-aim, no gravity, no deferred launch or hidden timer.
Zero outcomes are exactly Vector3.ZERO. Nonzero vector/cap comparisons permit
normal float32 rounding (relative1e-5 or absolute1e-5).

Tests synthetic positions only: linear10units/s at30/60fps same; diagonal
direction; verticalup/down; fastclamped180; slow1unit/s zero; window removes
old movement after still samples; stale release; duplicate/out-of-order/time0;
invalid point/NaN/Inf/time/cfg; finish consumed and cancel; bounded64samples.
Tests meaningful observable outcomes without accessing private implementation.
For stable-norm coverage use window1, points ZERO at0 and(1e30,1e30,0) at1,
finish1: nonzero vector with components approximately(127.27922,127.27922,0)
under max_speed180. A naive float32 length/dot overflow must not turn this
finite raw velocity into zero or a nonfinite result.

Return only JSON files hand_momentum.gd and verify_hand_momentum.gd. Test is
SceneTree preload res://hand_momentum.gd, reports checks and exit nonzero onfail.
Godot4.7; explicit types. No tools: never claim execution.
