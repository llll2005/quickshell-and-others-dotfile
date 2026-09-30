#version 440
// Reveal masks for a panel's open/close (used as its layer.effect only while
// the transition runs, so the resting panel renders untouched and crisp).
//   mode 0  iris   — a diamond opens from the centre
//   mode 1  scan   — a line draws across, then opens top/bottom
//   mode 2  blinds — vertical slats open one after another, left → right
// `progress` 0 = hidden, 1 = fully shown; closing runs it back to 0. The only
// light is a thin line on the moving edge, faded out before the end.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o reveal.frag.qsb reveal.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    vec2  dims;      // px
    vec4  edge;      // edge line colour
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2  uv   = qt_TexCoord0;
    vec2  p    = (uv - 0.5) * dims;                       // px from the centre
    float m    = 0.0, e = 0.0;
    float live = step(0.001, progress) * (1.0 - smoothstep(0.8, 1.0, progress));

    if (mode < 0.5) {
        float r  = (dims.x + dims.y) * 0.5 * progress * 1.02;
        float dd = (abs(p.x) + abs(p.y) - r) * 0.7071;   // ≈ px to the diamond edge
        m = clamp(0.5 - dd, 0.0, 1.0);
        e = exp(-abs(dd) / 1.1);
    } else if (mode < 1.5) {
        float gx = clamp(progress / 0.35, 0.0, 1.0);
        float gy = clamp((progress - 0.35) / 0.65, 0.0, 1.0);
        float dx = abs(p.x) - dims.x * 0.5 * gx;
        float dy = abs(p.y) - max(1.0, dims.y * 0.5 * gy);
        m = clamp(0.5 - dx, 0.0, 1.0) * clamp(0.5 - dy, 0.0, 1.0);
        e = exp(-abs(dy) / 1.0) * clamp(0.5 - dx, 0.0, 1.0);
    } else {
        float n  = 12.0, st = 0.5;                        // slats, stagger share
        float i  = floor(uv.x * n);
        float lp = clamp((progress - i / (n - 1.0) * st) / (1.0 - st), 0.0, 1.0);
        float dd = (fract(uv.x * n) - lp) * dims.x / n;   // px past the slat's open edge
        m = clamp(0.5 - dd, 0.0, 1.0);
        e = exp(-abs(dd) / 1.0) * step(0.001, lp) * (1.0 - step(0.999, lp));
    }

    vec4 src = texture(source, uv);
    fragColor = (src * m + vec4(edge.rgb, 1.0) * edge.a * e * live * (1.0 - m * 0.5)) * qt_Opacity;
}
