import QtQuick

import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets

/**
 * The apps that did not fit, as one target.
 *
 * A dock that silently stops showing what is running is a dock you cannot trust: the app is
 * open, and there is no sign of it anywhere. Android's answer is a folder, so this is one —
 * up to four of the grouped icons in a 2x2, and the count when there are more.
 *
 * It takes the last of the visible slots rather than being appended to them, which is why
 * the group holds the last app that would have been shown plus everything opened since.
 */
RippleButton {
    id: root

    /// Every app in the group, oldest first.
    property var appIds: []
    property real iconSize: 44
    property real buttonSize: root.iconSize + Appearance.sizes.elevationMargin * 2

    signal activated

    readonly property var previewIds: root.appIds.slice(0, 4)
    readonly property int hiddenCount: Math.max(0, root.appIds.length - root.previewIds.length)

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colRipple: Appearance.colors.colLayer2Active
    releaseAction: () => root.activated()

    Grid {
        id: previewGrid
        anchors.centerIn: parent
        columns: 2
        spacing: Math.round(root.iconSize * 0.08)

        Repeater {
            model: root.previewIds

            delegate: DockIcon {
                required property string modelData
                // Two per row inside the icon's footprint, minus the gap between them.
                width: Math.round((root.iconSize - previewGrid.spacing) / 2)
                height: width
                appId: modelData
                isRunning: false
            }
        }
    }

    // The count sits on the plate rather than inside the grid: it is about the group, not a
    // fifth member of it.
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(root.buttonSize * 0.04)
        visible: root.hiddenCount > 0
        implicitWidth: Math.max(countText.implicitWidth + 8, root.buttonSize * 0.34)
        implicitHeight: root.buttonSize * 0.34
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary

        StyledText {
            id: countText
            anchors.centerIn: parent
            text: "+" + root.hiddenCount
            font.pixelSize: Math.round(parent.implicitHeight * 0.6)
            color: Appearance.colors.colOnPrimary
        }
    }
}
