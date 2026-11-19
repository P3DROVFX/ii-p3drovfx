#version 450
// Kinetic lyrics backdrop: the sharp cover in the middle dissolves radially into
// its own blur. In the "side" layout the square also fades out at its left and
// right edges, into the ambient field behind it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float inner;      // radius (0 centre, 1 edge midpoint) where the blur starts
    float outer;      // radius where only the blur is left
    float edgeFade;   // 0..1: fade the left/right edges to transparent
    float soft;       // 0 heavy blur, 1 light blur
    vec2 sharpScale;  // item size / painted size: PreserveAspectCrop in UV
};
layout(binding = 1) uniform sampler2D sharpSource;
layout(binding = 2) uniform sampler2D blurSource;
layout(binding = 3) uniform sampler2D blurSoftSource;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 centred = (uv - 0.5) * 2.0;
    float t = smoothstep(inner, outer, length(centred));
    vec4 sharp = texture(sharpSource, 0.5 + (uv - 0.5) * sharpScale);
    vec4 blurred = mix(texture(blurSource, uv), texture(blurSoftSource, uv), soft);
    vec4 colour = mix(sharp, blurred, t);
    float edge = 1.0 - edgeFade * smoothstep(0.62, 1.0, abs(centred.x));
    fragColor = colour * edge * qt_Opacity;
}
