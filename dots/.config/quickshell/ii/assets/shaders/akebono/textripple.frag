#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float amp;
    float freq;
    vec2 invSize;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    float e = 1.2;
    vec2 ex = vec2(e * invSize.x, 0.0);
    vec2 ey = vec2(0.0, e * invSize.y);
    float a = texture(source, uv).a;
    float aL = texture(source, uv - ex).a;
    float aR = texture(source, uv + ex).a;
    float aD = texture(source, uv - ey).a;
    float aU = texture(source, uv + ey).a;
    vec2 grad = vec2(aR - aL, aU - aD);
    float edgeNear = clamp(length(grad) * 3.0, 0.0, 1.0);
    vec2 nin = length(grad) > 0.0001 ? normalize(grad) : vec2(0.0);

    vec4 inS = texture(source, uv + nin * 3.0 * invSize);
    vec3 col = inS.rgb / max(inS.a, 0.0001);

    vec2 cc = uv - vec2(0.5, 0.5);
    float ang = atan(cc.y, cc.x);
    float ripple = amp * edgeNear * sin(ang * freq - phase);

    float cov = smoothstep(0.5 - 0.18, 0.5 + 0.18, a + ripple);
    fragColor = vec4(col * cov, cov) * qt_Opacity;
}
