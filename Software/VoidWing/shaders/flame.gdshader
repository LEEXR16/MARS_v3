// Engine exhaust cone (mesh runs from z = 0 at the nozzle to z = 1 at the tip).
// Fades out when seen along its axis: end-on, the whole additive cone would stack
// into one over-bright blob (the glowing nozzle disc shows the engine instead).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 core : source_color = vec3(0.80, 0.92, 1.0);
uniform vec3 edge : source_color = vec3(0.25, 0.50, 1.0);
uniform float intensity = 2.5;
instance uniform float throttle = 1.0;

varying float along;
varying vec3 axis_v;

void vertex() {
	along = clamp(VERTEX.z, 0.0, 1.0);
	axis_v = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	float flick = 0.85 + 0.15 * sin(TIME * 70.0 + along * 23.0);
	float end_on = abs(dot(normalize(axis_v), VIEW));
	float side_view = 1.0 - smoothstep(0.55, 0.95, end_on);
	float a = pow(1.0 - along, 1.6) * pow(f, 1.3) * flick * side_view;
	vec3 c = mix(edge, core, pow(f, 2.0) * (1.0 - along));
	ALBEDO = c * a * intensity * throttle;
}
