pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.quickToggles.androidStyle

/**
 * Compact Media quick toggle.
 * Adapted from the desktop background's CompactMediaWidget.
 *
 * Freeform adaptive: 3 distinct pill sections (Metadata, Play/Pause, Next)
 * with proportional sizing and smooth transition between horizontal and vertical layouts.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.player && root.player.trackTitle) {
            var artist = root.player.trackArtist ? root.player.trackArtist : Translation.tr("Unknown Artist");
            return root.player.trackTitle + " - " + artist;
        }
        return Translation.tr("Compact Media");
    }

    property MprisPlayer player: MprisController.activePlayer

    readonly property bool isVertical: root.effectiveSizeH > root.effectiveSizeW || (root.surface.height > root.surface.width * 1.05)
    readonly property bool isShort: root.surface.height < 90 || root.effectiveSizeH === 1

    readonly property bool useDynamicColors: (Config.options.background.widgets.compact_media.dynamicAlbumColors ?? true) && root.artSource !== ""
    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: artUrl.startsWith("file://")

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: (artUrl && artUrl.length > 0) ? Qt.md5(artUrl) : ""
    property string artFilePath: artFileName.length > 0 ? `${artDownloadLocation}/${artFileName}` : ""
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl || artUrl.length === 0) return "";
        if (isLocalArt) return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!artUrl || artUrl.length === 0) { artDownloaded = false; return; }
        if (isLocalArt) { artDownloaded = true; return; }
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.artTempPath = artFilePath + ".tmp";
        artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: { artDownloaded = true; }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
        depth: 0
        rescaleSize: 1
    }

    readonly property color artDominantColor: {
        if (!root.useDynamicColors) return Appearance.colors.colPrimary;
        let raw = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary;
        let mixed = ColorUtils.mix(raw, Appearance.colors.colPrimaryContainer, 0.8);
        return mixed || Appearance.m3colors.m3secondaryContainer;
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property string trackTitle: player?.trackTitle || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")

    readonly property color colSectionOne: useDynamicColors ? blendedColors.colPrimaryContainer : WidgetColorScheme.cardBgColor
    readonly property color colSectionTwo: useDynamicColors ? blendedColors.colSecondaryContainer : WidgetColorScheme.innerShapeColor
    readonly property color colSectionThree: useDynamicColors ? blendedColors.colPrimary : WidgetColorScheme.accentColor
    readonly property color colTextOnOne: useDynamicColors ? blendedColors.colOnPrimaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colSubtextOnOne: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnPrimaryContainer, 0.6) : WidgetColorScheme.subtextColorOnBg
    readonly property color colIconOnTwo: useDynamicColors ? blendedColors.colOnSecondaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colIconOnThree: useDynamicColors ? blendedColors.colOnPrimary : WidgetColorScheme.onAccentColor

    readonly property int gap: 4
    readonly property real totalGap: root.gap * 2
    readonly property real availableWidth: Math.max(0, root.surface.width - root.totalGap - 12)
    readonly property real availableHeight: Math.max(0, root.surface.height - root.totalGap - 12)

    readonly property real sectionOneWidth: root.availableWidth * (6 / 12)
    readonly property real sectionTwoWidth: root.availableWidth * (3.8 / 12)
    readonly property real sectionThreeWidth: root.availableWidth * (2.2 / 12)

    readonly property real sectionOneHeight: root.availableHeight * (6 / 12)
    readonly property real sectionTwoHeight: root.availableHeight * (3.8 / 12)
    readonly property real sectionThreeHeight: root.availableHeight * (2.2 / 12)

    // ══════════════════════════════════════════════════════════════════════════
    // HORIZONTAL (Row)
    // ══════════════════════════════════════════════════════════════════════════
    Row {
        anchors.fill: parent
        anchors.margins: 6
        spacing: root.gap
        visible: !root.isVertical

        // Section 1: Title + Artist (6/12)
        Rectangle {
            id: sectionOneHoriz
            width: root.sectionOneWidth
            height: parent.height
            color: WidgetColorScheme.tintBackground(root.colSectionOne)
            radius: Appearance.rounding.normal
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.max(6, Math.min(12, Math.round(root.surface.width * 0.03)))
                anchors.rightMargin: Math.max(6, Math.min(12, Math.round(root.surface.width * 0.03)))
                anchors.topMargin: Math.max(6, Math.min(14, Math.round(root.surface.height * 0.12)))
                anchors.bottomMargin: Math.max(6, Math.min(12, Math.round(root.surface.height * 0.10)))
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.trackTitle
                    color: root.colTextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(11, Math.min(22, Math.round(root.surface.height * 0.18)))
                    font.weight: Font.Black
                    elide: Text.ElideRight
                    maximumLineCount: root.isShort ? 1 : 2
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignTop
                }

                Text {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    color: root.colSubtextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(9, Math.min(12, Math.round(root.surface.height * 0.09)))
                    font.weight: Font.Light
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignTop
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Section 2: Play/Pause (4/12)
        RippleButton {
            id: sectionTwoHoriz
            width: root.sectionTwoWidth
            height: parent.height
            colBackground: root.colSectionTwo
            buttonRadius: Appearance.rounding.normal

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: root.player?.isPlaying ? "pause" : "play_arrow"
                iconSize: Math.max(16, Math.min(32, Math.round(root.surface.height * 0.28)))
                color: root.colIconOnTwo
                fill: 1
            }
            onClicked: root.player?.togglePlaying()
        }

        // Section 3: Next (2/12)
        RippleButton {
            id: sectionThreeHoriz
            width: root.sectionThreeWidth
            height: parent.height
            colBackground: root.colSectionThree
            buttonRadius: Appearance.rounding.normal

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "skip_next"
                iconSize: Math.max(14, Math.min(24, Math.round(root.surface.height * 0.22)))
                color: root.colIconOnThree
                fill: 1
            }
            onClicked: root.player?.next()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // VERTICAL (Column)
    // ══════════════════════════════════════════════════════════════════════════
    Column {
        anchors.fill: parent
        anchors.margins: 6
        spacing: root.gap
        visible: root.isVertical

        // Section 1: Title + Artist (Top)
        Rectangle {
            width: parent.width
            height: root.sectionOneHeight
            color: WidgetColorScheme.tintBackground(root.colSectionOne)
            radius: Appearance.rounding.normal
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Math.max(4, Math.min(8, Math.round(root.surface.width * 0.04)))
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.trackTitle
                    color: root.colTextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(11, Math.min(18, Math.round(root.surface.width * 0.12)))
                    font.weight: Font.Black
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    color: root.colSubtextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(9, Math.min(12, Math.round(root.surface.width * 0.08)))
                    font.weight: Font.Light
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Section 2: Play/Pause (Middle)
        RippleButton {
            width: parent.width
            height: root.sectionTwoHeight
            colBackground: root.colSectionTwo
            buttonRadius: Appearance.rounding.normal

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: root.player?.isPlaying ? "pause" : "play_arrow"
                iconSize: Math.max(16, Math.min(28, Math.round(root.surface.width * 0.18)))
                color: root.colIconOnTwo
                fill: 1
            }
            onClicked: root.player?.togglePlaying()
        }

        // Section 3: Next (Bottom)
        RippleButton {
            width: parent.width
            height: root.sectionThreeHeight
            colBackground: root.colSectionThree
            buttonRadius: Appearance.rounding.normal

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "skip_next"
                iconSize: Math.max(14, Math.min(22, Math.round(root.surface.width * 0.14)))
                color: root.colIconOnThree
                fill: 1
            }
            onClicked: root.player?.next()
        }
    }
}
