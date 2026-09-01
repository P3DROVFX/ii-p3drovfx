import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

// What the lyrics column shows when there is no lyric to scroll.
//
// "instrumental" is an answer LRCLib actually gives, so it gets the visualizer
// rather than an apology. "notFound" is the only real failure, and it leads
// with the one action that can fix it permanently: pasting an .lrc that is then
// remembered for this track.
Item {
    id: root

    clip: true

    // "instrumental" | "notFound"
    property string mode: "notFound"
    property real largeFontSize: Appearance.font.pixelSize.hugeass * 1.5
    property color activeColor: Appearance.colors.colPrimary
    property color onAccentContainerColor: Appearance.colors.colOnPrimaryContainer
    property string artFilePath: ""
    property var player: null
    property list<var> visualizerPoints: []
    property bool playing: false
    property real edgeFadeFraction: 0.14

    readonly property bool instrumental: mode === "instrumental"
    readonly property string trackTitle: player?.trackTitle ?? ""
    readonly property string trackArtist: player?.trackArtist ?? ""
    readonly property bool hasCustomLyrics: CustomLyricsStore.has(trackTitle, trackArtist)

    property bool pasteExpanded: false

    component ActionButton: RippleButton {
        id: actionButton

        property string iconName: ""
        property string labelText: ""
        property bool emphasized: false

        implicitHeight: 38
        implicitWidth: actionRow.implicitWidth + 28
        buttonRadius: Appearance.rounding.full
        colBackground: emphasized
            ? ColorUtils.transparentize(root.activeColor, 0.25)
            : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.45)
        colBackgroundHover: emphasized
            ? ColorUtils.transparentize(root.activeColor, 0.12)
            : Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active

        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: 7

            MaterialSymbol {
                iconSize: 17
                color: actionButton.emphasized
                    ? root.activeColor : Appearance.colors.colOnLayer2
                text: actionButton.iconName
            }

            StyledText {
                text: actionButton.labelText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: actionButton.emphasized
                    ? root.activeColor : Appearance.colors.colOnLayer2
            }
        }
    }

    function lyricAxes(weight) {
        return {
            "wght": weight,
            "wdth": 100,
            "opsz": root.largeFontSize,
            "GRAD": 100,
            "ROND": Config.options.appearance.fonts.roundnessFull ? 100 : 0
        };
    }

    // Album art bloom, instrumental only. Scaled well past the viewport so only
    // the interior of the blur is ever visible — no edges to give away that it
    // is an image. The "nothing found" state stays bare so the actions that can
    // fix it are the only thing competing for attention.
    Item {
        id: bloom

        anchors.fill: parent
        visible: root.instrumental && root.artFilePath.length > 0
        opacity: 0.3
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bloom.width
                height: bloom.height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0 - root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Image {
            id: bloomSource

            anchors.centerIn: parent
            width: Math.max(bloom.width, bloom.height) * 1.6
            height: width
            source: root.artFilePath
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(360, 360)
            asynchronous: true
            visible: false
        }

        MultiEffect {
            anchors.fill: bloomSource
            source: bloomSource
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            saturation: 0.25
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(root.activeColor, 0.82)
        }
    }

    // Instrumental gets the real signal: this is Cava output, not an estimate.
    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.82
        height: width
        visible: root.instrumental

        RadialWaveVisualizer {
            anchors.fill: parent
            // Same reason: the canvas must not repaint behind another state.
            live: root.playing && root.visible
            color: root.activeColor
            points: root.visualizerPoints
        }
    }

    ColumnLayout {
        id: content

        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 620)
        spacing: 14

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: root.largeFontSize * 1.1
            fill: 1
            color: root.activeColor
            text: root.instrumental ? "graphic_eq" : "lyrics"
            opacity: 0.9
        }

        // Headline, in the same typography as the lyrics themselves.
        StyledText {
            Layout.fillWidth: true
            text: root.instrumental
                ? Translation.tr("Instrumental")
                : (root.trackTitle || Translation.tr("Unknown Title"))
            font.family: Appearance.font.family.main
            font.pixelSize: root.largeFontSize * 1.05
            font.variableAxes: root.lyricAxes(820)
            color: ColorUtils.mix(Appearance.colors.colOnLayer0, root.activeColor, 0.82)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: root.instrumental
                ? [root.trackTitle, root.trackArtist].filter(part => part.length > 0).join(" — ")
                : (root.trackArtist || Translation.tr("Unknown Artist"))
            font.family: Appearance.font.family.main
            font.pixelSize: root.largeFontSize * 0.46
            font.variableAxes: root.lyricAxes(520)
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.instrumental
            text: root.hasCustomLyrics
                ? Translation.tr("Your saved .lrc has no synced lines")
                : Translation.tr("No lyrics found for this track")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            opacity: 0.85
            horizontalAlignment: Text.AlignHCenter
        }

        // Which providers were asked, and what each one answered.
        Flow {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: !root.instrumental && !root.pasteExpanded
            spacing: 8

            Repeater {
                model: LyricsService.providerStates

                delegate: RippleButton {
                    id: providerChip

                    required property var modelData
                    readonly property bool disabled: !modelData.enabled

                    implicitWidth: chipRow.implicitWidth + 20
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.45)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    opacity: providerChip.disabled ? 0.45 : 1
                    enabled: !providerChip.disabled

                    onClicked: {
                        Config.options.lyricsService.lyricsProvider = providerChip.modelData.key;
                        LyricsService.retrySearch();
                    }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            iconSize: 14
                            color: Appearance.colors.colOnLayer2
                            text: providerChip.modelData.icon
                        }

                        StyledText {
                            text: providerChip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            iconSize: 14
                            text: {
                                if (providerChip.disabled)
                                    return "block";
                                if (providerChip.modelData.searching)
                                    return "progress_activity";
                                return providerChip.modelData.found ? "check_circle" : "close";
                            }
                            color: providerChip.modelData.found
                                ? root.activeColor : Appearance.colors.colSubtext
                        }
                    }

                    StyledToolTip {
                        text: {
                            if (providerChip.disabled)
                                return Translation.tr("Disabled in settings");
                            if (providerChip.modelData.searching)
                                return Translation.tr("Searching…");
                            return providerChip.modelData.found
                                ? Translation.tr("Returned lyrics - click to use this provider")
                                : Translation.tr("No result - click to retry with this provider");
                        }
                    }
                }
            }
        }

        Flow {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: !root.pasteExpanded
            spacing: 8

            ActionButton {
                iconName: "refresh"
                labelText: Translation.tr("Search again")
                onClicked: LyricsService.retrySearch()
            }

            ActionButton {
                iconName: "open_in_new"
                labelText: Translation.tr("Look up on Genius")
                onClicked: {
                    const query = [root.trackArtist, root.trackTitle]
                        .filter(part => part.length > 0).join(" ");
                    Qt.openUrlExternally(
                        `https://genius.com/search?q=${encodeURIComponent(query)}`);
                }
            }

            ActionButton {
                iconName: "content_paste"
                labelText: root.hasCustomLyrics
                    ? Translation.tr("Edit saved .lrc")
                    : Translation.tr("Paste .lrc")
                emphasized: true
                onClicked: {
                    lrcInput.text = CustomLyricsStore.get(root.trackTitle, root.trackArtist);
                    root.pasteExpanded = true;
                }
            }
        }

        // Paste panel. The only action here that permanently fixes a track.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.pasteExpanded
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                radius: Appearance.rounding.normal
                color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.35)

                Flickable {
                    id: lrcFlickable

                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    contentHeight: lrcInput.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    MaterialTextArea {
                        id: lrcInput

                        width: lrcFlickable.width
                        wrapMode: TextEdit.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        placeholderText: Translation.tr("[00:12.34] First line\n[00:16.02] Second line")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    readonly property int detectedLines: {
                        const matches = lrcInput.text.match(/\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]/g);
                        return matches ? matches.length : 0;
                    }

                    Layout.fillWidth: true
                    text: detectedLines > 0
                        ? Translation.tr("%1 synced lines detected").arg(detectedLines)
                        : Translation.tr("Paste LRC with [mm:ss.xx] timestamps")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: detectedLines > 0 ? root.activeColor : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                ActionButton {
                    iconName: "delete"
                    labelText: Translation.tr("Remove")
                    visible: root.hasCustomLyrics
                    onClicked: {
                        LyricsService.clearCustomLyrics();
                        lrcInput.text = "";
                        root.pasteExpanded = false;
                    }
                }

                ActionButton {
                    iconName: "close"
                    labelText: Translation.tr("Cancel")
                    onClicked: root.pasteExpanded = false
                }

                ActionButton {
                    iconName: "check"
                    labelText: Translation.tr("Save")
                    emphasized: true
                    onClicked: {
                        LyricsService.saveCustomLyrics(lrcInput.text);
                        root.pasteExpanded = false;
                    }
                }
            }
        }
    }
}
