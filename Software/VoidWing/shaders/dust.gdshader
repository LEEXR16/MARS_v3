// Space dust: specks in a box that wraps around the camera, stretched along the
// ship's velocity so speed reads at a glance.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 cam_pos = vec3(0.0);
uniform vec3 vel = vec3(0.0);
uniform float box = 240.0;

varying float fade;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 p = cam_pos + mod(o - cam_pos, box) - box * 0.5;
	vec4 cv = VIEW_MATRIX * vec4(p, 1.0);
	vec3 along = (VIEW_MATRIX * vec4(vel * 0.022, 0.0)).xyz;
	float len = length(along);
	vec3 dir = len > 1e-4 ? along / len : vec3(0.0, 1.0, 0.0);
	vec3 side = normalize(cross(dir, vec3(0.0, 0.0, 1.0)) + vec3(1e-5));
	vec3 vpos = cv.xyz + side * VERTEX.x * 0.09 + dir * (VERTEX.y + 0.5) * max(len, 0.12);
	float dist = length(cv.xyz);
	fade = (1.0 - smoothstep(box * 0.25, box * 0.5, dist)) * smoothstep(3.0, 10.0, dist);
	POSITION = PROJECTION_MATRIX * vec4(vpos, 1.0);
}

void fragment() {
	float e = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = vec3(0.8, 0.82, 0.85) * e * fade * 0.32;
}
