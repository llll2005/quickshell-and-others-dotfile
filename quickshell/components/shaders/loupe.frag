#version 440
// Magnifier for region selection: `cells` × `cells` source pixels around
// `center` (px in the source texture), each drawn as one flat square, with a
// 1 px grid and the centre pixel outlined.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o loupe.frag.qsb loupe.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  texSize;   // source size, px
    vec2  center;    // pixel under the cursor, px
    float cells;     // odd: the centre cell is the cursor pixel
    vec4  gridCol;
    vec4  hiCol;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2  cf    = qt_TexCoord0 * cells;
    vec2  ci    = floor(cf);
    vec2  half_ = vec2(floor(cells * 0.5));
    vec2  texel = floor(center) + ci - half_;
    bool  inTex = all(greaterThanEqual(texel, vec2(0.0))) && all(lessThan(texel, texSize));
    vec3  c     = inTex ? texture(source, (texel + 0.5) / texSize).rgb : vec3(0.08, 0.07, 0.05);

    vec2  f  = fract(cf);
    vec2  fw = fwidth(cf);
    float grid = max(step(f.x, fw.x), step(f.y, fw.y));
    c = mix(c, gridCol.rgb, grid * gridCol.a);

    if (all(equal(ci, half_))) {
        float e = max(max(step(f.x, fw.x * 1.6), step(1.0 - fw.x * 1.6, f.x)),
                      max(step(f.y, fw.y * 1.6), step(1.0 - fw.y * 1.6, f.y)));
        c = mix(c, hiCol.rgb, e);
    }
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
