#version 440
// Window close: the window melts downward. Each column lets go at its own moment and
// falls, accelerating and stretching; as it goes it coarsens into cells that drop
// out one by one, picking up a tint of the accent. The item reaches `drip` px below
// the window so the fall has room. Without a capture: paper/ink cells.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;    // 0 → 1
    float cell;        // cell size, px
    float hasSource;
    vec2  dims;        // item size, px (window width × window height + drip)
    float winH;        // window height, px
    float seed;
    vec4  paper;
    vec4  ink;
    vec4  accent;
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }

void main() {
    vec2 px = qt_TexCoord0 * dims;
    float colI = floor(px.x / cell);
    float t0 = hash(vec2(colI, 3.1)) * 0.35;
    float local = clamp((progress - t0) / 0.65, 0.0, 1.0);
    float drip = dims.y - winH;
    float fall = local * local * (winH * 0.5 + drip);
    float stretch = 1.0 + local * 0.4;
    float sy = (px.y - fall) / stretch;
    if (sy < 0.0 || sy > winH) { fragColor = vec4(0.0); return; }
    vec2 sp = vec2(px.x, sy);
    float pix = max(1.0, mix(1.0, cell, smoothstep(0.0, 0.3, local)));
    vec2 q = (floor(sp / pix) + 0.5) * pix;
    vec2 ci = floor(sp / cell);
    float rc = hash(ci + 7.3);
    float gone = smoothstep(0.3 + rc * 0.5, 0.42 + rc * 0.5, local);
    vec4 col;
    if (hasSource > 0.5) {
        col = texture(source, clamp(vec2(q.x / dims.x, q.y / winH), 0.0, 1.0));
    } else {
        col = mix(paper, ink, step(0.5, hash(ci)));
    }
    col.rgb = mix(col.rgb, accent.rgb * col.a, local * 0.3);
    col *= (1.0 - gone) * (1.0 - smoothstep(0.8, 1.0, local));
    fragColor = col * qt_Opacity;
}
