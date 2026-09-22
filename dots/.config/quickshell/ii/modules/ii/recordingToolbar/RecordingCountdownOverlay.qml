pragma ComponentBehavior: Bound
import qs
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

PanelWindow {
    id: root
    visible: countdownRemaining > 0
    color: "transparent"

    WlrLayershell.namespace: "quickshell:recordingCountdown"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    property int countdownRemaining: 0
    property var onCompleteCallback: null

    function start(seconds: int, callback: var) {
        if (seconds <= 0) {
            if (callback) callback();
            return;
        }
        root.countdownRemaining = seconds;
        root.onCompleteCallback = callback;
        pulseAnim.restart();
        countTimer.restart();
    }

    function cancel() {
        countTimer.stop();
        root.countdownRemaining = 0;
        root.onCompleteCallback = null;
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.cancel()
    }

    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdownRemaining--;
            if (root.countdownRemaining > 0) {
                pulseAnim.restart();
            } else {
                countTimer.stop();
                const cb = root.onCompleteCallback;
                root.onCompleteCallback = null;
                if (cb) cb();
            }
        }
    }

    // Centered countdown badge
    Item {
        anchors.centerIn: parent
        width: 140
        height: 140

        Rectangle {
            id: badgeBg
            anchors.fill: parent
            radius: width / 2
            color: Appearance.m3colors.m3surfaceContainerHighest

            StyledRectangularShadow {
                target: badgeBg
                radius: badgeBg.radius
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Appearance.sizes.elevationMargin / 2

                StyledText {
                    id: countText
                    Layout.alignment: Qt.AlignHCenter
                    text: String(root.countdownRemaining)
                    font.pixelSize: 52
                    font.bold: true
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Recording in…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Cancel hint below
        Rectangle {
            anchors.top: badgeBg.bottom
            anchors.topMargin: Appearance.sizes.elevationMargin * 2
            anchors.horizontalCenter: parent.horizontalCenter
            height: 32
            radius: Appearance.rounding.full
            color: Appearance.m3colors.m3surfaceContainerHigh
            implicitWidth: hintRow.implicitWidth + Appearance.sizes.elevationMargin * 3

            StyledRectangularShadow {
                target: parent
                radius: parent.radius
            }

            RowLayout {
                id: hintRow
                anchors.centerIn: parent
                spacing: Appearance.sizes.elevationMargin

                MaterialSymbol {
                    text: "close"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: Translation.tr("Press Esc to cancel")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Subtle scale feedback on second tick
        ParallelAnimation {
            id: pulseAnim
            NumberAnimation {
                target: badgeBg
                property: "scale"
                from: 1.15
                to: 1.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }
    }
}
