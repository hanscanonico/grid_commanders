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
		float ripple = sin(world_pos.x * 6.5 + TIME * 1.5) * sin(world_pos.z * 5.5 - TIME * 1.2);
		float glint = smoothstep(0.82, 0.98, ripple);
		col = col * (1.0 + 0.07 * ripple) + vec3(0.18, 0.22, 0.25) * glint;
		ROUGHNESS = 0.3;
		SPECULAR = 0.6;
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
