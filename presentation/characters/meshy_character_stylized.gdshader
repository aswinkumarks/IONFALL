shader_type spatial;
// Meshy characters (MeshyRig), Low quality: the clean stylized look. One
// small posterized texture (flat colour regions, baked by
// tools/bake_character_tiers.gd) in the player's colour, two-band cel
// lighting and a strong rim light; no normal or roughness maps.
#include "res://presentation/characters/meshy_team.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 team_color : source_color = vec3(0.31, 0.89, 1.0);
uniform float plate_tint = 0.6;
uniform float rim = 0.7;
uniform float floor_light = 0.08;
uniform float glow = 0.0;
uniform float flash = 0.0;

void fragment() {
	float strip;
	ALBEDO = team_albedo(texture(albedo_tex, UV).rgb, team_color, plate_tint, strip);
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
	EMISSION = team_color * strip * (1.6 + glow * 2.0) + team_color * glow * 0.25 + vec3(flash * 1.5)
			+ rim_and_floor(ALBEDO, NORMAL, VIEW, team_color, rim, floor_light);
}

void light() {
	// Lit or in shade, with a soft step between.
	float lit = smoothstep(0.0, 0.08, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += (0.25 + 0.75 * lit) * ATTENUATION * LIGHT_COLOR / PI;
}
