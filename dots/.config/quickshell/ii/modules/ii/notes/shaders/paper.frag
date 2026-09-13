#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// The page a note is written on.
//
// Procedural rather than a tiled image, because the pattern has to scroll with the text
// and stay crisp at any spacing the reader picks. A shader also means scrolling costs
// nothing: the offset is a uniform, so no geometry is rebuilt and nothing repaints.
//
// Everything is drawn in pixels, not in texture coordinates: a grid whose squares stretch
// with the width of the pane is not a grid.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // 0 plain, 1 grid, 2 dots, 3 ruled, 4 ruled with a margin, 5 isometric, 6 graph
    float style;
    float spacing;
    float lineWidth;
    float paperOpacity;
    vec2 paperSize;
    vec2 paperOffset;
    vec4 lineColor;
    vec4 accentColor;
};

/// Coverage of a line every `period` pixels, antialiased over one pixel so a hairline at
/// a fractional position is grey rather than absent.
float lineAt(float coordinate, float period, float width) {
    float distanceToLine = abs(mod(coordinate + period * 0.5, period) - period * 0.5);
    return 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, distanceToLine);
}

float dotAt(vec2 point, float period, float radius) {
    vec2 cell = mod(point + period * 0.5, period) - period * 0.5;
    return 1.0 - smoothstep(radius, radius + 1.0, length(cell));
}

void main() {
    vec2 pixel = qt_TexCoord0 * paperSize + paperOffset;
    float period = max(spacing, 4.0);
    float width = max(lineWidth, 1.0);
    float ink = 0.0;
    vec4 tint = lineColor;

    if (style < 0.5) {
        // Plain. Nothing to draw, and the branch keeps the cost at zero rather than
        // drawing a fully transparent pattern.
        fragColor = vec4(0.0);
        return;
    } else if (style < 1.5) {
        ink = max(lineAt(pixel.x, period, width), lineAt(pixel.y, period, width));
    } else if (style < 2.5) {
        ink = dotAt(pixel, period, width * 0.75);
    } else if (style < 3.5) {
        ink = lineAt(pixel.y, period, width);
    } else if (style < 4.5) {
        ink = lineAt(pixel.y, period, width);
        // The margin rule, a hand's width in from the edge and in its own colour — the
        // one line on a ruled page that means something different from the others.
        float margin = 1.0 - smoothstep(width, width + 1.0, abs(pixel.x - paperOffset.x - period * 2.5));
        if (margin > ink) {
            ink = margin;
            tint = accentColor;
        }
    } else if (style < 5.5) {
        // Isometric: verticals plus two diagonals at thirty degrees.
        float slope = 0.57735; // tan(30°)
        ink = max(lineAt(pixel.x, period, width),
              max(lineAt(pixel.y + pixel.x * slope, period, width),
                  lineAt(pixel.y - pixel.x * slope, period, width)));
    } else {
        // Graph paper: a fine grid with a heavier line every five squares, which is what
        // makes it countable rather than merely square.
        float fine = max(lineAt(pixel.x, period, width), lineAt(pixel.y, period, width));
        float coarse = max(lineAt(pixel.x, period * 5.0, width + 0.6),
                           lineAt(pixel.y, period * 5.0, width + 0.6));
        ink = max(fine * 0.55, coarse);
    }

    fragColor = vec4(tint.rgb, 1.0) * tint.a * ink * paperOpacity * qt_Opacity;
}
