// Blends Black & White's own ground materials per triangle corner, like the original landscape.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray mats : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 80.0;
uniform vec3 deep : source_color = vec3(0.04, 0.16, 0.26);

varying vec3 ma;
varying vec3 mb;
varying vec3 cf;
varying vec3 bary;
varying vec3 wpos;

void vertex() {
	ma = CUSTOM0.xyz;
	mb = CUSTOM1.xyz;
	cf = CUSTOM2.xyz;
	bary = CUSTOM3.xyz;
	wpos = VERTEX;
}

vec3 corner(vec2 uv, float a, float b, float w) {
	vec3 ca = texture(mats, vec3(uv, round(a))).rgb;
	vec3 cb = texture(mats, vec3(uv, round(b))).rgb;
	return mix(cb, ca, w);
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	vec3 c = corner(uv, ma.x, mb.x, cf.x) * bary.x
		+ corner(uv, ma.y, mb.y, cf.y) * bary.y
		+ corner(uv, ma.z, mb.z, cf.z) * bary.z;
	// under the sea the ground fades into the colour of the sea bed
	ALBEDO = mix(deep, c, smoothstep(0.1, 1.8, wpos.y));
	ROUGHNESS = 1.0;
}
