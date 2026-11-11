extends SceneTree
## Verification script for weather_zone.gd (SPEC-WEATHER-ZONE-001 v3).
## Run headless: exits nonzero on any failed check.

const WeatherZone = preload("res://scripts/weather_zone.gd")
const EPS: float = 0.00001
const VEC_EPS: float = 0.001

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
    call_deferred("_run_checks")


func _run_checks() -> void:
    _test_before_and_defaults()
    _test_lifetime_sequence()
    _test_spatial()
    _test_zero_fade_and_equal_radii()
    _test_invalid_and_large_delta()
    _test_visibility()
    _test_viewer_movement()
    _test_transform_domain()
    if _failures > 0:
        printerr("verify_weather_zone: %d of %d checks failed" % [_failures, _checks])
        quit(1)
    else:
        print("verify_weather_zone: all %d checks passed" % _checks)
        quit(0)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + message)


func _make_zone(parent_position: Vector3) -> WeatherZone:
    var holder: Node3D = Node3D.new()
    holder.position = parent_position
    get_root().add_child(holder)
    var zone: WeatherZone = WeatherZone.new()
    holder.add_child(zone)
    return zone


func _approx(a: float, b: float) -> bool:
    return absf(a - b) <= EPS


func _vapprox(a: Vector3, b: Vector3) -> bool:
    return absf(a.x - b.x) <= VEC_EPS and absf(a.y - b.y) <= VEC_EPS and absf(a.z - b.z) <= VEC_EPS


func _num(data: Dictionary, key: String) -> float:
    if not data.has(key):
        return NAN
    return float(data[key])


func _vec(data: Dictionary, key: String) -> Vector3:
    if data.has(key) and data[key] is Vector3:
        return data[key] as Vector3
    return Vector3(NAN, NAN, NAN)


func _same(a: Dictionary, b: Dictionary) -> bool:
    if a.size() != b.size():
        return false
    for k: Variant in a.keys():
        if not b.has(k):
            return false
        if typeof(a[k]) != typeof(b[k]):
            return false
        if a[k] != b[k]:
            return false
    return true


func _child3d(zone: Node, child_name: String) -> Node3D:
    return zone.get_node_or_null(NodePath(child_name)) as Node3D


func _shown(zone: Node, child_name: String) -> bool:
    var node: Node3D = _child3d(zone, child_name)
    return node != null and node.visible


func _first_mmi(node: Node) -> MultiMeshInstance3D:
    if node == null:
        return null
    for c: Node in node.get_children():
        if c is MultiMeshInstance3D:
            return c as MultiMeshInstance3D
    return null


func _mmi_ok(mmi: MultiMeshInstance3D, min_count: int, max_count: int) -> bool:
    if mmi == null or mmi.multimesh == null:
        return false
    var mm: MultiMesh = mmi.multimesh
    if mm.instance_count < min_count or mm.instance_count > max_count:
        return false
    if mm.mesh == null:
        return false
    var box: AABB = mm.mesh.get_aabb()
    return box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0


func _visible_clouds(zone: Node) -> int:
    var clouds: Node3D = _child3d(zone, "Clouds")
    if clouds == null:
        return -1
    var count: int = 0
    for c: Node in clouds.get_children():
        var mesh_instance: MeshInstance3D = c as MeshInstance3D
        if mesh_instance != null and mesh_instance.visible and mesh_instance.mesh != null:
            if mesh_instance.mesh.get_aabb().size.length() > 0.0:
                count += 1
    return count


func _descendants(node: Node) -> int:
    var total_count: int = node.get_child_count()
    for c: Node in node.get_children():
        total_count += _descendants(c)
    return total_count


func _instance_world(mmi: MultiMeshInstance3D, index: int) -> Vector3:
    return (mmi.global_transform * mmi.multimesh.get_instance_transform(index)).origin


