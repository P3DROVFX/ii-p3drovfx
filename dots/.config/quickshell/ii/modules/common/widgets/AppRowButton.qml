import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * A pill action inside an app settings row: secondary container by default,
 * error container when `danger` (filled only once `filled`, the confirming step).
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property string tooltip: ""
    property bool danger: false
    property bool filled: false

    readonly property color _fg: root.danger && root.filled ? Appearance.colors.colOnErrorContainer
        : root.danger ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer

    implicitHeight: 36
    implicitWidth: row.implicitWidth + 28
    buttonRadius: Appearance.rounding.full
    opacity: enabled ? 1 : 0.45
    colBackground: root.danger ? (root.filled ? Appearance.colors.colErrorContainer : "transparent") : Appearance.colors.colSecondaryContainer
    colBackgroundHover: root.danger ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
    colRipple: root.danger ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSecondaryContainerActive

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: root._fg
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root._fg
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.hovered && root.tooltip.length > 0
        text: root.tooltip
    }
}
