// The same miniature while it fades. It writes its depth, so it draws as one
// silhouette rather than showing its own far side through itself.
shader_type spatial;
render_mode blend_mix, depth_draw_always;

#define FADING
#include "res://scenes/board3d/painted/painted_miniature_3d.gdshaderinc"
