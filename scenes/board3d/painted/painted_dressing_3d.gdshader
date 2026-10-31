// The low dressing scattered on the grass: its mesh's own colours, and the
// board's fog over them like everything else.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform bool on_board = false;
uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform vec2 map_cells = vec2(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (on_board) {
		vec2 uv = world_pos.xz / map_cells;
		float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
		float fogged = texture(fog_cells, uv).r * inside;
		col = mix(col, col * vec3(0.4, 0.43, 0.55), fogged);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
