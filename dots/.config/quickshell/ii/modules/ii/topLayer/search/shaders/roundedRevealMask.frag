#version 440

// Shows a layer only inside a rounded box: the overview's contents revealed by the
// drop that carries them. A hard edge on purpose - a fade would sweep every pixel's
// alpha across the compositor's ignore_alpha and switch its blur on mid-animation.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 box;           // centre.xy, size.zw
    float radius;
} ubuf;

layout(binding = 1) uniform sampler2D source;

float roundedBoxDistance(vec2 pixel, vec4 shape, float radius)
{
    if (min(shape.z, shape.w) <= 0.001)
        return 1e5;
    float r = min(radius, min(shape.z, shape.w) * 0.5);
    vec2 edge = abs(pixel - shape.xy) - shape.zw * 0.5 + vec2(r);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - r;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float distance = roundedBoxDistance(pixel, ubuf.box, ubuf.radius);
    float inside = 1.0 - smoothstep(-0.5, 0.5, distance);
    fragColor = texture(source, qt_TexCoord0) * inside * ubuf.qt_Opacity;
}
