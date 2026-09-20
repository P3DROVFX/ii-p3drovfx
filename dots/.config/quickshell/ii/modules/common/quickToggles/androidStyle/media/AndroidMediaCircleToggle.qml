pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Media circle widget quick toggle.
 * Adapted from the desktop background's MediaWidget.
 *
 * Freeform adaptive: centered circular shape scaled smoothly to the tile's shortest dimension.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        var player = MprisController.activePlayer;
        if (player && player.trackTitle) {
            var artist = player.trackArtist ? player.trackArtist : Translation.tr("Unknown Artist");
            return player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Player");
    }

    readonly property bool useAlbumColors: Config.options.background.widgets.media.useAlbumColors ?? true
    readonly property bool useDynamicColors: root.useAlbumColors && root.currentPlayer != null
    readonly property bool showPreviousToggle: root.circleSize >= 120
    readonly property var playerList: MprisController.players
    property MprisPlayer currentPlayer: MprisController.activePlayer

    property string artUrl: MprisController.artUrl
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: (artUrl && artUrl !== "") ? Qt.md5(artUrl) : ""
    property string artFilePath: artFileName !== "" ? `${artDownloadLocation}/${artFileName}` : ""

    readonly property real circleSize: Math.max(40, Math.min(root.surface.width, root.surface.height) - 12)
    readonly property real controlsSize: Math.max(22, Math.min(48, Math.round(root.circleSize * 0.24)))
    readonly property real buttonIconSize: Math.max(12, Math.min(26, Math.round(root.controlsSize * 0.58)))

    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }
    property var dynamicColors: ({
        colPrimary: root.useDynamicColors ? blendedColors.colPrimary : Appearance.colors.colPrimary,
        colPrimaryBackground: root.useDynamicColors ? blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer,
        colPrimaryBackgroundHover: root.useDynamicColors ? blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover,
        colPrimaryRipple: root.useDynamicColors ? blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive,
        colSecondary: root.useDynamicColors ? blendedColors.colSecondary : Appearance.colors.colSecondary,
        colSecondaryBackground: root.useDynamicColors ? blendedColors.colSecondaryContainer : Appearance.colors.colSecondaryContainer,
        colSecondaryBackgroundHover: root.useDynamicColors ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover,
        colSecondaryRipple: root.useDynamicColors ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive,
        colTertiary: root.useDynamicColors ? blendedColors.colTertiary : Appearance.colors.colTertiary,
        colTertiaryBackground: root.useDynamicColors ? blendedColors.colTertiaryContainer : Appearance.colors.colTertiaryContainer,
        colTertiaryBackgroundHover: root.useDynamicColors ? blendedColors.colTertiaryContainerHover : Appearance.colors.colTertiaryContainerHover,
        colTertiaryRipple: root.useDynamicColors ? blendedColors.colTertiaryContainerActive : Appearance.colors.colTertiaryContainerActive
    })

    readonly property string backgroundShape: {
        const raw = Config.options.background.widgets.media.backgroundShape ?? "Circle";
        const legacy = { "circle": "Circle", "square": "Square", "cookie": "Cookie9Sided" };
        return legacy[raw] ?? raw;
    }

    property bool downloaded: false
    property string displayedArtFilePath: {
        if (!root.artUrl || root.artUrl === "") return "";
        if (root.artUrl.startsWith("file://")) return root.artUrl;
        if (root.artUrl.startsWith("/")) return "file://" + root.artUrl;
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    property list<real> visualizerPoints: Config.options.background.widgets.media.visualizer.enable ? CavaService.visualizerPoints : []

    onArtFilePathChanged: updateArt()

    function nextPlayer() {
        if (!root.playerList || root.playerList.length === 0) return;
        root.currentPlayer = root.playerList[(root.playerList.indexOf(root.currentPlayer) + 1) % root.playerList.length];
    }

    function updateArt() {
        if (!root.artUrl || root.artUrl === "") {
            root.downloaded = false;
            return;
        }
        if (root.artUrl.startsWith("file://") || root.artUrl.startsWith("/")) {
            root.downloaded = true;
            return;
        }
        coverArtDownloader.targetFile = root.artUrl;
        coverArtDownloader.artFilePath = root.artFilePath;
        coverArtDownloader.artTempPath = root.artFilePath + ".tmp";
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = exitCode === 0;
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    Item {
        id: centerCircleContainer
        anchors.centerIn: parent
        width: root.circleSize
        height: root.circleSize

        // Empty state when no player is active
        FadeLoader {
            z: 2
            anchors.centerIn: parent
            shown: root.currentPlayer == null
            sourceComponent: MaterialShapeWrappedMaterialSymbol {
                fill: 1
                padding: Math.max(8, root.circleSize * 0.1)
                text: root.currentPlayer == null ? "music_off" : (!root.downloaded ? "hourglass_bottom" : "")
                anchors.centerIn: parent
                iconSize: Math.max(16, root.circleSize * 0.35)
                shape: MaterialShape.Shape.Cookie12Sided
                color: root.blendedColors.colOnSecondaryContainer
                colSymbol: Appearance.colors.colPrimaryContainer
            }
        }

        // Art background shape
        MaterialShape {
            id: artBackground
            anchors.fill: parent
            color: WidgetColorScheme.tintBackground(Appearance.colors.colPrimaryContainer)
            shapeString: root.backgroundShape

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: artBackground.width
                    shapeString: root.backgroundShape
                    height: artBackground.height
                }
            }

            StyledImage {
                id: mediaArt
                property int size: parent.height
                anchors.fill: parent

                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true

                width: size
                height: size
                sourceSize.width: size
                sourceSize.height: size
            }

            FadeLoader {
                shown: Config.options.background.widgets.media.tintArtCover ?? true
                anchors.fill: mediaArt
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false
                        anchors.fill: parent
                        source: mediaArt
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.9)
                    }
                }
            }

            RadialWaveVisualizer {
                id: visualizer
                z: 1
                anchors.fill: parent
                points: root.visualizerPoints
                live: root.currentPlayer?.isPlaying ?? false
                color: root.dynamicColors.colSecondaryBackground
                waveOpacity: Config.options.background.widgets.media.visualizer.opacity ?? 0.8
                waveBlur: Config.options.background.widgets.media.visualizer.blur ?? 12
                smoothing: Config.options.background.widgets.media.visualizer.smoothing ?? 2
            }
        }

        // Play/Pause button (bottom-left)
        FadeLoader {
            shown: root.currentPlayer != null && root.circleSize >= 60
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            sourceComponent: ControlButton {
                buttonRadius: root.currentPlayer?.isPlaying ? Appearance.rounding.small : root.controlsSize / 2
                colBackground: root.dynamicColors.colSecondaryBackground
                colBackgroundHover: root.dynamicColors.colSecondaryBackgroundHover
                colRipple: root.dynamicColors.colSecondaryRipple
                symbolText: root.currentPlayer?.isPlaying ? "pause" : "play_arrow"
                symbolColor: root.useAlbumColors ? root.blendedColors.colTertiary : Appearance.colors.colTertiary
                onClicked: {
                    if (root.currentPlayer)
                        root.currentPlayer.togglePlaying();
                }
            }
        }

        // Skip buttons (top-right)
        Loader {
            active: root.currentPlayer != null && root.circleSize >= 75
            anchors {
                top: parent.top
                right: parent.right
            }
            sourceComponent: Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                }
                implicitWidth: root.showPreviousToggle ? root.controlsSize * 2 : root.controlsSize
                implicitHeight: root.controlsSize
                z: 2
                radius: Appearance.rounding.full
                color: root.dynamicColors.colTertiaryBackground

                FadeLoader {
                    shown: root.showPreviousToggle
                    sourceComponent: ControlButton {
                        anchors.left: parent.left
                        colBackground: root.dynamicColors.colTertiaryBackground
                        colBackgroundHover: root.dynamicColors.colTertiaryBackgroundHover
                        colRipple: root.dynamicColors.colTertiaryRipple
                        symbolColor: root.dynamicColors.colSecondary
                        symbolText: "skip_previous"
                        onClicked: {
                            if (root.currentPlayer)
                                root.currentPlayer.previous();
                        }
                    }
                }

                ControlButton {
                    anchors.right: parent.right
                    colBackground: root.dynamicColors.colTertiaryBackground
                    colBackgroundHover: root.dynamicColors.colTertiaryBackgroundHover
                    colRipple: root.dynamicColors.colTertiaryRipple
                    symbolColor: root.dynamicColors.colSecondary
                    symbolText: "skip_next"
                    onClicked: {
                        if (root.currentPlayer)
                            root.currentPlayer.next();
                    }
                }
            }
        }

        // Player switch button (bottom-right)
        FadeLoader {
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            z: 3
            shown: (root.playerList?.length ?? 0) > 1 && root.circleSize >= 90
            sourceComponent: ControlButton {
                colBackground: root.dynamicColors.colPrimaryBackground
                colBackgroundHover: root.dynamicColors.colPrimaryBackgroundHover
                colRipple: root.dynamicColors.colPrimaryRipple
                symbolColor: root.dynamicColors.colSecondary
                symbolText: "360"
                onClicked: {
                    root.nextPlayer();
                }
            }
        }
    }

    component ControlButton: RippleButton {
        id: button
        property string symbolText: ""
        property color symbolColor: Appearance.colors.colOnSecondaryContainer

        z: 2
        implicitWidth: root.controlsSize
        implicitHeight: root.controlsSize
        buttonRadius: Appearance.rounding.full

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: root.buttonIconSize
            text: button.symbolText
            fill: 1
            color: button.symbolColor
        }
    }
}
