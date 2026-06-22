pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Bar indicator that appears while the phone screen is being mirrored via
 * scrcpy. Mirrors the pattern of RecordIndicator: only visible when active,
 * supports both horizontal and vertical bar layouts, and provides quick
 * actions on click / popup.
 */
MouseArea {
    id: indicator
    property bool vertical: false

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    readonly property bool running: KdeConnectService.scrcpyRunning
    readonly property int elapsedSeconds: Math.floor(KdeConnectService.scrcpyElapsedMs / 1000)

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (running ? layoutHoriz.implicitWidth : 0)
    implicitHeight: vertical
        ? (running ? layoutVert.implicitHeight : 0)
        : Appearance.sizes.baseBarHeight

    visible: running

    Component.onCompleted: updateVisibility()
    onRunningChanged: {
        updateVisibility()
        updateHighlight()
    }

    function updateVisibility() {
        rootItem.toggleVisible(running)
    }

    function updateHighlight() {
        rootItem.toggleHighlight(running)
    }

    function formatTime(s) {
        const m = Math.floor(s / 60)
        const sec = s % 60
        return String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0")
    }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) {
            if (indicator.containsMouse) {
                KdeConnectService.focusScrcpyWindow()
            }
        } else if (mouse.button === Qt.MiddleButton) {
            KdeConnectService.killScrcpy()
        }
    }

    // ── Horizontal Layout ────────────────────────────────────────────────────
    RowLayout {
        id: layoutHoriz
        visible: !indicator.vertical
        anchors.centerIn: parent
        spacing: 6

        // Shape 1: Icon Shape
        MaterialShape {
            id: iconShapeHoriz
            width: 32
            height: 32
            shape: MaterialShape.Shape.Cookie9Sided
            color: indicator.containsMouse 
                ? Appearance.colors.colPrimaryContainerHover 
                : Appearance.colors.colPrimaryContainer

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "smart_display"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        // Shape 2: Timer/Status Shape
        Rectangle {
            id: timerShapeHoriz
            height: 32
            implicitWidth: timerLayoutHoriz.implicitWidth + 16
            radius: height / 2
            color: indicator.containsMouse 
                ? Appearance.colors.colPrimaryContainerHover 
                : Appearance.colors.colPrimaryContainer

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            RowLayout {
                id: timerLayoutHoriz
                anchors.centerIn: parent

                StyledText {
                    text: indicator.formatTime(indicator.elapsedSeconds)
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: ({ "tnum": 1 })
                    font.weight: Font.Bold
                }
            }
        }
    }

    // ── Vertical Layout ──────────────────────────────────────────────────────
    ColumnLayout {
        id: layoutVert
        visible: indicator.vertical
        anchors.centerIn: parent
        spacing: 6

        // Shape 1: Icon Shape
        MaterialShape {
            id: iconShapeVert
            width: 32
            height: 32
            shape: MaterialShape.Shape.Cookie9Sided
            color: indicator.containsMouse 
                ? Appearance.colors.colPrimaryContainerHover 
                : Appearance.colors.colPrimaryContainer
            Layout.alignment: Qt.AlignHCenter

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "smart_display"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        // Shape 2: Timer/Status Shape (vertical pill)
        Rectangle {
            id: timerShapeVert
            width: 32
            implicitHeight: timerLayoutVert.implicitHeight + 12
            radius: width / 2
            color: indicator.containsMouse 
                ? Appearance.colors.colPrimaryContainerHover 
                : Appearance.colors.colPrimaryContainer
            Layout.alignment: Qt.AlignHCenter

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            ColumnLayout {
                id: timerLayoutVert
                anchors.centerIn: parent
                spacing: 2

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(0, 2)
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(3, 5)
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("scrcpy mirror is running\n• Left-click: focus window\n• Middle-click: kill")
    }
}
