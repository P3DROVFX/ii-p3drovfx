#version 440

// Contour lines of a slowly changing height field, like the isolines of a map.
//
// The height is domain-warped value noise, so the lines flow in streams and pinch into
// islands instead of rippling in rings. `time` moves the field through a third noise
// dimension: the lines drift and reshape rather than slide as a rigid picture. Every
// fifth contour is an index line, thicker, as on a survey map. Line widths come from the
// field's own screen-space derivative, so they stay hairlines at any size.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 lineColor;   // premultiplied by Qt, as every colour uniform is; alpha is the lines' opacity
    float time;
    float levels;     // contours across the field's 0..1 range
    float hillSize;   // pixels per unit of noise: the size of the "hills"
    float radius;     // corner radius of the surface the lines are cut to
    float thinWidth;  // pixels
    float indexWidth; // pixels
    float pulse;      // 0..1, the music's bass: the field breathes and its streams twist harder
} ubuf;

float hash(vec3 p)
{
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x)
{
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p)
{
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        sum += amplitude * noise(p);
        p = p * 2.03 + vec3(11.7, 3.1, 5.3);
        amplitude *= 0.5;
    }
    return sum;
}

float roundedBox(vec2 pixel, vec2 size, float r)
{
    vec2 edge = abs(pixel - size * 0.5) - size * 0.5 + vec2(r);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - r;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    vec2 p = pixel / ubuf.hillSize;

    float strength = 1.9 + 1.0 * ubuf.pulse;
    vec2 warp = vec2(fbm(vec3(p * 0.9, ubuf.time * 0.6)),
                     fbm(vec3(p * 0.9 + 7.3, ubuf.time * 0.6 + 3.1)));
    float height = fbm(vec3(p + strength * warp, ubuf.time * 0.35));

    // Value noise piles up around the middle of its range; stretching it spreads the
    // contours over the whole surface instead of a few islands.
    float v = ((height - 0.5) * (3.2 + 0.9 * ubuf.pulse) + 0.5) * ubuf.levels;
    float nearest = floor(v + 0.5);
    float gradient = max(fwidth(v), 1e-4);
    float distancePx = abs(v - nearest) / gradient;

    bool index = mod(nearest, 5.0) < 0.5;
    float width = index ? ubuf.indexWidth : ubuf.thinWidth;
    float line = 1.0 - smoothstep(width * 0.5 - 0.5, width * 0.5 + 0.5, distancePx);
    // The index lines carry a little more weight than the thin ones.
    line *= index ? 1.0 : 0.8;

    float inside = clamp(0.5 - roundedBox(pixel, ubuf.resolution, ubuf.radius), 0.0, 1.0);
    fragColor = ubuf.lineColor * (line * inside * ubuf.qt_Opacity);
}