func _expect_rejected(zone: WeatherZone, baseline: Dictionary, child_total: int, label: String) -> void:
    _check(zone.advance(1.0, Vector3.ZERO).is_empty(), label + ": advance rejected")
    _check(not zone.set_weather(20.0, 0.5, 0.5, 0.5, 3.0), label + ": set_weather rejected")
    _check(not zone.set_clouds(4, 0.2, 90.0), label + ": set_clouds rejected")
    _check(not zone.set_lifetime(50.0, 10.0), label + ": set_lifetime rejected")
    _check(not zone.set_radii(5.0, 50.0), label + ": set_radii rejected")
    _check(not zone.configure(Vector3.ZERO), label + ": configure rejected")
    zone.set_wind_affected(not bool(baseline.get("wind_affected", false)))
    _check(_same(baseline, zone.snapshot()), label + ": snapshot unchanged")
    _check(_descendants(zone) == child_total, label + ": children unchanged")


# ---------------------------------------------------------------- tests

func _test_before_and_defaults() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.snapshot().is_empty(), "snapshot before configure is empty")
    _check(zone.advance(1.0, Vector3.ZERO).is_empty(), "advance before configure is empty")
    _check(not zone.set_weather(15.0, 1.0, 0.0, 1.0, 2.0), "set_weather fails before configure")
    _check(not zone.set_clouds(8, 0.8, 130.0), "set_clouds fails before configure")
    _check(not zone.set_lifetime(120.0, 40.0), "set_lifetime fails before configure")
    _check(not zone.set_radii(600.0, 1000.0), "set_radii fails before configure")
    zone.set_wind_affected(true)
    _check(zone.get_child_count() == 0, "no children before configure")
    _check(not zone.configure(Vector3(NAN, 0.0, 0.0)), "nonfinite center rejected")
    _check(not zone.configure(Vector3(0.0, 0.0, 100001.0)), "out of range center rejected")
    _check(zone.snapshot().is_empty(), "rejected configure leaves zone unconfigured")
    _check(zone.get_child_count() == 0, "rejected configure creates no children")

    _check(zone.configure(Vector3.ZERO), "configure ZERO succeeds")
    var s: Dictionary = zone.snapshot()
    var expected: PackedStringArray = PackedStringArray(["center", "age", "total", "fade", "inner", "outer", "temperature", "rain", "snow", "overcast", "fall_speed", "cloud_count", "shade", "height", "wind_affected", "temporal_strength", "spatial_strength", "strength", "rain_strength", "snow_strength", "expired", "rain_instances", "snow_instances", "precipitation_position"])
    _check(s.size() == expected.size(), "snapshot has exact key count")
    for key: String in expected:
        _check(s.has(key), "snapshot has key " + key)
    _check(_vapprox(_vec(s, "center"), Vector3.ZERO), "default center")
    _check(_approx(_num(s, "age"), 0.0), "default age")
    _check(_approx(_num(s, "total"), 120.0), "default total")
    _check(_approx(_num(s, "fade"), 40.0), "default fade")
    _check(_approx(_num(s, "inner"), 600.0), "default inner")
    _check(_approx(_num(s, "outer"), 1000.0), "default outer")
    _check(_approx(_num(s, "temperature"), 15.0), "default temperature")
    _check(_approx(_num(s, "rain"), 1.0), "default rain")
    _check(_approx(_num(s, "snow"), 0.0), "default snow")
    _check(_approx(_num(s, "overcast"), 1.0), "default overcast")
    _check(_approx(_num(s, "fall_speed"), 2.0), "default fall_speed")
    _check(typeof(s.get("cloud_count")) == TYPE_INT and int(s.get("cloud_count")) == 8, "default cloud_count int 8")
    _check(_approx(_num(s, "shade"), 0.8), "default shade")
    _check(_approx(_num(s, "height"), 130.0), "default height")
    _check(s.get("wind_affected", true) == false, "wind setter before configure was a no-op")
    _check(_approx(_num(s, "temporal_strength"), 0.0), "temporal 0 at age 0")
    _check(_approx(_num(s, "spatial_strength"), 1.0), "spatial 1 at center")
    _check(_approx(_num(s, "strength"), 0.0), "strength 0 at age 0")
    _check(s.get("expired", true) == false, "not expired at age 0")
    _check(typeof(s.get("rain_instances")) == TYPE_INT, "rain_instances is int")
    _check(typeof(s.get("snow_instances")) == TYPE_INT, "snow_instances is int")
    var rain_count: int = int(s.get("rain_instances", 0))
    var snow_count: int = int(s.get("snow_instances", 0))
    _check(rain_count >= 128 and rain_count <= 1024, "rain_instances in range")
    _check(snow_count >= 64 and snow_count <= 512, "snow_instances in range")
    _check(_vapprox(_vec(s, "precipitation_position"), Vector3.ZERO), "precipitation_position starts at center")
    _check(_child3d(zone, "Clouds") != null, "Clouds child exists")
    _check(_child3d(zone, "Rain") != null, "Rain child exists")
    _check(_child3d(zone, "Snow") != null, "Snow child exists")
    _check(not _shown(zone, "Clouds"), "Clouds hidden at temporal 0")
    _check(not _shown(zone, "Rain"), "Rain hidden at strength 0")
    _check(not _shown(zone, "Snow"), "Snow hidden at strength 0")

    var child_total: int = _descendants(zone)
    _check(not zone.configure(Vector3(5.0, 0.0, 5.0)), "repeated configure fails")
    _check(_same(s, zone.snapshot()), "repeated configure preserves snapshot")
    _check(_descendants(zone) == child_total, "repeated configure preserves children")

    var copy: Dictionary = zone.snapshot()
    copy["age"] = 999.0
    copy["center"] = Vector3(1.0, 2.0, 3.0)
    _check(_approx(_num(zone.snapshot(), "age"), 0.0), "snapshot mutation does not change age")
    _check(_vapprox(_vec(zone.snapshot(), "center"), Vector3.ZERO), "snapshot mutation does not change center")


