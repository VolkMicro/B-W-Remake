shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 world_position;

void vertex() {
	// Keep the surface at the same sea level used by actors and original paths.
	// A four-vertex ocean cannot represent geometric waves: displacing its corners
	// tilts the whole ocean. Small waves belong in the per-pixel normal instead.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 w = world_position;
	float a = w.x * 0.38 + w.z * 0.19 + TIME * 1.2;
	float b = w.x * -0.21 + w.z * 0.47 - TIME * 0.9;
	vec3 wave_normal = normalize(vec3(-0.09 * cos(a) + 0.04 * cos(b), 1.0, -0.045 * cos(a) - 0.09 * cos(b)));
	wave_normal = normalize(mix(wave_normal, vec3(0.0, 1.0, 0.0), smoothstep(120.0, 650.0, length(VERTEX))));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw_depth * 2.0 - 1.0;
#endif
	vec4 below = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float water_depth = max(0.0, VERTEX.z - below.z / below.w);
	float deep = 1.0 - exp(-water_depth * 0.16);
	float foam = (1.0 - smoothstep(0.0, 0.45, water_depth)) * (0.55 + 0.15 * sin(a + b));
	ALBEDO = mix(mix(vec3(0.07, 0.34, 0.39), vec3(0.025, 0.15, 0.25), deep), vec3(0.65, 0.82, 0.8), foam);
	// Surface detail must remain visible away from the reflected horizon too.
	float ripple = sin(a + 0.6 * sin(b)) * sin(b * 1.3);
	float ripple_fade = 1.0 - smoothstep(100.0, 450.0, length(VERTEX));
	ALBEDO *= 0.85 + 0.20 * ripple * ripple_fade;
	ALPHA = min(0.99, mix(0.72, 0.98, deep) + foam * 0.2);
	ROUGHNESS = 0.48;
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
