// The board's flocked ground and resin water. A top face wears a tile chosen by
// the 3x3 class lattice read through a little noise, so a road's edge wanders
// where the mesh's squares run straight; a wall wears the earth.
shader_type spatial;

uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_floor : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_classes : filter_nearest, repeat_disable;
uniform sampler2D land_mask : filter_linear_mipmap, repeat_disable;
uniform vec2 map_cells = vec2(1.0);
uniform bool water = false;
// On the board it wears the flat board's marks and its fog; on a cut-in, neither.
uniform bool on_board = false;
uniform sampler2D overlay : source_color, filter_linear, repeat_disable;
uniform sampler2D fog_cells : filter_nearest, repeat_disable;

const float TILE_CELLS = 2.7;
const vec3 DEEP = vec3(0.03, 0.2, 0.46);
const vec3 SHALLOW = vec3(0.09, 0.52, 0.6);
const vec3 FOAM = vec3(0.86, 0.92, 0.92);

// In the mesh's own frame and before the wander, so the tiles and the marks read
// the true grid wherever the mesh stands.
varying vec3 rest_pos;
varying vec3 world_normal;
varying vec3 vertex_colour;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// The class at a point: the mesher's sub-squares, a 0.3/0.4/0.3 cut of each cell.
int class_at(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = p - cell;
	ivec2 sub = ivec2(f.x < 0.3 ? 0 : (f.x < 0.7 ? 1 : 2), f.y < 0.3 ? 0 : (f.y < 0.7 ? 1 : 2));
	ivec2 at = clamp(
		ivec2(cell) * 3 + sub, ivec2(0), ivec2(map_cells) * 3 - ivec2(1)
	);
	return int(texelFetch(ground_classes, at, 0).r * 255.0 + 0.5);
}

vec3 tile_of(int which, vec2 uv) {
	if (which == 1) {
		return texture(forest_floor, uv).rgb;
	}
	if (which == 2) {
		return texture(road, uv).rgb;
	}
	if (which == 3) {
		return texture(sand, uv).rgb;
	}
	if (which == 4) {
		return texture(earth, uv).rgb;
	}
	return texture(grass, uv).rgb;
}

// A slow wander of every corner of land and water alike, so no edge runs dead
// straight. The tiles and the board's marks still read the unmoved grid.
vec2 wander(vec2 p) {
	return (vec2(value_noise(p * 1.7), value_noise(p * 1.7 + vec2(23.0, 41.0))) - 0.5) * 0.16;
}

void vertex() {
	rest_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_colour = mix(
		pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)),
		COLOR.rgb * (1.0 / 12.92),
		lessThan(COLOR.rgb, vec3(0.04045))
	);
	if (VERTEX.y <= 0.02) {
		VERTEX.xz += wander(VERTEX.xz);
	}
}

void fragment() {
	vec2 p = rest_pos.xz;
	vec3 col;
	if (water) {
		float near_land = textureLod(land_mask, p / map_cells, 0.0).r;
		// The same field heavily blurred: high in a narrow river, low on the open sea.
		float enclosed = textureLod(land_mask, p / map_cells, 4.0).r;
		float swell = value_noise(p * 0.5 + vec2(TIME * 0.05, TIME * 0.03)) * 0.6
			+ value_noise(p * 1.3 - vec2(TIME * 0.04, 0.0)) * 0.4;
		float ripple = value_noise(p * 5.0 + vec2(TIME * 0.2, -TIME * 0.16)) * 0.6
			+ value_noise(p * 11.0 + vec2(-TIME * 0.3, TIME * 0.22)) * 0.4;
		col = mix(DEEP, SHALLOW, smoothstep(0.02, 0.55, near_land));
		col *= 0.86 + 0.28 * swell;
		float lines = sin(near_land * 34.0 - TIME * 0.9 + swell * 4.0);
		float band = smoothstep(0.8, 0.97, lines);
		band *= smoothstep(0.05, 0.12, near_land) * smoothstep(0.3, 0.2, near_land);
		band *= smoothstep(0.55, 0.35, enclosed);
		float edge = smoothstep(0.8, 0.92, near_land + (ripple - 0.5) * 0.14);
		col = mix(col, FOAM, clamp(max(band * 0.55 * smoothstep(0.35, 0.65, ripple), edge * 0.9), 0.0, 1.0));
		col += vec3(0.018, 0.026, 0.03) * smoothstep(0.5, 0.8, ripple);
		ROUGHNESS = 0.32;
		SPECULAR = 0.5;
	} else if (rest_pos.y > 0.02 || (world_normal.y > 0.5 && class_at(p) == 5)) {
		// What the mesher builds and no tile dresses: a bridge's deck, a reef's rocks.
		col = vertex_colour * (0.85 + 0.3 * value_noise(p * 24.0));
		ROUGHNESS = 0.85;
		SPECULAR = 0.15;
	} else if (world_normal.y > 0.5) {
		vec2 warp = vec2(value_noise(p * 7.0), value_noise(p * 7.0 + vec2(31.0, 17.0))) - 0.5;
		warp += (vec2(value_noise(p * 19.0 + 5.0), value_noise(p * 19.0 + 11.0)) - 0.5) * 0.4;
		vec2 at = p + warp * 0.11;
		int which = class_at(at);
		col = tile_of(which, p / TILE_CELLS);
		// Breaks the tile's repeat, and shades the board in soft broad patches.
		float patches = value_noise(p * 0.65) * 0.6 + value_noise(p * 1.7 + 9.0) * 0.4;
		col *= 0.8 + 0.42 * patches;
		// A painted shadow line where the road's bed meets the flock.
		if (which == 2) {
			float rim = 0.0;
			for (int i = 0; i < 4; i++) {
				vec2 dir = vec2(cos(float(i) * 1.5708), sin(float(i) * 1.5708));
				rim = max(rim, class_at(at + dir * 0.045) != 2 ? 1.0 : 0.0);
			}
			col *= 1.0 - 0.34 * rim;
		} else if (which == 0 || which == 1) {
			float rim = 0.0;
			for (int i = 0; i < 4; i++) {
				vec2 dir = vec2(cos(float(i) * 1.5708), sin(float(i) * 1.5708));
				rim = max(rim, class_at(at + dir * 0.03) == 2 ? 1.0 : 0.0);
			}
			col = mix(col, col * vec3(1.15, 1.08, 0.72), 0.4 * rim);
		}
		ROUGHNESS = 0.95;
		SPECULAR = 0.08;
	} else {
		vec2 wall_uv = vec2(p.x + p.y, rest_pos.y) / TILE_CELLS;
		col = texture(earth, wall_uv).rgb;
		col *= mix(0.42, 1.05, smoothstep(-0.55, 0.0, rest_pos.y));
		ROUGHNESS = 0.95;
		SPECULAR = 0.05;
	}
	if (on_board) {
		vec2 uv = p / map_cells;
		float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
		vec4 mark = texture(overlay, uv) * inside;
		float up = smoothstep(0.45, 0.85, world_normal.y);
		col = col * (1.0 - mark.a * up) + mark.rgb * up;
		float fogged = texture(fog_cells, uv).r * inside;
		col = mix(col, col * vec3(0.4, 0.43, 0.55), fogged);
	}
	ALBEDO = col;
}
