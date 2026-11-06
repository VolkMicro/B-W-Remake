extends Node3D

const TARGET := Vector3(1416.337, 0.0, -2053.503)
const DIRECTION := Vector3(-1.0, -0.24, 1.0)
const RUN_UP := 4000.0
const SPEED := 450.0
var elapsed := 0.0


func configure(textures: Array[Texture2D]) -> void:
	var direction := DIRECTION.normalized()
	for i in 20:
		var sprite := Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.texture = textures[0 if i <= 5 else 2]
		var size := 3.0 + (19 - i) * 0.75
		if i > 5:
			size *= 2.0
		sprite.modulate.a = float(19 - i) / 20.0
		sprite.position = -direction * i * 6.0
		if i == 18:
			size = 80.0
			sprite.modulate.a = 40.0 / 255.0
			sprite.position = Vector3.ZERO
		elif i == 19:
			sprite.texture = textures[1]
			size = 350.0
			sprite.scale.y = 0.05
			sprite.modulate.a = 14.0 / 255.0
			sprite.position = -direction * 6.0
		sprite.pixel_size = size / 32.0
		add_child(sprite)
	position = TARGET - direction * RUN_UP


func advance(delta: float) -> void:
	elapsed += delta
	position = TARGET - DIRECTION.normalized() * maxf(10.0, RUN_UP - elapsed * SPEED)


func camera_eye() -> Vector3:
	return position - DIRECTION.normalized() * 150.0 + Vector3.UP * 30.0
