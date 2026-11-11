extends Node3D
## Procedural weather zone (SPEC-WEATHER-ZONE-001 v3).
## New remake presentation, not the original renderer. The caller owns this node
## and its clock: only advance() changes age. All visuals are owned children named
## Clouds, Rain and Snow. Supported placement: inside the SceneTree, with identity
## global bases on this node and every Node3D ancestor (translations allowed).

const COORD_LIMIT: float = 100000.0
const AGE_LIMIT: float = 36000.0
const RADIUS_LIMIT: float = 5000.0
const BASIS_TOLERANCE: float = 0.000001
const MAX_CLOUDS: int = 32
const RAIN_INSTANCES: int = 256
const SNOW_INSTANCES: int = 128
const REGION_HALF: float = 50.0
const PRECIP_SPAN: float = 30.0
const PRECIP_BOTTOM: float = -2.0
const CLOUD_SPREAD: float = 450.0
const GOLDEN_ANGLE: float = 2.3999632

var _configured: bool = false
var _center: Vector3 = Vector3.ZERO
var _viewer: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _total: float = 120.0
var _fade: float = 40.0
var _inner: float = 600.0
var _outer: float = 1000.0
var _temperature: float = 15.0
var _rain: float = 1.0
var _snow: float = 0.0
var _overcast: float = 1.0
var _fall_speed: float = 2.0
var _cloud_count: int = 8
var _shade: float = 0.8
var _cloud_height: float = 130.0
var _wind_affected: bool = false
var _temporal_strength: float = 0.0
var _spatial_strength: float = 1.0
var _strength: float = 0.0

var _clouds_root: Node3D = null
var _rain_root: Node3D = null
var _snow_root: Node3D = null
var _cloud_instances: Array[MeshInstance3D] = []
var _cloud_material: StandardMaterial3D = null
var _rain_material: StandardMaterial3D = null
var _snow_material: StandardMaterial3D = null
var _rain_multimesh: MultiMesh = null
var _snow_multimesh: MultiMesh = null


## Configures the zone once at a world-space center. Fails atomically otherwise.
func configure(center: Vector3) -> bool:
    if _configured:
        return false
    if not _is_valid_point(center):
        return false
    if not _placement_supported():
        return false
    _center = center
    _viewer = center
    _age = 0.0
    _total = 120.0
    _fade = 40.0
    _inner = 600.0
    _outer = 1000.0
    _temperature = 15.0
    _rain = 1.0
    _snow = 0.0
    _overcast = 1.0
    _fall_speed = 2.0
    _cloud_count = 8
    _shade = 0.8
    _cloud_height = 130.0
    _wind_affected = false
    global_position = center
    _build_children()
    _configured = true
    _refresh()
    return true


func set_weather(temperature: float, rain: float, snow: float, overcast: float, fall_speed: float) -> bool:
    if not _can_mutate():
        return false
    if not _in_range(temperature, 0.0, 255.0):
        return false
    if not _in_range(rain, 0.0, 1.0):
        return false
    if not _in_range(snow, 0.0, 1.0):
        return false
    if not _in_range(overcast, 0.0, 1.0):
        return false
    if not _in_range(fall_speed, 0.0, 1000.0):
        return false
    _temperature = temperature
    _rain = rain
    _snow = snow
    _overcast = overcast
    _fall_speed = fall_speed
    _refresh()
    return true


func set_clouds(count: int, shade: float, height: float) -> bool:
    if not _can_mutate():
        return false
    if count < 0 or count > MAX_CLOUDS:
        return false
    if not _in_range(shade, 0.0, 1.0):
        return false
    if not _in_range(height, 1.0, 2000.0):
        return false
    _cloud_count = count
    _shade = shade
    _cloud_height = height
    _refresh()
    return true