func _test_lifetime_sequence() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "lifetime: configure")
    var steps: Array[float] = [20.0, 20.0, 40.0, 20.0, 20.0]
    var ages: Array[float] = [20.0, 40.0, 80.0, 100.0, 120.0]
    var strengths: Array[float] = [0.5, 1.0, 1.0, 0.5, 0.0]
    for i: int in range(steps.size()):
        var r: Dictionary = zone.advance(steps[i], Vector3.ZERO)
        _check(not r.is_empty(), "lifetime step %d returns data" % i)
        _check(_approx(_num(r, "age"), ages[i]), "lifetime step %d age" % i)
        _check(_approx(_num(r, "temporal_strength"), strengths[i]), "lifetime step %d temporal" % i)
        _check(_approx(_num(r, "strength"), strengths[i]), "lifetime step %d strength" % i)
        _check(_approx(_num(r, "rain_strength"), strengths[i]), "lifetime step %d rain_strength" % i)
        _check(_approx(_num(r, "snow_strength"), 0.0), "lifetime step %d snow_strength" % i)
        _check(_same(r, zone.snapshot()), "lifetime step %d advance equals snapshot" % i)
        if i < steps.size() - 1:
            _check(r.get("expired", true) == false, "lifetime step %d not expired" % i)
    var last: Dictionary = zone.snapshot()
    _check(last.get("expired", false) == true, "expired at age 120")
    _check(not _shown(zone, "Clouds"), "Clouds hidden at expiry")
    _check(not _shown(zone, "Rain"), "Rain hidden at expiry")
    _check(not _shown(zone, "Snow"), "Snow hidden at expiry")
    _check(zone.is_inside_tree(), "zone does not free itself")


func _test_spatial() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "spatial: configure")
    var r: Dictionary = zone.advance(40.0, Vector3(800.0, 500.0, 0.0))
    _check(_approx(_num(r, "temporal_strength"), 1.0), "spatial: temporal 1 at age 40")
    _check(_approx(_num(r, "spatial_strength"), 0.5), "spatial: 0.5 at distance 800")
    _check(_approx(_num(r, "strength"), 0.5), "spatial: strength 0.5")
    _check(_approx(_num(r, "rain_strength"), 0.5), "spatial: rain_strength 0.5")
    r = zone.advance(0.0, Vector3(800.0, -300.0, 0.0))
    _check(_approx(_num(r, "spatial_strength"), 0.5), "spatial: y ignored")
    r = zone.advance(0.0, Vector3(0.0, 0.0, -800.0))
    _check(_approx(_num(r, "spatial_strength"), 0.5), "spatial: z axis distance")
    r = zone.advance(0.0, Vector3(1000.0, 0.0, 0.0))
    _check(_approx(_num(r, "spatial_strength"), 0.0), "spatial: 0 at outer")
    _check(_approx(_num(r, "strength"), 0.0), "spatial: strength 0 at outer")
    _check(not _shown(zone, "Rain"), "spatial: rain hidden at strength 0")
    _check(_shown(zone, "Clouds"), "spatial: clouds follow temporal strength only")
    r = zone.advance(0.0, Vector3(600.0, 0.0, 0.0))
    _check(_approx(_num(r, "spatial_strength"), 1.0), "spatial: 1 at inner")
    _check(_approx(_num(r, "age"), 40.0), "spatial: zero deltas keep age")


