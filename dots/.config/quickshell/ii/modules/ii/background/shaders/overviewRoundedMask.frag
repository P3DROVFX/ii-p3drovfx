#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float cornerRadius;
    vec2 screenExtent;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float radius = clamp(cornerRadius, 0.0, min(screenExtent.x, screenExtent.y) * 0.5);
    vec2 edge = abs((qt_TexCoord0 - vec2(0.5)) * screenExtent)
              - screenExtent * 0.5 + vec2(radius);
    float distanceToEdge = length(max(edge, vec2(0.0)))
                         + min(max(edge.x, edge.y), 0.0) - radius;
    // Derivatives keep a one-pixel antialiased edge at any monitor scale/zoom.
    float feather = max(fwidth(distanceToEdge), 0.0001) * 0.5;
    float alpha = radius > 0.0 ? 1.0 - smoothstep(-feather, feather, distanceToEdge) : 1.0;
    fragColor = texture(source, qt_TexCoord0) * (alpha * qt_Opacity);
}