func set_lifetime(total: float, fade: float) -> bool:
    if not _can_mutate():
        return false
    if not is_finite(total) or total <= 0.0 or total > AGE_LIMIT:
        return false
    if not _in_range(fade, 0.0, total * 0.5):
        return false
    _total = total
    _fade = fade
    _refresh()
    return true


func set_radii(inner: float, outer: float) -> bool:
    if not _can_mutate():
        return false
    if not _in_range(inner, 0.0, RADIUS_LIMIT):
        return false
    if not _in_range(outer, 0.0, RADIUS_LIMIT):
        return false
    if inner > outer or outer <= 0.0:
        return false
    _inner = inner
    _outer = outer
    _refresh()
    return true


func set_wind_affected(enabled: bool) -> void:
    if not _can_mutate():
        return
    _wind_affected = enabled
    _refresh()


func advance(delta: float, viewer: Vector3) -> Dictionary:
    if not _configured:
        return {}
    if not _in_range(delta, 0.0, AGE_LIMIT):
        return {}
    if not _is_valid_point(viewer):
        return {}
    if not _placement_supported():
        return {}
    _age = minf(_age + delta, AGE_LIMIT)
    _viewer = viewer
    _refresh()
    return snapshot()


func snapshot() -> Dictionary:
    if not _configured:
        return {}
    return {
        "center": _center,
        "age": _age,
        "total": _total,
        "fade": _fade,
        "inner": _inner,
        "outer": _outer,
        "temperature": _temperature,
        "rain": _rain,
        "snow": _snow,
        "overcast": _overcast,
        "fall_speed": _fall_speed,
        "cloud_count": _cloud_count,
        "shade": _shade,
        "height": _cloud_height,
        "wind_affected": _wind_affected,
        "temporal_strength": _temporal_strength,
        "spatial_strength": _spatial_strength,
        "strength": _strength,
        "rain_strength": _rain * _strength,
        "snow_strength": _snow * _strength,
        "expired": _age >= _total,
        "rain_instances": RAIN_INSTANCES,
        "snow_instances": SNOW_INSTANCES,
        "precipitation_position": _viewer,
    }


# ---------------------------------------------------------------- validation

func _can_mutate() -> bool:
    return _configured and _placement_supported()


func _in_range(value: float, low: float, high: float) -> bool:
    return is_finite(value) and value >= low and value <= high


func _is_valid_point(point: Vector3) -> bool:
    return _in_range(point.x, -COORD_LIMIT, COORD_LIMIT) and _in_range(point.y, -COORD_LIMIT, COORD_LIMIT) and _in_range(point.z, -COORD_LIMIT, COORD_LIMIT)


func _is_identity_basis(basis_value: Basis) -> bool:
    var columns: Array[Vector3] = [basis_value.x, basis_value.y, basis_value.z]
    var identity_columns: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)]
    for c: int in range(3):
        var diff: Vector3 = columns[c] - identity_columns[c]
        if not (absf(diff.x) <= BASIS_TOLERANCE and absf(diff.y) <= BASIS_TOLERANCE and absf(diff.z) <= BASIS_TOLERANCE):
            return false
    return true


func _placement_supported() -> bool:
    if not is_inside_tree():
        return false
    if not _is_identity_basis(global_transform.basis):
        return false
    var ancestor: Node = get_parent()
    while ancestor != null:
        var ancestor_3d: Node3D = ancestor as Node3D
        if ancestor_3d != null and not _is_identity_basis(ancestor_3d.global_transform.basis):
            return false
        ancestor = ancestor.get_parent()
    return true


# ---------------------------------------------------------------- state

func _refresh() -> void:
    _recompute()
    _sync_anchors()


