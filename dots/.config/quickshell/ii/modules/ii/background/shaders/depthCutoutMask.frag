#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Canvas alpha from which a pixel counts as covered: any widget pixel, its
    // anti-aliased rim and a translucent card included.
    float maskThreshold;
    // BarGradientOverlay, which the wallpaper window draws over the picture
    // under a transparent bar: 0..1 while it shows, the band's depth as a
    // fraction of the axis, 1 when the bar runs along x (band along y), 1 when
    // the bar sits at the far end (bottom/right).
    float barBand;
    float barBandSize;
    float barBandAlongY;
    float barBandFromEnd;
    // Widget outlines over the subject: 0..1, the mask's texel size, and the
    // outline's width in pixels.
    float outline;
    vec2 maskTexel;
    float outlineWidth;
};

// The cutout (premultiplied) and the widget canvas, both in window space.
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D maskSource;

// "Source atop", near enough: the subject is painted only where the canvas
// has pixels. Over bare wallpaper the surface stays transparent, so the screen
// shows the wallpaper itself - never the compositor's blur behind a
// half-transparent cutout edge. Coverage is binary: a proportional mask let a
// widget's half-covered rim (alpha a) leak through at a(1-a), tracing the
// clock's digits across the subject's face, and any partial coverage leaves a
// half-transparent pixel the compositor blurs behind (a dark seam along each
// widget's edge). Covered, the cutout is opaque over the subject's interior
// and the pixel is the wallpaper's own; uncovered, nothing is drawn.
//
// Under a transparent bar the wallpaper is darkened and blurred toward the
// bar; the cutout, drawn in another window, has neither. It takes the same
// darkening and yields to the widget as much as the picture is blurred there,
// so no untreated piece of wallpaper shows inside a widget near the bar.
float covered(vec2 uv) {
    return step(maskThreshold, texture(maskSource, uv).a);
}

// How near the canvas's coverage ends, seen from a covered pixel: 1 within
// half the outline's width of an uncovered pixel, fading out by its full
// width. Inside the widget only, so the outline never leaves a
// half-transparent pixel over bare wallpaper.
// One direction, both radii. Spelled out per direction rather than looped
// over a const array: the GLSL that qsb emits for that is refused by the
// NVIDIA driver ("OpenGL does not allow constant arrays").
float edgeAlong(vec2 uv, vec2 dir, float nearR, float farR) {
    float nearEdge = 1.0 - covered(uv + dir * nearR * maskTexel);
    float farEdge = 0.5 * (1.0 - covered(uv + dir * farR * maskTexel));
    return max(nearEdge, farEdge);
}

float innerEdge(vec2 uv) {
    float nearR = max(1.0, outlineWidth * 0.5);
    float farR = max(nearR + 1.0, outlineWidth);
    float d = 0.70710678;
    float edge = edgeAlong(uv, vec2(1.0, 0.0), nearR, farR);
    edge = max(edge, edgeAlong(uv, vec2(-1.0, 0.0), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(0.0, 1.0), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(0.0, -1.0), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(d, d), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(-d, d), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(d, -d), nearR, farR));
    edge = max(edge, edgeAlong(uv, vec2(-d, -d), nearR, farR));
    return edge;
}

void main() {
    vec4 mask = texture(maskSource, qt_TexCoord0);
    float coverage = step(maskThreshold, mask.a);
    vec4 color = texture(source, qt_TexCoord0);

    float t = barBandAlongY > 0.5 ? qt_TexCoord0.y : qt_TexCoord0.x;
    if (barBandFromEnd > 0.5)
        t = 1.0 - t;
    // 0 at the bar's edge of the screen, 1 where the band ends.
    float p = t / max(barBandSize, 0.0001);
    if (barBand > 0.0 && p < 1.0) {
        // The overlay's black gradient: 0.45 at the edge, 0.15 at 55%, 0 at the end.
        float dark = p < 0.55 ? mix(0.45, 0.15, p / 0.55) : mix(0.15, 0.0, (p - 0.55) / 0.45);
        // Its blur mask, from the band's end: 0, 0.4 at 55%, 1 at the edge.
        float q = 1.0 - p;
        float blurred = q < 0.55 ? mix(0.0, 0.4, q / 0.55) : mix(0.4, 1.0, (q - 0.55) / 0.45);
        color.rgb *= 1.0 - dark * barBand;
        coverage *= 1.0 - blurred * barBand;
    }
    vec4 result = color * coverage;
    // The widget's outline, in the widget's own colour, drawn over the
    // subject (and nowhere else): the clock's digits traced across a face.
    if (outline > 0.0 && coverage > 0.0 && color.a > 0.0) {
        float strength = innerEdge(qt_TexCoord0) * outline * color.a * coverage;
        vec3 widgetColor = mask.rgb / max(mask.a, 0.0001);
        result = result * (1.0 - strength) + vec4(widgetColor, 1.0) * strength;
    }
    fragColor = result * qt_Opacity;
}
