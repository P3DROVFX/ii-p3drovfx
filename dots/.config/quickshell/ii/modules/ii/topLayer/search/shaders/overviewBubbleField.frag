#version 440

// The connect-mode overview as a drop pulled out of the search drop.
//
// The island's bubbleField, turned downwards: a smooth minimum joins the search's
// rounded box (the body) and the overview's (the bubble) with a liquid neck while
// they are close, and a zero blend separates them. Only what lies outside the body is
// drawn - the search surface draws its own - so the body's coverage is subtracted
// from the union's, which leaves nothing under a translucent search and meets its
// edge with the complementary coverage.
//
// The two surfaces wear different colours; the neck runs from one to the other by
// which shape a pixel is nearer to. Colours come in premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 bodyColor;
    vec4 bubbleColor;
    vec4 bodyShape;     // centre.xy, size.zw
    vec4 bubbleShape;   // centre.xy, size.zw
    float bodyRadius;
    float bubbleRadius;
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

float coverage(float distance)
{
    float aa = max(fwidth(distance), 0.001);
    return 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float body = roundedBoxDistance(pixel, ubuf.bodyShape, ubuf.bodyRadius);
    float bubble = roundedBoxDistance(pixel, ubuf.bubbleShape, ubuf.bubbleRadius);
    float surface = smoothMinimum(body, bubble, ubuf.blend);

    float alpha = max(0.0, coverage(surface) - coverage(body));
    // The hue runs from one surface to the other through the neck, but the alpha
    // switches at its middle: a gradient of alpha would sweep the neck's pixels across
    // the compositor's ignore_alpha while it moves, and their blur would flicker.
    float towardsBubble = smoothstep(-1.0, 1.0, (body - bubble) / max(ubuf.blend * 0.5, 1.0));
    vec3 bodyHue = ubuf.bodyColor.rgb / max(ubuf.bodyColor.a, 0.001);
    vec3 bubbleHue = ubuf.bubbleColor.rgb / max(ubuf.bubbleColor.a, 0.001);
    float surfaceAlpha = bubble < body ? ubuf.bubbleColor.a : ubuf.bodyColor.a;
    vec3 hue = mix(bodyHue, bubbleHue, towardsBubble);
    fragColor = vec4(hue * surfaceAlpha, surfaceAlpha) * alpha * ubuf.qt_Opacity;
}
