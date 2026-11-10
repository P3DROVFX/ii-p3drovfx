import QtQuick
import qs.modules.common.widgets

/**
 * Text on a dock tile. Curve rendering keeps the glyphs vector, so the lens
 * can enlarge the tile without stretching a bitmap.
 */
StyledText {
    renderType: Text.CurveRendering
}
