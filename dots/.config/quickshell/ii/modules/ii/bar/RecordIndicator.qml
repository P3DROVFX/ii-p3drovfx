import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "./cards"

MouseArea {
    id: indicator
    property bool vertical: false

    property bool activelyRecording: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
    property bool isLoading: (Persistent.states.screenRecord && Persistent.states.screenRecord.loading) || false
    property bool isPaused: (Persistent.states.screenRecord && Persistent.states.screenRecord.paused) || false

    property color colText: Appearance.colors.colOnPrimary

    hoverEnabled: true
    implicitWidth: vertical ? 20 : 80 // we have to enter a fixed size to make it dull
    implicitHeight: vertical ? 75 : 20

    Component.onCompleted: updateVisibility()
    onActivelyRecordingChanged: updateVisibility()
    onIsLoadingChanged: updateVisibility()

    function updateVisibility() {
        rootItem.toggleVisible(activelyRecording || isLoading);
    }

    function formatTime(totalSeconds) {
        let mins = Math.floor(totalSeconds / 60);
        let secs = totalSeconds % 60;
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    RippleButton {
        anchors.centerIn: parent
        implicitWidth: indicator.vertical ? 20 : parent.implicitWidth
        implicitHeight: indicator.vertical ? parent.implicitHeight : 20
        colBackgroundHover: "transparent"
        colRipple: "transparent"

        onClicked: {
            if (Qt.keyboardModifiers() & Qt.ShiftModifier) {
                Quickshell.execDetached([Directories.recordScriptPath, "--region"]);
            } else {
                Quickshell.execDetached(Directories.recordScriptPath);
            }
        }

        StyledPopup {
            hoverTarget: indicator
            contentItem: PopupContent {}
        }
    }

    Loader {
        active: !indicator.vertical
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                id: iconIndicator
                Layout.bottomMargin: 2
                z: 1
                text: indicator.isLoading ? "progress_activity" : "screen_record"
                color: indicator.colText
                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            StyledText {
                id: textIndicator
                Layout.topMargin: 2
                visible: !indicator.isLoading

                text: indicator.formatTime(Persistent.states.screenRecord.seconds)
                color: indicator.colText
            }
        }
    }

    Loader {
        active: indicator.vertical
        anchors.centerIn: parent
        sourceComponent: ColumnLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                id: iconIndicator
                Layout.alignment: Text.AlignHCenter
                text: indicator.isLoading ? "progress_activity" : "screen_record"
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            StyledText {
                Layout.alignment: Text.AlignHCenter
                text: indicator.formatTime(Persistent.states.screenRecord.seconds).substring(0, 2)
                color: indicator.colText
                visible: !indicator.isLoading
            }

            StyledText {
                text: indicator.formatTime(Persistent.states.screenRecord.seconds).substring(3, 5)
                color: indicator.colText
                Layout.alignment: Text.AlignHCenter
                visible: !indicator.isLoading
            }
        }
    }

    component PopupContent: ColumnLayout {
        implicitWidth: heroCard.implicitWidth
        implicitHeight: heroCard.implicitHeight

        HeroCard {
            id: heroCard
            title: indicator.isLoading ? "..." : indicator.formatTime(Persistent.states.screenRecord.seconds)
            subtitle: indicator.isLoading ? Translation.tr("Starting OBS...") : Translation.tr("Recording Screen")

            pillText: indicator.isLoading ? "OBS Studio" : "REC"
            pillIcon: indicator.isLoading ? "progress_activity" : "radio_button_checked"
            pillColor: indicator.isLoading ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer
            pillTextColor: indicator.isLoading ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
            pillIconColor: pillTextColor

            shapeString: indicator.isLoading ? "Circle" : "Cookie9Sided"
            shapeColor: indicator.isLoading ? Appearance.colors.colSecondary : Appearance.colors.colError

            shapeContent: MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.isLoading ? "progress_activity" : "screen_record"
                iconSize: 48
                color: Appearance.colors.colOnError // Match HeroCard symbol color logic
                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            // Add a click-to-stop message in the subtitle area or similar
            StyledText {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    margins: 16
                }
                text: Translation.tr("Click to stop recording")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.7
                visible: !indicator.isLoading
            }
        }
    }
}
