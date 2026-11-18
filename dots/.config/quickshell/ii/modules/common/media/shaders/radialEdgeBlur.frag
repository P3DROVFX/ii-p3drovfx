#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // The item's size in logical pixels.
    float itemWidth;
    float itemHeight;
    // How far in from every edge, in logical pixels, the blur reaches before
    // the picture is sharp. The strong level holds at the edge itself.
    float band;
};

// The same picture three times, same geometry: sharp, medium and strong blur.
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D mediumBlur;
layout(binding = 3) uniform sampler2D strongBlur;

// A progressive blur that grows towards all four edges at once. Distance is
// measured out of a centred box inset by `band` on every side, so the ramp
// has the same width along each edge and rounds itself off at the corners.
// Blur levels are handed over to one another rather than one blurred copy
// being crossfaded with the sharp picture, which reads as a ghosted double
// image instead of blur getting stronger.
void main() {
    vec2 size = vec2(max(itemWidth, 1.0), max(itemHeight, 1.0));
    vec2 pos = (qt_TexCoord0 - 0.5) * size;
    vec2 inner = max(size * 0.5 - vec2(band), vec2(0.0));
    float outside = length(max(abs(pos) - inner, vec2(0.0)));
    float ramp = smoothstep(0.0, max(band, 1.0), outside);

    vec4 sharp = texture(source, qt_TexCoord0);
    vec4 medium = texture(mediumBlur, qt_TexCoord0);
    vec4 strong = texture(strongBlur, qt_TexCoord0);
    vec4 color = mix(sharp, medium, clamp(ramp * 2.0, 0.0, 1.0));
    color = mix(color, strong, clamp(ramp * 2.0 - 1.0, 0.0, 1.0));
    fragColor = color * qt_Opacity;
}
