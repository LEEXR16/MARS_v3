// Painted spaceship hull: staggered panel lines, per-panel tint and roughness,
// an optional accent stripe, lit windows (capital ships), weathering grime and
// Ranger-style cockpit glazing: irregular polygon panes (Voronoi cells) inside an
// oval on the top deck.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.82, 0.84, 0.86);
uniform vec3 accent_color : source_color = vec3(0.95, 0.70, 0.16);
uniform float metal = 0.3;
uniform float rough = 0.4;
uniform float panel_scale = 1.5;
uniform float line_dark = 0.45;
uniform float tint_var = 0.06;
// accent stripe: dot(local position, stripe_axis) between stripe_a and stripe_b
uniform vec3 stripe_axis = vec3(1.0, 0.0, 0.0);
uniform float stripe_a = 1e6;
uniform float stripe_b = 1e6;
uniform float stripe_emit = 0.0;
// lit windows
uniform float window_amount = 0.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.78, 0.5);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// weathering: soft streaks along the ship (z) and dark grime in the panel seams
uniform float grime = 0.0;
// glazing: panes in the oval (centre, radii) in local x / z on upward faces
uniform vec2 glass_center = vec2(0.0);
uniform vec2 glass_radii = vec2(0.0);
uniform float glass_cell = 0.7;
uniform float glass_frame = 0.09;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 h22(vec2 p) {
	return vec2(h21(p), h21(p + 19.19));
}

float vnoise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Voronoi: distance to the nearest cell border, and that cell's feature point (iq's method).
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + 0.15 + 0.7 * h22(n + g) - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + 0.15 + 0.7 * h22(n + g) - f;
			if (dot(mr - r, mr - r) > 1e-5) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec3(md, x + mr);
}

void fragment() {
	vec3 an = abs(ln);
	vec2 q;
	if (an.x > an.y && an.x > an.z) {
		q = lp.zy;
	} else if (an.y > an.z) {
		q = lp.xz;
	} else {
		q = lp.xy;
	}
	q *= panel_scale;
	// staggered rows of panels of different lengths
	float row = floor(q.y);
	q.x = q.x * (0.6 + 0.8 * h21(vec2(row, 3.1))) + h21(vec2(row, 7.7)) * 3.0;
	vec2 cell = floor(q);
	vec2 g = fract(q);
	vec2 fw = max(fwidth(q), vec2(1e-4));
	vec2 d = min(g, 1.0 - g) / fw;
	float line = 1.0 - clamp(min(d.x, d.y) - 0.4, 0.0, 1.0);
	float fade = clamp(1.4 - max(fw.x, fw.y) * 5.0, 0.0, 1.0);
	line *= fade;

	float rnd = h21(cell);
	vec3 col = base_color * (1.0 + (rnd - 0.5) * 2.0 * tint_var);
	float s = dot(lp, stripe_axis);
	float in_stripe = step(stripe_a, s) * step(s, stripe_b);
	col = mix(col, accent_color, in_stripe);
	col *= 1.0 - line * line_dark;
	float rgh = clamp(rough + (rnd - 0.5) * 0.18 + line * 0.25, 0.04, 1.0);
	float met = metal;

	if (grime > 0.0) {
		float streak = vnoise2(vec2(lp.x * 2.2, lp.z * 0.35)) * 0.6 + vnoise2(lp.xz * 1.3 + 7.0) * 0.4;
		col *= 1.0 - grime * (smoothstep(0.45, 0.95, streak) * 0.35 + line * 0.4);
		rgh = clamp(rgh + grime * streak * 0.2, 0.04, 1.0);
	}

	if (glass_radii.x > 0.0 && ln.y > 0.6) {
		vec3 v = voronoi(lp.xz / glass_cell);
		vec2 cen = v.yz * glass_cell;
		vec2 e = (cen - glass_center) / glass_radii;
		if (dot(e, e) < 1.0) {
			float fw2 = max(fwidth(v.x), 1e-4);
			float pane = smoothstep(glass_frame - fw2, glass_frame + fw2, v.x);
			float gasket = smoothstep(glass_frame - fw2 * 3.0, glass_frame, v.x) * (1.0 - pane);
			col = mix(col * (1.0 - gasket * 0.6), vec3(0.015, 0.017, 0.02), pane);
			rgh = mix(rgh, 0.06, pane);
			met = mix(met, 0.0, pane);
		}
	}

	ALBEDO = col;
	METALLIC = met;
	ROUGHNESS = rgh;

	vec3 em = emission_color * emission_energy + accent_color * in_stripe * stripe_emit;
	if (window_amount > 0.0) {
		vec2 wq = q * vec2(5.0, 2.0);
		vec2 wc = floor(wq);
		vec2 wf = fract(wq);
		float lit = step(1.0 - window_amount, h21(wc + 17.0));
		float box = step(0.3, wf.x) * step(wf.x, 0.7) * step(0.35, wf.y) * step(wf.y, 0.65);
		em += window_color * lit * box * 4.0 * fade;
	}
	EMISSION = em;
}
