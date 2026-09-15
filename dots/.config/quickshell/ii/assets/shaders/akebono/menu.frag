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
    float sminK;
    vec2 mainCenter;
    vec2 mainHalf;
    vec2 subCenter;
    vec2 subHalf;
    float subProgress;
    float subSide;
    float overlap;
    vec2 rippleOrigin;
    float rippleProgress;
    float rippleAmp;
    float attachY;
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

void main() {
    vec2 P = qt_TexCoord0 * size;
    float n = max(smoothing, 2.0);

    float rMain = min(radius, min(mainHalf.x, mainHalf.y));
    float d = sdSquircle(P - mainCenter, mainHalf, rMain, n);

    if (subProgress > 0.001) {
        float innerX = mainCenter.x + subSide * mainHalf.x - subSide * overlap;
        vec2 sc = mix(vec2(innerX, attachY), subCenter, subProgress);
        vec2 sh = subHalf * subProgress;
        float rSub = min(radius, min(sh.x, sh.y));
        float dSub = sdSquircle(P - sc, sh, rSub, n);
        d = smin(d, dSub, sminK);
    }

    if (rippleProgress > 0.0 && rippleProgress < 1.0) {
        float dist = length(P - rippleOrigin);
        float amp = rippleAmp * (1.0 - rippleProgress);
        float ripple = amp * sin(0.06 * dist - 12.0 * rippleProgress) * exp(-0.012 * dist);
        d -= ripple;
    }

    float coverage = clamp(0.5 - d, 0.0, 1.0);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
