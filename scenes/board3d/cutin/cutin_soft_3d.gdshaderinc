// Shared by the cut-in's soft smoke and soft fire: smooth balls whose edge
// melts away with the angle to the lens, so a puff reads as a puff rather than
// a faceted rock. Colour and density are the vertex colour's, set per frame
// off the cut-in's clock; nothing here reads TIME.

// How sharply the edge falls off: higher is a smaller, harder core.
uniform float softness = 1.6;
// How much brighter the top of a puff is than its underside.
uniform float top_light = 0.0;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(
			pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)),
			COLOR.rgb * (1.0 / 12.92),
			lessThan(COLOR.rgb, vec3(0.04045))
		);
	}
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, -1.0, 1.0);
	ALBEDO = COLOR.rgb * (1.0 - top_light * 0.5 + top_light * 0.5 * up);
	ALPHA = clamp(COLOR.a * pow(facing, softness), 0.0, 1.0);
}
