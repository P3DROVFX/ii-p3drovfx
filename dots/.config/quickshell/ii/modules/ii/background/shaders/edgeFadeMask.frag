#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Along the fade axis, in 0..1: fully clear before startClear, fully shown
    // from startSolid to endSolid, clear again after endClear.
    float startClear;
    float startSolid;
    float endSolid;
    float endClear;
    // 1 = fade along y, 0 = along x.
    float vertical;
};

layout(binding = 1) uniform sampler2D source;

// A continuous fade computed per pixel: no mask texture and no threshold, so
// the opacity changes smoothly and anything cut at the clear end is at zero.
void main() {
    float t = vertical > 0.5 ? qt_TexCoord0.y : qt_TexCoord0.x;
    float fadeIn = startSolid > startClear ? smoothstep(startClear, startSolid, t) : step(startClear, t);
    float fadeOut = endClear > endSolid ? 1.0 - smoothstep(endSolid, endClear, t) : 1.0 - step(endClear, t);
    fragColor = texture(source, qt_TexCoord0) * (fadeIn * fadeOut * qt_Opacity);
}
