extends CanvasLayer
## Original main temple room and its recorded five-second entry camera.
## Room navigation and room-specific mechanics are not implemented here yet.

var active := false
var error := ""
var viewport := SubViewport.new()
var camera := Camera3D.new()
var _camera_track := PackedByteArray()
var _camera_age := 0.0
var _duration := 0.0
var _frames := 0

func start(folder: String) -> bool:
	layer = 1
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	for filename in ["main_l3d.zzz", "mainfloor_l3d.zzz", "mainwater_l3d.zzz"]:
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(filename))
		if bytes.size() < 6 or bytes.decode_u32(0) > 32000000:
			error = "Original temple room is unavailable"
			return false
		var rig := L3dRig.new()
		var model := rig.load_bytes(bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_DEFLATE))
		if model == null:
			error = rig.error
			return false
		# Original room textures contain their baked illumination.
		for child in model.get_children():
			if child is MeshInstance3D:
				for surface in child.mesh.get_surface_count():
					var material := child.mesh.surface_get_material(surface) as StandardMaterial3D
					if material != null:
						material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		scene.add_child(model)
	_camera_track = FileAccess.get_file_as_bytes(folder.path_join("main.cam"))
	if _camera_track.size() < 36 or _camera_track.decode_u32(0) != _camera_track.size():
		error = "Invalid original temple camera"
		return false
	_duration = _camera_track.decode_u32(4) / 1000.0
	_frames = _camera_track.decode_u32(8)
	if _duration <= 0.0 or _frames < 2 or _frames > 10000 or 12 + _frames * 24 != _camera_track.size():
		error = "Invalid original temple camera frames"
		return false
	scene.add_child(camera)
	camera.current = true
	camera.near = 0.05
	camera.far = 500.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	camera.environment = environment
	var screen := TextureRect.new()
	screen.texture = viewport.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hint := Label.new()
	hint.text = "Esc — вернуться на остров"
	hint.position = Vector2(20, 20)
	add_child(hint)
	active = true
	_process(0.0)
	return true

func _process(delta: float) -> void:
	if not active:
		return
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	_camera_age = minf(_camera_age + delta, _duration)
	var frame := _camera_age / _duration * float(_frames - 1)
	var a := int(frame)
	var b := mini(a + 1, _frames - 1)
	var weight := frame - a
	camera.position = _point(a, 0).lerp(_point(b, 0), weight)
	var focus := _point(a, 12).lerp(_point(b, 12), weight)
	if camera.position.distance_squared_to(focus) > 0.00001:
		camera.look_at(focus)

func _point(frame: int, field: int) -> Vector3:
	var offset := 12 + frame * 24 + field
	return Vector3(_camera_track.decode_float(offset), _camera_track.decode_float(offset + 4), -_camera_track.decode_float(offset + 8))

func close() -> void:
	active = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()
