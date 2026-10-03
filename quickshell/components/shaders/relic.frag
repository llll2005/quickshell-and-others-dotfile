#version 440
// relic.frag — the relic lock's ground: an old dark surface (smoke, faint cracks, grain,
// a vignette) with embers smouldering in the two bottom corners. `time` only moves while
// the lock is active, so an idle lock renders nothing new.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  res;      // item size, px
    float time;     // s, advances only while active
    float glow;     // ember strength 0..1
    float flash;    // the failure's red bleed 0..1
    vec4  ember;    // deep warm colour
    vec4  gold;     // bright warm colour
};

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}
// distance to the nearest Voronoi edge: thin lines where cells meet (the cracks)
float edges(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec2 g = vec2(x, y);
        float d = length(g + hash2(i + g) - f);
        if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d;
    }
    return d2 - d1;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float asp = res.x / max(res.y, 1.0);
    vec2 p = vec2(uv.x * asp, uv.y);
    float t = time * 0.02;

    // smoke over a warm black
    float sm  = fbm(p * 2.2 + vec2(t, -t * 0.6));
    float sm2 = fbm(p * 5.0 - vec2(t * 0.7, t));
    vec3 col = vec3(0.034, 0.030, 0.027) + vec3(0.05, 0.043, 0.036) * (sm * 1.2 - 0.3) + 0.015 * sm2;

    // cracks: faint, only where a slow noise lets them through
    // finer cells, a thinner line, and only short broken stretches of it
    float ck = 1.0 - smoothstep(0.0, 0.016, edges(p * 7.0 + fbm(p * 3.0) * 0.6));
    col += vec3(0.06, 0.052, 0.043) * ck * smoothstep(0.58, 0.78, fbm(p * 2.1 + 3.1));

    // vignette
    vec2 q = uv - 0.5;
    col *= 1.0 - 1.6 * dot(q, q);

    // embers in the bottom corners: a smoky warm glow and a few bright specks
    float dl = length((uv - vec2(-0.02, 1.06)) * vec2(asp * 0.85, 1.0));
    float dr = length((uv - vec2(1.02, 1.06)) * vec2(asp * 0.85, 1.0));
    float burn = smoothstep(0.78, 0.0, min(dl, dr) + (sm - 0.5) * 0.4);
    vec3 warm = mix(ember.rgb, gold.rgb, smoothstep(0.35, 0.95, burn));
    col += warm * pow(burn, 2.0) * 0.6 * glow;
    float speck = step(0.986, noise(p * 95.0 + vec2(0.0, -t * 30.0))) * burn;
    col += gold.rgb * speck * 0.7 * glow;

    // grain (it only changes while time moves)
    col += (hash(uv * res + floor(time * 8.0)) - 0.5) * 0.04;

    // the failure: red bleeds into everything
    col = mix(col, col * vec3(1.7, 0.5, 0.45) + vec3(0.09, 0.0, 0.0), flash);

    fragColor = vec4(max(col, 0.0), 1.0) * qt_Opacity;
}
