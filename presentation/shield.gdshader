// Shield crackle (PLAN §3.9): a hex-grid shell that flashes around a player
// whose shield takes a hit, brightest on the side that was hit. Additive,
// unshaded and branch-free, so it also runs on the Compatibility renderer.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float strength = 0.0;
uniform vec3 hit_dir = vec3(0.0, 0.0, 1.0);  // object space, towards the attacker

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// Offset rows of cells: a cheap hexagonal look.
	vec2 p = vec2(atan(obj.x, obj.z) * 2.6, obj.y * 5.0);
	p.x += 0.5 * mod(floor(p.y), 2.0);
	vec2 g = abs(fract(p) - 0.5);
	float edge = smoothstep(0.40, 0.48, max(g.x * 1.15, g.y));
	float facing = smoothstep(-0.3, 1.0, dot(normalize(obj - vec3(0.0, 0.9, 0.0)), normalize(hit_dir)));
	float a = strength * (fresnel * 0.5 + edge * (0.25 + facing));
	ALBEDO = color.rgb * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
