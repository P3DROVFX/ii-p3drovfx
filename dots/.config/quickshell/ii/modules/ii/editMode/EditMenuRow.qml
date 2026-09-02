import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One row of an edit-mode menu card: a symbol, a label, a ripple. Shared by
 * the widget menu and the desktop menu so the two cannot drift apart.
 */
RippleButton {
    id: row
    property string symbol: ""
    property string label: ""
    property color colText: Appearance.m3colors.m3onSurface
    // The card's inner padding, so the hover shape follows the card's corner.
    property real cardPadding: 6

    Layout.fillWidth: true
    implicitHeight: 34
    buttonRadius: Math.max(0, Appearance.rounding.windowRounding - row.cardPadding)
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        MaterialSymbol {
            text: row.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: row.enabled ? row.colText : Appearance.m3colors.m3outline
        }
        StyledText {
            Layout.fillWidth: true
            text: row.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: row.enabled ? row.colText : Appearance.m3colors.m3outline
            elide: Text.ElideRight
        }
    }
}
