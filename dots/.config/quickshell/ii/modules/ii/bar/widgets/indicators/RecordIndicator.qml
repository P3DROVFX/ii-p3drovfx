import qs.modules.ii.bar.shared
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../shared/cards"

MouseArea {
    id: indicator
    property bool vertical: false

    // State properties (fully reactive)
    readonly property bool activelyRecording: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
    readonly property bool isLoading: (Persistent.states.screenRecord && Persistent.states.screenRecord.loading) || false
    readonly property bool isPaused: (Persistent.states.screenRecord && Persistent.states.screenRecord.paused) || false
    readonly property int elapsedSeconds: (Persistent.states.screenRecord && Persistent.states.screenRecord.seconds) || 0

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    // Size calculation (dynamic and perfectly padded to prevent any overlapping)
    implicitWidth: vertical 
        ? Appearance.sizes.verticalBarWidth 
        : (activelyRecording || isLoading ? layoutHoriz.implicitWidth : 0)
    implicitHeight: vertical 
        ? (activelyRecording || isLoading ? layoutVert.implicitHeight : 0) 
        : Appearance.sizes.baseBarHeight

    visible: activelyRecording || isLoading

    Component.onCompleted: {
        updateHighlight()
        updateVisibility()
    }
    onActivelyRecordingChanged: {
        updateHighlight()
        updateVisibility()
    }
    onIsLoadingChanged: {
        updateHighlight()
        updateVisibility()
    }
    onIsPausedChanged: {
        updateHighlight()
    }

    function updateVisibility() {
        rootItem.toggleVisible(activelyRecording || isLoading)
    }

    function updateHighlight() {
        // Highlight the bar item when recording (and not paused) or loading
        rootItem.toggleHighlight((activelyRecording && !isPaused) || isLoading)
    }

    function formatTime(s) {
        let m = Math.floor(s / 60)
        let sec = s % 60
        return String(m).padStart(2, '0') + ":" + String(sec).padStart(2, '0')
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
            color: indicator.isLoading 
                ? (indicator.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.isLoading 
                    ? "progress_activity" 
                    : (indicator.containsMouse ? "stop" : "fiber_manual_record")
                iconSize: indicator.isLoading ? 16 : (indicator.containsMouse ? 14 : 12)
                color: indicator.isLoading 
                    ? Appearance.colors.colOnSecondaryContainer 
                    : Appearance.colors.colOnErrorContainer

                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }
        }

        // Shape 2: Timer/Status Shape
        Rectangle {
            id: timerShapeHoriz
            height: 32
            implicitWidth: timerLayoutHoriz.implicitWidth + 16
            radius: height / 2
            color: indicator.isLoading 
                ? (indicator.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            opacity: (indicator.isPaused && !indicator.containsMouse) ? 0.6 : 1.0

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            RowLayout {
                id: timerLayoutHoriz
                anchors.centerIn: parent

                StyledText {
                    visible: !indicator.isLoading
                    text: indicator.formatTime(indicator.elapsedSeconds)
                    color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: ({ "tnum": 1 })
                    font.weight: Font.Bold
                }

                StyledText {
                    visible: indicator.isLoading
                    text: Translation.tr("REC...")
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
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
            color: indicator.isLoading 
                ? (indicator.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            Layout.alignment: Qt.AlignHCenter

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.isLoading 
                    ? "progress_activity" 
                    : (indicator.containsMouse ? "stop" : "fiber_manual_record")
                iconSize: indicator.isLoading ? 16 : (indicator.containsMouse ? 14 : 12)
                color: indicator.isLoading 
                    ? Appearance.colors.colOnSecondaryContainer 
                    : Appearance.colors.colOnErrorContainer

                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }
        }

        // Shape 2: Timer/Status Shape (vertical pill)
        Rectangle {
            id: timerShapeVert
            width: 32
            implicitHeight: timerLayoutVert.implicitHeight + 12
            radius: width / 2
            color: indicator.isLoading 
                ? (indicator.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            Layout.alignment: Qt.AlignHCenter
            opacity: (indicator.isPaused && !indicator.containsMouse) ? 0.6 : 1.0

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            ColumnLayout {
                id: timerLayoutVert
                anchors.centerIn: parent
                spacing: 2

                StyledText {
                    visible: !indicator.isLoading
                    Layout.alignment: Qt.AlignHCenter
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(0, 2)
                    color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }

                StyledText {
                    visible: !indicator.isLoading
                    Layout.alignment: Qt.AlignHCenter
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(3, 5)
                    color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }

                // Vertical stacked letters for "REC" when loading
                Column {
                    visible: indicator.isLoading
                    spacing: 1
                    Layout.alignment: Qt.AlignHCenter

                    StyledText {
                        text: "R"
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: 10
                        font.weight: Font.Black
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: "E"
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: 10
                        font.weight: Font.Black
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: "C"
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: 10
                        font.weight: Font.Black
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    // ── Click Action (Stop recording on click) ───────────────────────────────
    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            if (activelyRecording) {
                Quickshell.execDetached(["bash", Directories.recordScriptPath])
                controlsPopup.close()
            }
        }
    }

    // ── Premium Recording Controls Popup ─────────────────────────────────────
    StyledPopup {
        id: controlsPopup
        hoverTarget: indicator
        stickyHover: true
        popupRadius: Appearance.rounding.large

        contentItem: ColumnLayout {
            spacing: 16
            implicitWidth: 320

            HeroCard {
                id: recCard
                icon: indicator.isLoading ? "progress_activity" : (indicator.isPaused ? "pause_circle" : "videocam")
                compactMode: true
                adaptiveWidth: true
                implicitHeight: 125 // Add breathing room to prevent ANY overlapping!

                // Custom font sizing to guarantee breathing room and prevent text overlapping
                titleSize: Appearance.font.pixelSize.larger
                subtitleSize: Appearance.font.pixelSize.small

                title: indicator.isLoading ? Translation.tr("Preparing...") : indicator.formatTime(indicator.elapsedSeconds)
                subtitle: indicator.isLoading 
                    ? Translation.tr("Authorize screen sharing in portal") 
                    : (indicator.isPaused ? Translation.tr("Recording Paused") : Translation.tr("Recording Screen"))

                pillText: indicator.isLoading 
                    ? Translation.tr("Loading") 
                    : (indicator.isPaused ? Translation.tr("PAUSED") : Translation.tr("LIVE"))
                pillIcon: indicator.isLoading ? "sync" : (indicator.isPaused ? "pause" : "radio_button_checked")
                
                pillColor: indicator.isLoading 
                    ? Appearance.colors.colSecondaryContainer 
                    : (indicator.isPaused ? Appearance.colors.colSecondary : Appearance.colors.colError)
                pillTextColor: Appearance.colors.colOnPrimary
                pillIconColor: Appearance.colors.colOnPrimary
            }

            // Interactive Controls Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: !indicator.isLoading

                // Pause / Resume Button (Vibrant & fully rounded pill)
                RippleButton {
                    id: pauseBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    buttonRadius: Appearance.rounding.full 
                    
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    
                    onClicked: {
                        Quickshell.execDetached([Directories.recordScriptPath, "--pause"])
                    }

                    // Centered and pixel-perfect aligned icon and text layout
                    contentItem: Item {
                        implicitWidth: pauseContent.implicitWidth
                        implicitHeight: pauseContent.implicitHeight

                        Row {
                            id: pauseContent
                            spacing: 8
                            anchors.centerIn: parent

                            MaterialSymbol {
                                text: indicator.isPaused ? "play_arrow" : "pause"
                                color: Appearance.colors.colOnSecondaryContainer
                                iconSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: indicator.isPaused ? Translation.tr("Resume") : Translation.tr("Pause")
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                // Stop Button (Premium red Container styling, fully rounded pill)
                RippleButton {
                    id: stopBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    buttonRadius: Appearance.rounding.full 
                    
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    
                    onClicked: {
                        Quickshell.execDetached([Directories.recordScriptPath])
                        controlsPopup.close()
                    }

                    contentItem: Item {
                        implicitWidth: stopContent.implicitWidth
                        implicitHeight: stopContent.implicitHeight

                        Row {
                            id: stopContent
                            spacing: 8
                            anchors.centerIn: parent

                            MaterialSymbol {
                                text: "stop"
                                color: Appearance.colors.colOnErrorContainer
                                iconSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: Translation.tr("Stop")
                                color: Appearance.colors.colOnErrorContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
