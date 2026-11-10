#version 440

// A glowing spectrum around the edges of the screen. The perimeter is mirrored left
// to right: bass at the bottom centre, rising along both sides to treble at the top
// centre. Each point of the edge grows a band as thick as its level, and the band
// glows inward. Two copies shifted diagonally in opposite directions give the
// coloured fringes, like chromatic aberration; where all three overlap the core colour wins.

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
    float radius;     // screen corner radius, pixels
    float baseWidth;  // band thickness at silence, pixels
    float thickness;  // extra thickness at full level, pixels
    float glowRadius; // pixels
    float spread;     // fringe offset, pixels
    float intensity;
} ubuf;

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

// Catmull-Rom through the 32 bands, so the edge is a curve, not a staircase.
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

// Depth into the screen from its rounded edge; negative outside it.
float depthAt(vec2 p)
{
    vec2 h = ubuf.resolution * 0.5;
    vec2 q = abs(p - h) - (h - vec2(ubuf.radius));
    return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - ubuf.radius);
}

// Position along the mirrored perimeter, from the nearest edge: 0 at the bottom
// centre, 1 at the top centre.
float perimeterAt(vec2 p)
{
    vec2 res = ubuf.resolution;
    vec2 h = res * 0.5;
    float side = min(p.x, res.x - p.x);
    float top = p.y;
    float bottom = res.y - p.y;
    float s;
    if (bottom <= side && bottom <= top)
        s = abs(p.x - h.x);
    else if (top <= side)
        s = h.x + res.y + (h.x - abs(p.x - h.x));
    else
        s = h.x + (res.y - p.y);
    return s / (res.x + res.y);
}

// x: solid band, y: glow
vec2 band(vec2 p)
{
    float depth = depthAt(p);
    if (depth < 0.0)
        return vec2(0.0);
    float level = spectrum(perimeterAt(p));
    float th = ubuf.baseWidth + level * ubuf.thickness;
    float aa = 1.0;
    float fill = 1.0 - smoothstep(th - aa, th + aa, depth);
    float glow = exp(-max(depth - th, 0.0) / (ubuf.glowRadius * (0.5 + level))) * (0.2 + 0.8 * level);
    return vec2(fill, glow);
}

void main()
{
    vec2 shift = vec2(ubuf.spread, ubuf.spread);
    vec2 p = qt_TexCoord0 * ubuf.resolution;
    if (min(depthAt(p - shift), min(depthAt(p), depthAt(p + shift)))
            > ubuf.baseWidth + ubuf.thickness + ubuf.glowRadius * 6.0) {
        fragColor = vec4(0.0);
        return;
    }

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
