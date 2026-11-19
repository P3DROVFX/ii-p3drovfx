#version 440

// Camera look for the kinetic lyrics: the type layer smeared along the camera's
// motion (pan as a straight streak, zoom as a radial one, like a shutter left open
// for a frame) over a soft drop shadow cast from the same smeared alpha, optionally
// seen through a fisheye lens. Beat hits (kinetic beat shake) add a glow halo
// tinted by the type itself and an RGB split.
//
// The streak taps start at a per-pixel offset (interleaved gradient noise). With
// fixed offsets a long streak is a stack of copies, and every horizontal or vertical
// stroke shows their steps as notches; jittered, the steps dissolve into a smooth smear.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 velocity;     // pan streak, uv units
    float zoomRate;    // radial streak, uv units per uv from the centre
    vec2 shadowOffset; // uv
    vec2 texel;        // 1 / texture size
    float shadowBlur;  // texels
    vec4 shadowColor;  // premultiplied
    float fisheye;     // barrel strength, 0 for none
    float aspect;      // width / height
    float glow;        // 0..1 halo strength on a beat hit
    vec2 split;        // RGB split offset, uv
    float turbulence;  // turbulent displacement on a hit, uv (AE Turbulent Displace)
    float turbSeed;
    // Camera move applied here instead of on the item (the artwork): offset in uv,
    // roll in radians, zoom as a factor; with `mirror` the samples past the edges
    // reflect the image (Sapphire's Wrap: Reflect), so the cover never shows its edge.
    vec2 shakeOffset;
    float shakeRoll;
    float shakeZoom;
    float mirror;
} ubuf;

layout(binding = 1) uniform sampler2D source;

const int TAPS = 16;
const int SHADOW_TAPS = 12;

vec4 tap(vec2 uv)
{
    if (ubuf.mirror > 0.5) {
        vec2 m = mod(uv, 2.0);
        uv = mix(m, 2.0 - m, step(1.0, m));
    }
    return texture(source, uv);
}

vec2 camera(vec2 uv)
{
    vec2 d = (uv - 0.5 - ubuf.shakeOffset) * vec2(ubuf.aspect, 1.0);
    float c = cos(ubuf.shakeRoll), s = sin(ubuf.shakeRoll);
    d = vec2(c * d.x + s * d.y, -s * d.x + c * d.y) / max(0.01, ubuf.shakeZoom);
    return 0.5 + d / vec2(ubuf.aspect, 1.0);
}

vec2 streak(vec2 uv, float t)
{
    return uv + (ubuf.velocity + (uv - 0.5) * ubuf.zoomRate) * t;
}

// Barrel distortion that keeps the corners in place: the middle swells, the edges
// crowd together, like a wide lens close to the subject.
vec2 lens(vec2 uv)
{
    if (ubuf.fisheye <= 0.0)
        return uv;
    vec2 p = (uv - 0.5) * vec2(ubuf.aspect, 1.0);
    float r2 = dot(p, p);
    float corner = 0.25 * (ubuf.aspect * ubuf.aspect + 1.0);
    float f = (1.0 + ubuf.fisheye * r2) / (1.0 + ubuf.fisheye * corner);
    return 0.5 + p * f / vec2(ubuf.aspect, 1.0);
}

float hash21(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main()
{
    vec2 uv = camera(lens(qt_TexCoord0));
    if (ubuf.turbulence > 0.0001) {
        vec2 q = uv * vec2(ubuf.aspect, 1.0) * 5.0 + ubuf.turbSeed;
        vec2 n = vec2(valueNoise(q) + 0.5 * valueNoise(q * 2.1 + 7.3),
                      valueNoise(q + 19.7) + 0.5 * valueNoise(q * 2.1 + 31.1)) / 1.5 - 0.5;
        uv += n * 2.0 * ubuf.turbulence;
    }
    float jitter = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

    vec4 col = vec4(0.0);
    for (int i = 0; i < TAPS; i++) {
        float t = (float(i) + jitter) / float(TAPS) - 0.5;
        col += tap(streak(uv, t));
    }
    col /= float(TAPS);

    // RGB split: red and blue pulled apart along the hit's direction.
    if (dot(ubuf.split, ubuf.split) > 1e-8) {
        vec4 r = tap(uv + ubuf.split);
        vec4 b = tap(uv - ubuf.split);
        col = vec4(r.r, col.g, b.b, max(col.a, max(r.a, b.a)));
    }

    // Two rings of taps around the offset point, each also spread along the streak.
    float a = tap(uv - ubuf.shadowOffset).a * 2.0;
    for (int i = 0; i < SHADOW_TAPS; i++) {
        float angle = float(i) * 0.5235988 + jitter * 0.5235988; // 2π / 12
        float ring = (i - (i / 2) * 2) == 0 ? 1.0 : 0.5;
        vec2 o = vec2(cos(angle), sin(angle)) * ubuf.shadowBlur * ring * ubuf.texel;
        float t = (float(i) + jitter) / float(SHADOW_TAPS) - 0.5;
        a += tap(streak(uv - ubuf.shadowOffset + o, t)).a;
    }
    a /= float(SHADOW_TAPS) + 2.0;

    vec4 shadow = ubuf.shadowColor * a;
    vec4 outColor = col + shadow * (1.0 - col.a);

    // Glow: two wide rings of the type's own colour, added on top.
    if (ubuf.glow > 0.002) {
        vec4 halo = vec4(0.0);
        for (int i = 0; i < 12; i++) {
            float angle = float(i) * 0.5235988 + jitter * 0.5235988;
            float ring = (i - (i / 2) * 2) == 0 ? 1.0 : 0.45;
            halo += tap(uv + vec2(cos(angle), sin(angle)) * 34.0 * ring * ubuf.texel);
        }
        halo /= 12.0;
        outColor.rgb += halo.rgb * ubuf.glow * 1.1 + col.rgb * ubuf.glow * 0.12;
        outColor.a = max(outColor.a, min(1.0, halo.a * ubuf.glow));
    }
    fragColor = outColor * ubuf.qt_Opacity;
}
