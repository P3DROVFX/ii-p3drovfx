import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * One side of an Anki card as Qt rich text. The daemon already reshaped Anki's HTML for
 * Qt (formulas as SVG, sizes clamped, page colours dropped); this wraps it with the
 * note type's CSS and a theme sheet that recolours what Anki styles for a white page
 * (cloze, typed-answer diff, readings) with the theme's roles.
 */
Text {
    id: root

    property string body: ""
    property string css: ""
    property color colText: ClockStyle.colOnSurface
    property color colAccent: Appearance.m3colors.m3primary
    property color colGood: Appearance.m3colors.m3tertiary
    property color colBad: Appearance.m3colors.m3error
    property color colMuted: ClockStyle.colSubtext

    /// Big for a word, stepping down as the side grows into a paragraph.
    function sizeFor(plainLength: int): int {
        if (plainLength <= 24)
            return Appearance.font.pixelSize.huge + 10;
        if (plainLength <= 80)
            return Appearance.font.pixelSize.huge;
        if (plainLength <= 240)
            return Appearance.font.pixelSize.larger;
        return Appearance.font.pixelSize.normal;
    }

    /// Formulas come sized for the daemon's base font; scale them to this side's text.
    property int baseFontPx: Anki.themeFontPx
    readonly property string scaledBody: {
        const k = root.font.pixelSize / Math.max(1, root.baseFontPx);
        if (Math.abs(k - 1) < 0.01)
            return root.body;
        return root.body.replace(/<img data-ii-math="1" src="([^"]*)" width="([\d.]+)" height="([\d.]+)"/g,
            (m, src, w, h) => {
                // Never wider than the text column.
                const s = Math.min(k, root.width > 0 ? root.width / w : k);
                return `<img src="${src}" width="${Math.round(w * s)}" height="${Math.round(h * s)}"`;
            });
    }

    readonly property int plainLength: root.body.replace(/<[^>]+>/g, "").replace(/&\w+;/g, " ").trim().length

    readonly property string themeCss: [
        `.cloze{color:${root.colAccent};font-weight:bold}`,
        `.cloze-inactive{color:${root.colText}}`,
        `.ii-ruby{color:${root.colMuted};font-size:${Math.round(root.font.pixelSize * 0.6)}px}`,
        `#typeans{font-family:monospace}`,
        `.typeGood{color:${root.colGood}}`,
        `.typeBad{color:${root.colBad};text-decoration:line-through}`,
        `.typeMissed{color:${root.colMuted}}`,
        `a{color:${root.colAccent}}`,
        `code{font-family:monospace}`,
        `table{border-color:${root.colMuted};border-style:solid}`,
        `td,th{padding:4px 8px}`
    ].join("\n")

    text: `<html><head><style>${root.css}\n${root.themeCss}</style></head><body><div class="card">${root.scaledBody}</div></body></html>`
    textFormat: Text.RichText
    wrapMode: Text.Wrap
    color: root.colText
    linkColor: root.colAccent
    font.family: Appearance.font.family.main
    font.pixelSize: root.sizeFor(root.plainLength)
    // Left-aligned inside a block as wide as its longest line, the block centred by the
    // parent: Qt Quick draws inline images at their left-aligned x even when the line is
    // centred, so centring the text itself would pull images and formulas to the edge.
    horizontalAlignment: Text.AlignLeft
    /// The width this side wants in a column `available` wide.
    function fitWidth(available: real): real {
        return Math.min(Math.ceil(root.implicitWidth) + 1, available);
    }
    onLinkActivated: link => Qt.openUrlExternally(link)

    HoverHandler {
        enabled: root.hoveredLink.length > 0
        cursorShape: Qt.PointingHandCursor
    }
}
