// Comfort vignette: darkens the screen edges, more while the view turns fast.
// Less motion in peripheral vision means less motion sickness.
shader_type canvas_item;

uniform float strength = 0.3;
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p) / (0.5 * length(vec2(aspect, 1.0)));
	float v = smoothstep(0.42, 1.05, r);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v * strength * 1.7, 0.0, 0.85));
}
