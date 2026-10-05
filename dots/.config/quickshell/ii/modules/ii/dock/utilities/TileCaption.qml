import QtQuick
import qs.modules.ii.clock.components

/**
 * The small line under a value: bold, wide-set capitals at 72 % of the
 * content colour — the contrast against the condensed digits above it.
 */
TileText {
    font.family: ClockStyle.fontMain
    font.variableAxes: ({ "wght": 700, "wdth": 110, "ROND": 100 })
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.4
    elide: Text.ElideRight
}
