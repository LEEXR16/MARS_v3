// Banded gas giant with a thin atmosphere rim.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 c1 : source_color = vec3(0.62, 0.50, 0.37);
uniform vec3 c2 : source_color = vec3(0.38, 0.28, 0.20);
uniform vec3 c3 : source_color = vec3(0.75, 0.68, 0.58);
uniform vec3 atmo : source_color = vec3(0.95, 0.72, 0.50);

varying vec3 lp;

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
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	float warp = fbm(lp * vec3(3.0, 9.0, 3.0)) * 0.22;
	float lat = lp.y + warp;
	float b = sin(lat * 26.0) * 0.5 + 0.5;
	float b2 = sin(lat * 61.0 + 1.3) * 0.5 + 0.5;
	vec3 col = mix(c2, c1, b);
	col = mix(col, c3, b2 * 0.35 * smoothstep(0.2, 0.9, fbm(lp * 6.0)));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = atmo * fres * 0.25;
}
