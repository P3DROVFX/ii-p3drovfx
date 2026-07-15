pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

Item {
    id: root

    // Visible only if there is at least one player
    implicitWidth: 304
    implicitHeight: 100
    readonly property var realPlayers: MprisController.players
    readonly property var players: filterDuplicatePlayers(realPlayers)

    Component.onCompleted: {
        console.log("[VolumeDialogMedia] Count: " + players.length);
        for (var i = 0; i < players.length; i++) {
            console.log("[VolumeDialogMedia] Player " + i + ": id=" + players[i].identity + " dbus=" + players[i].dbusName + " title=" + players[i].trackTitle + " art=" + players[i].trackArtUrl);
        }
    }

    function filterDuplicatePlayers(playersList) {
        if (!playersList) return [];
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < playersList.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = playersList[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (var j = i + 1; j < playersList.length; ++j) {
                let p2 = playersList[j];
                if ((p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle))) || (Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => playersList[idx].trackArtUrl && playersList[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(playersList[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Repeater {
            model: root.players

            delegate: Item {
                id: cardRoot
                required property MprisPlayer modelData
                readonly property MprisPlayer player: modelData

                readonly property bool isExpanded: {
                    if (!player || !MprisController.activePlayer) return false;
                    if (player.dbusName === MprisController.activePlayer.dbusName) return true;
                    // Fallback: expand first item if active player is not in the list
                    const activeInList = root.players.some(p => p.dbusName === MprisController.activePlayer.dbusName);
                    return !activeInList && (root.players[0] === player);
                }

                // Layout properties for carousel behavior
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.preferredWidth: isExpanded ? (root.width - (root.players.length - 1) * 36) : 28

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }

                readonly property string artUrl: player ? (player.trackArtUrl ?? "") : ""
                readonly property string trackTitle: player ? (StringUtils.cleanMusicTitle(player.trackTitle) || Translation.tr("No media")) : ""
                readonly property string trackArtist: player ? (player.trackArtist || Translation.tr("Unknown Artist")) : ""
                readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
                readonly property string identity: player ? (player.identity ?? "") : ""

                property bool isLocalArt: artUrl.startsWith("file://")
                property string artDownloadLocation: Directories.coverArt
                property string artFileName: Qt.md5(artUrl)
                property string artFilePath: `${artDownloadLocation}/${artFileName}`
                property bool artDownloaded: false

                readonly property string artSource: {
                    if (!artUrl) return "";
                    if (isLocalArt) return artUrl;
                    return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
                }

                onArtFilePathChanged: {
                    if (!artUrl || artUrl.length === 0) {
                        artDownloaded = false;
                        return;
                    }
                    if (isLocalArt) {
                        artDownloaded = true;
                        return;
                    }
                    artDownloader.targetFile = artUrl;
                    artDownloader.artFilePath = artFilePath;
                    artDownloader.artTempPath = artFilePath + ".tmp";
                    artDownloaded = false;
                    artDownloader.running = true;
                }

                Process {
                    id: artDownloader
                    property string targetFile: cardRoot.artUrl
                    property string artFilePath: cardRoot.artFilePath
                    property string artTempPath: cardRoot.artFilePath + ".tmp"
                    command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
                    onExited: {
                        artDownloaded = true;
                    }
                }

                property real artVignetteBlur: cardRoot.playing ? 50 : 90

                readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && cardRoot.artSource !== ""

                ColorQuantizer {
                    id: colorQuantizer
                    source: cardRoot.artSource
                    depth: 0
                    rescaleSize: 1
                }

                property color artDominantColor: ColorUtils.mix(
                    (colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary),
                    Appearance.colors.colPrimaryContainer, 0.8
                ) || Appearance.m3colors.m3secondaryContainer

                property QtObject blendedColors: AdaptedMaterialScheme {
                    color: cardRoot.artDominantColor
                }

                readonly property color artTextColor: Appearance.colors.colOnSurface
                readonly property color artSubtextColor: Appearance.colors.colOnSurfaceVariant

                Behavior on artVignetteBlur {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    id: mainBg
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    radius: Appearance.rounding.normal
                    clip: true

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: mainBg.width
                            height: mainBg.height
                            radius: mainBg.radius
                        }
                    }

                    // Album Art Blurred / Vignette Backgrounds
                    Item {
                        anchors.fill: parent

                        Image {
                            id: artBlurredUnderlay
                            anchors.fill: parent
                            source: cardRoot.artSource
                            fillMode: Image.PreserveAspectCrop
                            visible: cardRoot.artSource !== ""
                            layer.enabled: cardRoot.artVignetteBlur > 0
                            layer.effect: MultiEffect {
                                blurEnabled: cardRoot.artVignetteBlur > 0
                                blurMax: 128
                                blur: cardRoot.artVignetteBlur / 128
                            }
                        }

                        Item {
                            id: vignetteMask
                            anchors.fill: parent
                            visible: true

                            Rectangle {
                                id: hMask
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.08; color: "transparent" }
                                    GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.3) }
                                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                                    GradientStop { position: 0.45; color: "white" }
                                    GradientStop { position: 0.55; color: "white" }
                                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                                    GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.3) }
                                    GradientStop { position: 0.92; color: "transparent" }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.15; color: Qt.rgba(1, 1, 1, 0.3) }
                                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                                    GradientStop { position: 0.5; color: "white" }
                                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                                    GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.3) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: hMask
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: vignetteMask
                            }

                            Image {
                                id: artExpanded
                                anchors.fill: parent
                                source: cardRoot.artSource
                                fillMode: Image.PreserveAspectCrop
                                opacity: 0.85
                                visible: cardRoot.artSource !== ""
                            }
                        }
                    }

                    // Dimming overlays
                    Item {
                        anchors.fill: parent
                        opacity: cardRoot.playing ? 0.55 : 0.75

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                                GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.3)
                            opacity: cardRoot.playing ? 0.0 : 0.5

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    // Expanded Content (visible only when the player card has enough width)
                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 6
                        opacity: cardRoot.isExpanded ? 1.0 : 0.0
                        visible: cardRoot.isExpanded || opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Top Row: App Icon + Identity
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24

                            MaterialShape {
                                implicitWidth: 24
                                implicitHeight: 24
                                shapeString: "Cookie12Sided"
                                color: "transparent"
                                Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                                Loader {
                                    id: appIconLoader
                                    anchors.fill: parent
                                    active: cardRoot.player && cardRoot.player.desktopEntry !== ""
                                    sourceComponent: IconImage {
                                        implicitSize: Appearance.font.pixelSize.huge
                                        source: Quickshell.iconPath(cardRoot.player ? cardRoot.player.desktopEntry : "audio-x-generic", "audio-x-generic")
                                    }
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: !appIconLoader.active
                                    sourceComponent: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        iconSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                            }

                            StyledText {
                                text: cardRoot.identity !== "" ? cardRoot.identity : Translation.tr("Media")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.bold: true
                                color: cardRoot.artTextColor
                                Layout.leftMargin: 4
                                opacity: 0.8
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        // Middle Row: Title/Artist (left) + Play button (right)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.Black
                                    font.styleName: "Rounded"
                                    color: cardRoot.artTextColor
                                    text: cardRoot.trackTitle
                                    maximumLineCount: 1
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: cardRoot.artSubtextColor
                                    text: cardRoot.trackArtist
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }
                            }

                            RippleButton {
                                id: playBtn
                                implicitWidth: 40
                                implicitHeight: 40
                                buttonRadius: 14
                                colBackground: cardRoot.useDynamicColors ? cardRoot.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                                colBackgroundHover: cardRoot.useDynamicColors ? cardRoot.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                                colRipple: cardRoot.useDynamicColors ? cardRoot.blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                onClicked: {
                                    if (cardRoot.player) {
                                        if (cardRoot.playing)
                                            cardRoot.player.pause();
                                        else
                                            cardRoot.player.play();
                                    }
                                }

                                contentItem: Item {
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: cardRoot.playing ? "pause" : "play_arrow"
                                        iconSize: Appearance.font.pixelSize.huge
                                        color: cardRoot.useDynamicColors ? cardRoot.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                                        fill: 1
                                    }
                                }
                            }
                        }
                    }
                }

                // Interactive Mouse Area for contracted items
                MouseArea {
                    anchors.fill: parent
                    enabled: !cardRoot.isExpanded
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        MprisController.setActivePlayer(cardRoot.player);
                    }
                }
            }
        }
    }
}
