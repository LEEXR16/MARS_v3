// Asteroid rock: two-tone noise colour, bump from the same noise, slow tumble
// per MultiMesh instance (INSTANCE_CUSTOM = spin axis xyz + speed w).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 col_a : source_color = vec3(0.31, 0.29, 0.27);
uniform vec3 col_b : source_color = vec3(0.12, 0.115, 0.11);
uniform float detail = 1.0;
uniform float bump = 0.9;
uniform bool spin = true;

varying vec3 lp;
varying float inst_scale;

vec3 rot(vec3 v, vec3 axis, float a) {
	return v * cos(a) + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - cos(a));
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lp = VERTEX;
	inst_scale = length(MODEL_MATRIX[0].xyz);
	if (spin) {
		vec3 axis = normalize(INSTANCE_CUSTOM.xyz * 2.0 - 1.0 + vec3(0.001, 0.002, 0.003));
		float a = TIME * (INSTANCE_CUSTOM.w - 0.5) * 0.15;
		VERTEX = rot(VERTEX, axis, a);
		NORMAL = rot(NORMAL, axis, a);
	}
}

void fragment() {
	vec3 p = lp * detail;
	float n = fbm(p * 1.6);
	float n2 = fbm(p * 7.0 + 11.0);
	vec3 col = mix(col_b, col_a, smoothstep(0.3, 0.72, n));
	col *= 0.7 + 0.55 * n2;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.35;

	// bump mapping from the noise height (surface-gradient method)
	float h = (n * 0.6 + n2 * 0.4) * bump / max(inst_scale, 0.001) * 3.0;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float hx = dFdx(h);
	float hy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * inst_scale);
}
