pragma ComponentBehavior: Bound

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
        : (activelyRecording || isLoading ? (layoutHoriz.implicitWidth + 24) : 0)
    implicitHeight: vertical 
        ? (activelyRecording || isLoading ? (layoutVert.implicitHeight + 24) : 0) 
        : Appearance.sizes.baseBarHeight

    visible: activelyRecording || isLoading

    Component.onCompleted: {
        updateColors()
        updateHighlight()
        updateVisibility()
    }
    onActivelyRecordingChanged: {
        updateColors()
        updateHighlight()
        updateVisibility()
    }
    onIsLoadingChanged: {
        updateColors()
        updateHighlight()
        updateVisibility()
    }
    onIsPausedChanged: {
        updateHighlight()
    }
    onContainsMouseChanged: {
        updateColors()
    }

    function updateVisibility() {
        rootItem.toggleVisible(activelyRecording || isLoading)
    }

    function updateHighlight() {
        // Highlight the bar item when recording (and not paused) or loading
        rootItem.toggleHighlight((activelyRecording && !isPaused) || isLoading)
    }

    // Proactively update BarGroup's background color dynamically on state/hover changes
    function updateColors() {
        if (indicator.isLoading) {
            rootItem.colBackgroundHighlight = indicator.containsMouse 
                ? Appearance.colors.colSecondaryContainerHover 
                : Appearance.colors.colSecondaryContainer
        } else {
            rootItem.colBackgroundHighlight = indicator.containsMouse 
                ? Appearance.colors.colErrorContainerHover 
                : Appearance.colors.colErrorContainer
        }
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
        spacing: 8

        // Blinking dot when recording, or loading spinner / stop icon on hover
        Item {
            implicitWidth: 16
            implicitHeight: 16
            Layout.alignment: Qt.AlignVCenter

            // Loading spinner (high contrast on highlighted background)
            MaterialSymbol {
                visible: indicator.isLoading
                anchors.centerIn: parent
                text: "progress_activity"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer

                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            // REC Dot / Stop Icon on hover
            MaterialSymbol {
                visible: !indicator.isLoading
                anchors.centerIn: parent
                text: indicator.containsMouse ? "stop" : "fiber_manual_record"
                iconSize: indicator.containsMouse ? 14 : 12
                color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer

                SequentialAnimation on opacity {
                    running: indicator.activelyRecording && !indicator.isPaused && !indicator.containsMouse
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }
                opacity: (indicator.isPaused && !indicator.containsMouse) ? 0.5 : 1.0
            }
        }

        // Timer Text (high contrast colOnErrorContainer when active, colSubtext when paused)
        StyledText {
            visible: !indicator.isLoading
            text: indicator.formatTime(indicator.elapsedSeconds)
            color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
            font.pixelSize: Appearance.font.pixelSize.small
            font.features: ({ "tnum": 1 })
            font.weight: Font.Bold
            Layout.alignment: Qt.AlignVCenter
        }

        // Quick Indicator label if loading
        StyledText {
            visible: indicator.isLoading
            text: Translation.tr("REC...")
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // ── Vertical Layout ──────────────────────────────────────────────────────
    ColumnLayout {
        id: layoutVert
        visible: indicator.vertical
        anchors.centerIn: parent
        spacing: 6

        // Blinking dot / Loading spinner / Stop Icon on hover
        Item {
            implicitWidth: 16
            implicitHeight: 16
            Layout.alignment: Qt.AlignHCenter

            MaterialSymbol {
                visible: indicator.isLoading
                anchors.centerIn: parent
                text: "progress_activity"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer

                RotationAnimator on rotation {
                    running: indicator.isLoading
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            MaterialSymbol {
                visible: !indicator.isLoading
                anchors.centerIn: parent
                text: indicator.containsMouse ? "stop" : "fiber_manual_record"
                iconSize: indicator.containsMouse ? 14 : 12
                color: indicator.isPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer

                SequentialAnimation on opacity {
                    running: indicator.activelyRecording && !indicator.isPaused && !indicator.containsMouse
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }
                opacity: (indicator.isPaused && !indicator.containsMouse) ? 0.5 : 1.0
            }
        }

        // Vertical Timer digits (Minutes on top, Seconds below)
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
