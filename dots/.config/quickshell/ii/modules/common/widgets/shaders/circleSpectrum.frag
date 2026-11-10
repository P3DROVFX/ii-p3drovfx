#version 440

// A ring whose spectrum grows outward, mirrored left to right: bass at the bottom,
// treble at the top. The band between the ring and the spectrum is solid and glows on
// both sides. Two copies shifted diagonally in opposite directions give the coloured
// fringes, like chromatic aberration; where all three overlap the core colour wins.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float blend;
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;
    vec4 c0; vec4 c1; vec4 c2; vec4 c3; vec4 c4; vec4 c5; vec4 c6; vec4 c7;
    vec4 coreColor;
    vec4 colorA;
    vec4 colorB;
    float ringRadius;  // pixels
    float lineWidth;   // ring thickness, pixels
    float spikeHeight; // spectrum length at full level, pixels
    float glowRadius;  // pixels
    float spread;      // fringe offset, pixels
    float intensity;
} ubuf;

const float PI = 3.14159265;

float pick(vec4 v, int c)
{
    return c == 0 ? v.x : (c == 1 ? v.y : (c == 2 ? v.z : v.w));
}

float bandAt(int i)
{
    int v = i / 4;
    int c = i - v * 4;
    vec4 a = ubuf.p7;
    vec4 b = ubuf.c7;
    if (v == 0) { a = ubuf.p0; b = ubuf.c0; }
    else if (v == 1) { a = ubuf.p1; b = ubuf.c1; }
    else if (v == 2) { a = ubuf.p2; b = ubuf.c2; }
    else if (v == 3) { a = ubuf.p3; b = ubuf.c3; }
    else if (v == 4) { a = ubuf.p4; b = ubuf.c4; }
    else if (v == 5) { a = ubuf.p5; b = ubuf.c5; }
    else if (v == 6) { a = ubuf.p6; b = ubuf.c6; }
    return mix(pick(a, c), pick(b, c), ubuf.blend);
}

// Catmull-Rom through the 32 bands, so the outline is a curve, not a staircase.
float spectrum(float t)
{
    float x = clamp(t, 0.0, 1.0) * 31.0;
    float fi = floor(x);
    float f = x - fi;
    // Indices in float: GLSL 120, which Qt can translate this to, has no integer min/max.
    float a = bandAt(int(max(fi - 1.0, 0.0)));
    float b = bandAt(int(fi));
    float c = bandAt(int(min(fi + 1.0, 31.0)));
    float d = bandAt(int(min(fi + 2.0, 31.0)));
    return clamp(b + 0.5 * f * (c - a + f * (2.0 * a - 5.0 * b + 4.0 * c - d + f * (3.0 * (b - c) + d - a))),
                 0.0, 1.0);
}

// x: solid band, y: glow
vec2 band(vec2 p)
{
    float r = length(p);
    float angle = atan(p.x, p.y); // 0 straight down, ±PI straight up
    float level = spectrum(abs(angle) / PI);
    float inner = ubuf.ringRadius - ubuf.lineWidth * 0.5;
    float outer = ubuf.ringRadius + ubuf.lineWidth * 0.5 + level * ubuf.spikeHeight;
    float sd = max(r - outer, inner - r);
    float aa = max(fwidth(sd), 0.75);
    float fill = 1.0 - smoothstep(-aa, aa, sd);
    // Outside, the glow swells with the level; inside the ring it stays a soft rim, or
    // loud bands throw rays into the middle.
    float glow = r > inner
        ? exp(-max(sd, 0.0) / (ubuf.glowRadius * (0.7 + level))) * (0.45 + 0.55 * level)
        : exp(-(inner - r) / ubuf.glowRadius) * 0.45;
    return vec2(fill, glow);
}

void main()
{
    vec2 p = (qt_TexCoord0 - 0.5) * ubuf.resolution;
    vec2 shift = vec2(ubuf.spread, ubuf.spread);

    vec2 core = band(p);
    vec2 a = band(p + shift);
    vec2 b = band(p - shift);

    float wa = a.x * 0.8 + a.y;
    float wb = b.x * 0.8 + b.y;
    // Coverage comes from the weights, not from how bright the colours are, so dark
    // colours on a light surface still show. Colour is clamped to it (premultiplied).
    float alpha = min(1.0, max(core.x, max(wa, wb)) * ubuf.intensity);
    vec3 col = (ubuf.colorA.rgb * wa + ubuf.colorB.rgb * wb + ubuf.coreColor.rgb * core.x) * ubuf.intensity;
    fragColor = vec4(min(col, vec3(alpha)), alpha) * ubuf.qt_Opacity;
}
