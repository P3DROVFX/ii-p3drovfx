import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * One compact action under a recents card — Android's "Screenshot" / "Select" row.
 *
 * Shared by the per-card actions and the row at the bottom of the surface, because they are
 * the same control at two sizes and having two of them is how the two drift apart.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    /// Errors and confirmations wear the error container; everything else is neutral.
    property bool accent: false
    property real pillHeight: 44

    signal triggered

    implicitHeight: root.pillHeight
    implicitWidth: pillRow.implicitWidth + 36
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.small

    colBackground: root.accent ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.accent ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer1Hover
    colBackgroundActive: root.accent ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer1Active
    colRipple: root.accent ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer1Active

    readonly property color contentColor: root.accent
        ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1

    releaseAction: () => root.triggered()

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    contentItem: RowLayout {
        id: pillRow
        anchors.centerIn: parent
        spacing: 8

        MaterialSymbol {
            text: root.symbol
            iconSize: Math.round(root.pillHeight * 0.45)
            color: root.contentColor
        }

        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contentColor
        }
    }
}
