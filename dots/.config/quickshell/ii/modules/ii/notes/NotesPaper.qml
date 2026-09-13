import QtQuick

import qs.modules.common
import qs.modules.ii.notes

/**
 * The page a note is written on.
 *
 * Drawn procedurally so it can scroll with the text and stay crisp at any spacing: the
 * scroll position is a uniform, so moving the page rebuilds no geometry and repaints
 * nothing. A tiled image would have to be regenerated whenever the spacing, the colour or
 * the theme changed, and would stretch its squares out of square with the pane.
 *
 * The colour is a theme token, never a literal. Paper that stayed the same shade when the
 * wallpaper changed would be the one surface in the app that did.
 */
ShaderEffect {
    id: root

    /// One of `Doc.PAPER_STYLES`: plain, grid, dots, ruled, ruled-margin, isometric, graph.
    property string paperStyle: "plain"
    /// Pixels between lines, and how strongly the pattern shows.
    property real paperSpacing: NotesMetrics.paperLineHeight
    property real paperStrength: 0.5
    /// How far the page has been scrolled, so the pattern travels with the text.
    property real scrollOffset: 0
    /// Distance from the top of the editor to the first text baseline.
    property real baselineOffset: 24

    readonly property var styleOrder: ["plain", "grid", "dots", "ruled", "ruled-margin", "isometric", "graph"]

    visible: root.paperStyle !== "plain" && root.paperStrength > 0

    // ── Uniforms ──────────────────────────────────────────────────────────
    // Matched to the shader's uniform block by name.
    property real style: Math.max(0, root.styleOrder.indexOf(root.paperStyle))
    property real spacing: Math.max(8, root.paperSpacing)
    property real lineWidth: 1
    property real paperOpacity: Math.max(0, Math.min(1, root.paperStrength))
    property vector2d paperSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
    property vector2d paperOffset: Qt.vector2d(0, root.scrollOffset - root.baselineOffset)
    property vector4d lineColor: root.asVector(Appearance.colors.colOutlineVariant)
    property vector4d accentColor: root.asVector(Appearance.m3colors.m3error)

    function asVector(colour): vector4d {
        return Qt.vector4d(colour.r, colour.g, colour.b, colour.a);
    }

    fragmentShader: "shaders/paper.frag.qsb"
}
