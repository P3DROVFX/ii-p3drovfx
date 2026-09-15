#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 color;
    float radius;
    float smoothing;
    float inset;
    float pillHalfH;
    float fromY;
    float toY;
    float leadProg;
    float bodyProg;
    float dollopScale;
    float sminK;
};

float sdSquircle(vec2 p, vec2 b, float r, float n) {
    vec2 q = abs(p) - b + vec2(r);
    float outside = pow(pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n), 1.0 / n);
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float lobe(vec2 p, float cy, float hw, float hh, float r, float n) {
    return sdSquircle(p - vec2(0.0, cy), vec2(hw, hh), min(r, min(hw, hh)), n);
}

void main() {
    vec2 halfSize = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    float n = max(smoothing, 2.0);
    float halfW = halfSize.x - inset;

    float leadY = mix(fromY, toY, leadProg) - halfSize.y;
    float bodyY = mix(fromY, toY, bodyProg) - halfSize.y;

    float trail = clamp(abs(leadProg - bodyProg), 0.0, 1.0);
    float bodyHH = pillHalfH * (1.0 + 0.40 * trail);
    float bodyHW = halfW * (1.0 - 0.12 * trail);

    float dolHH = pillHalfH * dollopScale;
    float dolHW = halfW * mix(0.55, 1.0, clamp(bodyProg, 0.0, 1.0));

    float dBody = lobe(p, bodyY, bodyHW, bodyHH, radius, n);
    float dDol = lobe(p, leadY, dolHW, dolHH, radius, n);
    float d = smin(dBody, dDol, sminK);

    float coverage = clamp(0.5 - d, 0.0, 1.0);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
