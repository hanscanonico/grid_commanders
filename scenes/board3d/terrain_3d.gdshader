// The 3D board's ground, props and buildings. The colour is the mesh's own
// (sRGB vertex colours, converted the way StandardMaterial3D converts them);
// on top of it go two things read off the 2D board in map space:
//
// - `overlay`: the 2D board's flat marks (move, attack and threat ranges, the
//   path arrow, capture pips, objective marks, combat flashes) rendered from
//   above into a texture and laid onto every upward-facing surface;
// - `fog_cells`: one texel per cell, lit where the viewer cannot see.
shader_type spatial;

uniform sampler2D overlay : source_color, filter_linear, repeat_disable;
uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform vec2 map_cells = vec2(1.0);
uniform float overlay_strength = 1.0;
uniform bool water = false;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise in [0, 1]: random heights on a lattice, eased between.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(
			pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)),
			COLOR.rgb * (1.0 / 12.92),
			lessThan(COLOR.rgb, vec3(0.04045))
		);
	}
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec2 uv = world_pos.xz / map_cells;
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	if (water) {
		// Read in world space, so the water runs on across cell seams, and built
		// from a drifting value noise and three waves at angles and spacings no
		// cell lines up with, so nothing repeats from one cell to the next.
		vec2 p = world_pos.xz;
		float swell = value_noise(p * 0.55 + vec2(TIME * 0.06, TIME * 0.04)) * 2.0 - 1.0;
		float waves = (
			sin(dot(p, vec2(3.7, 1.6)) + TIME * 1.1)
			+ sin(dot(p, vec2(-1.9, 4.1)) - TIME * 0.8)
			+ sin(dot(p, vec2(4.6, -2.9)) + TIME * 1.3)
		) / 3.0;
		float glint = smoothstep(0.6, 0.85, waves + 0.3 * swell);
		col = col * (1.0 + 0.09 * swell + 0.04 * waves) + vec3(0.12, 0.15, 0.17) * glint;
		ROUGHNESS = 0.55;
		SPECULAR = 0.3;
	} else {
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
	}
	// The overlay is rendered over a clear background, so its colour arrives
	// already multiplied by its alpha.
	vec4 mark = texture(overlay, uv) * inside;
	float up = smoothstep(0.45, 0.85, world_normal.y) * overlay_strength;
	col = col * (1.0 - mark.a * up) + mark.rgb * up;
	float fogged = texture(fog_cells, uv).r * inside;
	col = mix(col, col * vec3(0.4, 0.43, 0.55), fogged);
	ALBEDO = col;
}
