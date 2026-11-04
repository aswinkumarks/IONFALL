// Shared by the Meshy character shaders (MeshyRig): the player's colour on
// the armour. Blue/cyan panels and light strips take its hue (value kept)
// and the strips glow; light, unsaturated armour plates are tinted with it,
// so a team reads from a distance while dark undersuits stay dark.

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

// `base` (linear) in team colour `team_color`; `strip` = how much it is a
// light strip (0..1), for the glow.
vec3 team_albedo(vec3 base, vec3 team_color, float plate_tint, out float strip) {
	vec3 hsv = rgb2hsv(pow(base, vec3(1.0 / 2.2)));
	// Blue/cyan, saturated texels are the paint and the light strips.
	float blue = smoothstep(0.08, 0.02, abs(hsv.x - 0.58)) * smoothstep(0.25, 0.45, hsv.y);
	vec3 team = rgb2hsv(team_color);
	vec3 painted = pow(hsv2rgb(vec3(team.x, mix(hsv.y, team.y, 0.6), hsv.z)), vec3(2.2));
	float plate = smoothstep(0.42, 0.62, hsv.z) * (1.0 - smoothstep(0.12, 0.3, hsv.y)) * (1.0 - blue);
	vec3 team_lin = pow(hsv2rgb(vec3(team.x, team.y * 0.85, 1.0)), vec3(2.2));
	strip = blue * smoothstep(0.5, 0.85, hsv.z);
	return mix(mix(base, painted, blue), base * team_lin * 1.15, plate * plate_tint);
}

// A team-coloured edge light (silhouettes read against any background) and
// an ambient floor (dark corners never turn a player into a black shape).
vec3 rim_and_floor(vec3 albedo, vec3 normal, vec3 view, vec3 team_color, float rim, float floor_light) {
	float edge = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
	return team_color * edge * rim + albedo * floor_light;
}
