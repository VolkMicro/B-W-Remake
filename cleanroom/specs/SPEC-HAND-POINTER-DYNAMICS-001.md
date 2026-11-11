# SPEC-HAND-POINTER-DYNAMICS-001 v1

Review candidate. Pure Godot4.7 RefCounted `hand_pointer_dynamics.gd`.
No files, input events, geometry, clock, animation loading or scene access.
Bounded static observations HP-LAG/BLEND-20261111-A; original runtime was not run.

API:
```
reset(cursor:Vector2)->bool
step(dt_seconds:float,cursor:Vector2)->Dictionary
state()->Dictionary
static blend_pose(previous:Array[Transform3D],current:Array[Transform3D],progress:float)->Array[Transform3D]
```

reset records lag=cursor, velocity=ZERO, sliders=Vector2(.5,.5).
New defensive API policy: cursor finite and each abs component<=1000000.
Invalid reset preserves prior state. Repeated valid reset replaces it.
Before reset, state/step return{}. step requires finite0<=dt_seconds<=.25
and valid cursor. Larger steps are rejected atomically as an explicit remake
pause/stall policy; caller must resume/reset rather than advance a long stall.
All returns are detached snapshots with lag,velocity,sliders (Vector2).

Each valid frame, both axes independently in this order:
lag += dt_seconds*velocity;
lag = clamp(lag,cursor-80,cursor+80);
velocity = (velocity+(cursor-lag)*20*dt_seconds)*pow(.03,dt_seconds).
LR slider=(clamp(lag.x-cursor.x,-80,80)+80)/160.
FB slider=(clamp(cursor.y-lag.y,-80,80)+80)/160.
Sliders are phases[0,1], not raw deltas; signs intentionally differ.
The clamp also runs at dt0. Do not normalize, smoothstep or substep this law.
Per-event relative movement and frame event count do not enter this API.
Source state gating is caller scope: frozen periods need not reset the filter.

blend_pose is independent of the state/filter. With equal-length finite input
arrays and finite progress[0,1], linearly interpolate each of the 12 scalar
components (basis columns and origin) independently. Do not quaternion slerp,
orthonormalize or remove scale/shear/reflection. Return a fresh array, never
modify inputs. Empty equal arrays are valid, return[]. Mismatched arrays,
nonfinite input transforms or invalid progress return[] atomically.
The caller uses progress=elapsed/.13, clamped[0,1]; .13 seconds is the checked
source transition interval, elapsed clock/state switching are outside this API.

Synthetic fixtures; Vector2 float32 comparison tolerance1e-4:
- Reset(400,300), step(.02,(500,340)): lag(420,300),
  velocity(29.83268919,14.91634459), sliders(0,.75).
- Second identical step: lag(420.59665378,300.29832689),
  velocity(57.42235885,28.71117943), sliders(.00372908615,.74813545693).
- reset(0,0), step(0,(1000,-1000)): lag(920,-920), velocityZERO,
  sliders(0,0). No dt acceleration, but position clamped.
- Static cursor converges back toward slidercentre; both motion signs, reversal,
  reset replacement, invalid atomic state and detached snapshots.
- Blend identity to +90degree Y rotation at progress.25 gives columns
  (.75,0,-.25),(0,1,0),(.25,0,.75), determinant.625. OriginZERO to(4,8,12)
  gives(1,2,3). At.25 the result differs from smoothstep or quaternion slerp.
  Test endpoints and mirrored/scaled bases without normalization.

Return only a JSON object whose keys hand_pointer_dynamics.gd and
verify_hand_pointer_dynamics.gd contain the full file texts. Test extends
SceneTree, preload res://hand_pointer_dynamics.gd, nonzero exit on failure.
Use explicit GDScript types. No tools or execution claims.
