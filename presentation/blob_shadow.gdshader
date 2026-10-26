shader_type spatial;
// Soft contact shadow under a character when realtime shadows are off
// (BlobShadows): black, alpha-blended, strongest at the centre. (Not
// blend_mul: the Mobile renderer stores colours scaled, so multiplying by
// white still darkened the whole quad.) INSTANCE_CUSTOM.a fades it with
// height above the floor.
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float darkness = 0.6;

varying float strength;

void vertex() {
	strength = INSTANCE_CUSTOM.a;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, r)) * darkness * strength;
}
