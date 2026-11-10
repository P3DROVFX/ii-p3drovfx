#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Along the axis, in 0..1: sharp before blurStart, blurred by maxRadius
    // from blurEnd on, the radius easing in between.
    float blurStart;
    float blurEnd;
    // Largest blur radius, in the item's logical pixels.
    float maxRadius;
    // The item's size in logical pixels, to turn the radius into texture space.
    float itemWidth;
    float itemHeight;
    // Opacity reached at blurEnd (1 keeps the blurred end fully opaque).
    float endOpacity;
    // 1 = the blur grows along y, 0 = along x; 1 = it grows towards the start.
    float vertical;
    float reversed;
};

layout(binding = 1) uniform sampler2D source;

const int TAPS = 48;
const float GOLDEN_ANGLE = 2.39996323;

// A variable-radius blur in one pass: every pixel averages a golden-angle
// spiral of taps over a disc whose radius follows its position on the axis.
// The blur itself gets stronger - no sharp copy crossfaded with a blurred one,
// which ghosts a transparent subject such as text into a double image.
void main() {
    float t = vertical > 0.5 ? qt_TexCoord0.y : qt_TexCoord0.x;
    if (reversed > 0.5)
        t = 1.0 - t;
    float amount = blurEnd > blurStart ? smoothstep(blurStart, blurEnd, t) : step(blurStart, t);
    float radius = maxRadius * amount;

    vec4 color;
    if (radius < 0.5) {
        color = texture(source, qt_TexCoord0);
    } else {
        vec2 toUv = vec2(radius / max(itemWidth, 1.0), radius / max(itemHeight, 1.0));
        vec4 sum = vec4(0.0);
        float weightSum = 0.0;
        for (int i = 0; i < TAPS; i++) {
            float f = (float(i) + 0.5) / float(TAPS);
            float r = sqrt(f);
            float a = float(i) * GOLDEN_ANGLE;
            // Gaussian falloff over a uniformly filled disc.
            float w = exp(-2.5 * f);
            sum += texture(source, qt_TexCoord0 + vec2(cos(a), sin(a)) * r * toUv) * w;
            weightSum += w;
        }
        color = sum / weightSum;
    }
    // Premultiplied colour: scaling the whole vector fades it correctly.
    fragColor = color * mix(1.0, endOpacity, amount) * qt_Opacity;
}
