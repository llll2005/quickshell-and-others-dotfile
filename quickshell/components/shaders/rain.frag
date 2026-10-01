#version 440
// Window open: the window's own pixels rain down into place. The item reaches
// `drop` px above the window; cells fall from there, the bottom row first, then each
// row above it (columns a little out of step), land with a small bounce and a light
// flash, and sharpen from their cell's colour into the real image. Without a capture
// the cells are the theme's paper with an ink edge.
// Rebuild: /usr/lib/qt6/bin/qsb --qt6 -o rain.frag.qsb rain.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;    // 0 → 1: everything has landed and is sharp
    float cell;        // cell size, px
    float hasSource;
    vec2  dims;        // item size, px (window width × window height + drop)
    float drop;        // fall height, px
    float seed;
    vec4  paper;
    vec4  ink;
    vec4  light;
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }

// where row r of column cx is: its top edge in window px, and how far it has come
float rowTop(float r, float cx, float rows, out float local) {
    float t0 = (1.0 - (r + 0.5) / rows) * 0.5 + hash(vec2(cx, 0.0)) * 0.18 + hash(vec2(cx, r)) * 0.06;
    local = clamp((progress - t0) / 0.26, 0.0, 1.0);
    // fall with gravity, then a small bounce
    float f;
    if (local < 0.8) { float u = local / 0.8; f = 1.0 - u * u; }
    else { float u = (local - 0.8) / 0.2; f = -0.06 * sin(u * 3.14159); }
    return r * cell - f * drop;
}

void main() {
    vec2 px = qt_TexCoord0 * dims;
    float wy = px.y - drop;                       // window coordinates
    float winH = dims.y - drop;
    float rows = ceil(winH / cell);
    float cx = floor(px.x / cell);
    // which falling or landed cell covers this pixel? (cells only ever sit at or
    // above their own row, so look from this row down to one `drop` below)
    float r0 = max(0.0, floor(wy / cell));
    float local = 0.0, row = -1.0, top = 0.0;
    for (int k = 0; k < 40; k++) {
        float r = r0 + float(k);
        if (r >= rows || (r - r0) * cell > drop + cell) break;
        float l;
        float t = rowTop(r, cx, rows, l);
        if (l > 0.0 && wy >= t && wy < t + cell) { row = r; local = l; top = t; break; }
    }
    if (row < 0.0) { fragColor = vec4(0.0); return; }
    // the pixel's place inside its cell → where it samples the window
    vec2 within = vec2(px.x - cx * cell, wy - top);
    vec2 home   = vec2(cx * cell, row * cell) + within;
    vec2 centre = vec2(cx + 0.5, row + 0.5) * cell;
    float sharp = smoothstep(0.85, 1.0, local);   // flat while falling, real once landed
    vec4 col;
    if (hasSource > 0.5) {
        vec4 flat_ = texture(source, clamp(centre / vec2(dims.x, winH), 0.0, 1.0));
        vec4 real  = texture(source, clamp(home / vec2(dims.x, winH), 0.0, 1.0));
        col = mix(flat_, real, sharp);
    } else {
        col = paper;
        col.rgb *= 0.94 + 0.1 * hash(vec2(cx, row) + 5.1);
        float e = step(cell - 1.2, max(within.x, within.y)) + step(max(within.x, within.y), 1.2);
        col.rgb = mix(col.rgb, ink.rgb, clamp(e, 0.0, 1.0) * 0.5);
    }
    // a light flash as it lands
    float flash = smoothstep(0.7, 0.8, local) * (1.0 - smoothstep(0.8, 1.0, local));
    col.rgb = mix(col.rgb, light.rgb * col.a, flash * 0.75);
    fragColor = col * qt_Opacity;
}
