import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: coverArt

    property string backgroundShapeString: Config.options.background.mediaMode.backgroundShape
    property bool showLoadingIndicator: false
    property bool effectiveShowLoadingIndicator: false
    property color accentColor: Appearance.colors.colPrimary
    property color accentContainerColor: Appearance.colors.colPrimaryContainer
    property color onAccentContainerColor: Appearance.colors.colOnPrimaryContainer

    onShowLoadingIndicatorChanged: {
        if (coverArt.showLoadingIndicator) {
            loadingIndTimer.restart();
        } else {
            loadingIndTimer.stop();
            coverArt.effectiveShowLoadingIndicator = false;
        }
    }

    Timer {
        id: loadingIndTimer
        interval: 200
        repeat: false
        running: false
        onTriggered: {
            coverArt.effectiveShowLoadingIndicator = true;
        }
    }

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0) return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${m}:${s < 10 ? '0' : ''}${s}`;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumHeight: parent.height * 0.48
            Layout.alignment: Qt.AlignHCenter

            StyledDropShadow {
                target: artBackgroundLoader
            }

            Loader {
                id: artBackgroundLoader
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                active: true

                sourceComponent: Item {
                    id: artContainer
                    anchors.fill: parent

                    // Soft pulse breathing animation when music plays
                    scale: root.player?.isPlaying ? 1.025 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 800; easing.type: Easing.OutBack }
                    }

                    MaterialShape {
                        id: artBackground
                        anchors.fill: parent
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
                        shapeString: coverArt.backgroundShapeString

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: MaterialShape {
                                width: artBackground.width
                                height: artBackground.height
                                shapeString: coverArt.backgroundShapeString
                            }
                        }

                        TransitionImage {
                            id: mediaArt
                            anchors.fill: parent
                            imageSource: root.displayedArtFilePath
                            sourceSize: Qt.size(Math.max(400, width), Math.max(400, height))
                        }

                        FadeLoader {
                            shown: coverArt.effectiveShowLoadingIndicator
                            anchors.centerIn: parent
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                loading: true
                                visible: loading
                                implicitSize: 84
                                color: coverArt.accentColor
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    const availableShapes = [
                                        "Square", "Circle", "Slanted", "Arch", "Fan", "Arrow", "SemiCircle", 
                                        "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", 
                                        "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", 
                                        "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", 
                                        "Burst", "SoftBurst", "Boom", "SoftBoom", "Flower", "Puffy", "PuffyDiamond", 
                                        "Bun", "Heart"
                                    ];
                                    const current = Config.options.background.mediaMode.backgroundShape || "Square";
                                    let idx = availableShapes.indexOf(current);
                                    let next = availableShapes[(idx + 1) % availableShapes.length];
                                    Config.options.background.mediaMode.backgroundShape = next;
                                } else if (mouse.button === Qt.MiddleButton) {
                                    root.displayedArtFilePath = "";
                                    root.updateArt();
                                }
                            }
                        }
                    }
                }
            }
        }

        // Track Info Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Layout.alignment: Qt.AlignHCenter

            // Album / Player Badge Chip
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: badgeRow.implicitWidth + 24
                implicitHeight: 28
                visible: (root.player?.trackAlbum || root.player?.identity || "").length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                }

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        iconSize: 14
                        text: "album"
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: root.player?.trackAlbum || root.player?.identity || ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: coverArt.onAccentContainerColor
                        opacity: 0.8
                        elide: Text.ElideRight
                        Layout.maximumWidth: 280
                    }
                }
            }

            // Track Title
            StyledText {
                Layout.fillWidth: true
                text: root.player?.trackTitle || Translation.tr("Unknown Title")
                font.pixelSize: Appearance.font.pixelSize.hugeass * 1.35
                font.weight: Font.Bold
                font.family: Appearance.font.family.expressive || Appearance.font.family.title
                color: coverArt.onAccentContainerColor
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
                horizontalAlignment: Text.AlignHCenter
                font.variableAxes: ({
                    "wght": 700,
                    "ROND": 100
                })
            }

            // Artist Name
            StyledText {
                Layout.fillWidth: true
                text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                color: coverArt.onAccentContainerColor
                opacity: 0.85
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.variableAxes: ({
                    "wght": 500,
                    "ROND": 100
                })
            }
        }

        // Seekbar Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Layout.alignment: Qt.AlignHCenter
            visible: Config.options.background.mediaMode.showSeekBar ?? true

            StyledSlider {
                id: positionSlider
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                Layout.alignment: Qt.AlignHCenter

                readonly property real trackLength: root.player?.length ?? 0
                // MPRIS players can briefly report a position past the end of the
                // track (most visibly right after a seek). Clamping here keeps a
                // 3 minute song from ever displaying as 15 minutes.
                readonly property real reportedPosition: Math.max(0,
                    Math.min(trackLength, root.player?.position ?? 0))
                // While a drag is in flight, and until the player confirms the new
                // position, the slider owns its own value.
                property real pendingSeekPosition: -1
                property real dragValue: 0
                property bool seekDirty: false
                readonly property bool seeking: pressed || pendingSeekPosition >= 0
                readonly property real displayPosition: seeking
                    ? Math.max(0, Math.min(trackLength, value * trackLength))
                    : reportedPosition

                // One absolute seek per gesture. Seeking on every onMoved fires
                // dozens of requests per drag, and each one is resolved against a
                // position the player has not caught up to yet, so they compound
                // and run the track far past its own length.
                function commitSeek() {
                    if (positionSlider.trackLength <= 0 || !(root.player?.canSeek ?? false))
                        return;

                    const target = Math.max(0, Math.min(positionSlider.trackLength,
                        positionSlider.dragValue * positionSlider.trackLength));
                    positionSlider.seekDirty = false;
                    positionSlider.pendingSeekPosition = target;
                    positionSlider.value = target / positionSlider.trackLength;
                    root.player.position = target;
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
                    if (positionSlider.pendingSeekPosition >= 0
                            && Math.abs(reportedPosition - positionSlider.pendingSeekPosition) < 1.5) {
                        positionSlider.pendingSeekPosition = -1;
                        seekSettleTimer.stop();
                    }
                }

                // Assigning value during a drag would otherwise destroy the
                // binding permanently and freeze the track after the first seek.
                Binding {
                    target: positionSlider
                    property: "value"
                    value: positionSlider.trackLength > 0
                        ? positionSlider.reportedPosition / positionSlider.trackLength : 0
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

                Timer {
                    interval: 250
                    running: (root.player?.isPlaying ?? false) && !positionSlider.pressed
                    repeat: true
                    onTriggered: {
                        if (root.player) {
                            root.player.positionChanged();
                        }
                    }
                }

                configuration: StyledSlider.Configuration.Wavy
                // Media Mode is the foreground experience itself. The desktop
                // widget pauses this animation behind application windows, but
                // that optimization must not apply to this dedicated surface.
                animateWave: root.player?.isPlaying ?? false
                trackWidth: 14 // Increased thickness for prominent M3 wavy track!
                highlightColor: coverArt.accentColor
                trackColor: ColorUtils.transparentize(coverArt.accentColor, 0.25)
                handleColor: coverArt.accentColor
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                Layout.alignment: Qt.AlignHCenter

                StyledText {
                    text: coverArt.formatTime(positionSlider.displayPosition)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: coverArt.onAccentContainerColor
                    opacity: 0.8
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: coverArt.formatTime(root.player?.length || 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: coverArt.onAccentContainerColor
                    opacity: 0.8
                }
            }
        }

        // Playback Control Buttons Row (M3 Expressive Shapes)
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            // Shuffle Button
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: (root.player?.shuffle ?? false) ? coverArt.accentColor : ColorUtils.transparentize(coverArt.accentColor, 0.2)
                colBackgroundHover: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Hover, 0.85)
                colBackgroundActive: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Active, 0.7)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    color: coverArt.onAccentContainerColor
                    text: "shuffle"
                }
                onClicked: {
                    if (root.player) root.player.shuffle = !root.player.shuffle;
                }
            }

            // Previous Button
            RippleButton {
                implicitWidth: 56
                implicitHeight: 56
                buttonRadius: Appearance.rounding.verylarge
                colBackground: ColorUtils.transparentize(coverArt.accentColor, 0.25)
                colBackgroundHover: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Hover, 0.85)
                colBackgroundActive: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Active, 0.7)

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    iconSize: 26
                    color: coverArt.onAccentContainerColor
                    text: "skip_previous"
                }
                onClicked: root.player?.previous()
            }

            // Play / Pause Main Hero Button
            RippleButton {
                implicitWidth: 76
                implicitHeight: 76
                buttonRadius: Appearance.rounding.full
                colBackground: coverArt.accentColor
                colBackgroundHover: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Hover, 0.87)
                colBackgroundActive: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Active, 0.7)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 38
                    fill: 1
                    color: coverArt.onAccentContainerColor
                    text: root.player?.isPlaying ? "pause" : "play_arrow"
                }
                onClicked: root.player?.togglePlaying()
            }

            // Next Button
            RippleButton {
                implicitWidth: 56
                implicitHeight: 56
                buttonRadius: Appearance.rounding.verylarge
                colBackground: ColorUtils.transparentize(coverArt.accentColor, 0.25)
                colBackgroundHover: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Hover, 0.85)
                colBackgroundActive: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Active, 0.7)

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    iconSize: 26
                    color: coverArt.onAccentContainerColor
                    text: "skip_next"
                }
                onClicked: root.player?.next()
            }

            // Loop Button
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: (root.player?.loopState ?? 0) !== 0 ? coverArt.accentColor : ColorUtils.transparentize(coverArt.accentColor, 0.2)
                colBackgroundHover: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Hover, 0.85)
                colBackgroundActive: ColorUtils.mix(coverArt.accentColor, Appearance.colors.colLayer1Active, 0.7)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    color: coverArt.onAccentContainerColor
                    text: (root.player?.loopState === 2) ? "repeat_one" : "repeat"
                }
                onClicked: {
                    if (root.player) {
                        root.player.loopState = ((root.player.loopState ?? 0) + 1) % 3;
                    }
                }
            }
        }

        // Volume Bar Row
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            visible: Config.options.background.mediaMode.showVolumeSlider ?? true

            MaterialSymbol {
                iconSize: 20
                color: coverArt.onAccentContainerColor
                text: {
                    const vol = root.player?.volume ?? 1.0;
                    if (vol <= 0) return "volume_off";
                    if (vol < 0.5) return "volume_down";
                    return "volume_up";
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                trackWidth: 8
                highlightColor: coverArt.accentColor
                trackColor: ColorUtils.transparentize(coverArt.accentColor, 0.25)
                handleColor: coverArt.accentColor
                value: root.player?.volume ?? 1.0
                onMoved: {
                    if (root.player) root.player.volume = value;
                }
            }
        }
    }
}