func _recompute() -> void:
    if _fade > 0.0:
        var ramp: float = minf(minf(_age / _fade, (_total - _age) / _fade), 1.0)
        _temporal_strength = clampf(ramp, 0.0, 1.0)
    elif _age < _total:
        _temporal_strength = 1.0
    else:
        _temporal_strength = 0.0
    var dx: float = _viewer.x - _center.x
    var dz: float = _viewer.z - _center.z
    var distance: float = sqrt(dx * dx + dz * dz)
    if distance <= _inner:
        _spatial_strength = 1.0
    elif distance >= _outer:
        _spatial_strength = 0.0
    else:
        _spatial_strength = clampf((_outer - distance) / (_outer - _inner), 0.0, 1.0)
    _strength = _temporal_strength * _spatial_strength
    _update_visuals()


func _sync_anchors() -> void:
    if _clouds_root == null or _rain_root == null or _snow_root == null:
        return
    _clouds_root.global_position = _center
    _rain_root.global_position = _viewer
    _snow_root.global_position = _viewer


# ---------------------------------------------------------------- visuals

func _make_material(color: Color) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.albedo_color = color
    return material


func _make_multimesh(mesh_resource: Mesh, count: int) -> MultiMesh:
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = count
    multimesh.mesh = mesh_resource
    return multimesh


func _make_multimesh_instance(node_name: String, multimesh: MultiMesh) -> MultiMeshInstance3D:
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multimesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var span: float = REGION_HALF * 2.0 + 10.0
    instance.custom_aabb = AABB(Vector3(-REGION_HALF - 5.0, PRECIP_BOTTOM - 2.0, -REGION_HALF - 5.0), Vector3(span, PRECIP_SPAN + 4.0, span))
    return instance


func _build_children() -> void:
    _clouds_root = Node3D.new()
    _clouds_root.name = "Clouds"
    add_child(_clouds_root)
    _cloud_material = _make_material(Color(0.6, 0.6, 0.63, 0.0))
    var cloud_mesh: SphereMesh = SphereMesh.new()
    cloud_mesh.radius = 70.0
    cloud_mesh.height = 22.0
    cloud_mesh.radial_segments = 16
    cloud_mesh.rings = 6
    cloud_mesh.material = _cloud_material
    _cloud_instances.clear()
    for i: int in range(MAX_CLOUDS):
        var cloud: MeshInstance3D = MeshInstance3D.new()
        cloud.name = "Cloud%02d" % i
        cloud.mesh = cloud_mesh
        cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        cloud.visible = false
        _clouds_root.add_child(cloud)
        _cloud_instances.append(cloud)

    _rain_root = Node3D.new()
    _rain_root.name = "Rain"
    add_child(_rain_root)
    _rain_material = _make_material(Color(0.72, 0.78, 0.9, 0.0))
    var streak: BoxMesh = BoxMesh.new()
    streak.size = Vector3(0.06, 0.9, 0.06)
    streak.material = _rain_material
    _rain_multimesh = _make_multimesh(streak, RAIN_INSTANCES)
    _rain_root.add_child(_make_multimesh_instance("RainStreaks", _rain_multimesh))

    _snow_root = Node3D.new()
    _snow_root.name = "Snow"
    add_child(_snow_root)
    _snow_material = _make_material(Color(0.97, 0.98, 1.0, 0.0))
    var flake: SphereMesh = SphereMesh.new()
    flake.radius = 0.07
    flake.height = 0.14
    flake.radial_segments = 6
    flake.rings = 3
    flake.material = _snow_material
    _snow_multimesh = _make_multimesh(flake, SNOW_INSTANCES)
    _snow_root.add_child(_make_multimesh_instance("SnowFlakes", _snow_multimesh))

    _clouds_root.visible = false
    _rain_root.visible = false
    _snow_root.visible = false


func _update_visuals() -> void:
    if _clouds_root == null or _rain_root == null or _snow_root == null:
        return
    _update_clouds()
    _update_rain()
    _update_snow()


