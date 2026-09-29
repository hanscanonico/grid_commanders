// A general's portrait projected over their post: upright, turned to the lens,
// drawn in from the bottom as it switches on, in scanlines and the army's tint.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D portrait : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
// How much of the picture is drawn in, from the bottom up: 0 none, 1 all.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float clock = 0.0;
// A voice with no seat on the board comes in over a worse line.
uniform float static_noise : hint_range(0.0, 1.0) = 0.0;
uniform vec2 texels = vec2(110.0, 134.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float up = 1.0 - UV.y;
	if (up > reveal) {
		discard;
	}
	vec2 texel = floor(UV * texels);
	vec3 art = texture(portrait, UV).rgb;
	float scan = mod(texel.y, 2.0) < 1.0 ? 1.0 : 0.74;
	float sweep = smoothstep(0.1, 0.0, abs(fract(up * 0.7 - clock * 0.35) - 0.5) - 0.4);
	float drawing = step(reveal, 0.999) * smoothstep(0.08, 0.0, reveal - up);
	float rim = min(min(texel.x, texels.x - 1.0 - texel.x), min(texel.y, texels.y - 1.0 - texel.y));
	float border = step(rim, 0.5);
	vec3 color = mix(art, art * 0.5 + tint.rgb * 0.6, 0.3) * scan;
	color += tint.rgb * (sweep * 0.16 + drawing * 1.4 + border * 0.9);
	float row_tear = static_noise * step(0.86, hash(floor(clock * 20.0) + texel.y * 0.37));
	color = mix(color, tint.rgb * 1.3, row_tear * 0.8);
	float blink = 1.0 - static_noise * 0.35 * step(0.9, hash(floor(clock * 24.0)));
	ALBEDO = color;
	ALPHA = fade * 0.92 * blink;
}
