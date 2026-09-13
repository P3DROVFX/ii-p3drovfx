pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

// Apple Music–style frontend: artwork fills the screen, the title and a glass
// transport card sit over it, and lyrics or the queue live on the blurred side.
Item {
    id: root
    required property var context
    readonly property bool optionsOpen: GlobalStates.mediaModeImmersiveOptionsOpen
    function setOptionsOpen(open) {
        GlobalStates.mediaModeImmersiveOptionsOpen = open;
    }
    Component.onDestruction: GlobalStates.mediaModeImmersiveOptionsOpen = false
    property string panelTab: "lyrics"

    // Always light-on-dark over the artwork, whatever the shell theme is. With "match
    // shell colors to album art" on, text and controls take a faint tint of the cover:
    // a very light tone of its colour, mixed in at a quarter.
    readonly property color neutralForeground: ColorUtils.getContrastingTextColor(Appearance.m3colors.m3scrim)
    property color foreground: context.dynamicColorEnabled
                               ? ColorUtils.mix(neutralForeground, ColorUtils.colorWithLightness(
                                                    context.albumArtExtractedColor, 0.86), 0.72)
                               : neutralForeground
    Behavior on foreground {
        ColorAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    readonly property color subtleForeground: ColorUtils.applyAlpha(foreground, 0.64)
    readonly property color tint: context.videoActive ? context.extractedColor : context.albumArtExtractedColor
    // Mid-grey material, like Apple's: it lifts dark covers and dims light ones, so
    // glass reads as a surface on any artwork. A pure scrim tint vanished on dark art.
    readonly property color glass: ColorUtils.applyAlpha(ColorUtils.mix(ColorUtils.mix(Appearance.m3colors.m3scrim,
                                                                                       foreground, 0.78), tint, 0.8),
                                                         0.34)
    // Solid field beside the whole cover. With "match shell colors" on, matugen was
    // seeded from this cover, so its dark primary container is the most faithful
    // tone; otherwise fall back to the extracted colour itself, kept dark for the
    // always-light text.
    property color fieldColor: context.dynamicColorEnabled ? (Appearance.m3colors.darkmode
                                                              ? Appearance.m3colors.m3primaryContainer
                                                              : ColorUtils.colorWithLightness(
                                                                    Appearance.m3colors.m3primary, 0.2))
                                                           : ColorUtils.colorWithLightness(
                                                                 context.albumArtExtractedColor, 0.18)
    Behavior on fieldColor {
        ColorAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    readonly property real gutter: Math.max(Appearance.sizes.elevationMargin * 4, Math.min(width, height) * 0.045)
    readonly property string artLayout: Persistent.states.background.mediaMode.immersiveArtLayout === "cover"
                                        ? "cover" : "side"
    readonly property real panelProgress: context.rightPanelAnimationProgress
    readonly property real columnX: Math.round(width * 0.56)
    // Room for the title and the transport card on the artwork side.
    readonly property real stageWidth: width + (columnX - width) * panelProgress
    readonly property bool bothTabs: context.lyricsPanelVisible && context.queueEligible
    readonly property string activeTab: !context.lyricsPanelVisible ? "queue" : (!context.queueEligible ? "lyrics" :
                                                                                                        panelTab)

    function expressiveAxes(weight, width) {
        return {
            "wght": weight,
            "wdth": width,
            "ROND": 100
        };
    }

    // YouTube Music often serves the cover pillarboxed inside a 16:9 thumbnail. A
    // helper trims uniform dark bars into a cached copy; until it answers, the
    // previous artwork stays up instead of flashing the bars.
    property string artSource: ""
    function trimArtwork() {
        const path = root.context.displayedArtFilePath;
        if (!path) {
            root.artSource = "";
            return;
        }
        trimProcess.requested = path;
        trimProcess.exec(["python3", `${Directories.scriptPath}/media/trim_cover_borders.py`, path,
                          `${Directories.coverArt}/trimmed`]);
    }
    Connections {
        target: root.context
        function onDisplayedArtFilePathChanged() {
            root.trimArtwork();
        }
    }
    Component.onCompleted: {
        root.syncTrackTexts();
        root.trimArtwork();
    }
    Process {
        id: trimProcess
        property string requested: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (trimProcess.requested !== root.context.displayedArtFilePath || out.length === 0)
                    return;
                root.artSource = out.startsWith("/") ? `file://${out}` : out;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && trimProcess.requested === root.context.displayedArtFilePath)
                root.artSource = trimProcess.requested;
        }
    }

    // Entrance -------------------------------------------------------------------
    // The Immersive tree is created fresh every time Media Mode opens, so a single
    // one-shot driver is enough. Offsets go through margins/positions (not
    // transforms) so the frosted glass, which follows geometry, moves with them.
    //
    // It starts once the first artwork is decoded (or after a short timeout when
    // there is none), so the first visible frame is never a half-loaded blur.
    property real intro: 0
    property bool introStarted: false
    function startIntro() {
        if (root.introStarted)
            return;
        root.introStarted = true;
        if (Appearance.animMultiplier <= 0)
            root.intro = 1;
        else
            introAnimation.start();
    }
    NumberAnimation {
        id: introAnimation
        target: root
        property: "intro"
        from: 0
        to: 1
        duration: Math.round(1100 * Appearance.animMultiplier)
    }
    Connections {
        target: artwork
        function onReadyChanged() {
            if (artwork.ready)
                root.startIntro();
        }
    }
    Timer {
        interval: 900
        running: !root.introStarted
        onTriggered: root.startIntro()
    }
    function introAt(delay, span) {
        const x = Math.max(0, Math.min(1, (root.intro - delay) / span));
        return 1 - Math.pow(1 - x, 4);
    }
    readonly property real introChrome: introAt(0, 0.5)
    readonly property real introArt: introAt(0, 0.45)
    readonly property real introTitle: introAt(0.1, 0.55)
    readonly property real introCard: introAt(0.2, 0.55)
    readonly property real introPanels: introAt(0.28, 0.6)

    // Track change: the title block leaves upward and the new one rises in.
    property string shownAlbum: ""
    property string shownTitle: ""
    property string shownArtist: ""
    function syncTrackTexts() {
        root.shownAlbum = root.context.player?.trackAlbum ?? "";
        root.shownTitle = root.context.player?.trackTitle || Translation.tr("Nothing playing");
        root.shownArtist = root.context.player?.trackArtist || Translation.tr("Unknown artist");
    }
    Connections {
        target: root.context
        function onCurrentTrackKeyChanged() {
            if (Appearance.animMultiplier <= 0) {
                root.syncTrackTexts();
                return;
            }
            trackTextAnimation.restart();
        }
    }
    Connections {
        target: root.context.player
        ignoreUnknownSignals: true
        function onTrackAlbumChanged() {
            if (!trackTextAnimation.running)
                root.shownAlbum = root.context.player?.trackAlbum ?? "";
        }
    }
    SequentialAnimation {
        id: trackTextAnimation
        ParallelAnimation {
            NumberAnimation {
                target: trackTexts
                property: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: trackTextsShift
                property: "y"
                to: -Appearance.sizes.elevationMargin * 1.5
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
        }
        ScriptAction {
            script: root.syncTrackTexts()
        }
        PropertyAction {
            target: trackTextsShift
            property: "y"
            value: Appearance.sizes.elevationMargin * 2
        }
        ParallelAnimation {
            NumberAnimation {
                target: trackTexts
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: trackTextsShift
                property: "y"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
    }

    function formatTime(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0));
        return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0");
    }

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.applyAlpha(ColorUtils.mix(Appearance.m3colors.m3scrim, root.tint, 0.85),
                                     root.context.videoActive ? 0 : 1)
        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }

    MediaModeImmersiveArtwork {
        id: artwork
        anchors.fill: parent
        opacity: root.introArt
        source: root.artSource
        layout: root.artLayout
        panelProgress: root.panelProgress
        videoActive: root.context.videoActive
        tint: root.tint
        fieldColor: root.fieldColor
    }

    MaterialSymbol {
        x: (root.stageWidth - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.context.displayedArtFilePath && !root.context.videoActive && root.introStarted
        opacity: root.introArt
        text: "album"
        iconSize: Appearance.font.pixelSize.hugeass * 4
        color: ColorUtils.applyAlpha(root.foreground, 0.24)
    }

    // Frosted surfaces share the artwork's coordinate space and sit under their content.
    MediaModeImmersiveGlass {
        x: sourceChip.x
        y: sourceChip.y
        width: sourceChip.width
        height: sourceChip.height
        radius: sourceChip.radius
        opacity: root.introChrome
        backdrop: artwork
        color: root.glass
    }
    MediaModeImmersiveGlass {
        x: toolbar.x
        y: toolbar.y
        width: toolbar.width
        height: toolbar.height
        radius: toolbar.radius
        opacity: root.introChrome
        backdrop: artwork
        color: root.glass
    }
    MediaModeImmersiveGlass {
        x: nowPlaying.x + transportCard.x
        y: nowPlaying.y + transportCard.y
        width: transportCard.width
        height: transportCard.height
        radius: transportCard.radius
        opacity: root.introCard
        backdrop: artwork
        color: root.glass
    }
    MediaModeImmersiveGlass {
        x: panels.x + tabs.x
        y: panels.y + tabs.y
        width: tabs.width
        height: tabs.height
        radius: tabs.radius
        visible: panels.visible && tabs.visible
        opacity: panels.opacity
        backdrop: artwork
        color: root.glass
    }

    // Top bar ---------------------------------------------------------------
    Rectangle {
        id: sourceChip
        opacity: root.introChrome
        anchors.left: parent.left
        anchors.leftMargin: root.gutter
        anchors.verticalCenter: toolbar.verticalCenter
        implicitWidth: sourceRow.implicitWidth + Appearance.sizes.elevationMargin * 3
        implicitHeight: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin / 2
        radius: Appearance.rounding.full
        color: ColorUtils.applyAlpha(root.glass, 0)
        RowLayout {
            id: sourceRow
            anchors.centerIn: parent
            spacing: Appearance.sizes.elevationMargin * 0.8
            MaterialSymbol {
                text: root.context.localSource ? "library_music" : (root.context.videoActive ? "music_video" :
                                                                                               "graphic_eq")
                iconSize: Appearance.font.pixelSize.large
                color: root.foreground
                fill: 1
            }
            StyledText {
                Layout.maximumWidth: root.width * 0.3
                text: root.context.localSource ? Translation.tr("Local music") : (root.context.player?.identity
                                                                                  || Translation.tr("Now playing"))
                elide: Text.ElideRight
                color: root.foreground
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
        }
    }

    Rectangle {
        id: toolbar
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.gutter / 2 - (1 - root.introChrome) * Appearance.sizes.elevationMargin * 2
        anchors.rightMargin: root.gutter
        opacity: root.introChrome
        implicitWidth: toolbarRow.implicitWidth + Appearance.sizes.elevationMargin
        implicitHeight: toolbarRow.implicitHeight + Appearance.sizes.elevationMargin
        radius: Appearance.rounding.full
        color: ColorUtils.applyAlpha(root.glass, 0)
        RowLayout {
            id: toolbarRow
            anchors.centerIn: parent
            spacing: 0
            MediaModeImmersiveButton {
                visible: root.context.rightPanelEligible
                symbol: root.context.queueEligible && !root.context.lyricsPanelVisible ? "queue_music" : "lyrics"
                quiet: true
                foreground: root.foreground
                highlighted: !root.context.coverExpanded
                tooltip: Translation.tr("Show or hide side panels")
                onClicked: {
                    root.context.coverExpanded = !root.context.coverExpanded;
                    Persistent.states.background.mediaMode.coverExpanded = root.context.coverExpanded;
                }
            }
            MediaModeImmersiveButton {
                symbol: root.artLayout === "cover" ? "fullscreen_exit" : "fullscreen"
                quiet: true
                foreground: root.foreground
                tooltip: root.artLayout === "cover" ? Translation.tr("Show the whole cover") :
                                                      Translation.tr("Fill the screen with the cover")
                onClicked: Persistent.states.background.mediaMode.immersiveArtLayout = root.artLayout === "cover"
                           ? "side" : "cover"
            }
            MediaModeImmersiveButton {
                symbol: "headphones"
                quiet: true
                foreground: root.foreground
                tooltip: Translation.tr("Audio output")
                onClicked: root.context.showAudioOutputDialog = true
            }
            MediaModeImmersiveButton {
                symbol: "more_horiz"
                quiet: true
                foreground: root.foreground
                highlighted: root.optionsOpen
                tooltip: Translation.tr("Player options")
                onClicked: root.setOptionsOpen(!root.optionsOpen)
            }
            MediaModeImmersiveButton {
                symbol: "close"
                quiet: true
                foreground: root.foreground
                tooltip: Translation.tr("Exit Fullscreen Media Mode")
                onClicked: root.context.closeRequested(!Config.options.background.mediaMode.togglePerMonitor)
            }
        }
    }

    // Title and transport ----------------------------------------------------
    ColumnLayout {
        id: nowPlaying
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.gutter
        anchors.bottomMargin: root.gutter - (1 - root.introTitle) * Appearance.sizes.elevationMargin * 3
        width: Math.max(0, Math.min(root.stageWidth - root.gutter * 2, 640))
        opacity: root.introTitle
        spacing: 0

        ColumnLayout {
            id: trackTexts
            Layout.fillWidth: true
            spacing: 0
            transform: Translate {
                id: trackTextsShift
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.shownAlbum
                color: root.subtleForeground
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: root.expressiveAxes(600, 115)
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.sizes.elevationMargin / 2
                text: root.shownTitle
                color: root.foreground
                font.family: Appearance.font.family.title
                font.pixelSize: nowPlaying.width < 480 ? Appearance.font.pixelSize.hugeass * 1.5 :
                                                         Appearance.font.pixelSize.hugeass * 2.3
                font.variableAxes: root.expressiveAxes(760, 125)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.sizes.elevationMargin / 2
                text: root.shownArtist
                color: root.subtleForeground
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.variableAxes: root.expressiveAxes(520, 118)
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: transportCard
            Layout.fillWidth: true
            Layout.topMargin: Appearance.sizes.elevationMargin * 2 + (1 - root.introCard) * Appearance.sizes.elevationMargin
                              * 3
            opacity: root.introCard
            implicitHeight: transport.implicitHeight + Appearance.sizes.elevationMargin * 3
            radius: Appearance.rounding.verylarge
            color: ColorUtils.applyAlpha(root.glass, 0)

            ColumnLayout {
                id: transport
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Appearance.sizes.elevationMargin * 2
                anchors.rightMargin: Appearance.sizes.elevationMargin * 2
                spacing: Appearance.sizes.elevationMargin / 2

                // Apple-style scrubber: elapsed and remaining time flank a thick,
                // fully rounded bar with no handle.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.sizes.elevationMargin / 2
                    spacing: Appearance.sizes.elevationMargin
                    visible: Config.options.background.mediaMode.showSeekBar
                    StyledText {
                        Layout.minimumWidth: remainingLabel.implicitWidth
                        horizontalAlignment: Text.AlignRight
                        text: root.formatTime(positionSlider.displayPosition)
                        color: root.subtleForeground
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledSlider {
                        id: positionSlider
                        Layout.fillWidth: true
                        readonly property real trackLength: root.context.player?.length ?? 0
                        // MPRIS players can briefly report a position past the end of the
                        // track (most visibly right after a seek). Clamping here keeps a
                        // 3 minute song from ever displaying as 15 minutes.
                        readonly property real reportedPosition: Math.max(0, Math.min(trackLength,
                                                                                      root.context.player?.position
                                                                                      ?? 0))
                        // While a drag is in flight, and until the player confirms the new
                        // position, the slider owns its own value.
                        property real pendingSeekPosition: -1
                        property real dragValue: 0
                        property bool seekDirty: false
                        readonly property bool seeking: pressed || pendingSeekPosition >= 0
                        readonly property real displayPosition: seeking ? Math.max(0, Math.min(trackLength, value
                                                                                               * trackLength)) :
                                                                          reportedPosition

                        // One absolute seek per gesture. Seeking on every onMoved fires
                        // dozens of requests per drag, and each one is resolved against a
                        // position the player has not caught up to yet, so they compound
                        // and run the track far past its own length.
                        function commitSeek() {
                            if (positionSlider.trackLength <= 0 || !(root.context.player?.canSeek ?? false))
                                return;

                            const target = Math.max(0, Math.min(positionSlider.trackLength, positionSlider.dragValue
                                                                * positionSlider.trackLength));
                            positionSlider.seekDirty = false;
                            positionSlider.pendingSeekPosition = target;
                            positionSlider.value = target / positionSlider.trackLength;
                            if (typeof root.context.player.seek === "function") {
                                root.context.player.seek(target);
                            } else {
                                root.context.player.position = target;
                            }
                            seekSettleTimer.restart();
                        }

                        // A groove click can emit moved() on either side of the release,
                        // so the commit is driven by "the value changed" rather than by a
                        // single handler, and fires exactly once either way.
                        onMoved: {
                            positionSlider.dragValue = value;
                            positionSlider.seekDirty = true;
                            if (!pressed)
                                positionSlider.commitSeek();
                        }
                        onPressedChanged: {
                            if (pressed) {
                                positionSlider.dragValue = value;
                                positionSlider.seekDirty = false;
                            } else if (positionSlider.seekDirty) {
                                positionSlider.commitSeek();
                            }
                        }
                        onReportedPositionChanged: {
                            if (positionSlider.pendingSeekPosition >= 0 && Math.abs(reportedPosition
                                                                                    - positionSlider.pendingSeekPosition)
                                    < 1.5) {
                                positionSlider.pendingSeekPosition = -1;
                                seekSettleTimer.stop();
                            }
                        }

                        // Assigning value during a drag would otherwise destroy the
                        // binding permanently and freeze the track after the first seek.
                        Binding {
                            target: positionSlider
                            property: "value"
                            value: positionSlider.trackLength > 0 ? positionSlider.reportedPosition
                                                                    / positionSlider.trackLength : 0
                            when: !positionSlider.seeking
                            restoreMode: Binding.RestoreNone
                        }

                        // Give up waiting for confirmation if the player never reports the
                        // seeked position, rather than freezing the track forever.
                        Timer {
                            id: seekSettleTimer
                            interval: 1500
                            onTriggered: positionSlider.pendingSeekPosition = -1
                        }

                        // Most external MPRIS players do not emit continuous position signals.
                        // Poll at ~4 Hz while playing so the slider tracks smoothly.
                        // Local player streams position updates continuously, so avoid redundant polling.
                        Timer {
                            interval: 250
                            running: (root.context.player?.isPlaying ?? false) && !positionSlider.pressed
                                     && !root.context.localSource
                            repeat: true
                            onTriggered: {
                                if (root.context.player && !root.context.localSource) {
                                    root.context.player.positionChanged();
                                }
                            }
                        }

                        enabled: (root.context.player?.canSeek ?? false) && trackLength > 0
                        usePercentTooltip: false
                        tooltipContent: root.formatTime(displayPosition)
                        leftPadding: 0
                        rightPadding: 0
                        implicitHeight: Appearance.sizes.minimumTouchTarget / 2

                        // The bar thickens under the pointer and while scrubbing.
                        property real barHeight: (pressed || hovered) ? Appearance.sizes.elevationMargin * 1.1 :
                                                                        Appearance.sizes.elevationMargin * 0.7
                        Behavior on barHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        handle: Item {
                            implicitWidth: 0
                            implicitHeight: 0
                        }
                        background: Item {
                            implicitHeight: positionSlider.implicitHeight
                            width: positionSlider.availableWidth
                            height: positionSlider.height
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: positionSlider.barHeight
                                radius: Appearance.rounding.full
                                color: ColorUtils.applyAlpha(root.foreground, 0.22)
                                // Rounded on both ends, and never narrower than its own
                                // height so the leading cap stays a full semicircle.
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    width: Math.max(height, positionSlider.visualPosition * parent.width)
                                    visible: positionSlider.visualPosition > 0
                                    radius: Appearance.rounding.full
                                    color: ColorUtils.applyAlpha(root.foreground, positionSlider.enabled ? 0.9 : 0.5)
                                }
                            }
                        }
                    }
                    StyledText {
                        id: remainingLabel
                        text: "−" + root.formatTime(positionSlider.trackLength - positionSlider.displayPosition)
                        color: root.subtleForeground
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin / 2

                    MediaModeImmersiveButton {
                        symbol: "shuffle"
                        quiet: true
                        foreground: root.foreground
                        highlighted: root.context.player?.shuffle ?? false
                        tooltip: Translation.tr("Shuffle")
                        onClicked: if (root.context.player)
                                       root.context.player.shuffle = !root.context.player.shuffle
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    MediaModeImmersiveButton {
                        symbol: "fast_rewind"
                        quiet: true
                        symbolSize: Appearance.font.pixelSize.hugeass * 1.3
                        implicitWidth: Appearance.sizes.minimumTouchTarget * 1.2
                        foreground: root.foreground
                        tooltip: Translation.tr("Previous track")
                        enabled: root.context.player?.canGoPrevious ?? false
                        onClicked: root.context.player?.previous()
                    }
                    // Expressive primary action: the container squares off while
                    // playing, the same shape language as the M3 play/pause morph.
                    MediaModeImmersiveButton {
                        readonly property bool playing: root.context.player?.isPlaying ?? false
                        Layout.leftMargin: Appearance.sizes.elevationMargin
                        Layout.rightMargin: Appearance.sizes.elevationMargin
                        symbol: playing ? "pause" : "play_arrow"
                        filled: true
                        symbolSize: Appearance.font.pixelSize.hugeass * 1.35
                        implicitWidth: Appearance.sizes.minimumTouchTarget * 1.35
                        buttonRadius: playing ? Appearance.rounding.large : implicitWidth / 2
                        foreground: root.foreground
                        tooltip: Translation.tr("Play / Pause")
                        onClicked: root.context.player?.togglePlaying()
                        Behavior on buttonRadius {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }
                    MediaModeImmersiveButton {
                        symbol: "fast_forward"
                        quiet: true
                        symbolSize: Appearance.font.pixelSize.hugeass * 1.3
                        implicitWidth: Appearance.sizes.minimumTouchTarget * 1.2
                        foreground: root.foreground
                        tooltip: Translation.tr("Next track")
                        enabled: root.context.player?.canGoNext ?? false
                        onClicked: root.context.player?.next()
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    MediaModeImmersiveButton {
                        symbol: root.context.player?.loopState === 2 ? "repeat_one" : "repeat"
                        quiet: true
                        foreground: root.foreground
                        highlighted: (root.context.player?.loopState ?? 0) !== 0
                        tooltip: Translation.tr("Repeat")
                        onClicked: if (root.context.player)
                                       root.context.player.loopState = ((root.context.player.loopState ?? 0) + 1) % 3
                    }
                }
            }
        }
    }

    // Lyrics and queue -------------------------------------------------------
    Item {
        id: panels
        x: root.columnX + root.gutter * (1 - root.panelProgress) + (1 - root.introPanels) * root.gutter * 1.5
        y: root.gutter / 2 + toolbar.height + root.gutter / 2
        width: Math.max(0, root.width - root.columnX - root.gutter)
        height: Math.max(0, root.height - y - root.gutter)
        visible: root.context.rightPanelVisible
        opacity: root.panelProgress * root.introPanels

        Rectangle {
            id: tabs
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            visible: root.bothTabs
            implicitWidth: tabsRow.implicitWidth + 8
            implicitHeight: tabsRow.implicitHeight + 8
            radius: Appearance.rounding.full
            color: ColorUtils.applyAlpha(root.glass, 0)

            // Selection pill that slides between tabs (M3 expressive spatial curve).
            Rectangle {
                id: tabIndicator
                readonly property Item target: tabsRepeater.count > 1 ? tabsRepeater.itemAt(root.activeTab === "queue"
                                                                                              ? 1 : 0) : null
                x: tabsRow.x + (target?.x ?? 0)
                y: tabsRow.y + (target?.y ?? 0)
                width: target?.width ?? 0
                height: target?.height ?? 0
                radius: Appearance.rounding.full
                color: root.foreground
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
            }
            RowLayout {
                id: tabsRow
                anchors.centerIn: parent
                spacing: 0
                Repeater {
                    id: tabsRepeater
                    model: [
                        {
                            key: "lyrics",
                            icon: "lyrics",
                            label: Translation.tr("Lyrics")
                        },
                        {
                            key: "queue",
                            icon: "queue_music",
                            label: Translation.tr("Up next")
                        }
                    ]
                    delegate: RippleButton {
                        id: tabButton
                        required property var modelData
                        readonly property bool selected: root.activeTab === modelData.key
                        implicitHeight: Appearance.sizes.minimumTouchTarget - 8
                        implicitWidth: tabContent.implicitWidth + Appearance.sizes.elevationMargin * 3
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.applyAlpha(root.foreground, 0)
                        colBackgroundHover: ColorUtils.applyAlpha(root.foreground, selected ? 0 : 0.12)
                        colBackgroundActive: ColorUtils.applyAlpha(root.foreground, 0.2)
                        colRipple: ColorUtils.applyAlpha(root.tint, 0.2)
                        onClicked: root.panelTab = modelData.key
                        RowLayout {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: Appearance.sizes.elevationMargin / 2
                            property color contentColor: tabButton.selected
                                                         ? ColorUtils.getContrastingTextColor(root.foreground)
                                                         : root.foreground
                            Behavior on contentColor {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            MaterialSymbol {
                                text: tabButton.modelData.icon
                                iconSize: Appearance.font.pixelSize.large
                                color: tabContent.contentColor
                                fill: 1
                            }
                            StyledText {
                                text: tabButton.modelData.label
                                color: tabContent.contentColor
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.variableAxes: root.expressiveAxes(620, 112)
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: panelBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: root.bothTabs ? tabs.bottom : parent.top
            anchors.topMargin: root.bothTabs ? Appearance.sizes.elevationMargin : 0

            Loader {
                id: lyricsLoader
                anchors.fill: parent
                active: root.context.lyricsPanelVisible
                opacity: root.activeTab === "lyrics" ? 1 : 0
                visible: opacity > 0
                transform: Translate {
                    x: (1 - lyricsLoader.opacity) * -Appearance.sizes.elevationMargin * 3
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
                sourceComponent: MediaModeLyricsContent {
                    context: root.context
                    activeColor: root.foreground
                    onAccentContainerColor: ColorUtils.getContrastingTextColor(root.foreground)
                    textColor: root.foreground
                    subtextColor: root.subtleForeground
                    surfaceColor: ColorUtils.applyAlpha(root.foreground, 0.1)
                    surfaceHoverColor: ColorUtils.applyAlpha(root.foreground, 0.16)
                    surfaceActiveColor: ColorUtils.applyAlpha(root.foreground, 0.24)
                    onSurfaceColor: root.foreground
                }
            }

            Loader {
                id: queueLoader
                anchors.fill: parent
                active: root.context.queueEligible
                opacity: root.activeTab === "queue" ? 1 : 0
                visible: opacity > 0
                transform: Translate {
                    x: (1 - queueLoader.opacity) * Appearance.sizes.elevationMargin * 3
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
                sourceComponent: MediaModeQueue {
                    immersive: true
                    expanded: true
                    lyricsToggleAvailable: false
                    expandToggleAvailable: false
                    queueSnapshot: LocalMediaService.queueSnapshot
                    accentColor: root.foreground
                    accentContainerColor: ColorUtils.applyAlpha(root.foreground, 0.18)
                    onAccentContainerColor: root.foreground
                    cardColor: ColorUtils.applyAlpha(root.glass, 0)
                    cardBaseColor: ColorUtils.mix(Appearance.m3colors.m3scrim, root.tint, 0.8)
                    dialogColor: ColorUtils.mix(Appearance.m3colors.m3scrim, root.tint, 0.7)
                    textColor: root.foreground
                    subtextColor: root.subtleForeground
                    surfaceColor: ColorUtils.applyAlpha(root.foreground, 0.1)
                    surfaceHoverColor: ColorUtils.applyAlpha(root.foreground, 0.16)
                    surfaceActiveColor: ColorUtils.applyAlpha(root.foreground, 0.24)
                    surfaceHighColor: ColorUtils.applyAlpha(root.foreground, 0.14)
                    onSurfaceColor: root.foreground
                    onOpenFileBrowserRequested: audioOnly => root.context.openFileBrowser(audioOnly)
                }
            }
        }
    }

    MediaModeImmersiveOptions {
        anchors.fill: parent
        context: root.context
        open: root.optionsOpen
        backdrop: artwork
        foreground: root.foreground
        tint: root.tint
        sheetTopMargin: toolbar.y + toolbar.height + Appearance.sizes.elevationMargin
        sheetRightMargin: root.gutter
        lyricsStatus: lyricsLoader.item?.statusLabel ?? ""
        onDismissed: root.setOptionsOpen(false)
    }
}
