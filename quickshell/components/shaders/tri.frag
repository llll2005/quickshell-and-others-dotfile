#version 440
// Triangle backdrop — GPU port of NierTriBg (widgets/NierTriBg.qml): the same
// equilateral grid and 3 px gaps, triangles unfolding outward from `origin` on
// show and scattering inside-out on hide. On top of that:
//   · glass   — with a `source` frame (hasSrc = 1) every triangle is a pane of
//               frosted glass: the screen behind is refracted a few px, with a
//               faint prismatic split toward its edges
//   · glare   — two slow light beams circle `glareC`; the panes they cross
//               catch the light and their rims glow
//   · stars   — four-point glints twinkle on some of the grid's vertices
//   · flicker — now and then a pane lights up or darkens (some with a stutter)
//   · impact  — impact(x, y): a ring runs out through the panes around the point
//               (rims light, panes lift and their offset kicks outward), local
//               and gone in IMP_LIFE s
//   · select  — with selOn = 1, `selRect` is an exact spotlight: inside it there
//               is no pane, dim, glare or refraction (1 px anti-aliased edge).
//               Panes that overlap `foldRect` (the selection, trailed a little by
//               QML) disappear the NierTriBg way: the corner nearest the selection
//               folds onto the opposite edge until the pane is a line. Only panes
//               that actually reach the selection react (from SEL_NEAR px away, gone
//               at SEL_DEEP px of overlap); panes further out stay whole
// Everything fades in with the triangles and back out on hide, so the frozen
// frame cross-fades to the live screen instead of jumping.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o tri.frag.qsb tri.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  res;       // item size, px
    vec2  origin;    // spread origin, px
    vec2  glareC;    // glare centre, px
    float cellW;     // triangle base width, px
    float gap;       // px between triangles
    float tIn;       // s since show began
    float tOut;      // s since hide began, < 0 while not hiding
    float time;      // s, idle clock
    float flicker;   // 0..1
    float alpha;     // resting pane opacity
    float dim;       // backdrop darkening
    float hasSrc;    // 1 = `source` holds a frame of the screen
    float selOn;     // 1 = region selection active
    vec4  selRect;   // x, y, w, h in px
    vec4  foldRect;  // selRect, eased — drives the corner fold
    vec2  impactPx;  // impact point, px
    float impT;      // s since the impact, < 0 = none
    float impS;      // impact strength 0..1
    vec4  triColor;
    vec4  glint;     // light: lit panes, glare, stars
    vec4  shade;     // ink: dim, darkening panes
};
layout(binding = 1) uniform sampler2D source;

const float PI    = 3.14159265;
const float ENTER = 1.25;   // s for the spread to cross the screen (NierTriBg's was 0.9)
const float EXIT  = 0.34;   // s for the scatter to reach the far corner
const float IMP_LIFE  = 0.7;    // s an impact ring lives
const float IMP_SPEED = 900.0;  // px/s the ring travels
const float IMP_REACH = 460.0;  // px beyond which panes don't react
const float SEL_NEAR = 6.0;   // px: a pane this close to the selection starts to fold
const float SEL_DEEP = 24.0;  // px of overlap at which it has folded away completely

