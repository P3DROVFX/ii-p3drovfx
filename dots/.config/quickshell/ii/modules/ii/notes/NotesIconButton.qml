import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/**
 * A round icon button, sized for touch.
 *
 * A local wrapper rather than a new widget: it is `RippleButton` with the app's shape and
 * hit size, and every one of these in the app should look and measure the same. 44px is
 * the floor the project holds itself to, and the notes app also runs on the tablet.
 */
RippleButton {
    id: root

    property string symbol: "circle"
    property real size: 44
    property real iconSize: 22
    property string tooltipText: ""
    /// Optional themed SVG asset. Material Symbols remain the default for the app chrome.
    property string iconSource: ""
    property color colIcon: Appearance.colors.colOnLayer1

    signal triggered()

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: Appearance.rounding.full

    onClicked: root.triggered()

    contentItem: Item {
        Loader {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            active: root.iconSource.length > 0
            sourceComponent: CustomIcon {
                anchors.fill: parent
                source: root.iconSource
                colorize: true
                color: root.enabled ? root.colIcon : Appearance.colors.colOnLayer1Inactive
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.iconSource.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.symbol
            iconSize: root.iconSize
            color: root.enabled ? root.colIcon : Appearance.colors.colOnLayer1Inactive
        }
    }

    StyledToolTip {
        text: root.tooltipText
        extraVisibleCondition: root.tooltipText.length > 0
    }
}