func _test_zero_fade_and_equal_radii() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "zero fade: configure")
    _check(zone.set_lifetime(100.0, 0.0), "zero fade: set_lifetime(100,0)")
    var s: Dictionary = zone.snapshot()
    _check(_approx(_num(s, "age"), 0.0), "zero fade: age stays 0")
    _check(_approx(_num(s, "temporal_strength"), 1.0), "zero fade: temporal 1 at age 0")
    _check(_approx(_num(s, "strength"), 1.0), "zero fade: strength recomputed")
    var r: Dictionary = zone.advance(100.0, Vector3.ZERO)
    _check(_approx(_num(r, "temporal_strength"), 0.0), "zero fade: temporal 0 at total")
    _check(r.get("expired", false) == true, "zero fade: expired at total")
    _check(zone.set_radii(10.0, 10.0), "equal radii accepted")
    r = zone.advance(0.0, Vector3(10.0, 0.0, 0.0))
    _check(_approx(_num(r, "spatial_strength"), 1.0), "equal radii: distance 10 inclusive")
    r = zone.advance(0.0, Vector3(10.01, 0.0, 0.0))
    _check(_approx(_num(r, "spatial_strength"), 0.0), "equal radii: distance 10.01 cut off")
    _check(zone.set_lifetime(200.0, 50.0), "setter extends lifetime")
    s = zone.snapshot()
    _check(_approx(_num(s, "age"), 100.0), "setter preserves age")
    _check(s.get("expired", true) == false, "extending total clears expired")
    _check(_approx(_num(s, "temporal_strength"), 1.0), "setter recomputes temporal")
    _check(_approx(_num(s, "spatial_strength"), 0.0), "retained viewer still outside")
    _check(zone.set_radii(20.0, 40.0), "widen radii")
    s = zone.snapshot()
    _check(_approx(_num(s, "spatial_strength"), 1.0), "radii setter recomputes spatial at retained viewer")
    _check(_approx(_num(s, "age"), 100.0), "radii setter preserves age")
    _check(zone.set_weather(15.0, 0.25, 0.75, 0.5, 3.0), "weather setter")
    s = zone.snapshot()
    _check(_approx(_num(s, "rain_strength"), 0.25), "weather setter recomputes rain_strength")
    _check(_approx(_num(s, "snow_strength"), 0.75), "weather setter recomputes snow_strength")
    _check(_approx(_num(s, "age"), 100.0), "weather setter preserves age")


