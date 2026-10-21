// Bright additive bolt (lasers, missile exhaust). HDR so it blooms.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 color : source_color = vec3(0.5, 0.8, 1.0);
uniform float energy = 6.0;

void fragment() {
	float f = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALBEDO = color * energy * (0.3 + 0.7 * f);
}
