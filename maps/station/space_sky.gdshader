shader_type sky;
// Meridian Station sky: deep space with a star field, the nebula glow of the
// star the station orbits (matches the sun direction) and a planet limb
// below the horizon. Cheap: a few hashes per pixel, rendered to the radiance
// cubemap only when it changes.

uniform vec3 space_color : source_color = vec3(0.01, 0.015, 0.03);
uniform vec3 nebula_color : source_color = vec3(0.1, 0.18, 0.35);
uniform vec3 planet_color : source_color = vec3(0.12, 0.3, 0.5);
uniform vec3 rim_color : source_color = vec3(0.45, 0.8, 1.0);
uniform float star_density = 0.004;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = space_color;
	// Stars: one cell per direction bucket; a few are bright.
	vec3 p = d * 320.0;
	vec3 cell = floor(p);
	float h = hash(cell);
	if (h < star_density) {
		float b = hash(cell + 7.0);
		float r = length(fract(p) - 0.5);
		col += vec3(0.6 + 0.4 * b, 0.7 + 0.3 * b, 1.0) * (0.3 + 2.0 * b * b) * smoothstep(0.3, 0.0, r);
	}
	// Soft glow around the sun direction.
	if (LIGHT0_ENABLED) {
		float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += nebula_color * pow(s, 4.0) * 0.8 + LIGHT0_COLOR * pow(s, 400.0) * 6.0;
	}
	// Planet: a huge sphere below; bright atmospheric rim at its edge.
	float horizon = d.y + 0.18;
	if (horizon < 0.0) {
		col = mix(planet_color * 0.35, planet_color, clamp(-horizon * 3.0, 0.0, 1.0) * 0.4);
		col += rim_color * exp(horizon * 40.0) * 0.8;
	} else {
		col += rim_color * exp(-horizon * 25.0) * 0.25;
	}
	COLOR = col;
}
