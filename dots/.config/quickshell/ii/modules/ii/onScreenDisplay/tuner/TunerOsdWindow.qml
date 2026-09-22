import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The Tuner OSD on its own, for when the Dynamic Island isn't there to hold it: the same
 * face in an island-coloured pill, top centre under the bar (bottom when the bar is).
 *
 * The window keeps the widest pill's size; only the pill inside morphs to the content, so a
 * width change never resizes the surface.
 */
PanelWindow {
    id: root

    property bool shown: false
    property bool appeared: false
    readonly property bool revealed: root.appeared && root.shown
    readonly property int maxPillWidth: 460
    readonly property int shadowMargin: Appearance.sizes.elevationMargin * 2

    Component.onCompleted: root.appeared = true

    color: "transparent"
    WlrLayershell.namespace: "quickshell:onScreenDisplay"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    anchors {
        top: !BarPlacement.bottom
        bottom: BarPlacement.bottom
    }
    margins {
        top: Appearance.sizes.barHeight
        bottom: Appearance.sizes.barHeight
    }

    implicitWidth: root.maxPillWidth + root.shadowMargin * 2
    implicitHeight: face.osdHeight + root.shadowMargin * 2
    mask: Region {
        item: pill
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: pill.width
        height: pill.height
        opacity: root.revealed ? 1 : 0
        scale: root.revealed ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        StyledRectangularShadow {
            target: pill
        }

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: Math.min(root.maxPillWidth, face.osdWidth > 0 ? face.osdWidth : 200)
            height: face.osdHeight
            radius: height / 2
            color: Appearance.colors.colLayer0
            clip: true

            Behavior on width {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.3, 1.35, 0.5, 1, 1, 1]
                }
            }

            TunerIndicator {
                id: face
                anchors.fill: parent
            }
        }
    }
}
