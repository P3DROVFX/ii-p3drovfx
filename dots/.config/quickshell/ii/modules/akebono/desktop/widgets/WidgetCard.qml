pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.akebono
import qs.modules.akebono.desktop.widgets

DesktopWidgetBase {
    id: root

    default property alias cardContent: contentArea.data
    property int padding: 14
    property color color: Appearance.colors.colLayer1
    readonly property real cardRadius: Appearance.rounding.large

    shadowRadius: root.cardRadius

    Squircle {
        anchors.fill: parent
        radius: root.cardRadius
        smoothing: AkebonoAppearance.squircleSmoothing
        color: root.color
    }

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
