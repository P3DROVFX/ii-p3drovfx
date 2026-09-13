import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common.models
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "compact_media"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"

    readonly property real contentScale: (Config.options.background.widgets.compact_media.widgetSize ?? 100) / 100.0
    implicitWidth: 492 * contentScale
    implicitHeight: 240 * contentScale

    // --- Mpris ---
    property MprisPlayer player: MprisController.activePlayer

    // ── Dynamic album colors pipeline ──
    readonly property bool useDynamicColors: (Config.options.background.widgets.compact_media.dynamicAlbumColors ?? false) && root.artSource !== ""
    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: artUrl.startsWith("file://")

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

    // --- Colors (WidgetColorScheme with dynamic album colors support) ---
    readonly property color colSectionOne: useDynamicColors ? blendedColors.colPrimaryContainer : WidgetColorScheme.cardBgColor
    readonly property color colSectionTwo: useDynamicColors ? blendedColors.colSecondaryContainer : WidgetColorScheme.innerShapeColor
    readonly property color colSectionThree: useDynamicColors ? blendedColors.colPrimary : WidgetColorScheme.accentColor
    readonly property color colTextOnOne: useDynamicColors ? blendedColors.colOnPrimaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colSubtextOnOne: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnPrimaryContainer, 0.6) : WidgetColorScheme.subtextColorOnBg
    readonly property color colIconOnTwo: useDynamicColors ? blendedColors.colOnSecondaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colIconOnThree: useDynamicColors ? blendedColors.colOnPrimary : WidgetColorScheme.onAccentColor

    // --- Layout proportions 6:4:2 (total 12) ---
    readonly property int gap: 6
    readonly property real totalGap: root.gap * 2
    readonly property real availableWidth: root.width - root.totalGap
    readonly property real sectionOneWidth: root.availableWidth * (6 / 12)
    readonly property real sectionTwoWidth: root.availableWidth * (4 / 12)
    readonly property real sectionThreeWidth: root.availableWidth * (2 / 12)

    readonly property int globalRadius: Appearance.rounding.large

    // --- Shadow ---
    StyledRectangularShadow {
        id: bgShadow
        target: mainContainer
        visible: Config.options.background.widgets.compact_media.enableShadows ?? true
    }

    Row {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 8
        spacing: root.gap

        // ─── SECTION 1: Title + Artist (6/12) ───
        Rectangle {
            id: sectionOne
            width: root.sectionOneWidth
            height: parent.height
            color: WidgetColorScheme.tintBackground(root.colSectionOne)
            radius: root.globalRadius

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 48
                anchors.bottomMargin: 12
                spacing: 4

                // Song title — variable axis font, heavy weight + wide, max 3 lines
                Text {
                    id: titleText
                    Layout.fillWidth: true
                    text: root.trackTitle
                    color: root.colTextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: 34
                    font.weight: Font.Black
                    font.variableAxes: ({ "wght": 900, "wdth": 145 })
                    elide: Text.ElideRight
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignTop
                    renderType: Text.QtRendering
                }

                // Artist name — thinner, smaller, right below title
                Text {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    color: root.colSubtextOnOne
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    font.weight: Font.Light
                    font.variableAxes: ({ "wght": 300 })
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignTop
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // ─── SECTION 2: Play/Pause (4/12) ───
        Rectangle {
            id: sectionTwo
            readonly property real pressExpansion: sectionTwoMouse.pressed ? 12 : 0
            width: root.sectionTwoWidth + pressExpansion
            height: parent.height
            radius: sectionTwoMouse.pressed ? Appearance.rounding.small : root.globalRadius
            color: {
                if (sectionTwoMouse.pressed) return WidgetColorScheme.tintBackground(Qt.darker(root.colSectionTwo, 1.2));
                if (sectionTwoMouse.containsMouse) return WidgetColorScheme.tintBackground(Qt.lighter(root.colSectionTwo, 1.1));
                return WidgetColorScheme.tintBackground(root.colSectionTwo);
            }

            Behavior on width {
                animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
            }

            Behavior on radius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Behavior on color {
                ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.player?.isPlaying ? "pause" : "play_arrow"
                iconSize: 32
                color: root.colIconOnTwo
                fill: 1
            }

            MouseArea {
                id: sectionTwoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.player?.togglePlaying()
            }
        }

        // ─── SECTION 3: Next (2/12) ───
        Rectangle {
            id: sectionThree
            readonly property real pressExpansion: sectionThreeMouse.pressed ? 12 : 0
            width: root.sectionThreeWidth + pressExpansion
            height: parent.height
            radius: sectionThreeMouse.pressed ? Appearance.rounding.small : root.globalRadius
            color: {
                if (sectionThreeMouse.pressed) return WidgetColorScheme.tintBackground(Qt.darker(root.colSectionThree, 1.2));
                if (sectionThreeMouse.containsMouse) return WidgetColorScheme.tintBackground(Qt.lighter(root.colSectionThree, 1.1));
                return WidgetColorScheme.tintBackground(root.colSectionThree);
            }

            Behavior on width {
                animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
            }

            Behavior on radius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Behavior on color {
                ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "skip_next"
                iconSize: 22
                color: root.colIconOnThree
                fill: 1
            }

            MouseArea {
                id: sectionThreeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.player?.next()
            }
        }
    }
}
