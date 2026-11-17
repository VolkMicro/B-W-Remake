# SPEC-ORBIT-ACTORS-001 v3

Review candidate. New Godot4.7.2 Node3D visual orbit controller. Every movement
rule below is new presentation policy, not original animal AI. No assets/files,
animation decoding, audio, input, quests, economics, physics or network.

Host supplies1..64 plain Node3D containers (`get_class()=="Node3D"`), direct
children of this controller. Actors and ALL descendants must have
`get_script()==null`. Parsed mesh/skeleton descendants are supported; reactive
actor scripts/transform-notification callbacks are not. Host must not modify,
free or reparent supplied subtrees during a call, must use the main SceneTree
thread and must not make nested calls. Concurrent/reentrant host mutation is
outside this API; do not attempt rollback of arbitrary host code. Actor/subtree
script presence is validated before every mutation. No reentrancy fixture or
reactive scripts are required for conforming actors.

Host owns creation, parenting, animation and deletion. Module never creates,
reparents or frees actors, installs signals/callbacks, or processes automatically.
Define no _process/_physics_process/_input/_notification work. Coordinates are
local, so normal Godot parent transforms compose. Deliver `orbit_actors.gd`
(extends Node3D, no class_name), standalone synthetic SceneTree tests and notes.

## API

```
configure(actors:Array, radius:float, height:float, angular_speed:float)->bool
advance(delta:float)->bool
snapshot()->Dictionary
```

configure succeeds once, while this controller is inside the SceneTree. Actors
must be distinct, valid, in-tree direct children of self, with top_level=false,
rotation_order=EULER_ORDER_YXZ and rotation_edit_mode=ROTATION_EDIT_MODE_EULER.
Rotation components must be finite; scale components finite and strictly
positive. Validate is_instance_valid BEFORE type checks/access, including freed
references in configure. Descendants may be any standard Node types but must
have no scripts. Queued-for-deletion actors are valid until actually freed.
Changed parent/tree/mode/order/scale/script conditions reject in advance too.

Radius finite(0,1000], height finite[0,1000], angular_speed finite[-5,5]. Typed
scalar parameters accept floats or coercible ints; strings/objects as scalars
are outside this typed API and need not return false. Accepted float inputs,
including signed zero, are stored without clamping or quantization. Copy Array
membership. Actor index i is its configure-time Array index, independent of
child order and later remove/reparent/restore operations.

Invalid calls/repeated configure return false with no stored-state, hierarchy
or transform mutation. Validate the entire request, all actors and subtree
script restrictions BEFORE changing anything. A bad later actor must not move
earlier actors. Successful configure stores inputs, sets float64 age0 and
immediately applies every actor's initial placement using the formula below.

advance requires the configured in-tree controller and all retained actors
still satisfying the domain above. Accept finite delta[0,36000] with
next_age<=1e9. Age is the float64 running sum of accepted deltas in their order.
Failed calls preserve age. delta0 is valid and reapplies placement. Restoring
valid parenting/tree/mode conditions permits advancement without resetting age.
A freed retained actor cannot be restored: subsequent advances fail permanently,
while snapshot remains available.

## Placement (normative float64 evaluation order)

For actor i among configured count N:

```
phase_i = (float(i) * TAU) / float(N)
angle = fposmod(next_age * angular_speed + phase_i, TAU)
position = Vector3(radius*cos(angle), height, radius*sin(angle))
s = sign(angular_speed)
yaw = 0.0 if angular_speed == 0.0 else atan2(-s*sin(angle), s*cos(angle))
```

Configure uses next_age=0.0. Zero includes negative zero. Sign rather than speed
magnitude avoids subnormal-product underflow in heading. Write ONLY position
and rotation. Immediately before each rotation write read current_x/current_z
and use `actor.rotation=Vector3(current_x,yaw,current_z)`. Never write basis,
transform, scale or descendant state. X/Z tilt and scale are preserved with
is_equal_approx against their values immediately before each placement, not
configure values. For zero tilt +Z intentionally aligns with the tangent;
Godot's usual -Z forward convention does not change this rule. With tilt only
yaw is normative, not a horizontal world-forward claim.

snapshot returns{} before configure. Afterwards return a fresh Dictionary with
exactly String keys `age`, `radius`, `height`, `angular_speed`, `count`.
First four values are float, count is int and retains the original membership
size. No actor references, input Array or mutable internal state are returned.
Mutating the snapshot has no effect. Snapshot is readable out of tree/after
actor removal, reflects committed successful calls and is not an API for
interleaving into a mutation call.

## Synthetic verification

Standard Godot4.7.2 single-precision Vector3 build. Plain Node3D containers and
built-in descendants, no external data. Defer tests until tree entry. Load the
module relative to the test script directory, no class_name. Run
`godot --headless --script <absolute-test.gd>`. Exit quit(0)/quit(1), with a
deadline-based failure guard so an accidental wait cannot hang indefinitely.

Position tolerance1e-5+1e-6*max(1,radius,height). Heading tolerance1e-5 moduloTAU.
Preserved tilt/scale use is_equal_approx. Snapshot age equals the float64 sum
in the same order exactly; partitioned positions compare within tolerance.
For age>=1e6 reference angles use the exact evaluation order above. Under
parent scale, compare global_position to controller.global_transform*local_point
with tolerance multiplied by max(1,max absolute parent scale component).
Do not assert global rotation under nonuniform parent scale/shear.

Cover1/3/20 actor phases, positive/negative/zero/tiny speed, quarter-turns,
delta0, partitioning,36000 delta, radius1000, tilt/scale preservation including
host edits between advances. Invalid radius/height/speed/delta/nonfinite
values, count0/65, duplicates/wrong-parent/freed/non-Node actors, top_level,
mode/order/scale domain, attached actor or descendant scripts must reject
atomically. Test before configure, repeated configure, out-of-tree/re-entry,
remove/reparent/restore, freed actor permanence, input Array/snapshot mutation,
a bad later actor, and no process-driven movement from waiting frames.
A runtime-created local GDScript may be used to test rejection of script
attachment; it is never a conforming actor and needs no reactive hook.