float h1(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float edgeD(vec2 p, vec2 a, vec2 b, float s) {
    vec2 e = b - a;
    return -s * (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / max(length(e), 1e-4);
}
// < 0 inside, px
float triSD(vec2 p, vec2 a, vec2 b, vec2 c) {
    float s = sign((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x));
    return max(max(edgeD(p, a, b, s), edgeD(p, b, c, s)), edgeD(p, c, a, s));
}
// signed distance from p to foldRect, px (< 0 inside)
float foldSD(vec2 p) {
    vec2 d = max(foldRect.xy - p, p - (foldRect.xy + foldRect.zw));
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Separation between a pane and foldRect, px (< 0 = overlap depth): its corners
// against the rect, and the rect's corners / edge midpoints / centre against it.
float paneRectD(vec2 L, vec2 R, vec2 Y) {
    float d = min(min(foldSD(L), foldSD(R)), foldSD(Y));
    vec2 lo = foldRect.xy, hi = foldRect.xy + foldRect.zw, m = 0.5 * (lo + hi);
    d = min(d, triSD(lo, L, R, Y));               d = min(d, triSD(hi, L, R, Y));
    d = min(d, triSD(vec2(lo.x, hi.y), L, R, Y)); d = min(d, triSD(vec2(hi.x, lo.y), L, R, Y));
    d = min(d, triSD(m, L, R, Y));
    d = min(d, triSD(vec2(m.x, lo.y), L, R, Y));  d = min(d, triSD(vec2(m.x, hi.y), L, R, Y));
    d = min(d, triSD(vec2(lo.x, m.y), L, R, Y));  d = min(d, triSD(vec2(hi.x, m.y), L, R, Y));
    return d;
}

// how hard the impact ring is hitting the pane centred at c (0..1)
float impactK(vec2 c) {
    if (impT < 0.0 || impT > IMP_LIFE) return 0.0;
    float d = length(c - impactPx);
    float band = exp(-pow((d - impT * IMP_SPEED) / 70.0, 2.0));
    return band * impS * (1.0 - impT / IMP_LIFE) * (1.0 - smoothstep(IMP_REACH * 0.55, IMP_REACH, d));
}

// four-point glint centred on v
float star(vec2 px, vec2 v, float t) {
    vec2  d  = px - v;
    float sd = h1(floor(v + 0.5));
    if (sd < 0.72) return 0.0;                              // ~28 % of vertices
    float tw = pow(max(sin(t * (0.72 + sd * 1.36) + sd * 40.0), 0.0), 8.0);
    float dia  = pow(max(0.0, 1.0 - (abs(d.x) + abs(d.y)) / 7.0), 3.0);
    float rays = exp(-abs(d.x) / 1.1) * exp(-abs(d.y) / 16.0)
               + exp(-abs(d.y) / 1.1) * exp(-abs(d.x) / 16.0);
    return (dia + rays * 0.55) * tw;
}

void main() {
    vec2  px = qt_TexCoord0 * res;
    float hw = cellW * 0.5, ch = cellW * 0.8660254;
    float gw = cellW - gap, gh = ch - gap * 0.5;
    float yi  = floor(px.y / ch + 0.5);
    float xi0 = floor(px.x / hw);

    vec2  oc   = origin / vec2(hw, ch);                    // origin in cell units
    float cols = res.x / hw + 2.0, rows = res.y / ch + 2.0;
    float md   = length(vec2(max(oc.x, cols - oc.x) * 0.5, max(oc.y, rows - oc.y))) + 1.0;
    float out1 = tOut < 0.0 ? 1.0 : 1.0 - smoothstep(0.16, 0.58, tOut);   // whole-backdrop fade on hide

    float selIn = 0.0;                                     // 1 inside the selection
    if (selOn > 0.5) {
        vec2 dd = max(selRect.xy - px, px - (selRect.xy + selRect.zw));
        selIn = clamp(0.5 - max(dd.x, dd.y), 0.0, 1.0);
    }
    float keep = 1.0 - selIn;

    // the pane covering this pixel (+ what the stars and rims need from all candidates)
    float bw = 0.0, bSd = 1e3, bFl = 0.0;
    bool  bDip = false;
    vec2  bC = vec2(0.0), bCell = vec2(0.0);
    float stars = 0.0, rims = 0.0;
    for (int k = -1; k <= 2; k++) {
        float xi = xi0 + float(k);
        bool  up = mod(xi, 2.0) < 0.5 ? mod(yi, 2.0) > 0.5 : mod(yi, 2.0) < 0.5;
        vec2  c  = vec2(xi * hw, yi * ch);
        float sy = up ? 1.0 : -1.0;
        vec2  L = c + vec2(-gw * 0.5, sy * gh * 0.5);
        vec2  R = c + vec2( gw * 0.5, sy * gh * 0.5);
        vec2  Y = c + vec2(0.0, -sy * gh * 0.5);

        vec2  cell = vec2(xi, yi);
        float d    = length(vec2((xi - oc.x) * 0.5, yi - oc.y));
        float age  = tIn - d / (md * (0.5 + 0.5 * h1(cell))) * ENTER;
        if (age <= 0.0) continue;
        float g = 1.0 - exp(-age / 0.10);                  // unfold the far vertex
        if (g < 0.03) continue;
        float op = 1.0 - exp(-age / 0.42);                 // fade in
        if (xi < oc.x) L = mix(0.5 * (R + Y), L, g);
        else           R = mix(0.5 * (L + Y), R, g);
        if (selOn > 0.5) {                                 // panes reaching the selection fold away
            float k = 1.0 - smoothstep(-SEL_DEEP, SEL_NEAR, paneRectD(L, R, Y));
            if (k > 0.0) {
                float dL = foldSD(L), dR = foldSD(R), dY = foldSD(Y);
                if (dL <= dR && dL <= dY) L = mix(L, 0.5 * (R + Y), k);
                else if (dR <= dY)        R = mix(R, 0.5 * (L + Y), k);
                else                      Y = mix(Y, 0.5 * (L + R), k);
                // a folded pane is a line: its SDF would cover everything, skip it
                if (abs((R.x - L.x) * (Y.y - L.y) - (R.y - L.y) * (Y.x - L.x)) < 2.0) continue;
            }
        }
        if (tOut >= 0.0) {                                 // scatter out, near the origin first
            float ea = tOut - (d / md) * (0.3 + 0.7 * h1(cell + 9.1)) * EXIT;
            if (ea > 0.0) op *= exp(-ea / 0.07);
        }

        // flicker
        float ph   = time * 1.25 + h1(cell + 3.7) * 29.0;
        float slot = floor(ph), f = fract(ph);
        float ev   = step(0.955, h1(cell + slot * 1.37));
        float env  = sin(f * PI); env *= env;
        float stut = h1(cell + slot * 3.3) > 0.55 ? 0.5 + 0.5 * step(0.5, fract(f * 5.0)) : 1.0;
        float fl   = ev * env * stut * flicker * min(tIn / 1.6, 1.0);
        bool  dip  = h1(cell + slot * 2.11) < 0.35;

        float sd  = triSD(px, L, R, Y);
        float cov = clamp(0.5 - sd, 0.0, 1.0);

        // glare: beams circling glareC light the whole pane + its rim
        vec2  gv   = c - glareC;
        float ang  = atan(gv.y, gv.x);
        float ba   = time * 0.26;
        float d1   = abs(mod(ang - ba + PI, 2.0 * PI) - PI);
        float d2   = abs(mod(ang - ba, 2.0 * PI) - PI);
        float beam = exp(-d1 * d1 * 7.0) + 0.55 * exp(-d2 * d2 * 7.0);
        float lit  = dip ? 0.0 : fl;
        float imp  = impactK(c);
        rims = max(rims, (lit * 0.9 + beam * 0.35 + imp * 1.2) * exp(-abs(sd + 1.5) / 1.3) * op);

        // stars on the (unshrunk) vertices of this cell
        vec2 fL = c + vec2(-hw, sy * ch * 0.5), fR = c + vec2(hw, sy * ch * 0.5), fY = c + vec2(0.0, -sy * ch * 0.5);
        stars = max(stars, max(star(px, fL, time), max(star(px, fR, time), star(px, fY, time))) * op);

        float w = cov * op;
        if (w > bw) {
            bw = w; bSd = sd; bC = c; bCell = cell;
            bFl = fl + beam * (0.25 + 0.55 * h1(cell + 4.4)) * 0.45 + imp * 0.6;   // glare / impact count as light
            bDip = dip;
        }
    }

    vec3  light = glint.rgb, ink = shade.rgb;
    float dimA  = dim * smoothstep(0.0, 0.26, tIn) * out1 * keep;
    // Tone: the brighter half of the panes stays as is; the darker ones lean to
    // ink (and darken what is behind them) for more contrast between the two.
    float tone  = h1(bCell + 7.7);
    float darkK = smoothstep(0.7, 0.2, tone) * (1.0 - clamp(bFl, 0.0, 1.0));   // ~2/3 of the panes lean dark
    float paneA = (bDip ? alpha : min(alpha + 0.32 * bFl, 1.0)) * bw * keep;
    paneA = min(paneA + darkK * 0.30 * bw * keep, 1.0);
    vec3  paneC = mix(mix(triColor.rgb, light, clamp(bFl, 0.0, 1.0) * 0.75), ink, bDip ? bFl * 0.55 : 0.0);
    paneC = mix(paneC, ink * 0.6, darkK * 0.9);
    float glow  = clamp(rims + stars, 0.0, 1.0) * keep;

    if (hasSrc > 0.5) {
        // frosted-glass panes: refract the frame behind by a few px
        float amt  = bw * keep;
        vec2  rd   = vec2(h1(bCell + 1.1), h1(bCell + 2.3)) - 0.5;
        float hs   = h1(bCell + 5.5) * 6.2832;
        vec2  off  = rd * 16.0 * amt + vec2(sin(time * 0.5 + hs), cos(time * 0.45 + hs)) * 1.6 * amt;
        off += normalize(bC - impactPx + vec2(1e-3)) * 12.0 * impactK(bC) * amt;   // the ring kicks the offset outward
        vec2  sp   = px + off + (px - bC) * (-0.05 * amt);
        vec2  dirC = normalize(px - bC + vec2(1e-3));
        vec2  ca   = dirC * (1.0 + 3.0 * exp(clamp(bSd, -40.0, 0.0) / 9.0)) * amt;   // clamp: bSd is 1e3 in gaps → exp overflow → NaN
        vec3  col  = vec3(texture(source, (sp + ca) / res).r,
                          texture(source,  sp       / res).g,
                          texture(source, (sp - ca) / res).b);
        float lum  = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(col, vec3(lum) * vec3(1.08, 0.97, 0.78), 0.35 * dimA / max(dim, 1e-3));
        col = mix(col, ink, dimA);
        col *= 1.0 + max(tone - 0.5, 0.0) * 0.12 * amt;      // bright facets catch a little light
        col *= 1.0 - darkK * 0.7 * amt;                       // dark facets sink
        col = mix(col, paneC, paneA);
        col += light * glow * 0.85;
        // overall contrast: darks sink, lights lift a little (fades in with the dim);
        // the pivot sits a little low so the whole field reads a shade darker
        col = clamp(mix(col, (col - 0.55) * 1.42 + 0.51, dimA / max(dim, 1e-3)), 0.0, 1.0);
        // out1 cross-fades the frozen frame back to the live screen on hide
        fragColor = vec4(col, 1.0) * out1 * qt_Opacity;
    } else {
        // no frame: dim + panes over the live (transparent) surface
        vec3  C = ink * dimA;
        float A = dimA;
        C = C * (1.0 - paneA) + paneC * paneA;
        A = A * (1.0 - paneA) + paneA;
        C += light * glow * 0.85;
        A  = clamp(A + glow * 0.85, 0.0, 1.0);
        fragColor = vec4(C, A) * qt_Opacity;
    }
}
