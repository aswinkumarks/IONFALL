shader_type spatial;
// Meshy characters (MeshyRig), High and Medium quality: the model's PBR
// textures in the player's colour (meshy_team.gdshaderinc), with a rim light.
// glow = spawn-protection shimmer, flash = hit flash.
#include "res://presentation/characters/meshy_team.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic;  // glTF: G roughness, B metallic
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 team_color : source_color = vec3(0.31, 0.89, 1.0);
uniform float plate_tint = 0.6;  // how strongly light plates take the colour
uniform float rim = 0.35;
uniform float floor_light = 0.04;
uniform float glow = 0.0;
uniform float flash = 0.0;

void fragment() {
	float strip;
	ALBEDO = team_albedo(texture(albedo_tex, UV).rgb, team_color, plate_tint, strip);
	vec4 mr = texture(mr_tex, UV);
	ROUGHNESS = mr.g;
	METALLIC = mr.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	EMISSION = team_color * strip * (1.6 + glow * 2.0) + team_color * glow * 0.25 + vec3(flash * 1.5)
			+ rim_and_floor(ALBEDO, NORMAL, VIEW, team_color, rim, floor_light);
}
