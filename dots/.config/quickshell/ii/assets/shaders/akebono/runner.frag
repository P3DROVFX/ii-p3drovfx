#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 color;
    vec2 rippleOrigin;
    float radiusTop;
    float radiusBottom;
    float smoothing;
    float inset;
    float rippleProgress;
    float rippleAmp;
};

float sdSquircle(vec2 p, vec2 b, float r, float n) {
    vec2 q = abs(p) - b + vec2(r);
    float outside = pow(pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n), 1.0 / n);
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

void main() {
    vec2 halfSize = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 b = halfSize - vec2(inset);
    float r = (p.y < 0.0) ? radiusTop : radiusBottom;
    r = min(r, min(b.x, b.y));
    float d = sdSquircle(p, b, r, max(smoothing, 2.0));

    if (rippleProgress > 0.0 && rippleProgress < 1.0) {
        vec2 ro = rippleOrigin - halfSize;
        float dist = length(p - ro);
        float amp = rippleAmp * (1.0 - rippleProgress);
        float ripple = amp * sin(0.05 * dist - 11.0 * rippleProgress) * exp(-0.006 * dist);
        float t = clamp(p.y / halfSize.y * 0.5 + 0.5, 0.0, 1.0);
        ripple *= smoothstep(0.4, 1.0, t);
        d -= ripple;
    }

    float coverage = clamp(0.5 - d, 0.0, 1.0);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
