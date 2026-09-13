pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

// Secondary actions for the Immersive frontend, in a frosted sheet that drops
// from the toolbar: source, lyrics, library and display.
//
// The sheet is opaque glass over the blurred artwork, in the Immersive's fixed
// light-on-dark palette. Themed layer colours are translucent when shell
// transparency is on, which let the lyrics show through, and themed controls
// were dark-on-dark here.
Item {
    id: root
    required property var context
    property bool open: false
    property Item backdrop: null
    property color foreground: ColorUtils.getContrastingTextColor(Appearance.m3colors.m3scrim)
    property color tint: Appearance.colors.colPrimary
    property real sheetTopMargin: 0
    property real sheetRightMargin: 0
    property string lyricsStatus: ""
    signal dismissed

    readonly property color subtleForeground: ColorUtils.applyAlpha(foreground, 0.62)
    readonly property color sheetColor: ColorUtils.applyAlpha(ColorUtils.mix(Appearance.m3colors.m3scrim, tint, 0.82), 0.72)
    readonly property real smallButton: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin

    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: root.open ? Appearance.animation.elementMoveEnter.duration
                                : Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel
                                          : Appearance.animationCurves.emphasizedAccel
        }
    }
    visible: progress > 0.001

    onOpenChanged: if (open)
                       forceActiveFocus()
    Keys.onEscapePressed: event => {
        event.accepted = true;
        root.dismissed();
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.dismissed()
    }

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Appearance.sizes.elevationMargin
        color: root.subtleForeground
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.variableAxes: ({
                "wght": 620,
                "wdth": 112,
                "ROND": 100
            })
    }

    component SheetAction: RippleButton {
        id: action
        property string symbol
        property string label
        property bool selected: false
        implicitHeight: root.smallButton
        implicitWidth: actionContent.implicitWidth + Appearance.sizes.elevationMargin * 3
        buttonRadius: Appearance.rounding.full
        colBackground: selected ? root.foreground : ColorUtils.applyAlpha(root.foreground, 0.1)
        colBackgroundHover: selected ? root.foreground : ColorUtils.applyAlpha(root.foreground, 0.16)
        colBackgroundActive: ColorUtils.applyAlpha(root.foreground, 0.24)
        colRipple: ColorUtils.applyAlpha(selected ? root.tint : root.foreground, 0.2)
        RowLayout {
            id: actionContent
            readonly property color contentColor: action.selected ? ColorUtils.getContrastingTextColor(root.foreground)
                                                                  : root.foreground
            anchors.centerIn: parent
            spacing: Appearance.sizes.elevationMargin / 2
            MaterialSymbol {
                visible: action.symbol.length > 0
                text: action.symbol
                iconSize: Appearance.font.pixelSize.large
                color: actionContent.contentColor
                fill: 1
            }
            StyledText {
                text: action.label
                color: actionContent.contentColor
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: sheet.width - Appearance.sizes.elevationMargin * 10
            }
        }
    }

    component SwitchRow: RowLayout {
        id: switchRow
        property string symbol
        property string label
        property bool checked
        signal toggled(bool checked)
        Layout.fillWidth: true
        spacing: Appearance.sizes.elevationMargin
        MaterialSymbol {
            text: switchRow.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: root.foreground
            fill: 1
        }
        StyledText {
            Layout.fillWidth: true
            text: switchRow.label
            color: root.foreground
            elide: Text.ElideRight
        }
        StyledSwitch {
            checked: switchRow.checked
            activeColor: root.foreground
            inactiveColor: ColorUtils.applyAlpha(root.foreground, 0.2)
            activeThumbColor: ColorUtils.getContrastingTextColor(root.foreground)
            inactiveThumbColor: ColorUtils.applyAlpha(root.foreground, 0.62)
            // Clicking flips `checked` and would drop the binding; restore it so the
            // switch keeps following the config it represents.
            onClicked: {
                const value = checked;
                checked = Qt.binding(() => switchRow.checked);
                switchRow.toggled(value);
            }
        }
    }

    Item {
        id: sheet
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.sheetTopMargin
        anchors.rightMargin: root.sheetRightMargin
        width: Math.min(420, root.width - root.sheetRightMargin * 2)
        height: Math.min(content.implicitHeight + Appearance.sizes.elevationMargin * 4, root.height
                         - root.sheetTopMargin - root.sheetRightMargin)
        opacity: root.progress
        transform: Translate {
            y: (1 - root.progress) * -Appearance.sizes.elevationMargin * 2
        }

        MouseArea {
            anchors.fill: parent
        }

        MediaModeImmersiveGlass {
            anchors.fill: parent
            backdrop: root.backdrop
            backdropOffset: Qt.point(sheet.x, sheet.y)
            radius: Appearance.rounding.verylarge
            color: root.sheetColor
            blurRadius: 30
        }

        StyledFlickable {
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin * 2
            contentHeight: content.implicitHeight
            clip: true
            ColumnLayout {
                id: content
                width: parent.width
                spacing: Appearance.sizes.elevationMargin

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Player options")
                        color: root.foreground
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.variableAxes: ({
                                "wght": 720,
                                "wdth": 120,
                                "ROND": 100
                            })
                    }
                    MediaModeImmersiveButton {
                        symbol: "close"
                        quiet: true
                        implicitWidth: root.smallButton
                        foreground: root.foreground
                        tooltip: Translation.tr("Close")
                        onClicked: root.dismissed()
                    }
                }

                SectionLabel {
                    visible: root.context.showPlayerSwitcher
                    text: Translation.tr("Source")
                }
                Flow {
                    Layout.fillWidth: true
                    visible: root.context.showPlayerSwitcher
                    spacing: Appearance.sizes.elevationMargin / 2
                    Repeater {
                        model: MprisController.applicationPlayers
                        delegate: SheetAction {
                            required property var modelData
                            symbol: "music_note"
                            label: modelData.identity || modelData.desktopEntry || Translation.tr("Player")
                            selected: root.context.applicationsSource && root.context.player === modelData
                            onClicked: {
                                if (root.context.localSource && LocalMediaService.player?.isPlaying)
                                    LocalMediaService.pause();
                                LocalMediaService.releaseMprisControl();
                                MprisController.selectMediaModeApplicationPlayer(modelData);
                                root.dismissed();
                            }
                        }
                    }
                    SheetAction {
                        symbol: "library_music"
                        label: Translation.tr("Local music")
                        selected: root.context.localSource
                        onClicked: {
                            if (root.context.applicationsSource && root.context.player?.isPlaying)
                                root.context.player.pause();
                            MprisController.setMediaModeSource("local");
                            LocalMediaService.claimMprisControl();
                            root.dismissed();
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.context.showLyricsPanel
                    SectionLabel {
                        text: Translation.tr("Lyrics")
                    }
                    StyledText {
                        Layout.topMargin: Appearance.sizes.elevationMargin
                        text: root.lyricsStatus
                        color: root.subtleForeground
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.context.showLyricsPanel
                    spacing: Appearance.sizes.elevationMargin / 2
                    MediaModeLyricsProviderRow {
                        buttonSize: root.smallButton
                        accentColor: root.foreground
                        activeFillOpacity: 1
                        activeIconColor: ColorUtils.getContrastingTextColor(root.foreground)
                        surfaceColor: ColorUtils.applyAlpha(root.foreground, 0.1)
                        surfaceHoverColor: ColorUtils.applyAlpha(root.foreground, 0.16)
                        surfaceActiveColor: ColorUtils.applyAlpha(root.foreground, 0.24)
                        onSurfaceColor: root.foreground
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    MediaModeImmersiveButton {
                        symbol: "text_decrease"
                        implicitWidth: root.smallButton
                        symbolSize: Appearance.font.pixelSize.normal
                        foreground: root.foreground
                        tooltip: Translation.tr("Decrease Lyrics Size")
                        onClicked: root.context.lyricsScaleMultiplier = Math.max(0.7,
                                                                                 root.context.lyricsScaleMultiplier
                                                                                 - 0.15)
                    }
                    MediaModeImmersiveButton {
                        symbol: "text_increase"
                        implicitWidth: root.smallButton
                        symbolSize: Appearance.font.pixelSize.normal
                        foreground: root.foreground
                        tooltip: Translation.tr("Increase Lyrics Size")
                        onClicked: root.context.lyricsScaleMultiplier = Math.min(1.8,
                                                                                 root.context.lyricsScaleMultiplier
                                                                                 + 0.15)
                    }
                    MediaModeImmersiveButton {
                        symbol: "refresh"
                        implicitWidth: root.smallButton
                        symbolSize: Appearance.font.pixelSize.normal
                        foreground: root.foreground
                        tooltip: Translation.tr("Reload Lyrics")
                        onClicked: LyricsService.initiliazeLyrics()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.context.showLyricsPanel
                    spacing: Appearance.sizes.elevationMargin / 2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Lyrics offset") + " · " + (
                                  Config.options.background.mediaMode.lyricsOffsetMs ?? 0) + " ms"
                        color: root.foreground
                    }
                    MediaModeImmersiveButton {
                        symbol: "remove"
                        implicitWidth: root.smallButton
                        symbolSize: Appearance.font.pixelSize.normal
                        foreground: root.foreground
                        tooltip: Translation.tr("Nudge Lyrics -250ms (Earlier)")
                        onClicked: Config.options.background.mediaMode.lyricsOffsetMs -= 250
                    }
                    MediaModeImmersiveButton {
                        symbol: "add"
                        implicitWidth: root.smallButton
                        symbolSize: Appearance.font.pixelSize.normal
                        foreground: root.foreground
                        tooltip: Translation.tr("Nudge Lyrics +250ms (Later)")
                        onClicked: Config.options.background.mediaMode.lyricsOffsetMs += 250
                    }
                }

                SectionLabel {
                    text: Translation.tr("Library")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin / 2
                    SheetAction {
                        symbol: "audio_file"
                        label: Translation.tr("Files")
                        onClicked: {
                            root.dismissed();
                            root.context.openFileBrowser(true);
                        }
                    }
                    SheetAction {
                        symbol: "folder_open"
                        label: Translation.tr("Folder")
                        onClicked: {
                            root.dismissed();
                            root.context.openFileBrowser(false);
                        }
                    }
                    SheetAction {
                        visible: LocalMediaService.importActive
                        symbol: "cancel"
                        label: Translation.tr("Cancel import")
                        onClicked: LocalMediaService.cancelImport()
                    }
                    SheetAction {
                        visible: root.context.localSource
                        symbol: "power_settings_new"
                        label: Translation.tr("Stop local music service")
                        onClicked: {
                            LocalMediaService.terminateService();
                            root.context.closeRequested(!Config.options.background.mediaMode.togglePerMonitor);
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: LocalMediaService.importActive
                    text: LocalMediaService.importStatus
                    wrapMode: Text.Wrap
                    color: root.subtleForeground
                }

                SectionLabel {
                    text: Translation.tr("Display")
                }
                SwitchRow {
                    symbol: "palette"
                    label: Translation.tr("Match shell colors to album art")
                    checked: Config.options.background.mediaMode.changeShellColor
                    onToggled: checked => {
                        Config.options.background.mediaMode.changeShellColor = checked;
                        if (checked) {
                            LyricsService.changeShellColor(root.context.albumArtExtractedColor, true);
                        } else if (LyricsService.shellColorChanged) {
                            // BackgroundRoot only restores the wallpaper palette once Media
                            // Mode closes; turning the option off should undo it right away.
                            LyricsService.shellColorChanged = false;
                            LyricsService.lastAppliedShellColor = "";
                            if (Config.options.appearance.palette.type.startsWith("scheme"))
                                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color",
                                                         "clear", "--mode", Appearance.m3colors.darkmode ? "dark" :
                                                                                                           "light"]);
                        }
                    }
                }
                SwitchRow {
                    visible: root.context.applicationsSource
                    symbol: "music_video"
                    label: Translation.tr("Music video background")
                    checked: Config.options.background.mediaMode.musicVideo.enable
                    onToggled: checked => {
                        Config.options.background.mediaMode.musicVideo.enable = checked;
                        if (checked)
                            MusicVideoService.tryPlayCurrent();
                        else
                            MusicVideoService.stopVideo();
                    }
                }
                SheetAction {
                    symbol: "refresh"
                    label: Translation.tr("Reload artwork")
                    onClicked: root.context.refreshArtwork()
                }
            }
        }
    }
}
