#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float hS0, hA0, hS1, hA1, hS2, hA2, hS3, hA3, hS4, hA4;
    float hS5, hA5, hS6, hA6, hS7, hA7, hS8, hA8, hS9, hA9;
    float vS0, vA0, vS1, vA1, vS2, vA2, vS3, vA3;
    float vS4, vA4, vS5, vA5, vS6, vA6;
};

float gradient10(float t,
    float s0, float a0, float s1, float a1, float s2, float a2,
    float s3, float a3, float s4, float a4, float s5, float a5,
    float s6, float a6, float s7, float a7, float s8, float a8,
    float s9, float a9) {
    float r = a0;
    r = mix(r, a1, clamp((t - s0) / (s1 - s0), 0.0, 1.0));
    r = mix(r, a2, clamp((t - s1) / (s2 - s1), 0.0, 1.0));
    r = mix(r, a3, clamp((t - s2) / (s3 - s2), 0.0, 1.0));
    r = mix(r, a4, clamp((t - s3) / (s4 - s3), 0.0, 1.0));
    r = mix(r, a5, clamp((t - s4) / (s5 - s4), 0.0, 1.0));
    r = mix(r, a6, clamp((t - s5) / (s6 - s5), 0.0, 1.0));
    r = mix(r, a7, clamp((t - s6) / (s7 - s6), 0.0, 1.0));
    r = mix(r, a8, clamp((t - s7) / (s8 - s7), 0.0, 1.0));
    r = mix(r, a9, clamp((t - s8) / (s9 - s8), 0.0, 1.0));
    return r;
}

float gradient7(float t,
    float s0, float a0, float s1, float a1, float s2, float a2,
    float s3, float a3, float s4, float a4, float s5, float a5,
    float s6, float a6) {
    float r = a0;
    r = mix(r, a1, clamp((t - s0) / (s1 - s0), 0.0, 1.0));
    r = mix(r, a2, clamp((t - s1) / (s2 - s1), 0.0, 1.0));
    r = mix(r, a3, clamp((t - s2) / (s3 - s2), 0.0, 1.0));
    r = mix(r, a4, clamp((t - s3) / (s4 - s3), 0.0, 1.0));
    r = mix(r, a5, clamp((t - s4) / (s5 - s4), 0.0, 1.0));
    r = mix(r, a6, clamp((t - s5) / (s6 - s5), 0.0, 1.0));
    return r;
}

void main() {
    float hAlpha = gradient10(qt_TexCoord0.x,
        hS0, hA0, hS1, hA1, hS2, hA2, hS3, hA3, hS4, hA4,
        hS5, hA5, hS6, hA6, hS7, hA7, hS8, hA8, hS9, hA9);
    float vAlpha = gradient7(qt_TexCoord0.y,
        vS0, vA0, vS1, vA1, vS2, vA2, vS3, vA3, vS4, vA4,
        vS5, vA5, vS6, vA6);
    fragColor = vec4(0.0, 0.0, 0.0, hAlpha * vAlpha) * qt_Opacity;
}
