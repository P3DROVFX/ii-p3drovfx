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
    float bubbleRadius; // a pill or a circle rounds fully; an expanded bubble is a card
    float bodyCut;      // how far inside the body's edge the field is cut away; 0 = at it
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
    float bubble = roundedBoxDistance(pixel, ubuf.bubbleShape, ubuf.bubbleRadius);
    float surface = smoothMinimum(body, bubble, ubuf.blend);

    float aa = max(fwidth(surface), 0.001);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, surface);

    // Only what lies outside the body is drawn: the island draws its own body, and
    // drawing it twice would double its edge and its shadow.
    //
    // An opaque island hides whatever is under it, so the cut sits `bodyCut` inside its
    // edge and the neck tucks beneath it with no seam to align. A see-through one hides
    // nothing: that tuck showed through as a dark rim all the way round the body, ending
    // at the island's centre because the field is only drawn on the bubble's half.
    // Moving it is no answer - the cut and the union's own edge are a fixed distance
    // apart, so the rim only moves with it.
    //
    // With `bodyCut` at zero the body's coverage is subtracted from the union's instead.
    // Away from the neck the two are the same number - the union IS the body there - so
    // the difference is exactly zero and nothing is drawn under the island. Only where
    // the smooth minimum actually pulls the surface out past the body, which is the
    // neck, does anything survive, and it meets the body's edge with the complementary
    // coverage: no rim, no seam, at any alpha.
    float bodyAa;
    if (ubuf.bodyCut > 0.0) {
        float inner = body + ubuf.bodyCut;
        bodyAa = max(fwidth(inner), 0.001);
        float insideBody = 1.0 - smoothstep(-bodyAa * 0.5, bodyAa * 0.5, inner);
        alpha *= 1.0 - insideBody;
    } else {
        bodyAa = max(fwidth(body), 0.001);
        float insideBody = 1.0 - smoothstep(-bodyAa * 0.5, bodyAa * 0.5, body);
        alpha = max(0.0, alpha - insideBody);
    }

    fragColor = ubuf.fillColor * alpha * ubuf.qt_Opacity;
}