func _update_clouds() -> void:
    _clouds_root.visible = _temporal_strength > 0.0 and _cloud_count > 0
    var darkness: float = clampf(0.55 * _shade + 0.35 * _overcast, 0.0, 0.9)
    var grey: float = 0.95 - 0.75 * darkness
    var alpha: float = clampf(_temporal_strength * (0.35 + 0.55 * _overcast), 0.0, 1.0)
    _cloud_material.albedo_color = Color(grey, grey, minf(grey * 1.05, 1.0), alpha)
    for i: int in range(MAX_CLOUDS):
        var cloud: MeshInstance3D = _cloud_instances[i]
        var active: bool = i < _cloud_count
        cloud.visible = active
        if not active:
            continue
        var fi: float = float(i)
        var angle: float = fi * GOLDEN_ANGLE
        var radius: float = CLOUD_SPREAD * sqrt((fi + 0.5) / float(MAX_CLOUDS))
        var offset: Vector3 = Vector3(cos(angle) * radius, _cloud_height, sin(angle) * radius)
        if _wind_affected:
            offset.x += sin(_age * 0.02 + fi) * 40.0
            offset.z += cos(_age * 0.015 + fi * 0.7) * 25.0
        var stretch: Vector3 = Vector3(1.0 + 0.4 * sin(fi * 1.7), 1.0, 1.0 + 0.3 * cos(fi * 2.3))
        cloud.transform = Transform3D(Basis.from_scale(stretch), offset)


func _update_rain() -> void:
    var rain_strength: float = _rain * _strength
    _rain_root.visible = rain_strength > 0.0
    _rain_material.albedo_color = Color(0.72, 0.78, 0.9, clampf(0.3 + 0.6 * rain_strength, 0.0, 1.0))
    var speed: float = 4.0 + 4.0 * _fall_speed
    var lean: float = 0.0
    var tilt: Basis = Basis.IDENTITY
    if _wind_affected:
        lean = 0.3
        tilt = Basis(Vector3(0.0, 0.0, 1.0), -0.29)
    var span2: float = REGION_HALF * 2.0
    for i: int in range(RAIN_INSTANCES):
        var fi: float = float(i)
        var x: float = fposmod(fi * 0.7548776662, 1.0) * span2 - REGION_HALF
        var z: float = fposmod(fi * 0.5698402910, 1.0) * span2 - REGION_HALF
        var phase: float = fposmod(fi * 0.6180339887, 1.0)
        var fallen: float = fposmod(phase * PRECIP_SPAN + _age * speed, PRECIP_SPAN)
        var y: float = PRECIP_BOTTOM + PRECIP_SPAN - fallen
        if _wind_affected:
            x = fposmod(x + fallen * lean + REGION_HALF, span2) - REGION_HALF
        _rain_multimesh.set_instance_transform(i, Transform3D(tilt, Vector3(x, y, z)))


func _update_snow() -> void:
    var snow_strength: float = _snow * _strength
    _snow_root.visible = snow_strength > 0.0
    _snow_material.albedo_color = Color(0.97, 0.98, 1.0, clampf(0.35 + 0.6 * snow_strength, 0.0, 1.0))
    var speed: float = 0.6 + 0.4 * _fall_speed
    var span2: float = REGION_HALF * 2.0
    var drift: float = 0.0
    if _wind_affected:
        drift = fposmod(_age * 2.0, span2)
    for i: int in range(SNOW_INSTANCES):
        var fi: float = float(i)
        var x: float = fposmod(fi * 0.7548776662, 1.0) * span2 - REGION_HALF
        var z: float = fposmod(fi * 0.5698402910, 1.0) * span2 - REGION_HALF
        x += sin(_age * 1.1 + fi * 1.3) * 0.6 + drift
        z += cos(_age * 0.9 + fi) * 0.6
        x = fposmod(x + REGION_HALF, span2) - REGION_HALF
        z = fposmod(z + REGION_HALF, span2) - REGION_HALF
        var phase: float = fposmod(fi * 0.6180339887, 1.0)
        var fallen: float = fposmod(phase * PRECIP_SPAN + _age * speed, PRECIP_SPAN)
        var y: float = PRECIP_BOTTOM + PRECIP_SPAN - fallen
        _snow_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
