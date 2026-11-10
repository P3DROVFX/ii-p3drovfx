#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Along the band's axis, as fractions of this item measured from the bar's
    // edge of the screen: fully blurred up to bandSolid (the bar itself), clear
    // from bandSize on. Past bandSize the item only holds padding for the blur.
    float bandSolid;
    float bandSize;
    // 1 when the bar runs along x (band along y), 1 when it sits at the far
    // end (bottom/right).
    float alongY;
    float fromEnd;
};

// The wallpaper under the band, blurred twice (premultiplied, same geometry).
layout(binding = 1) uniform sampler2D mediumBlur;
layout(binding = 2) uniform sampler2D strongBlur;

// A progressive blur: the strong level holds under the whole bar, hands over
// to the medium one past it, and that fades into the sharp wallpaper. A
// single level crossfaded with the sharp picture reads as a ghosted double
// image rather than as blur getting weaker.
void main() {
    float t = alongY > 0.5 ? qt_TexCoord0.y : qt_TexCoord0.x;
    if (fromEnd > 0.5)
        t = 1.0 - t;
    float span = max(bandSize, 0.0001);
    // 0 at the bar's edge of the screen, 1 where the band ends.
    float p = t / span;
    float solid = clamp(bandSolid / span, 0.0, 0.999);
    float ramp = clamp((p - solid) / (1.0 - solid), 0.0, 1.0);

    float strongWeight = 1.0 - smoothstep(0.0, 0.55, ramp);
    // Squared: leaves full strength gently, then drops early, so the
    // weak tail of the blur does not reach far below the bar.
    float coverage = 1.0 - smoothstep(0.0, 1.0, ramp);
    coverage *= coverage;

    vec4 blurred = mix(texture(mediumBlur, qt_TexCoord0), texture(strongBlur, qt_TexCoord0), strongWeight);
    fragColor = blurred * (coverage * qt_Opacity);
}
