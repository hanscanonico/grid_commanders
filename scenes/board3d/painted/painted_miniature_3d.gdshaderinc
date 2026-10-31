// A baked painted miniature. The texture's alpha marks what wears the army's
// colour, and there its grey is a place on the army's ramp, so one texture
// dresses every army and a shadow on red stays red.
//
// Parts move here rather than on a skeleton, so a model stays one draw call: the
// second UV says which motion a vertex follows and about which pivot
// (`generators/models/modelgen/kit.py`).

// `generators/models` lifts the mask off zero, so no importer drops the paint.
const float MASK_FLOOR = 0.25;
const float WHEEL = 1.0;
const float LEG_A = 2.0;
const float LEG_B = 3.0;
const float ARM_A = 4.0;
const float ARM_B = 5.0;
const float RECOIL = 6.0;
const float TREAD = 7.0;
// Radians a road wheel turns per cell driven, and a limb's swing.
const float WHEEL_TURN = 18.0;
const float SWING = 0.62;
const float AIM_LIFT = 1.15;
const float TREAD_BANDS = 26.0;

uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normals : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 ramp_dark : source_color;
uniform vec3 ramp_base : source_color;
uniform vec3 ramp_light : source_color;
uniform sampler2D emblem : source_color, filter_linear_mipmap, repeat_disable;
// Where the army's badge is painted, seen from straight above, in the model's frame.
uniform vec3 emblem_centre = vec3(0.0);
uniform float emblem_radius = 0.0;

// What the game drives: how far it has rolled, in cells; the march's phase; how
// far the arms are raised to fire; how far the gun has kicked.
uniform float roll = 0.0;
uniform float gait = 0.0;
uniform float aim = 0.0;
uniform float recoil = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float alpha_scale = 1.0;
uniform vec3 flash_colour = vec3(1.0);
uniform float flash = 0.0;

// A building or a prop on the board: it wears the board's marks and its fog.
uniform bool on_board = false;
uniform sampler2D overlay : source_color, filter_linear, repeat_disable;
uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform vec2 map_cells = vec2(1.0);

varying vec3 model_pos;
varying vec3 model_normal;
varying vec3 world_pos;
varying vec3 world_normal;
varying float tread;

vec2 turned(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
}

vec3 on_ramp(float value) {
	if (value < 0.3) {
		return ramp_dark * mix(0.5, 1.0, value / 0.3);
	}
	if (value < 0.62) {
		return mix(ramp_dark, ramp_base, (value - 0.3) / 0.32);
	}
	if (value < 0.95) {
		return mix(ramp_base, ramp_light, (value - 0.62) / 0.33);
	}
	return mix(ramp_light, vec3(1.0), clamp((value - 0.95) / 0.8, 0.0, 0.6));
}

void vertex() {
	model_pos = VERTEX;
	model_normal = NORMAL;
	float kind = floor(UV2.x / 10.0);
	tread = kind == TREAD ? 1.0 : 0.0;
	if (kind >= WHEEL && kind <= ARM_B) {
		vec2 pivot = vec2(UV2.x - kind * 10.0 - 5.0, 1.0 - UV2.y);
		float angle = 0.0;
		if (kind == WHEEL) {
			angle = roll * WHEEL_TURN;
		} else if (kind == LEG_A) {
			angle = -sin(gait) * SWING;
		} else if (kind == LEG_B) {
			angle = sin(gait) * SWING;
		} else if (kind == ARM_A) {
			angle = sin(gait) * SWING * (1.0 - aim) - aim * AIM_LIFT;
		} else {
			angle = -sin(gait) * SWING * (1.0 - aim) - aim * AIM_LIFT;
		}
		VERTEX.xy = pivot + turned(VERTEX.xy - pivot, angle);
		NORMAL.xy = turned(NORMAL.xy, angle);
		TANGENT.xy = turned(TANGENT.xy, angle);
		BINORMAL.xy = turned(BINORMAL.xy, angle);
	} else if (kind == RECOIL) {
		VERTEX.x -= recoil;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 texel = texture(paint, UV);
	float mask = clamp((texel.a - MASK_FLOOR) / (1.0 - MASK_FLOOR), 0.0, 1.0);
	vec3 col = mix(texel.rgb, on_ramp(texel.g), mask);
	if (emblem_radius > 0.0 && model_normal.y > 0.8 && model_pos.y > emblem_centre.y - 0.02) {
		vec2 at = (model_pos.xz - emblem_centre.xz) / (2.0 * emblem_radius) + 0.5;
		if (at.x > 0.0 && at.x < 1.0 && at.y > 0.0 && at.y < 1.0) {
			vec4 badge = texture(emblem, at);
			col = mix(col, badge.rgb * (0.55 + 0.75 * texel.g), badge.a * 0.92);
		}
	}
	if (tread > 0.5) {
		float band = step(0.5, fract((model_pos.x + roll) * TREAD_BANDS));
		col *= mix(0.72, 1.12, band);
	}
	col *= tint;
	if (on_board) {
		vec2 uv = world_pos.xz / map_cells;
		float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
		vec4 mark = texture(overlay, uv) * inside;
		float up = smoothstep(0.45, 0.85, world_normal.y);
		col = col * (1.0 - mark.a * up) + mark.rgb * up;
		float fogged = texture(fog_cells, uv).r * inside;
		col = mix(col, col * vec3(0.4, 0.43, 0.55), fogged);
	}
	ALBEDO = col;
	NORMAL_MAP = texture(normals, UV).rgb;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	EMISSION = flash_colour * flash;
#ifdef FADING
	ALPHA = alpha_scale;
#endif
}
