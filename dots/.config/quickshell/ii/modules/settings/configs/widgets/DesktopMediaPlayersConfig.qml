import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.media
import qs.modules.settings.configs.widgets

/*
 * One page for the Poster and Cover (1x2), Deck (2x1) and Halo (1x1) media
 * widgets. The hero is the four real widgets, live (`isPreview`), laid out as the grid
 * cells they take on the desktop; the options follow in plain sections.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var posterOptions: root.widgets.media_poster
    readonly property var deckOptions: root.widgets.media_deck
    readonly property var haloOptions: root.widgets.media_halo
    readonly property var coverOptions: root.widgets.media_cover

    function placementNote(widgetId) {
        const count = Config.countWidgetInstances(widgetId);
        if (count === 0)
            return Translation.tr("Not on the desktop. Add it from Desktop Widgets; these options apply once it is there.");
        return count === 1 ? Translation.tr("On the desktop.") : Translation.tr("On the desktop %1 times.").arg(count);
    }

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Media Players Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Live preview: the widgets as grid cells (1x2 | 1x2 | 2x1 over 1x1 + status) ──
    Rectangle {
        id: stage
        Layout.fillWidth: true
        implicitHeight: Math.round(stage.boardHeight * stage.boardScale) + stage.padding * 2
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        readonly property real padding: 20
        readonly property real cell: 240
        readonly property real cellGap: 12
        readonly property real boardWidth: stage.cell * 4 + stage.cellGap * 3
        readonly property real boardHeight: stage.cell * 2 + stage.cellGap
        readonly property real boardScale: Math.min(1, Math.max(0.1, (stage.width - stage.padding * 2) / stage.boardWidth))

        Item {
            id: board
            anchors.centerIn: parent
            width: stage.boardWidth
            height: stage.boardHeight
            scale: stage.boardScale

            Item {
                id: posterSlot
                x: 0
                y: 0
                width: stage.cell
                height: stage.boardHeight

                PosterMediaWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: posterSlot.height / Math.max(1, implicitHeight)
                }
            }

            Item {
                id: coverSlot
                x: stage.cell + stage.cellGap
                y: 0
                width: stage.cell
                height: stage.boardHeight

                CoverMediaWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: coverSlot.height / Math.max(1, implicitHeight)
                }
            }

            Item {
                id: deckSlot
                x: (stage.cell + stage.cellGap) * 2
                y: 0
                width: stage.cell * 2 + stage.cellGap
                height: stage.cell

                DeckMediaWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: deckSlot.width / Math.max(1, implicitWidth)
                }
            }

            Item {
                id: haloSlot
                x: deckSlot.x
                y: stage.cell + stage.cellGap
                width: stage.cell
                height: stage.cell

                HaloMediaWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: haloSlot.width / Math.max(1, implicitWidth)
                }
            }

            // What the three are showing right now
            Rectangle {
                x: haloSlot.x + stage.cell + stage.cellGap
                y: haloSlot.y
                width: stage.cell
                height: stage.cell
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 4

                    MaterialShapeWrappedMaterialSymbol {
                        shape: MprisController.isPlaying ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                        text: MprisController.isPlaying ? "graphic_eq" : "music_off"
                        iconSize: 26
                        padding: 14
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Media Players")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const player = MprisController.activePlayer;
                            if (!player)
                                return Translation.tr("Nothing playing. The previews follow your active player.");
                            const name = player.identity || Translation.tr("Player");
                            return MprisController.isPlaying ? Translation.tr("%1 · Playing").arg(name) : Translation.tr("%1 · Paused").arg(name);
                        }
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Poster ──
    ContentSection {
        title: Translation.tr("Poster Media (1x2)")
        icon: "queue_music"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("media_poster")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.posterOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.posterOptions.widgetSize = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Album colors")
                    checked: root.posterOptions.dynamicAlbumColors ?? false
                    onCheckedChanged: root.posterOptions.dynamicAlbumColors = checked
                    StyledToolTip {
                        text: Translation.tr("Take the card's colors from the cover instead of the widget color scheme.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "format_color_text"
                    text: Translation.tr("Accent title")
                    checked: root.posterOptions.accentTitle ?? true
                    onCheckedChanged: root.posterOptions.accentTitle = checked
                    StyledToolTip {
                        text: Translation.tr("Set the track title in the accent color, like a poster headline.")
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "text_fields"
                text: Translation.tr("Play label")
                checked: root.posterOptions.showPlayLabel ?? true
                onCheckedChanged: root.posterOptions.showPlayLabel = checked
                StyledToolTip {
                    text: Translation.tr("Write \"PLAY\" or \"PAUSE\" next to the icon on the big button.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Cover shape")
            }

            ConfigSelectionArray {
                currentValue: root.posterOptions.artShape ?? "Puffy"
                onSelected: value => root.posterOptions.artShape = value
                options: ["Puffy", "Cookie9Sided", "Cookie12Sided", "Clover8Leaf", "Flower", "SoftBurst", "Sunny", "Bun", "Ghostish", "Circle", "Square"].map(shapeName => ({
                    "displayName": "",
                    "shape": shapeName,
                    "value": shapeName
                }))
            }
        }
    }

    // ── Cover ──
    ContentSection {
        title: Translation.tr("Cover Media (1x2)")
        icon: "photo_album"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("media_cover")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.coverOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.coverOptions.widgetSize = value
            }

            ConfigSlider {
                buttonIcon: "blur_on"
                text: Translation.tr("Control band blur")
                value: root.coverOptions.blurStrength ?? 70
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: root.coverOptions.blurStrength = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Album colors")
                    checked: root.coverOptions.dynamicAlbumColors ?? false
                    onCheckedChanged: root.coverOptions.dynamicAlbumColors = checked
                    StyledToolTip {
                        text: Translation.tr("Take the card's colors from the cover instead of the widget color scheme.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "person"
                    text: Translation.tr("Artist chip")
                    checked: root.coverOptions.artistChip ?? true
                    onCheckedChanged: root.coverOptions.artistChip = checked
                    StyledToolTip {
                        text: Translation.tr("Set the artist on a filled chip under the title instead of plain text.")
                    }
                }
            }
        }
    }

    // ── Deck ──
    ContentSection {
        title: Translation.tr("Deck Media (2x1)")
        icon: "album"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("media_deck")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.deckOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.deckOptions.widgetSize = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Album colors")
                    checked: root.deckOptions.dynamicAlbumColors ?? false
                    onCheckedChanged: root.deckOptions.dynamicAlbumColors = checked
                    StyledToolTip {
                        text: Translation.tr("Take the card's colors from the cover instead of the widget color scheme.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "label"
                    text: Translation.tr("Player tag")
                    checked: root.deckOptions.showPlayerChip ?? true
                    onCheckedChanged: root.deckOptions.showPlayerChip = checked
                    StyledToolTip {
                        text: Translation.tr("Name the app that is playing on a tag over the cover.")
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Times")
                checked: root.deckOptions.showTimes ?? true
                onCheckedChanged: root.deckOptions.showTimes = checked
                StyledToolTip {
                    text: Translation.tr("Show the elapsed time and the track length at the ends of the seek line.")
                }
            }
        }
    }

    // ── Halo ──
    ContentSection {
        title: Translation.tr("Halo Media (1x1)")
        icon: "motion_photos_on"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("media_halo")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.haloOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.haloOptions.widgetSize = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Album colors")
                    checked: root.haloOptions.dynamicAlbumColors ?? false
                    onCheckedChanged: root.haloOptions.dynamicAlbumColors = checked
                    StyledToolTip {
                        text: Translation.tr("Take the card's colors from the cover instead of the widget color scheme.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "interests"
                    text: Translation.tr("Morph cover")
                    checked: root.haloOptions.morphArt ?? true
                    onCheckedChanged: root.haloOptions.morphArt = checked
                    StyledToolTip {
                        text: Translation.tr("Cut the cover as a scalloped cookie while music plays and as a circle while paused.")
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "waves"
                text: Translation.tr("Wavy ring")
                checked: root.haloOptions.wavyRing ?? true
                onCheckedChanged: root.haloOptions.wavyRing = checked
                StyledToolTip {
                    text: Translation.tr("Draw the progress ring as a wave while music plays.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