func _test_invalid_and_large_delta() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "invalid: configure")
    zone.advance(10.0, Vector3(5.0, 0.0, 5.0))
    var baseline: Dictionary = zone.snapshot()
    var child_total: int = _descendants(zone)
    _check(zone.advance(-1.0, Vector3.ZERO).is_empty(), "negative delta rejected")
    _check(zone.advance(NAN, Vector3.ZERO).is_empty(), "NAN delta rejected")
    _check(zone.advance(INF, Vector3.ZERO).is_empty(), "INF delta rejected")
    _check(zone.advance(36000.5, Vector3.ZERO).is_empty(), "delta above limit rejected")
    _check(zone.advance(1.0, Vector3(NAN, 0.0, 0.0)).is_empty(), "NAN viewer rejected")
    _check(zone.advance(1.0, Vector3(0.0, INF, 0.0)).is_empty(), "INF viewer y rejected")
    _check(zone.advance(1.0, Vector3(100001.0, 0.0, 0.0)).is_empty(), "out of range viewer rejected")
    _check(not zone.set_weather(256.0, 1.0, 0.0, 1.0, 2.0), "temperature above range rejected")
    _check(not zone.set_weather(-1.0, 1.0, 0.0, 1.0, 2.0), "temperature below range rejected")
    _check(not zone.set_weather(15.0, 1.5, 0.0, 1.0, 2.0), "rain above range rejected")
    _check(not zone.set_weather(15.0, 1.0, NAN, 1.0, 2.0), "NAN snow rejected")
    _check(not zone.set_weather(15.0, 1.0, 0.0, 2.0, 2.0), "overcast above range rejected")
    _check(not zone.set_weather(15.0, 1.0, 0.0, 1.0, 1001.0), "fall_speed above range rejected")
    _check(not zone.set_clouds(-1, 0.5, 100.0), "negative cloud count rejected")
    _check(not zone.set_clouds(33, 0.5, 100.0), "cloud count 33 rejected")
    _check(not zone.set_clouds(4, 1.1, 100.0), "shade above range rejected")
    _check(not zone.set_clouds(4, 0.5, 0.5), "height below range rejected")
    _check(not zone.set_clouds(4, 0.5, 2001.0), "height above range rejected")
    _check(not zone.set_clouds(4, 0.5, NAN), "NAN height rejected")
    _check(not zone.set_lifetime(0.0, 0.0), "zero total rejected")
    _check(not zone.set_lifetime(36001.0, 0.0), "total above range rejected")
    _check(not zone.set_lifetime(100.0, 51.0), "fade above half total rejected")
    _check(not zone.set_lifetime(100.0, -1.0), "negative fade rejected")
    _check(not zone.set_lifetime(NAN, 1.0), "NAN total rejected")
    _check(not zone.set_radii(10.0, 5.0), "inner above outer rejected")
    _check(not zone.set_radii(0.0, 0.0), "zero outer rejected")
    _check(not zone.set_radii(-1.0, 5.0), "negative inner rejected")
    _check(not zone.set_radii(0.0, 5001.0), "outer above range rejected")
    _check(not zone.set_radii(NAN, 5.0), "NAN inner rejected")
    _check(_same(baseline, zone.snapshot()), "invalid requests preserve snapshot")
    _check(_descendants(zone) == child_total, "invalid requests preserve children")

    _check(zone.set_lifetime(100.0, 50.0), "fade == total/2 accepted")
    _check(zone.set_radii(0.0, 5000.0), "radii endpoints accepted")
    _check(zone.set_weather(0.0, 0.0, 0.0, 0.0, 0.0), "weather lower endpoints accepted")
    _check(zone.set_weather(255.0, 1.0, 1.0, 1.0, 1000.0), "weather upper endpoints accepted")
    _check(zone.set_clouds(32, 1.0, 2000.0), "cloud upper endpoints accepted")
    _check(_visible_clouds(zone) == 32, "32 clouds visible geometry")
    _check(zone.set_clouds(0, 0.0, 1.0), "cloud lower endpoints accepted")
    _check(not _shown(zone, "Clouds"), "Clouds hidden at count 0")
    _check(_approx(_num(zone.snapshot(), "age"), 10.0), "endpoint setters preserve age")

    var r: Dictionary = zone.advance(36000.0, Vector3.ZERO)
    _check(_approx(_num(r, "age"), 36000.0), "large delta saturates age")
    _check(r.get("expired", false) == true, "large delta expires")
    _check(_approx(_num(r, "temporal_strength"), 0.0), "large delta temporal 0")
    r = zone.advance(36000.0, Vector3.ZERO)
    _check(_approx(_num(r, "age"), 36000.0), "age stays saturated")
    _check(zone.set_lifetime(36000.0, 0.0), "maximum total accepted")
    _check(zone.snapshot().get("expired", false) == true, "age equal to total is expired")
    _check(_descendants(zone) == child_total, "children constant after many calls")


