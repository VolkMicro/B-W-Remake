# SPEC-WEATHER-ZONE-001 v3

Review candidate for a new Godot4.7 Node3D `weather_zone.gd`. The caller owns
the node and its clock. No assets, files, input, network, quests or NPC health.
This is a visible remake weather representation, not the original renderer.
The numeric parameter/lifetime observations are bounded static facts WZ-20261111-A.
The boundary is:

| Bounded original observation | New module / presentation policy |
| --- | --- |
| Weather values are temperature/rain/snow/overcast/fall speed; rain/snow/overcast use byte percentages times100 in the checked setter | This API retains unquantized floats exactly; temperature is stored without rounding and has no visual effect |
| Parameter setters preserve the weather age; the checked lifetime shape is a symmetric fade-in/plateau/fade-out | Caller supplies seconds; original frame/update units are not claimed |
| The episode requests120/40, weather15/1/0/1/2, clouds8/.8/130 and radii600/1000 | These are this module's initial values, not claimed original factory defaults |
| The source exposes several different weather/object operations | All API method shapes/order here are new, including set_radii(inner,outer) and set_clouds(count,shade,height); the coordinator owns native conversion |

Mesh layout, precipitation speeds/counts, colors, wind and distance falloff below
are new presentation policies. Do not infer additional original rules.

API (bool methods return false on invalid input, no mutation):
```
configure(center:Vector3)->bool
set_weather(temperature:float,rain:float,snow:float,overcast:float,fall_speed:float)->bool
set_clouds(count:int,shade:float,height:float)->bool
set_lifetime(total:float,fade:float)->bool
set_radii(inner:float,outer:float)->bool
set_wind_affected(enabled:bool)->void
advance(delta:float,viewer:Vector3)->Dictionary
snapshot()->Dictionary
```

Supported placement: the node must be inside the SceneTree for configure and
all mutating methods. Its global basis and every Node3D ancestor global basis
must be identity (component tolerance1e-6); translations are allowed. This is
an explicit supported-domain restriction, not arbitrary transform support.
Outside that domain bool methods fail, advance returns{}, wind setter is a
no-op, and stored state/children remain unchanged. snapshot is read-only and
does not need a tree or transform. Before configure it still returns{}.
Configure once; center is world-space, finite with abs components<=100000.
It sets node.global_position=center,
age0, total120,fade40, inner600,outer1000, weather(15,1,0,1,2),
clouds(count8,shade.8,height130), windfalse. Before configure snapshot/advance
return{} and setters fail/no-op. Repeated configure fails atomically.
No automatic _process: only advance changes age. Node never auto-frees itself.
No external Environment/Light/Camera mutation. All visuals are owned children.
No collisions or shadows from precipitation; no economic/gameplay effects.

New supported input ranges: temperature finite[0,255]; rain/snow/overcast and
shade finite[0,1]; fall_speed finite[0,1000]; clouds0..32; height finite[1,2000];
total finite(0,36000], fade finite[0,total/2]; radii finite0<=inner<=outer<=5000,
outer>0. Delta finite[0,36000], viewer same bounds as center.
Domain endpoints are valid, including delta0/fade==total/2/inner==outer.
Nonfinite vector components invalidate the whole request. set_wind_affected
silently does nothing before configure. Invalid requests preserve all state and children. A setter changes only its
parameters, never age. A successful advance returns the same content as snapshot
after the update. Invalid advance returns{} atomically. Snapshot returns a fresh dictionary including all scalar
parameters, center, age, temporal_strength, spatial_strength, strength,
rain_strength, snow_strength, cloud_count and expired. Snapshot mutations do
not affect state. Strengths refer to the last advance viewer (initial=center).
Exact snapshot keys: center,age,total,fade,inner,outer,temperature,rain,snow,
overcast,fall_speed,cloud_count,shade,height,wind_affected,temporal_strength,
spatial_strength,strength,rain_strength,snow_strength,expired,rain_instances,
snow_instances,precipitation_position. cloud_count is the configured count.

