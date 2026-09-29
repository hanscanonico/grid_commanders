// A general projected onto a board their army is not on: the figure's own
// vertex colours washed into `tint`, cut by scanlines running up the world's
// Y and flickering, translucent and seen from both sides.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float alpha = 0.7;
// The figure's own fade, for walking in and out: multiplies `alpha`.
uniform float fade = 1.0;
// Scanlines per world unit, and how fast they climb.
uniform float lines = 90.0;
uniform float climb = 0.6;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float scan = step(0.45, fract(world_y * lines - TIME * climb));
	float flicker = 0.92 + 0.08 * sin(TIME * 41.0) * sin(TIME * 13.0);
	float value = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 lit = tint.rgb * (0.55 + 0.9 * value);
	ALBEDO = lit * (0.7 + 0.3 * scan) * flicker;
	ALPHA = clamp(alpha * fade * (0.65 + 0.35 * scan) * flicker, 0.0, 1.0);
}
