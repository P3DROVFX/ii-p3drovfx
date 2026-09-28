#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // 0 fades along y (top → bottom), 1 along x (left → right).
    float horizontal;
    float startAlpha;
    float startStop;
    float endStop;
    float endAlpha;
};

layout(binding = 1) uniform sampler2D source;

// The same four-stop linear ramp the Gradient mask drew, computed per pixel instead of
// rendered into a second texture.
void main() {
    float t = mix(qt_TexCoord0.y, qt_TexCoord0.x, horizontal);
    float a = 1.0;
    if (t < startStop)
        a = mix(startAlpha, 1.0, clamp(t / max(startStop, 1e-4), 0.0, 1.0));
    else if (t > endStop)
        a = mix(1.0, endAlpha, clamp((t - endStop) / max(1.0 - endStop, 1e-4), 0.0, 1.0));
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}