Time is seconds supplied by caller, an explicit new API choice. Original frame
and update time units are not claimed. The120/40 ratio-shaped source ramp is
re-expressed in seconds, not a proof of engine-time equivalence. The shape:
age0->0,20->.5,40->1,60->1,80->1,100->.5,120->0 and expiredtrue.
For fade>0 temporal_strength=clamp(min(age/fade,(total-age)/fade,1),0,1).
For fade0 use1 before total,0 at/after total. Age saturates at36000.
Setters recompute strengths at the retained viewer/age; do not restart lifetime.
Expired means age>=total; changing total may make that false, without age reset.

Spatial policy uses XZ distance (Godot Y-up) from the immutable configured center:
later caller changes to node.position do not change stored center or snapshot.
Strength is1 at distance<=inner,
0 at distance>=outer; otherwise (outer-distance)/(outer-inner). At equal
inner==outer use the inclusive inner test first (a hard cutoff).
strength=temporal_strength*spatial_strength. rain_strength=rain*strength;
snow_strength=snow*strength. Overcast/shade affect visible cloud opacity/color,
not the temporal strength. Wind changes presentation only, never node.center.

Create visible storm geometry using only procedural Godot resources:
- up to32 broad flattened cloud meshes around center at configured height;
  clouds darken with shade/overcast, alpha follows temporal strength.
- at least128 bounded rain streaks and64 snow flakes in camera-local vicinity,
  within a roughly100x100 metre horizontal region around viewer; positions are
  deterministic functions of index and age, no unbounded loops/random timers.
  Use bounded MultiMesh or instances. Rain moves downward with speed derived
  from fall_speed; snow slower. Rain/snow visually hide when their strength0.
  Rain streaks must have a visible width at normal camera distance, not lines
  with zero screen coverage. Materials support alpha and work with Godot's
  Compatibility renderer. Do not rely on GPUParticles simulation in headless.
- expose owned Node3D children named Clouds, Rain and Snow so integration tests
  can inspect visibility and nonempty geometry. Moving viewer updates nearby
  precipitation without moving the weather's stored center or cloud anchor.
  Clouds is hidden at temporal_strength0 or cloud_count0; no nonempty cloud
  geometry is required when count0. Rain/Snow hide at their strength0.
The visual design is flexible; keep resource/instance counts bounded. The
functional lifetime/strength API above is exact. Include snapshot integers
rain_instances/snow_instances: allocated counts constant after configure,
rain128..1024 and snow64..512, not visible counts. precipitation_position is
the world-space last valid viewer, initially center. On configure and every
successful mutating method, re-sync Clouds.global_position to stored center
and Rain/Snow.global_position to the retained viewer. This keeps anchors fixed
when caller translates node/ancestors; only identity bases are supported.
There is no automatic _process to re-sync between calls. At configuration all
three children exist, even when initially hidden.

Synthetic fixtures with tolerance1e-5 (Vector3 tolerance1e-3):
- configureZERO; advance20,viewerZERO ->age20,strength.5,rain.5.
  advance20 ->1; advance40 ->1; advance20 ->.5; advance20 ->0,expired.
- at age40, inner600/outer1000 and viewer(800,500,0): spatial.5,strength.5;
  y does not affect spatial distance. Viewer(1000,0,0) ->0.
- Fresh configure, lifetime(100,0),age0 ->1; advance100 ->0. Equal radii(10,10): distance10
  spatial1;10.01 spatial0. Parameter setters preserve age and recompute strength.
- large valid delta expires without per-time loops; invalid/nonfinite values
  and repeated configure preserve snapshot/children; before configure no effects.
- visible configured rain and clouds at age40; snow hidden with snow0;
  after weather(15,0,1,1,2), snow visible/rain hidden. All three Clouds/Rain/Snow
  hide at expiry.
- viewer movement shifts precipitation geometry and precipitation_position,
  but center and cloud world anchor stay unchanged. Child counts bounded.
  advance(0,Vector3(30,0,-40)) gives precipitation_position(30,0,-40).
- Configure under a translated identity-basis parent; world-space center and
  anchors match. Translate the node, call advance0: anchors re-sync as above.
  Rotation/scaling and out-of-tree mutation reject atomically; restoring the
  supported transform permits subsequent valid calls.

Return only JSON mapping weather_zone.gd and verify_weather_zone.gd to their
complete text. Test extends SceneTree, preload res://weather_zone.gd, checks
real Node3D geometry/state, nonzero exit on failure. Explicit GDScript types.
No tools or claims of execution. No original data or reference code is supplied.
