#version 440

// Camera look for the kinetic lyrics: the type layer smeared along the camera's
// motion (pan as a straight streak, zoom as a radial one, like a shutter left open
// for a frame) over a soft drop shadow cast from the same smeared alpha, optionally
// seen through a fisheye lens.
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
} ubuf;

layout(binding = 1) uniform sampler2D source;

const int TAPS = 16;
const int SHADOW_TAPS = 12;

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

void main()
{
    vec2 uv = lens(qt_TexCoord0);
    float jitter = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

    vec4 col = vec4(0.0);
    for (int i = 0; i < TAPS; i++) {
        float t = (float(i) + jitter) / float(TAPS) - 0.5;
        col += texture(source, streak(uv, t));
    }
    col /= float(TAPS);

    // Two rings of taps around the offset point, each also spread along the streak.
    float a = texture(source, uv - ubuf.shadowOffset).a * 2.0;
    for (int i = 0; i < SHADOW_TAPS; i++) {
        float angle = float(i) * 0.5235988 + jitter * 0.5235988; // 2π / 12
        float ring = (i - (i / 2) * 2) == 0 ? 1.0 : 0.5;
        vec2 o = vec2(cos(angle), sin(angle)) * ubuf.shadowBlur * ring * ubuf.texel;
        float t = (float(i) + jitter) / float(SHADOW_TAPS) - 0.5;
        a += texture(source, streak(uv - ubuf.shadowOffset + o, t)).a;
    }
    a /= float(SHADOW_TAPS) + 2.0;

    vec4 shadow = ubuf.shadowColor * a;
    fragColor = (col + shadow * (1.0 - col.a)) * ubuf.qt_Opacity;
}
