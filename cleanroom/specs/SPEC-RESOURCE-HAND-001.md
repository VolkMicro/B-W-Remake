# SPEC-RESOURCE-HAND-001 v1

DRAFT until exact SHA256 review. New native remake components, independently
implemented from this API. No game parser, original code, input bindings,
filesystem or networking. Two resources: food0/wood1; integer units.
Bounded static observations BW002-DATA/STATIC-20261107-A/B/C/D motivate the
25 initial,8→70 quadratic gather,0.1s turn,6s ramp,20000 capacity examples.
These are static expectations, not measurements of a running original.
New robustness and visual policies below are explicitly remake policies.

## ResourceHand (RefCounted, resource_hand.gd)

Public read-only-by-convention properties `resource:int=-1`, `amount:int=0`,
`collecting:bool=false`. Caller must not write properties.
Signal `moved(direction:String, resource:int, amount:int)` after committed
positive changes, direction `pickup` or `putdown`. Observers see final state.
The signal resource is the transferred0/1, including putdown which emptied the
hand and changed its live resource to-1. No signal for no-op. Cosmetic signals
never own economic quantity.

```
configure(profiles:Array[Dictionary], turn_seconds:float=0.1)->bool
begin(resource:int, take:Callable)->bool
stop()->void
advance(delta:float)->void
give(accept:Callable)->int
snapshot()->Dictionary
```

Configure once. Validate both profiles before committing. Each required field:
`initial`, `rate_start`, `rate_end`, `maximum` positive ints (not bool/float),
initial<=maximum<=20000;1<=start<=end<=20000. `ramp_seconds` is an int or float
(not bool), finite and positive. Exactly two entries; finite
0.001<=turn_seconds<=1.0. These bounds are new API policy. Before converting
the quotient to int, require ramp_seconds/turn_seconds finite and<=1000000;
derived ramp turns=max(1,int(quotient)).
Failure/reconfigure leaves existing state unchanged. Copy profile fields.

begin allowed only configured, empty amount, resource0/1 and valid callback.
Calls take with min(initial,capacity), credits the actual returned int and
starts collection only on positive result with remaining hand capacity. If
begin fills capacity it still returns true, but collecting is immediately false
and its source callback is released. A positive partial initial return does not
prove exhaustion; collection can continue until the next zero return.
Callback contract: synchronous
take(requested:int)->int in[0,requested], already debits its own authoritative
source by actual amount. Invalid return is treated as0; callbacks are trusted
to uphold conservation and never throw. Empty result resets resource=-1 and
returns false. Holding another resource/any amount rejects begin without debit.

During collection each elapsed turn n=1,2,... requests
int(start+(end-start)*clamp(float(n)/float(ramp_turns),0,1)^2), capped by free capacity.
Floating point must not truncate a boundary spuriously below a mathematically
integral fixture value. The actual callback return is credited immediately,
before signal. No extra particle ledger. Empty source, invalid/freed callable,
or capacity stops collection; retained amount remains in hand.
stop discards unprocessed time/backlog, releases source callback and retains
quantity. Further advance cannot debit. One new begin starts elapsed turns0.

advance finite delta>=0 accumulates elapsed seconds. New policy: process at most
256 turns per call, retaining pending time; advance(0) may drain backlog.
Do not convert huge elapsed floats directly to int or loop unboundedly. Saturate
pending time at1000000turns (explicit pause-resume policy). Negative/NaN/Inf does
nothing, including no callback. No overshoot past capacity or source supply.
Accumulate pending time with saturating arithmetic so even a largest finite
delta cannot produce infinity before saturation. At turn boundaries tolerate
only floating accumulation roundoff (<=1e-9 seconds), not a visible extra turn.
Time subdivisions below saturation with the same total yield the same quantity
once backlog drains; deliberate pause-time saturation is excluded from that
equivalence claim.

give stops collection before attempting transfer; invalid callback returns0 and
retains quantity. accept(offered:int)->int synchronously credits its destination
and returns actual accepted in[0,offered]. Remove only that amount; partial
acceptance retains remainder, resource stays selected until empty then becomes-1.
Repeated give on empty does not call receiver. Invalid result treated0.
New policy: recursive mutation calls during callbacks or moved observers are
rejected/no-op to avoid double debit; snapshot always allowed. Snapshot is fresh
dictionary with resource,amount,collecting and cannot mutate live state.

Tests: both resources; supplied source1000 begin25; at1s108/3s413/6s1746/10s4546
with sufficient stock; source7 credits7; full hand stops; release retains and no
later debit; partial/zero/invalid receiver; duplicate give; freed source;
negative/nonfinite/huge delta bounded; timestep subdivisions; signals and
reentrant callback/observer safety; bad configuration atomic; stock conservation.

## ResourceStream (Node3D, resource_stream.gd)

Cosmetic paths over caller-provided original meshes; owns no resource quantity.
Exact original particle trajectories are UNKNOWN. This bounded arc is a new
remake presentation policy; do not describe it as original PSys decoding.

```
burst(mesh:Mesh, origin:Vector3, destination:Callable, scale_factor:float, seconds:float=0.35)->bool
advance(delta:float)->void
active_count()->int
```

No auto process. Coordinates view-local. Caller advances once per frame.
One MeshInstance3D per burst; shares Mesh/material unmodified. All arguments
must be valid/finite, scale_factor>0,seconds>0, mesh with at least one surface
and a finite AABB with positive height and nonzero size. The resulting uniform
Vector3 scale must be finite and positive. Destination initially valid and
returns finite Vector3; sample it once for validation and initialization.
Require finite initial distance, arc and midpoint position (including lift);
otherwise reject before creating a child. Validate before child.
Maximum64 live particles; if full reject burst without mutation. Never fabricate
proxy meshes/materials. Destination sampled at creation and each advance so
pickup follows a moving hand. If invalid later, or its new endpoint would make
the distance/midpoint/path nonfinite, retain the last valid endpoint.

At normalized t position=origin.lerp(current_endpoint,t)+UP*arc*4*t*(1-t),
arc=min(4,max(0.4,initial_endpoint.distance_to(origin)*0.12)); scale constant.
At t=1 free instance immediately; clamp huge finite steps without loops.
Negative/NaN/Inf dt ignored; zero may sample endpoint without moving time.
No mutation of stock or callbacks except the read-only destination.
Deleting this Node deletes all particles. active_count correct immediately
after each call, including off-tree standalone tests (use free or detach safely).

Tests synthetic BoxMesh, actual midpoint/endpoint, moving/invalid endpoint,
independent bursts,64 cap, invalid input atomic, huge/negative dt, shared material
unmodified, no leaked nodes after cleanup. No original assets needed.

## Delivery

Only JSON `files` [{path,content}], paths resource_hand.gd,resource_stream.gd,
verify_resource_hand.gd. Test extends SceneTree; preloads res://resource_hand.gd
and res://resource_stream.gd, meaningful assertions, exits nonzero on failure.
No tools available: do not claim execution. Godot4.7 GDScript explicit types.
