extends Node3D
## Spot visual 10 (COMMAND_SUCCEED) uses the original CreatureTarget sprite bank.

const ATLAS_SIZE := 256
const FRAME_SIZE := 32
const FIRST_FRAME := 48
const FRAME_COUNT := 9
const PARTICLE_COUNT := 6
const RADIUS := 2.65619
const CENTRE_HEIGHT := 1.82168
const SPRITE_SIZE := 1.33009
const FRAME_RATE := 13.5226
const ROTATION_PER_SECOND := 0.446903
const FADE_TIME := 0.5
const REMOVAL_DELAY := 3.46286
const TINT := Color8(253, 251, 181, 250)

var _frames: Array[Texture2D] = []
var _materials: Array[StandardMaterial3D] = []
var _first_frames := PackedInt32Array()
var _duration := 0.0
var _elapsed := 0.0


static func load_frames(textures_folder: String, sheet := "S_SpriteSheet1", first_frame := FIRST_FRAME, count := FRAME_COUNT) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var colour := FileAccess.get_file_as_bytes(textures_folder.path_join(sheet + ".raw"))
	var alpha := FileAccess.get_file_as_bytes(textures_folder.path_join(sheet + "a.raw"))
	var pixels := ATLAS_SIZE * ATLAS_SIZE
	if colour.size() != pixels * 3 or alpha.size() != pixels:
		return frames
	var rgba := PackedByteArray()
	rgba.resize(pixels * 4)
	for i in pixels:
		rgba[i * 4] = colour[i * 3]
		rgba[i * 4 + 1] = colour[i * 3 + 1]
		rgba[i * 4 + 2] = colour[i * 3 + 2]
		rgba[i * 4 + 3] = alpha[i]
	var atlas := Image.create_from_data(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8, rgba)
	var columns := ATLAS_SIZE / FRAME_SIZE
	for i in range(first_frame, first_frame + count):
		var region := Rect2i(i % columns * FRAME_SIZE, i / columns * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.append(ImageTexture.create_from_image(atlas.get_region(region)))
	return frames


func start(frames: Array[Texture2D], seconds: float) -> void:
	_frames = frames
	_duration = seconds
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SPRITE_SIZE
	for i in PARTICLE_COUNT:
		var sprite := MeshInstance3D.new()
		sprite.mesh = quad
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.albedo_color = TINT
		var frame := randi_range(0, FRAME_COUNT - 1)
		material.albedo_texture = _frames[frame]
		_materials.append(material)
		_first_frames.append(frame)
		sprite.material_override = material
		var azimuth := randf() * TAU
		var y := randf_range(-1.0, 1.0)
		var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
		sprite.position = RADIUS * Vector3(horizontal * cos(azimuth), y, horizontal * sin(azimuth)) + Vector3.UP * CENTRE_HEIGHT
		add_child(sprite)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration + REMOVAL_DELAY:
		queue_free()
		return
	if _elapsed >= _duration + FADE_TIME:
		hide()
		return
	rotation.y = _elapsed * ROTATION_PER_SECOND
	var opacity := 1.0 - clampf((_elapsed - _duration) / FADE_TIME, 0.0, 1.0)
	var frame_advance := floori(_elapsed * FRAME_RATE)
	for i in _materials.size():
		var material := _materials[i]
		material.albedo_texture = _frames[(_first_frames[i] + frame_advance) % FRAME_COUNT]
		material.albedo_color = Color(TINT, TINT.a * opacity)
