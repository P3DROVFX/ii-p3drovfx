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
                    scale: root.player?.isPlaying ? 1.02 : 1.0
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
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.displayedArtFilePath = "";
                                root.updateArt();
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
                    color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.3)
                }

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        iconSize: 14
                        text: "album"
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: root.player?.trackAlbum || root.player?.identity || ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSecondaryContainer
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
                color: Appearance.colors.colOnLayer0
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
                color: Appearance.colors.colSubtext
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
            spacing: 2
            Layout.alignment: Qt.AlignHCenter

            StyledSlider {
                id: positionSlider
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                Layout.alignment: Qt.AlignHCenter

                configuration: StyledSlider.Configuration.Wavy
                trackWidth: 10
                highlightColor: Appearance.colors.colPrimary
                trackColor: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.4)
                handleColor: Appearance.colors.colPrimary
                value: (root.player?.length > 0) ? (root.player?.position / root.player?.length) : 0
                onMoved: {
                    if (root.player?.length > 0) {
                        root.player.position = value * root.player.length;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                Layout.alignment: Qt.AlignHCenter

                StyledText {
                    text: coverArt.formatTime(root.player?.position || 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: coverArt.formatTime(root.player?.length || 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
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
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    color: (root.player?.shuffle ?? false) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
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
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundActive: Appearance.colors.colPrimaryContainerActive

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    iconSize: 26
                    color: Appearance.colors.colOnPrimaryContainer
                    text: "skip_previous"
                }
                onClicked: root.player?.previous()
            }

            // Play / Pause Main Hero Button
            RippleButton {
                implicitWidth: 76
                implicitHeight: 76
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colBackgroundActive: Appearance.colors.colPrimaryActive

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 38
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                    text: root.player?.isPlaying ? "pause" : "play_arrow"
                }
                onClicked: root.player?.togglePlaying()
            }

            // Next Button
            RippleButton {
                implicitWidth: 56
                implicitHeight: 56
                buttonRadius: Appearance.rounding.verylarge
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundActive: Appearance.colors.colPrimaryContainerActive

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    iconSize: 26
                    color: Appearance.colors.colOnPrimaryContainer
                    text: "skip_next"
                }
                onClicked: root.player?.next()
            }

            // Loop Button
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    color: (root.player?.loopState ?? 0) !== 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
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

            MaterialSymbol {
                iconSize: 20
                color: Appearance.colors.colSubtext
                text: {
                    const vol = root.player?.volume ?? 1.0;
                    if (vol <= 0) return "volume_off";
                    if (vol < 0.5) return "volume_down";
                    return "volume_up";
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                trackWidth: 6
                highlightColor: Appearance.colors.colSecondary
                trackColor: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                handleColor: Appearance.colors.colSecondary
                value: root.player?.volume ?? 1.0
                onMoved: {
                    if (root.player) root.player.volume = value;
                }
            }
        }
    }
}
