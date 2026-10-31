// A far-off painted model that wears only its bake: the stage's clouds, which the
// sun would otherwise cut into hard facets at this distance.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform sampler2D paint : source_color, filter_linear_mipmap;

void fragment() {
	ALBEDO = texture(paint, UV).rgb;
}