func _test_visibility() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "visibility: configure")
    zone.advance(40.0, Vector3.ZERO)
    _check(_shown(zone, "Clouds"), "Clouds visible at age 40")
    _check(_visible_clouds(zone) == 8, "8 visible nonempty cloud meshes")
    _check(_shown(zone, "Rain"), "Rain visible at age 40")
    _check(not _shown(zone, "Snow"), "Snow hidden with snow 0")
    _check(_mmi_ok(_first_mmi(_child3d(zone, "Rain")), 128, 1024), "Rain has nonempty bounded geometry")
    _check(_mmi_ok(_first_mmi(_child3d(zone, "Snow")), 64, 512), "Snow has nonempty bounded geometry")
    var clouds: Node3D = _child3d(zone, "Clouds")
    if clouds != null and clouds.get_child_count() > 0:
        var first: MeshInstance3D = clouds.get_child(0) as MeshInstance3D
        _check(first != null and absf(first.global_position.y - 130.0) <= VEC_EPS, "cloud at configured height")
    _check(zone.set_weather(15.0, 0.0, 1.0, 1.0, 2.0), "switch to snow")
    var s: Dictionary = zone.snapshot()
    _check(_approx(_num(s, "age"), 40.0), "weather switch preserves age")
    _check(_shown(zone, "Snow"), "Snow visible after switch")
    _check(not _shown(zone, "Rain"), "Rain hidden after switch")
    _check(_approx(_num(s, "snow_strength"), 1.0), "snow_strength 1")
    _check(_approx(_num(s, "rain_strength"), 0.0), "rain_strength 0")
    _check(zone.set_clouds(4, 0.3, 200.0), "set four clouds")
    _check(_visible_clouds(zone) == 4, "four visible clouds")
    zone.advance(80.0, Vector3.ZERO)
    _check(not _shown(zone, "Clouds"), "Clouds hidden at expiry")
    _check(not _shown(zone, "Rain"), "Rain hidden at expiry")
    _check(not _shown(zone, "Snow"), "Snow hidden at expiry")


func _test_viewer_movement() -> void:
    var zone: WeatherZone = _make_zone(Vector3.ZERO)
    _check(zone.configure(Vector3.ZERO), "movement: configure")
    zone.advance(0.0, Vector3.ZERO)
    var clouds_root: Node3D = _child3d(zone, "Clouds")
    var rain_root: Node3D = _child3d(zone, "Rain")
    var snow_root: Node3D = _child3d(zone, "Snow")
    var rain_mmi: MultiMeshInstance3D = _first_mmi(rain_root)
    var snow_mmi: MultiMeshInstance3D = _first_mmi(snow_root)
    _check(clouds_root != null and rain_root != null and snow_root != null, "movement: children present")
    _check(_mmi_ok(rain_mmi, 128, 1024) and _mmi_ok(snow_mmi, 64, 512), "movement: precipitation geometry")
    _check(_descendants(zone) <= 64, "movement: child count bounded")
    if clouds_root == null or rain_root == null or snow_root == null or rain_mmi == null or snow_mmi == null:
        return
    _check(clouds_root.get_child_count() <= 32, "movement: cloud children bounded")
    var readable: bool = rain_mmi.multimesh.get_instance_transform(0).origin.length() > 0.0
    var rain0: Vector3 = Vector3.ZERO
    var snow0: Vector3 = Vector3.ZERO
    if readable:
        rain0 = _instance_world(rain_mmi, 0)
        snow0 = _instance_world(snow_mmi, 0)
    else:
        print("note: multimesh transforms not readable on this rendering server; checking anchors only")
    var cloud_mesh: MeshInstance3D = clouds_root.get_child(0) as MeshInstance3D
    var cloud0: Vector3 = cloud_mesh.global_position

    var target: Vector3 = Vector3(30.0, 0.0, -40.0)
    var r: Dictionary = zone.advance(0.0, target)
    _check(_vapprox(_vec(r, "precipitation_position"), target), "precipitation_position follows viewer")
    _check(_vapprox(_vec(r, "center"), Vector3.ZERO), "center unchanged by viewer")
    _check(_vapprox(clouds_root.global_position, Vector3.ZERO), "cloud anchor unchanged by viewer")
    _check(_vapprox(rain_root.global_position, target), "Rain anchored at viewer")
    _check(_vapprox(snow_root.global_position, target), "Snow anchored at viewer")
    _check(_vapprox(rain_mmi.global_position, target), "rain geometry shifted to viewer")
    _check(_vapprox(snow_mmi.global_position, target), "snow geometry shifted to viewer")
    _check(_vapprox(cloud_mesh.global_position, cloud0), "cloud mesh unchanged by viewer")
    if readable:
        _check(_vapprox(_instance_world(rain_mmi, 0), rain0 + target), "rain instance shifted by viewer delta")
        _check(_vapprox(_instance_world(snow_mmi, 0), snow0 + target), "snow instance shifted by viewer delta")
        var rain_y: float = rain_mmi.multimesh.get_instance_transform(0).origin.y
        var snow_y: float = snow_mmi.multimesh.get_instance_transform(0).origin.y
        zone.advance(0.05, target)
        _check(rain_mmi.multimesh.get_instance_transform(0).origin.y < rain_y, "rain falls downward")
        _check(snow_mmi.multimesh.get_instance_transform(0).origin.y < snow_y, "snow falls downward")
        var rain_drop: float = rain_y - rain_mmi.multimesh.get_instance_transform(0).origin.y
        var snow_drop: float = snow_y - snow_mmi.multimesh.get_instance_transform(0).origin.y
        _check(snow_drop < rain_drop, "snow slower than rain")
    else:
        zone.advance(0.05, target)
    var age_before: float = _num(zone.snapshot(), "age")
    zone.set_wind_affected(true)
    var s: Dictionary = zone.snapshot()
    _check(s.get("wind_affected", false) == true, "wind enabled")
    _check(_vapprox(_vec(s, "center"), Vector3.ZERO), "wind does not move center")
    _check(_approx(_num(s, "age"), age_before), "wind setter preserves age")
    _check(_vapprox(clouds_root.global_position, Vector3.ZERO), "wind does not move cloud anchor")


