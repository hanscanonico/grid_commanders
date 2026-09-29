// The cut-in stage's water: calm, broad swells and a few soft highlights,
// driven by `clock`, which the director sets from its own cut-in clock — so a
// posed frame over the sea is the same frame every run. The board keeps its
// own busier water (terrain_3d.gdshader).
shader_type spatial;
render_mode cull_back;

uniform float clock = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(
			pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)),
			COLOR.rgb * (1.0 / 12.92),
			lessThan(COLOR.rgb, vec3(0.04045))
		);
	}
}

void fragment() {
	vec2 p = world_pos.xz;
	float swell = sin(p.x * 0.55 + p.y * 0.3 + clock * 0.9)
		+ 0.6 * sin(p.x * -0.25 + p.y * 0.7 - clock * 0.6)
		+ 0.35 * sin(p.x * 1.1 - p.y * 0.9 + clock * 1.3);
	float shade = swell / 1.95;
	float glint = smoothstep(0.72, 0.95, shade) * 0.5;
	vec3 col = COLOR.rgb * (1.0 + 0.06 * shade) + vec3(0.12, 0.15, 0.17) * glint;
	ALBEDO = col;
	ROUGHNESS = 0.5;
	SPECULAR = 0.35;
}
