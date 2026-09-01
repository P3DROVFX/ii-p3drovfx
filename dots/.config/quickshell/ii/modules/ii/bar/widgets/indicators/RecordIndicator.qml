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
    Layout.fillHeight: vertical
    // With click-to-show popups the popup opens off containsMouse turning true on press,
    // so hover must stay off — otherwise the popup shows on hover like every other mode.
    readonly property bool clickToShowPopup: Config.options.bar.tooltips.clickToShow
    // containsMouse still flips on press with hover off, so keep the stop-morph out of that mode.
    readonly property bool showHoverState: containsMouse && !clickToShowPopup
    hoverEnabled: !clickToShowPopup
    cursorShape: Qt.PointingHandCursor

    // Size calculation (dynamic and perfectly padded to prevent any overlapping)
    implicitWidth: (activelyRecording || isLoading)
        ? (vertical ? Appearance.sizes.verticalBarWidth : layoutHoriz.implicitWidth)
        : 0
    implicitHeight: (activelyRecording || isLoading)
        ? (vertical ? layoutVert.implicitHeight : Appearance.sizes.baseBarHeight)
        : 0

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
                ? (indicator.showHoverState ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.showHoverState ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.isLoading 
                    ? "progress_activity" 
                    : (indicator.showHoverState ? "stop" : "fiber_manual_record")
                iconSize: indicator.isLoading ? 16 : (indicator.showHoverState ? 14 : 12)
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
                ? (indicator.showHoverState ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.showHoverState ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            opacity: (indicator.isPaused && !indicator.showHoverState) ? 0.6 : 1.0

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
                ? (indicator.showHoverState ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.showHoverState ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            Layout.alignment: Qt.AlignHCenter

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.isLoading 
                    ? "progress_activity" 
                    : (indicator.showHoverState ? "stop" : "fiber_manual_record")
                iconSize: indicator.isLoading ? 16 : (indicator.showHoverState ? 14 : 12)
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
                ? (indicator.showHoverState ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (indicator.showHoverState ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            Layout.alignment: Qt.AlignHCenter
            opacity: (indicator.isPaused && !indicator.showHoverState) ? 0.6 : 1.0

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
    // In click-to-show mode the click belongs to the popup; stopping is done from its Stop button.
    onClicked: (mouse) => {
        if (mouse.button !== Qt.LeftButton) return
        if (indicator.clickToShowPopup) return
        if (!activelyRecording) return
        Quickshell.execDetached(["bash", Directories.recordScriptPath])
        controlsPopup.close()
    }

    // ── Premium Recording Controls Popup ─────────────────────────────────────
    StyledPopup {
        id: controlsPopup
        hoverTarget: indicator
        stickyHover: true
        popupRadius: Appearance.rounding.large

        contentItem: ColumnLayout {
            id: recLayout
            spacing: 16
            implicitWidth: 320

            readonly property bool startAnim: controlsPopup.opened && controlsPopup.popupOpenProgress > 0.6

            onStartAnimChanged: {
                if (startAnim) {
                    recCard.opacity = 0.0;
                    recCard.scale = 0.85;
                    recCardTransform.y = 25;

                    controlsRow.opacity = 0.0;
                    controlsRow.scale = 0.85;
                    controlsRowTransform.y = 25;

                    Qt.callLater(function() {
                        recCardAnim.start();
                        controlsRowAnim.start();
                    });
                }
            }

            Connections {
                target: controlsPopup
                function onPopupOpenProgressChanged() {
                    if (controlsPopup.popupOpenProgress === 0.0) {
                        recCardAnim.stop();
                        controlsRowAnim.stop();

                        recCard.opacity = 0.0;
                        recCard.scale = 0.85;
                        recCardTransform.y = 25;

                        controlsRow.opacity = 0.0;
                        controlsRow.scale = 0.85;
                        controlsRowTransform.y = 25;
                    }
                }
            }

            HeroCard {
                id: recCard
                startAnim: recLayout.startAnim

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: recCardTransform
                    y: 25
                }

                SequentialAnimation {
                    id: recCardAnim
                    PauseAnimation { duration: 40 }
                    ParallelAnimation {
                        NumberAnimation { target: recCard; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: recCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: recCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

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
                id: controlsRow
                Layout.fillWidth: true
                spacing: 12
                visible: !indicator.isLoading

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: controlsRowTransform
                    y: 25
                }

                SequentialAnimation {
                    id: controlsRowAnim
                    PauseAnimation { duration: 100 }
                    ParallelAnimation {
                        NumberAnimation { target: controlsRow; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: controlsRow; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: controlsRowTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                // Keystroke display, for this recording only. It is re-seeded
                // from the persistent setting whenever a recording starts, so
                // switching it on here never carries over to the next one.
                RippleButton {
                    id: keysBtn
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    buttonRadius: Appearance.rounding.full

                    readonly property bool showingKeys: KeypressService.recordingEnabled

                    toggled: keysBtn.showingKeys
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                    onClicked: KeypressService.toggleForRecording()

                    contentItem: Item {
                        implicitWidth: keysIcon.implicitWidth
                        implicitHeight: keysIcon.implicitHeight

                        MaterialSymbol {
                            id: keysIcon
                            anchors.centerIn: parent
                            text: keysBtn.showingKeys ? "keyboard" : "keyboard_off"
                            iconSize: 18
                            color: keysBtn.showingKeys ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledToolTip {
                        text: keysBtn.showingKeys
                            ? Translation.tr("Stop showing keystrokes on screen")
                            : Translation.tr("Show keystrokes on screen for this recording")
                    }
                }

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
