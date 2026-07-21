pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Vertical slider for a Pipewire program playback node.
 * Shows the application icon at the bottom of the slider
 * (replacing the default material symbol icon).
 */
Item {
    id: root

    required property PwNode node

    PwObjectTracker {
        objects: [root.node]
    }

    readonly property bool isMuted: node?.audio?.muted ?? false
    readonly property real maxAllowedValue: 1.5

    readonly property string appIconName: {
        if (!node) return "";
        const _ = TaskbarApps.iconThemeRevision;
        let icon = AppSearch.guessIcon(node.properties["application.icon-name"] ?? "");
        if (AppSearch.iconExists(icon)) return icon;
        icon = AppSearch.guessIcon(node.properties["node.name"] ?? "");
        if (AppSearch.iconExists(icon)) return icon;
        return "";
    }

    readonly property string appIconSource: appIconName !== "" ? Quickshell.iconPath(appIconName, "image-missing") : ""

    implicitWidth: 56
    implicitHeight: 120

    StyledVerticalSlider {
        id: slider
        anchors.fill: parent
        from: 0
        to: root.maxAllowedValue
        value: (root.node && root.node.audio) ? root.node.audio.volume : 0
        rawValue: (root.node && root.node.audio) ? root.node.audio.volume : 0
        materialSymbol: ""
        configuration: 38
        usePercentTooltip: false
        tooltipContent: root.node ? Audio.appNodeDisplayName(root.node) : ""

        onMoved: {
            if (root.node && root.node.audio) {
                root.node.audio.volume = value;
            }
            GlobalStates.osdInteraction();
        }
    }

    // App icon overlay at the bottom of the slider
    Item {
        id: iconOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 20
        height: 20

        StyledImage {
            id: appIconImage
            anchors.fill: parent
            visible: root.appIconSource !== ""
            source: root.appIconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: !source.toString().startsWith("image://icon/")
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.appIconSource === ""
            text: "widgets"
            iconSize: 16
            color: Appearance.colors.colOnLayer1
        }
    }

    // Muted overlay
    Rectangle {
        anchors.fill: iconOverlay
        color: "#80000000"
        visible: root.isMuted
        radius: 4

        MaterialSymbol {
            anchors.centerIn: parent
            text: "volume_off"
            iconSize: 12
            color: "white"
        }
    }

    // Click to toggle mute
    MouseArea {
        anchors.fill: iconOverlay
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.node && root.node.audio) {
                root.node.audio.muted = !root.node.audio.muted;
            }
            GlobalStates.osdInteraction();
        }
    }
}
