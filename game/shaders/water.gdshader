shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

void vertex() {
	VERTEX.y += sin(TIME * 0.8 + VERTEX.x * 0.02) * 0.3 + cos(TIME * 0.6 + VERTEX.z * 0.03) * 0.3;
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple = sin(w.x * 0.08 + TIME) * cos(w.z * 0.07 - TIME * 0.7);
	ALBEDO = mix(vec3(0.05, 0.22, 0.38), vec3(0.1, 0.35, 0.5), ripple * 0.5 + 0.5);
	ALPHA = 0.82;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
