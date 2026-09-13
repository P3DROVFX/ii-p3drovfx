#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenExtent;
    float maskExtent;
    vec2 rotationVector;
    float maskReady;
    vec2 maskScreenExtent;
    float sourceScale;
    vec2 sourceOffset;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D maskSource;

void main() {
    if (maskReady < 0.5) {
        fragColor = texture(source, qt_TexCoord0) * qt_Opacity;
        return;
    }

    // Undo QML's centered rotation/scale in pixel space, including on portrait
    // and ultrawide screens. Normalized screen UVs alone distort the shape.
    vec2 p = qt_TexCoord0 * screenExtent * sourceScale + sourceOffset - maskScreenExtent * 0.5;
    vec2 rotated = vec2(rotationVector.x * p.x + rotationVector.y * p.y,
                        -rotationVector.y * p.x + rotationVector.x * p.y);
    vec2 uv = rotated / maskExtent + vec2(0.5);
    float inside = step(0.0, uv.x) * step(uv.x, 1.0)
                 * step(0.0, uv.y) * step(uv.y, 1.0);
    // Match MultiEffect's maskThresholdMin=.5, maskSpreadAtMin=1, preserving
    // the antialiased Canvas edge and transparent space outside its bounds.
    float alpha = smoothstep(0.0, 1.0, texture(maskSource, clamp(uv, 0.0, 1.0)).a) * inside;
    fragColor = texture(source, qt_TexCoord0) * (alpha * qt_Opacity);
}
