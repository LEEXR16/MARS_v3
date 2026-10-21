// Planet ring on a flat plane: radial bands with gaps.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec3 col_a : source_color = vec3(0.82, 0.70, 0.52);
uniform vec3 col_b : source_color = vec3(0.42, 0.34, 0.25);
uniform float inner = 0.52;
uniform float light = 0.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r < inner || r > 1.0) {
		discard;
	}
	float t = (r - inner) / (1.0 - inner);
	float bands = 0.5 + 0.25 * sin(t * 95.0) + 0.25 * sin(t * 37.0 + 1.0);
	float gap = (1.0 - smoothstep(0.0, 0.025, abs(t - 0.63))) + (1.0 - smoothstep(0.0, 0.012, abs(t - 0.86))) * 0.7;
	ALBEDO = mix(col_b, col_a, bands) * light;
	ALPHA = (0.25 + 0.6 * bands) * smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.92, 1.0, t)) * (1.0 - gap);
}
