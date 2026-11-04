# Isolated original 1.2 scripted-object influence falloff. Values come from
# each player's own Info data; this is not yet connected to campaign or Hand.
class_name InfluenceMath
extends RefCounted

const Data := preload("res://scripts/data.gd")


static func strength(distance: float, radius: float, settings: Dictionary) -> float:
	if not is_finite(distance) or not is_finite(radius) or distance < 0.0 or radius <= 0.0:
		return -1.0
	if not settings.has_all(["full", "gradient", "small"]):
		return -1.0
	var full := float(settings["full"])
	var gradient := float(settings["gradient"])
	var small := float(settings["small"])
	if not is_finite(full) or not is_finite(gradient) or not is_finite(small) or full <= 0.0 or gradient <= 0.0 or full + gradient >= 1.0 or small < 0.0 or small > 1.0:
		return -1.0
	var core := full * radius
	if distance <= core:
		return 1.0
	var shoulder := (full + gradient) * radius
	if distance <= shoulder:
		return (1.0 - (distance - core) / (shoulder - core)) * (1.0 - small)
	if distance < radius:
		return (1.0 - (distance - shoulder) / (radius - shoulder)) * float(Data.INFLUENCE_RULES["scripted_object"]["outer_tail"])
	return 0.0


static func strength_at(origin: Vector3, point: Vector3, radius: float, settings: Dictionary) -> float:
	if not origin.is_finite() or not point.is_finite():
		return -1.0
	var horizontal := Vector2(origin.x - point.x, origin.z - point.z).length()
	return strength(horizontal, radius, settings)
