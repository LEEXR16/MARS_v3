// Reactor shield bubble: fresnel rim, faint lattice, scan line, hit flash.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.65, 1.0);
uniform float strength = 1.0;
uniform float flash = 0.0;

varying vec3 lp;

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	vec3 p = lp * 9.0;
	float l1 = abs(fract(dot(p, vec3(1.0, 0.0, 0.0)) + 0.5) - 0.5);
	float l2 = abs(fract(dot(p, vec3(-0.5, 0.866, 0.0)) + 0.5) - 0.5);
	float l3 = abs(fract(dot(p, vec3(-0.5, -0.866, 0.3)) + 0.5) - 0.5);
	float grid = (1.0 - smoothstep(0.0, 0.06, min(l1, min(l2, l3))));
	float scan = smoothstep(0.92, 1.0, sin(lp.y * 9.0 - TIME * 2.5));
	float a = (fres * 1.3 + grid * 0.16 * (0.3 + fres) + scan * 0.1) * strength + flash * (0.35 + fres);
	ALBEDO = color * a;
}
