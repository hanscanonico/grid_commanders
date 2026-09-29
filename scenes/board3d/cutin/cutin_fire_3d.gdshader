// The 3D cut-in's fire and light: soft balls added over what is behind them.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://scenes/board3d/cutin/cutin_soft_3d.gdshaderinc"
