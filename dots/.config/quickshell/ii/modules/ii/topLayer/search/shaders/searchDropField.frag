#version 440

// The connect-mode search drop as one signed distance field: the bar's edge and the
// drop's rounded box, joined by a round union.
//
// Same idea as the island's bubbleField: the bar is the body and the drop is pulled out
// of it. The union's fillet is what draws the concave shoulders, so at rest the shape
// is the old Notch (quarter-circle shoulders of `fillet`, corners of `boxRadius`), and
// while the drop is small and rounder the same fillet reads as a liquid neck. The bar
// itself is never drawn: the field starts at its edge (y = 0).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 fillColor;
    vec4 box;           // centre.xy, size.zw
    float boxRadius;
    float fillet;
} ubuf;

float roundedBoxDistance(vec2 pixel, vec4 shape, float radius)
{
    if (min(shape.z, shape.w) <= 0.001)
        return 1e5;
    float r = min(radius, min(shape.z, shape.w) * 0.5);
    vec2 edge = abs(pixel - shape.xy) - shape.zw * 0.5 + vec2(r);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - r;
}

// A union whose joint is an exact circular arc of `radius` between perpendicular edges.
float roundUnion(float first, float second, float radius)
{
    vec2 inner = max(vec2(radius - first, radius - second), vec2(0.0));
    return max(radius, min(first, second)) - length(inner);
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float bar = pixel.y;
    float drop = roundedBoxDistance(pixel, ubuf.box, ubuf.boxRadius);
    float surface = roundUnion(bar, drop, max(ubuf.fillet, 0.0));

    float aa = max(fwidth(surface), 0.001);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, surface);
    fragColor = ubuf.fillColor * alpha * ubuf.qt_Opacity;
}
