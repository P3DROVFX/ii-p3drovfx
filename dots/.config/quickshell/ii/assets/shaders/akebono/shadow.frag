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
    float spread;
    vec2 boxHalf;
    vec2 boxCenter;
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
    float rB = min(radius, min(boxHalf.x, boxHalf.y));
    float d = sdSquircle(P - boxCenter, boxHalf, rB, n);
    float coverage = 1.0 - smoothstep(-spread, spread, d);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