func _test_transform_domain() -> void:
    var zone: WeatherZone = _make_zone(Vector3(100.0, 5.0, -20.0))
    var holder: Node3D = zone.get_parent() as Node3D
    zone.position = Vector3(3.0, 0.0, 0.0)
    var center: Vector3 = Vector3(10.0, 0.0, 10.0)
    _check(zone.configure(center), "domain: configure under translated parent")
    _check(_vapprox(zone.global_position, center), "domain: node placed at world center")
    _check(_vapprox(_vec(zone.snapshot(), "center"), center), "domain: snapshot center is world space")
    _check(_vapprox(_child3d(zone, "Clouds").global_position, center), "domain: Clouds at center")
    _check(_vapprox(_child3d(zone, "Rain").global_position, center), "domain: Rain at initial viewer")
    _check(_vapprox(_child3d(zone, "Snow").global_position, center), "domain: Snow at initial viewer")

    zone.position += Vector3(5.0, 0.0, 0.0)
    var r: Dictionary = zone.advance(0.0, center)
    _check(not r.is_empty(), "domain: advance after node translation")
    _check(_vapprox(_vec(r, "center"), center), "domain: stored center unchanged by node move")
    _check(_vapprox(_child3d(zone, "Clouds").global_position, center), "domain: Clouds re-synced")
    _check(_vapprox(_child3d(zone, "Rain").global_position, center), "domain: Rain re-synced")
    holder.position += Vector3(-7.0, 2.0, 3.0)
    var viewer: Vector3 = Vector3(40.0, 0.0, 10.0)
    r = zone.advance(0.0, viewer)
    _check(_vapprox(_child3d(zone, "Clouds").global_position, center), "domain: Clouds re-synced after parent move")
    _check(_vapprox(_child3d(zone, "Rain").global_position, viewer), "domain: Rain at viewer after parent move")
    _check(_vapprox(_child3d(zone, "Snow").global_position, viewer), "domain: Snow at viewer after parent move")

    var baseline: Dictionary = zone.snapshot()
    var child_total: int = _descendants(zone)
    holder.rotation = Vector3(0.0, 0.5, 0.0)
    _expect_rejected(zone, baseline, child_total, "rotated parent")
    holder.rotation = Vector3.ZERO
    zone.scale = Vector3(2.0, 2.0, 2.0)
    _expect_rejected(zone, baseline, child_total, "scaled node")
    zone.scale = Vector3.ONE
    holder.remove_child(zone)
    _expect_rejected(zone, baseline, child_total, "out of tree")
    _check(_same(baseline, zone.snapshot()), "snapshot readable out of tree")
    holder.add_child(zone)

    r = zone.advance(1.0, center)
    _check(not r.is_empty(), "domain: valid advance after restore")
    _check(_approx(_num(r, "age"), _num(baseline, "age") + 1.0), "domain: age advanced after restore")
    zone.set_wind_affected(true)
    _check(zone.snapshot().get("wind_affected", false) == true, "domain: wind setter works after restore")
    _check(zone.set_clouds(3, 0.5, 80.0), "domain: setter works after restore")
    _check(_vapprox(_child3d(zone, "Clouds").global_position, center), "domain: Clouds anchored after restore")
