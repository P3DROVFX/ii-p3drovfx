import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    signal requestReset

    configEntryName: "media"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "media")

    property real lastStaticWidth: 240
    property real lastStaticHeight: 240

    implicitHeight: (typeof bgRoot !== 'undefined' && bgRoot.lockAnimationActive) ? lastStaticHeight : contentItem.implicitHeight
    implicitWidth: (typeof bgRoot !== 'undefined' && bgRoot.lockAnimationActive) ? lastStaticWidth : contentItem.implicitWidth

    onImplicitHeightChanged: {
        if (typeof bgRoot === 'undefined' || !bgRoot.lockAnimationActive) {
            lastStaticHeight = contentItem.implicitHeight;
        }
    }
    onImplicitWidthChanged: {
        if (typeof bgRoot === 'undefined' || !bgRoot.lockAnimationActive) {
            lastStaticWidth = contentItem.implicitWidth;
        }
    }

    readonly property bool useAlbumColors: Config.options.background.widgets.media.useAlbumColors
    readonly property bool useDynamicColors: root.useAlbumColors && root.currentPlayer != null
    readonly property bool showPreviousToggle: Config.options.background.widgets.media.showPreviousToggle
    readonly property bool hideAllButtons: Config.options.background.widgets.media.hideAllButtons
    readonly property bool showRestButtons: hideAllButtons ? hovering : true

    readonly property var playerList: MprisController.players

    // not using for now, but could be useful in the future
    property var filteredPlayerList: playerList.filter(player => player != null && player.trackAlbum != "")

    property MprisPlayer currentPlayer: MprisController.activePlayer
    property var artUrl: MprisController.artUrl
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`

    property real widgetSize: 240
    property real controlsSize: 55
    property real buttonIconSize: 30
    property bool showSwitchButton: false
    // MultiEffect cannot paint outside its own item when auto padding is
    // disabled, so reserve the falloff area explicitly. Tying it to the
    // widget size keeps the halo proportional if a layout changes the widget.
    readonly property real glowPadding: Math.max(Appearance.rounding.large, root.widgetSize * 0.16)
    readonly property real glowOpacity: Config.options.background.widgets.media.glow.enable
        ? Math.min(1, 0.035 * Config.options.background.widgets.media.glow.brightness) : 0

    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }
    property var dynamicColors: {
        return {
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
        };
    }

    // The config page writes canonical MaterialShape keys ("Circle",
    // "Cookie9Sided", ...). Older configs stored lowercase values
    // ("circle"/"square"/"cookie") that never matched MaterialShape's
    // shapeMap, so every option silently rendered as a Circle — normalize
    // them here instead of shipping a one-shot migration.
    readonly property string backgroundShape: {
        const raw = Config.options.background.widgets.media.backgroundShape ?? "Circle";
        const legacy = { "circle": "Circle", "square": "Square", "cookie": "Cookie9Sided" };
        return legacy[raw] ?? raw;
    }

    property bool downloaded: false
    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""

    property list<real> visualizerPoints: Config.options.background.widgets.media.visualizer.enable ? CavaService.visualizerPoints : []

    // 'Switch button' visiblity on hover
    property bool hovering: false
    hoverEnabled: true
    onEntered: {
        hovering = true;
    }
    onExited: {
        hovering = false;
    }

    allowMiddleClick: true
    onClicked: event => {
        if (event.button === Qt.MiddleButton) {
            root.requestReset();
        }
    }

    onArtFilePathChanged: updateArt()

    function nextPlayer() {
        root.currentPlayer = root.playerList[(root.playerList.indexOf(root.currentPlayer) + 1) % root.playerList.length];
    }

    function updateArt() {
        coverArtDownloader.targetFile = root.artUrl;
        coverArtDownloader.artFilePath = root.artFilePath;
        coverArtDownloader.artTempPath = root.artFilePath + ".tmp";
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true;
        }
    }



    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing
    }

    Item {
        id: contentItem

        implicitWidth: root.widgetSize
        implicitHeight: root.widgetSize

        // Render a blurred copy of the shape in a manually padded native
        // QtQuick.Effects layer. The previous Qt5Compat DropShadow consumed an
        // invisible source on this background window and could produce no
        // output; the explicit host also gives the falloff room to exist
        // outside the silhouette without a clipping wall.
        Item {
            id: artGlow
            anchors.fill: parent
            anchors.margins: -root.glowPadding
            visible: root.glowOpacity > 0.01
            opacity: root.glowOpacity

            MaterialShape {
                id: glowSourceShape
                anchors.fill: parent
                anchors.margins: root.glowPadding
                shapeString: root.backgroundShape
                color: root.artDominantColor
            }

            MultiEffect {
                anchors.fill: parent
                source: glowSourceShape
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: root.glowPadding
                blur: 1.0
            }

            Behavior on opacity {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
        }

        FadeLoader {
            id: loopButtonLoader
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            z: 3
            shown: root.hovering
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

        FadeLoader {
            z: 2
            anchors.centerIn: parent
            shown: root.currentPlayer == null
            sourceComponent: MaterialShapeWrappedMaterialSymbol {
                fill: 1
                padding: 20
                text: root.currentPlayer == null ? "music_off" : !root.downloaded ? "hourglass_bottom" : ""
                anchors.centerIn: parent
                iconSize: root.widgetSize / 4
                shape: MaterialShape.Shape.Cookie12Sided
                color: blendedColors.colOnSecondaryContainer
                colSymbol: Appearance.colors.colPrimaryContainer
            }
        }

        MaterialShape {
            id: shadowSourceShape
            anchors.fill: parent
            shapeString: root.backgroundShape
            visible: false
        }

        StyledDropShadow {
            id: mediaShadow
            target: shadowSourceShape
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        MaterialShape { // Art background
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

            StyledImage { // Art image
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
                shown: Config.options.background.widgets.media.tintArtCover
                anchors.fill: mediaArt
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
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
                waveOpacity: Config.options.background.widgets.media.visualizer.opacity
                waveBlur: Config.options.background.widgets.media.visualizer.blur
                smoothing: Config.options.background.widgets.media.visualizer.smoothing
            }
        }

        FadeLoader {
            shown: root.showRestButtons
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            sourceComponent: ControlButton {
                id: playButton
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                buttonRadius: root.currentPlayer?.isPlaying ? Appearance.rounding.normal : controlsSize / 2
                colBackground: root.dynamicColors.colSecondaryBackground
                colBackgroundHover: root.dynamicColors.colSecondaryBackgroundHover
                colRipple: root.dynamicColors.colSecondaryRipple
                symbolText: root.currentPlayer?.isPlaying ? "pause" : "play_arrow"
                symbolColor: useAlbumColors ? blendedColors.colTertiary : Appearance.colors.colTertiary
                onClicked: {
                    root.currentPlayer.togglePlaying();
                }
            }
        }

        Loader {
            active: root.showRestButtons
            anchors {
                top: parent.top
                right: parent.right
            }
            sourceComponent: Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                }
                implicitWidth: root.showPreviousToggle ? controlsSize * 2 : controlsSize
                implicitHeight: controlsSize
                z: 2
                radius: Appearance.rounding.full
                color: dynamicColors.colTertiaryBackground

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

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
                            currentPlayer.previous();
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
                        currentPlayer.next();
                    }
                }
            }
        }
    }

    component ControlButton: RippleButton {
        id: button
        property string symbolText
        property color symbolColor

        z: 2
        implicitWidth: controlsSize
        implicitHeight: implicitWidth
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
