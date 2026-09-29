// Light added over the board, never lit by it: the projector's beam, the disc it
// rises from, and the shockwave a Command Power sends across the field.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, shadows_disabled, depth_draw_never;

// 0 beam: a cone brightest where it meets the screen, so a beam rising through
// a roof reads as the screen's own light. 1 disc: a core and a rim on a plane.
// 2 ring: one band at `radius` on a plane.
uniform int shape = 0;
uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float strength = 1.0;
uniform float clock = 0.0;
// The beam's height, and the plane's half-size, in the mesh's own units.
uniform float extent = 1.0;
// The ring's radius and width, as fractions of the plane's half-size.
uniform float radius = 0.0;
uniform float width = 0.04;
// The ground a ring may light, in world x/z (min x, min z, max x, max z): the
// board, so a shockwave stops at the diorama's rim rather than hanging over
// the table.
uniform vec4 bounds = vec4(-1e6, -1e6, 1e6, 1e6);

varying vec3 local;
varying vec3 world;

void vertex() {
	local = VERTEX;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float glow = 0.0;
	if (shape == 0) {
		float height = clamp(local.y / extent + 0.5, 0.0, 1.0);
		float streak = 0.75 + 0.25 * sin(atan(local.z, local.x) * 9.0 + clock * 2.0);
		glow = (0.15 + 0.85 * height * height) * streak * 0.5;
	} else {
		float r = length(local.xz) / extent;
		if (shape == 1) {
			float core = smoothstep(0.9, 0.0, r) * 0.5;
			float rim = smoothstep(0.12, 0.0, abs(r - 0.8));
			glow = (core + rim) * (0.8 + 0.2 * sin(clock * 6.0));
		} else {
			bool inside = all(greaterThanEqual(world.xz, bounds.xy)) && all(lessThanEqual(world.xz, bounds.zw));
			glow = inside ? smoothstep(width, 0.0, abs(r - radius)) * step(r, 1.0) : 0.0;
		}
	}
	ALBEDO = tint.rgb;
	ALPHA = clamp(glow * strength, 0.0, 1.0);
}
