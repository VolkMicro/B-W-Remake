# SPEC-HAND-SURFACE-MOTION-001 v1

DRAFT pending independent exact-hash review. Pure Godot4.7 RefCounted component
`hand_surface_motion.gd`, no geometry/parser/input/animation/filesystem/network.
Implements a bounded ordinary-terrain following law from reviewed observations
HM-DEPTH/SCALE/RESPONSE/FACING-20261111-A. Actual original runtime was not run.
Special object/camera predicates and raw mesh unit conversion are caller scope.

```
configure(maximum_distance:float, base_scale:float=1.0)->bool
reset(depth:float, normal:Vector3=Vector3.UP)->bool
step(delta:float, facing_delta:float, surface_distance:float, target_normal:Vector3, slow_outward:bool=false)->Dictionary
state()->Dictionary
```

New defensive API policy: configure once; finite2<=maximum_distance<=1800,
finite0<base_scale<=10. The1800 API bound is a supported input range, NOT proof
of original default max distance. Parameters are supplied by caller, not loaded.
Invalid/repeated configure preserves state. reset only configured, finite depth,
finite nonzero normal; clamps depth to[2,max], normalizes initialnormal, zeroes
all velocities and records scale using the function below. Repeated valid reset
replaces state; invalid reset leaves it unchanged.

step requires configured+reset, finite delta/facing_delta>=0, finite positive
surface_distance, finite nonzero target_normal. Invalid input returns{} without
mutation. New policy: positive finite steps at or beyond a duration settle its
controller exactly, without loops. Caller is responsible for camera resets.
Normalize target_normal before feeding its three scalar components.
Normals are supplied directions, not points. Normalize finite nonzero inputs
without overflowing their length calculation for large finite components.
surface_distance is Euclidean/radial camera-to-surface distance, not forward Z.

Every valid step first computes
L=clamp(surface_distance - 3.2*previous_output_scale*base_scale,2,max).
The scale on the right is cached from the previous valid output/reset, not an
iteratively solved new scale. Rebuild the depth response EVERY step, even for
unchanged L, preserving current internal position and velocity. Duration T=.28
if L>=current internaldepth, else .1; slow_outward selects2 only on the outward
branch. The caller supplies that special condition; this packet does not invent
its original predicates. Retarget each facing component every step at T=.4,
preserving each component's own unnormalized internal position and velocity.

Scalar update from p0,v0 to target with endv/endacceleration0:
t=min(dt/T,1), F=6t²−8t³+3t⁴, G=t(1−t)³,
p=p0+(target−p0)*F+v0*T*G,
v=(target−p0)*12t(1−t)²/T+v0*(1−t)²*(1−4t).
At dt>=T use p=target and v=0 (zero terminal velocity, not initial v0).
At dt0 preserve p/v. Use delta for depth and
facing_delta for facing; these represent separate source scheduling inputs.
Clamp internaldepth to at least1, retaining its velocity (explicit policy for
this low-bound edge; source visible output is still independently bounded).
Rendered depth=clamp(min(internaldepth,L),2,max). A nearer surface therefore
caps visible depth immediately without overwriting the internal response.
Normalize the resulting facing vector for output; if numerically zero useUP,
retaining unnormalized controller components for later steps.

Scale(d): for2<=d<10, (d/10)^0.8; for10<=d<=150,1; above150,
(1−.3*(d−150)/1650)*(d/150). Evaluate at rendered depth and cache that result.
This is dimensionless hand scale; raw original mesh normalization is NOT here.

state returns a fresh dictionary with internal_depth,depth_velocity,
limit,render_depth,scale,normal and normal_velocity(Vector3 of internal scalar
derivatives). Immediately afterreset limit/render_depth=clampedresetdepth.
step returns the same detached inspection fields as state. Reading/mutating
returned Dictionary never changes component state. No Node or scene effects.
Before a successful reset, state returns{}.

Synthetic meaningful fixtures (float rounding tolerance1e-5):
- Scale2≈.2759459323,5≈.5743491775,10/100/150=1,300≈1.9454545455,
  1000≈5.6363636364,1800=8.4 (use reset/state without geometry).
- Configmax1800/base1, reset20; distance103.2 givesL100; dt1/60 gives internal
  depth21.56871847 andv180.50927854. Because scale remains1 below150, repeated
  identical steps give depth51.30883736 at6frames and82.86689845 at12frames.
- Reset100, surface23.2 givesL20. With dt0 visibledepth20 while internal100
  remains; a dt.1 step settles internal20. No teleport of internal state atcap.
- Reset100, distance103.2 with delta0 and facingUP→RIGHT at facing_delta.2:
  raw normal(.6875,.3125,0), normalized foroutput. Repeating same target with
  facing_delta.2 gives raw normal(.99609375,.00390625,0), unlike the exactRIGHT
  endpoint of a one-shot animation clock at.4s.
- Previous scale: reset300 scale≈1.9454545; nextstep distance400 and delta.28
  computes L≈393.7745454545 and output scale≈2.5088094414. The following step
  at distance400 uses that new cached scale, giving L≈391.9718097875.
- slow_outward duration2, inward still.1; different depth/facing deltas; zero,
  negative/nonfinite and huge steps; atomic invalidconfig/reset; freshsnapshots.

Return only a JSON object with keys hand_surface_motion.gd and
verify_hand_surface_motion.gd, each containing that file's complete text.
Test extends SceneTree, preload res://hand_surface_motion.gd, checks outcomes,
nonzero exit onfail. Explicit GDScript types. No tools, no execution claims.
