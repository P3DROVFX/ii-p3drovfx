#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 color;
    vec4 bgColor;
    float radius;
    float smoothing;
    float level;
    float wavePhase;
    float waveAmp;
};

float sdSquircle(vec2 p, vec2 b, float r, float n) {
    vec2 q = abs(p) - b + vec2(r);
    float outside = pow(pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n), 1.0 / n);
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

void main() {
    vec2 P = qt_TexCoord0 * size;
    float n = max(smoothing, 2.0);
    vec2 half_ = size * 0.5;
    float r = min(radius, min(half_.x, half_.y));
    float d = sdSquircle(P - half_, half_, r, n);
    float cov = clamp(0.5 - d, 0.0, 1.0);

    float amp = waveAmp * smoothstep(0.0, 0.06, level) * smoothstep(1.0, 0.94, level);
    float wave = amp * (sin(P.x * 0.18 + wavePhase) + 0.4 * sin(P.x * 0.33 - 2.0 * wavePhase));
    float surface = size.y * (1.0 - level) + wave;
    float liquid = clamp(0.5 + (P.y - surface), 0.0, 1.0);

    vec4 col = mix(bgColor, color, liquid);
    float a = col.a * cov * qt_Opacity;
    fragColor = vec4(col.rgb * a, a);
}
