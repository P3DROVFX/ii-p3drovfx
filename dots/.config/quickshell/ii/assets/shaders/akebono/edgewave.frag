#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 color;
    float radiusTop;
    float radiusBottom;
    float smoothing;
    float inset;
    float phase;
    float amp;
    float waves;
};

const float PI = 3.14159265359;
const float HALF_PI = 1.57079632679;
const float TWO_PI = 6.28318530718;

float sdSquircle(vec2 p, vec2 b, float r, float n) {
    vec2 q = abs(p) - b + vec2(r);
    float outside = pow(pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n), 1.0 / n);
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

float perimU(vec2 p, vec2 b, float r) {
    float sx = max(b.x - r, 0.0);
    float sy = max(b.y - r, 0.0);
    float c = HALF_PI * r;
    float P = 4.0 * sx + 4.0 * sy + 4.0 * c;

    float t1 = sy;
    float t2 = t1 + c;
    float t3 = t2 + 2.0 * sx;
    float t4 = t3 + c;
    float t5 = t4 + 2.0 * sy;
    float t6 = t5 + c;
    float t7 = t6 + 2.0 * sx;
    float t8 = t7 + c;

    float ex = abs(p.x) - sx;
    float ey = abs(p.y) - sy;
    float s;

    if (ex <= 0.0) {
        if (p.y > 0.0)
            s = t2 + (sx - p.x);
        else
            s = t6 + (p.x + sx);
    } else if (ey <= 0.0) {
        if (p.x > 0.0)
            s = (p.y >= 0.0) ? p.y : (t8 + (p.y + sy));
        else
            s = t4 + (sy - p.y);
    } else {
        vec2 cen = vec2(sign(p.x) * sx, sign(p.y) * sy);
        vec2 o = p - cen;
        float a = atan(o.y, o.x);
        if (p.x > 0.0 && p.y > 0.0)
            s = t1 + a * r;
        else if (p.x < 0.0 && p.y > 0.0)
            s = t3 + (a - HALF_PI) * r;
        else if (p.x < 0.0 && p.y < 0.0)
            s = t5 + ((a < 0.0 ? a + TWO_PI : a) - PI) * r;
        else
            s = t7 + ((a + TWO_PI) - 1.5 * PI) * r;
    }

    return s / max(P, 0.0001);
}

void main() {
    vec2 halfSize = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 b = halfSize - vec2(inset);
    float r = (p.y < 0.0) ? radiusTop : radiusBottom;
    r = min(r, min(b.x, b.y));
    float d = sdSquircle(p, b, r, max(smoothing, 2.0));

    float u = perimU(p, b, r);
    d -= amp * sin(TWO_PI * waves * u - phase);

    float coverage = clamp(0.5 - d, 0.0, 1.0);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
