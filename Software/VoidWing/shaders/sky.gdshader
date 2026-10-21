// Deep-space sky, kept calm on purpose (a busy, shimmering sky causes motion sickness):
// sparse soft stars, a faint Milky Way band and Gargantua, a black hole with its
// accretion disk, as a fixed landmark. Nothing here moves, so the radiance map is
// rendered once.
shader_type sky;

uniform vec3 sun_dir = vec3(0.55, 0.42, 0.72);
uniform vec3 bh_dir = vec3(-0.45, 0.16, -0.88);
uniform float bh_size = 0.05;          // shadow radius (rad)
uniform float bh_incl = 0.07;          // disk seen this far (rad) from edge-on
uniform float milky = 0.035;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
	               mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
	               mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.02 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return s;
}

// One star layer: at most one soft star per cell.
vec3 stars(vec3 d, float scale, float density, float size, float bright) {
	vec3 p = d * scale;
	vec3 id = floor(p);
	vec3 f = fract(p);
	vec3 c = hash33(id) * 0.6 + 0.2;
	float present = step(1.0 - density, hash13(id + 3.7));
	float b = present * (1.0 - smoothstep(0.0, size, length(f - c)));
	vec3 col = mix(vec3(0.78, 0.85, 1.0), vec3(1.0, 0.9, 0.78), hash13(id + 9.1));
	float mag = pow(hash13(id + 1.3), 4.0) * 2.5 + 0.35;
	return col * b * b * mag * bright;
}

// Gargantua. p = position in the black hole's tangent plane, in shadow radii.
// Returns the light; occl = 1 inside the shadow (hides the stars behind it).
vec3 gargantua(vec3 d, out float occl) {
	occl = 0.0;
	vec3 f = normalize(bh_dir);
	float w = dot(d, f);
	if (w < 0.5) {
		return vec3(0.0);
	}
	vec3 rt = normalize(cross(f, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(rt, f);
	vec2 p = vec2(dot(d, rt), dot(d, up)) / w;
	float ca = cos(0.12);
	float sa = sin(0.12);
	p = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) / bh_size;
	float r = length(p);
	occl = 1.0 - smoothstep(0.97, 1.03, r);

	vec3 hot = vec3(1.0, 0.86, 0.66);
	vec3 warm = vec3(1.0, 0.56, 0.26);
	float si = sin(bh_incl);
	float left = -p.x / max(r, 1e-3);

	// the disk itself: an ellipse annulus; the near half (below centre) crosses in
	// front of the shadow, the far half is hidden by it
	float rho = sqrt(p.x * p.x + (p.y / si) * (p.y / si));
	float ring = smoothstep(1.55, 1.9, rho) * exp(-max(rho - 1.9, 0.0) * 1.0) * (1.0 - smoothstep(4.5, 6.5, rho));
	float streaks = 0.6 + 0.4 * vnoise(vec3(rho * 7.0, 0.0, 1.0)) + 0.15 * vnoise(vec3(rho * 23.0, 3.0, 0.0));
	float dopp = 1.0 + 0.5 * clamp(-p.x / max(rho, 1e-3), -1.0, 1.0);
	vec3 disk = mix(warm, hot, exp(-(rho - 1.6) * 0.7)) * ring * streaks * dopp * 2.4;
	vec3 front = p.y <= 0.0 ? disk : vec3(0.0);
	vec3 back = p.y > 0.0 ? disk : vec3(0.0);

	// the far side of the disk, bent by gravity into a halo over and under the shadow
	float ang = atan(p.y, p.x);
	float vert = pow(abs(p.y) / max(r, 1e-3), 2.0);
	float halo = exp(-pow((r - 1.18 - 0.22 * vert) / (0.08 + 0.26 * vert), 2.0)) * (0.05 + 0.95 * vert);
	halo *= 0.7 + 0.3 * vnoise(vec3(ang * 9.0, r * 6.0, 2.0));
	halo *= 1.0 + 0.35 * left;
	float photon = exp(-pow((r - 1.035) / 0.016, 2.0));
	float glow = exp(-max(r - 1.0, 0.0) * 1.6) * 0.06;
	vec3 lensed = (hot * halo * 2.0 + vec3(1.0, 0.92, 0.82) * photon * 2.5 + warm * glow) * (1.0 - occl);
	return front + back * (1.0 - occl) + lensed;
}

void sky() {
	vec3 d = EYEDIR;
	// faint Milky Way along one band of the sky
	vec3 gal_n = normalize(vec3(0.3, 1.0, 0.25));
	float band = exp(-pow(dot(d, gal_n) * 3.2, 2.0));
	float n = fbm(d * 3.0 + vec3(3.1));
	float lanes = smoothstep(0.45, 0.7, fbm(d * 7.0 + 5.0));
	vec3 col = mix(vec3(0.55, 0.6, 0.75), vec3(0.85, 0.75, 0.62), n) * band * (0.4 + n) * (1.0 - 0.6 * lanes) * milky;

	float occl;
	vec3 bh = gargantua(d, occl);
	if (!AT_CUBEMAP_PASS) {
		vec3 st = stars(d, 170.0, 0.05 + 0.08 * band, 0.28, 0.55);
		st += stars(d, 85.0, 0.035 + 0.03 * band, 0.2, 1.0);
		st += stars(d, 38.0, 0.022, 0.11, 2.4);
		col += st * (1.0 - occl);
	}
	col = col * (1.0 - occl) + bh;

	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.94, 0.86) * (pow(sd, 6000.0) * 9.0 + pow(sd, 300.0) * 0.03);
	COLOR = col;
}
