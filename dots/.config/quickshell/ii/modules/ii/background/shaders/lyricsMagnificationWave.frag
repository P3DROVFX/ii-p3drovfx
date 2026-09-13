#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float waveProgress;
    float waveStrength;
    float waveWidth;
    float waveLift;
    float lineCountValue;
    float firstLineSpan;
    float secondLineSpan;
    float thirdLineSpan;
    float textTopNorm;
    float lineSpanNorm;
    float waveDirection;
    float colorStrength;
    vec4 waveColor;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;

    // The text block is centred inside a box taller than itself, so line bands
    // come from the measured geometry rather than a fixed two-line assumption.
    float lines = clamp(lineCountValue, 1.0, 3.0);
    float spanY = max(0.0001, lineSpanNorm);
    float lineIndex = clamp(floor((uv.y - textTopNorm) / spanY), 0.0, lines - 1.0);

    // The wave sweeps each line in turn across the whole progress range.
    float lineProgress = clamp(waveProgress * lines - lineIndex, 0.0, 1.0);
    if (waveDirection < 0.0)
        lineProgress = 1.0 - lineProgress;

    float safeWidth = max(0.001, waveWidth);
    float rawSpan = lineIndex < 0.5
        ? firstLineSpan
        : (lineIndex < 1.5 ? secondLineSpan : thirdLineSpan);
    float contentSpan = clamp(rawSpan, 0.05, 1.0);
    float contentStart = 0.5 - contentSpan * 0.5;
    float contentEnd = 0.5 + contentSpan * 0.5;
    float travelMargin = safeWidth * 2.5;
    float waveCenter = mix(contentStart - travelMargin,
        contentEnd + travelMargin, lineProgress);
    float distanceToWave = (uv.x - waveCenter) / safeWidth;
    float envelope = exp(-0.5 * distanceToWave * distanceToWave);
    float localScale = 1.0 + waveStrength * envelope;

    float lineCenterY = textTopNorm + (lineIndex + 0.5) * spanY;
    vec2 sampleUv;
    sampleUv.x = waveCenter + (uv.x - waveCenter) / localScale;
    sampleUv.y = lineCenterY + (uv.y - lineCenterY) / localScale;
    sampleUv.y += waveLift * envelope;
    sampleUv = clamp(sampleUv, vec2(0.0), vec2(1.0));

    vec4 sampled = texture(source, sampleUv);
    float tintAmount = colorStrength * envelope;
    sampled.rgb = mix(sampled.rgb, waveColor.rgb * sampled.a, tintAmount);
    fragColor = sampled * qt_Opacity;
}
