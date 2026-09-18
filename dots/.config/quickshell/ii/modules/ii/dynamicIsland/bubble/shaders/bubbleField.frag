#version 440

// The island's body and its auxiliary bubble as one signed distance field.
//
// Adapted from clavis' spotlight_mode_field: a smooth minimum joins the two shapes with
// a liquid neck while they are close, and a zero blend separates them cleanly. Here the
// body is a rounded box (the island is not always a capsule) and there is one bubble.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 fillColor;
    vec4 mainShape;     // centre.xy, size.zw
    vec4 bubbleShape;   // centre.xy, size.zw
    float mainRadius;
    float blend;
} ubuf;

float roundedBoxDistance(vec2 pixel, vec4 shape, float radius)
{
    if (min(shape.z, shape.w) <= 0.001)
        return 1e5;
    float r = min(radius, min(shape.z, shape.w) * 0.5);
    vec2 edge = abs(pixel - shape.xy) - shape.zw * 0.5 + vec2(r);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - r;
}

float smoothMinimum(float first, float second, float radius)
{
    if (radius <= 0.001)
        return min(first, second);
    float influence = max(radius - abs(first - second), 0.0) / radius;
    return min(first, second) - influence * influence * radius * 0.25;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float body = roundedBoxDistance(pixel, ubuf.mainShape, ubuf.mainRadius);
    float bubble = roundedBoxDistance(pixel, ubuf.bubbleShape, 1e5);
    float surface = smoothMinimum(body, bubble, ubuf.blend);

    float aa = max(fwidth(surface), 0.001);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, surface);

    // Only what lies outside the body is drawn: the island draws its own body, and
    // drawing it twice would double its edge and its shadow. The cut sits a pixel and a
    // half inside the body's edge, so the neck tucks under it without a seam.
    float inner = body + 1.5;
    float bodyAa = max(fwidth(inner), 0.001);
    float insideBody = 1.0 - smoothstep(-bodyAa * 0.5, bodyAa * 0.5, inner);
    alpha *= 1.0 - insideBody;

    fragColor = ubuf.fillColor * alpha * ubuf.qt_Opacity;
}
