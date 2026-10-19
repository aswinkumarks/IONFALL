shader_type spatial;
// Sentinel armour: the model's PBR textures, with its blue panels and light
// strips recoloured to the player's colour (hue swap, value kept), the
// strips glowing. glow = spawn-protection shimmer, flash = hit flash.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic;  // glTF: G roughness, B metallic
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 team_color : source_color = vec3(0.31, 0.89, 1.0);
uniform float glow = 0.0;
uniform float flash = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-6)), d / (q.x + 1e-6), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(pow(base, vec3(1.0 / 2.2)));
	// Blue/cyan, saturated texels are the paint and the light strips.
	float blue = smoothstep(0.08, 0.02, abs(hsv.x - 0.58)) * smoothstep(0.25, 0.45, hsv.y);
	vec3 team = rgb2hsv(team_color);
	vec3 painted = pow(hsv2rgb(vec3(team.x, mix(hsv.y, team.y, 0.6), hsv.z)), vec3(2.2));
	ALBEDO = mix(base, painted, blue);
	vec4 mr = texture(mr_tex, UV);
	ROUGHNESS = mr.g;
	METALLIC = mr.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	float strip = blue * smoothstep(0.5, 0.85, hsv.z);
	EMISSION = team_color * strip * (1.6 + glow * 2.0) + team_color * glow * 0.25 + vec3(flash * 1.5);
}
