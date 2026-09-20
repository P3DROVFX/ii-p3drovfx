import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.media
import "QuickToggleResize.js" as Resize

// Playback, cover and metadata keep their identity from compact to expanded.
// The source image is loaded once by Qt, independently of the grid footprint.
// Three faces, chosen by span: the two-column vertical one (compact, square,
// then portrait with a progress ring from four rows), the cover-backed
// horizontal one (details, audio chip and transport on the edges, a seekbar at
// five columns, previous/next from four rows), and their morphs in between.
ClippingRectangle {
    id: root
    required property var tile
    // Hosts can pin this content to a specific player (the Phone tab pins the KDE
    // Connect phone player instead of following the desktop's active source).
    property var playerOverride: null
    readonly property var player: playerOverride ?? MprisController.activePlayer
    readonly property bool playing: root.player?.isPlaying ?? false
    readonly property real tall: Resize.progress(height, tile.baseCellHeight, tile.baseCellHeight * 2 + tile.cellSpacing)
    // Two columns are the vertical family; three and up are the cover-backed
    // horizontal face the 4x2 uses. The axis saturates at three columns because
    // that face is what a third column buys — measured against four, a 3-wide
    // tile sat half-way between the two designs, with the chip faded out and the
    // play control floating mid-slide.
    readonly property real wideFace: Resize.progress(width, tile.baseCellWidth * 2 + tile.cellSpacing,
        tile.baseCellWidth * 3 + tile.cellSpacing * 2)
    readonly property real pad: tile.scaled(12)
    readonly property real controlHeight: Resize.mix(tile.scaled(36), tile.scaled(44), tall)
    // The cover-backed face has the lateral room for a transport bar, so the play
    // control keeps its height there and takes exactly twice the width. The
    // vertical family keeps the round button: a doubled pill at 2x2 would leave
    // no room for the metadata column beside it.
    readonly property real controlWidth: Resize.mix(controlHeight, controlHeight * 2, wideFace)
    readonly property real compactPlayX: pad
    readonly property real squarePlayX: (width - controlWidth) / 2
    readonly property real largePlayX: width - pad - controlWidth - transportShift
    // Bottom-anchored from 2x2 on. At 4x2 the tile's top row is the audio device
    // chip's, and a vertically centered control sat right underneath it; the wide
    // layout used to pull the control back to the middle, closing that gap.
    readonly property real controlsY: Resize.mix((height - controlHeight) / 2, height - pad - controlHeight, tall)
    readonly property real metadataX: Resize.mix(pad + controlWidth + tile.scaled(10), pad, tall)
    readonly property real metadataY: Resize.mix((height - metadata.height) / 2, pad, tall)
    readonly property real skipGap: tile.scaled(8)
    /**
     * Row span as a progress: zero at three rows, one from four rows on.
     *
     * Rows spanned by a multi-row tile are never compacted (a slider row is
     * shorter than a cell), so the tile's own height is the uniform span and the
     * threshold is trustworthy. The vertical family spends the extra rows on the
     * portrait face; the cover-backed one grows its transport into
     * previous/play/next and shifts the play control in by one skip to leave the
     * right edge to `next`.
     */
    readonly property real fourRows: Resize.progress(height, tile.baseCellHeight * 3 + tile.cellSpacing * 2,
        tile.baseCellHeight * 4 + tile.cellSpacing * 3)
    /**
     * The portrait transport, for the two-column tiles four rows and taller.
     *
     * The `wideFace` guard hands the face over to the cover-backed one as soon as
     * a third column arrives — during the drag too, where the freeform preview
     * can be four rows tall and three wide.
     */
    readonly property real portrait: fourRows * (1 - wideFace)
    /**
     * The seekbar, for the cover-backed face at five columns and up.
     *
     * Row and column spans are the only reliable measure here: cell width and
     * height are not equal, so a tile's aspect says nothing about how many
     * columns it covers.
     */
    readonly property real seekReveal: wideFace
        * Resize.progress(width, tile.baseCellWidth * 4 + tile.cellSpacing * 3,
            tile.baseCellWidth * 5 + tile.cellSpacing * 4)
        // A stream has no duration to report; an empty track would read as a bug.
        * ((root.player?.length ?? 0) > 0 ? 1 : 0)
    readonly property real seekBarHeight: tile.scaled(16)
    // The seekbar shares the transport's row, centred on it, so both read as one
    // bottom line.
    readonly property real seekBarTop: controlsY + (controlHeight - seekBarHeight) / 2
    readonly property real transportShift: wideFace * fourRows * (controlHeight + skipGap)
    readonly property real portraitBaseGap: tile.scaled(10)
    readonly property real portraitMetaHeight: portraitMeta.height
    // Widest the cover may get, and the height it would take if nothing capped it.
    readonly property real portraitCoverMax: Math.max(0, width - pad * 2)
    readonly property real portraitNaturalCover: (height - pad * 2) - portraitMetaHeight - controlHeight - 2 * portraitBaseGap
    /**
     * Air the taller footprints share out.
     *
     * Past 2x4 the cover keeps growing until the tile's width caps it; whatever
     * height is left over cannot become cover, so it is split between the four
     * vertical slots — over the cover, under the cover, under the details and
     * under the transport. Without that the surplus collected in one hole under
     * the ring, and a 2x8 tile read as a card with a gap in the middle. At 2x4
     * the surplus is zero and every slot keeps its base value.
     */
    readonly property real portraitAir: Math.round(Math.max(0, portraitNaturalCover - portraitCoverMax) / 4)
    readonly property real portraitPad: pad + portraitAir
    readonly property real portraitGap: portraitBaseGap + portraitAir
    readonly property real portraitPlayY: height - portraitPad - controlHeight
    // The transport row's play control takes everything the next-track circle
    // and the gap leave, so the row is always filled edge to edge. The gap here
    // is the base one: the extra air belongs to the vertical slots, not to the
    // space between two buttons.
    readonly property real portraitPlayWidth: Math.max(0, width - pad * 2 - controlHeight - portraitBaseGap)
    // Most players publish `position` only when asked, so both faces that report it
    // — the portrait ring and the wide seekbar — need a ticking clock.
    readonly property real trackProgress: MprisController.trackProgressOf(root.player)
    // Lyrics belong to the active player; a pinned player (phone) shows none.
    readonly property bool hasLyrics: !root.playerOverride && LyricsService.hasSyncedLines && LyricsService.statusText !== ""
    // Read this player's metadata directly: the controller's artUrl fallback
    // can still belong to the previous track while the next cover is absent.
    readonly property string artSource: root.player?.trackArtUrl ?? ""
    readonly property bool remoteArt: artSource !== "" && !artSource.startsWith("file://")
    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && artSource !== ""
    readonly property color largeControlColor: useDynamicColors ? blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
    readonly property color largeControlText: useDynamicColors ? blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
    readonly property color titleColor: ColorUtils.mix(remoteArt ? "white" : Appearance.colors.colOnLayer0,
        Appearance.colors.colOnSurface, 1 - wideFace)
    readonly property color artistColor: ColorUtils.mix(remoteArt ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext,
        Appearance.colors.colOnSurfaceVariant, 1 - wideFace)
    ColorQuantizer {
        id: colorQuantizer
        source: root.useDynamicColors && root.wideFace > 0 ? root.artSource : ""
        depth: 0
        rescaleSize: 1
    }
    AdaptedMaterialScheme {
        id: blendedColors
        color: ColorUtils.mix(colorQuantizer.colors[0] ?? Appearance.colors.colPrimary,
            Appearance.colors.colPrimaryContainer, 0.8)
    }
    // Surface under the artwork: at full `wideFace` the mix lands on colLayer0 and
    // the vertical family keeps colLayer3 — either way it sits behind the cover
    // whenever the player publishes one, and shows for an art-less player.
    color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colLayer0, 1 - wideFace)
    radius: Config.options.appearance.sharpMode ? 0 : Math.min(width / 2, height / 2, Appearance.rounding.large)

    // One decoded surface sized to the tile: the cover is the tile's background,
    // so its source has to follow whatever footprint the user resized to, not the
    // 4x2 it was first drawn for.
    AndroidMediaArtwork {
        id: artwork
        anchors.fill: parent
        artSize: Qt.size(Math.ceil(root.width), Math.ceil(root.height))
        artSource: root.artSource
        trackKey: JSON.stringify([root.player?.uniqueId ?? "", root.player?.trackTitle ?? "",
            root.player?.trackArtist ?? "", root.player?.trackAlbum ?? ""])
        hasPlayer: !!root.player
        playing: root.player?.isPlaying ?? false
        wide: root.wideFace
    }
    Connections {
        target: root.player
        function onPostTrackChanged(): void {
            artwork.requestArt(true);
        }
    }

    Item {
        anchors.fill: parent
        visible: !!root.player

        // One live button, even when the wide layout moves it to the right.
        RippleButton {
            id: playButton
            objectName: "quickToggleSharedPlay"
            x: Resize.mix(Resize.mix(Resize.mix(root.compactPlayX, root.squarePlayX, root.tall),
                root.largePlayX, root.wideFace), root.pad, root.portrait)
            y: Resize.mix(root.controlsY, root.portraitPlayY, root.portrait)
            width: Resize.mix(root.controlWidth, root.portraitPlayWidth, root.portrait)
            height: root.controlHeight
            // Playing is the pill; paused pulls back to a rounded rectangle. The
            // press bypasses that Behavior so the tap lands as a step, not a slide.
            buttonRadius: root.playing ? Appearance.rounding.full : Appearance.rounding.small
            buttonRadiusPressed: Appearance.rounding.small
            radiusBehaviorEnabled: !playButton.down
            colBackground: ColorUtils.mix(Appearance.colors.colPrimary, root.largeControlColor, 1 - root.wideFace)
            colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer1Hover,
                root.useDynamicColors ? blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover, 1 - root.wideFace)
            colRipple: ColorUtils.mix(Appearance.colors.colPrimaryActive,
                root.useDynamicColors ? blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive, 1 - root.wideFace)
            contentItem: MaterialSymbol {
                text: root.playing ? "pause" : "play_arrow"
                color: ColorUtils.mix(Appearance.colors.colOnPrimary, root.largeControlText, 1 - root.wideFace)
                fill: 1
                iconSize: Resize.mix(root.tile.scaled(22), root.tile.scaled(28), root.tall)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: root.player?.togglePlaying()
        }

        QuickToggleMorphLayer {
            id: metadata
            objectName: "quickToggleSharedMediaLabels"
            x: root.metadataX
            y: Resize.mix(root.metadataY, root.pad + root.tile.scaled(28), root.wideFace)
            width: Math.max(0, Resize.mix(root.width - x - root.pad,
                playButton.x - x - root.pad, root.wideFace))
            height: title.implicitHeight + artist.implicitHeight
            reveal: (1 - root.portrait) * (1 - (root.hasLyrics ? Resize.progress(root.wideFace, 0, 0.5) : 0))
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(12)
            StyledText {
                id: title
                width: parent.width
                text: root.player?.trackTitle || Translation.tr("Untitled")
                color: root.titleColor
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.normal)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                id: artist
                y: title.height
                width: parent.width
                text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                color: root.artistColor
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.small)
                elide: Text.ElideRight
            }
        }

        QuickToggleMorphLayer {
            x: root.pad
            // Symmetric band so AlignVCenter lands on the tile's true middle.
            // The old `pad + 28` top reserved space for the metadata layer that is
            // hidden by this point (metadata reveal ends at wideFace 0.5), pushing
            // the line visibly below center.
            y: root.pad
            // Ends before the transport column and, when the wide face shows a
            // seekbar, above it: the two share the left column.
            width: Math.max(0, playButton.x - root.transportShift - x - root.pad)
            height: Math.max(0, Resize.mix(root.height - root.pad,
                root.seekBarTop - root.tile.scaled(8), root.seekReveal) - y)
            reveal: (1 - root.portrait) * (root.hasLyrics ? Resize.progress(root.wideFace, 0.45, 1) : 0)
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(12)
            StyledText {
                anchors.fill: parent
                text: LyricsService.statusText
                color: Appearance.colors.colOnSurface
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.large)
                font.weight: Font.DemiBold
                // Same per-line motion the bar lyrics use: outgoing line fades
                // and slides up, new line enters from below. Purely one-shot,
                // driven by the text-change Behavior itself — no timer here.
                animateChange: true
                animationDistanceY: root.tile.scaled(8)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        Repeater {
            model: 2
            QuickToggleMorphLayer {
                id: skip
                required property int index
                objectName: "quickToggleSharedSkip" + skip.index
                // Same object as the portrait face's next circle: the transport
                // is three filled circles/pill at every size that shows it, not
                // bare glyphs beside a filled control.
                width: root.controlHeight
                height: width
                x: playButton.x + (index === 0 ? -width - root.skipGap : playButton.width + root.skipGap)
                y: playButton.y + (playButton.height - height) / 2
                // The vertical family grows them beside the round play control
                // from two rows; the cover-backed one takes them from four rows,
                // where the play control has already made room for `next`.
                reveal: (1 - root.portrait) * Resize.mix(
                    Resize.progress(root.tall, index === 0 ? 0.25 : 0.4, 1),
                    root.fourRows, root.wideFace)
                entering: true
                directionX: root.tile.resizeDirectionX
                directionY: root.tile.resizeDirectionY
                travel: root.tile.scaled(10)
                RippleButton {
                    anchors.fill: parent
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    contentItem: MaterialSymbol {
                        text: skip.index === 0 ? "skip_previous" : "skip_next"
                        color: Appearance.colors.colOnSecondaryContainer
                        fill: 1
                        iconSize: root.tile.scaled(24)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (skip.index === 0 && root.player?.canGoPrevious) {
                            artwork.beginChange();
                            root.player.previous();
                        } else if (skip.index === 1 && root.player?.canGoNext) {
                            artwork.beginChange();
                            root.player.next();
                        }
                    }
                }
            }
        }

        // Cover-backed face, five columns and up: the position sits in the
        // transport's own row, to the left of it, centred on the same line. It is
        // the same wavy control every other media surface in the shell uses — the
        // seek slider while the player can seek, the wavy progress bar otherwise
        // — so a tile never grows a second progress language.
        QuickToggleMorphLayer {
            id: seekBar
            objectName: "quickToggleSharedSeekBar"
            x: root.pad
            y: root.seekBarTop
            // Stops short of the transport: the bottom row reads as the seekbar
            // then the controls, never a bar running under the skip pair.
            width: Math.max(0, playButton.x - root.transportShift - x - root.pad)
            height: root.seekBarHeight
            reveal: root.seekReveal
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(10)
            Loader {
                id: sliderLoader
                anchors.fill: parent
                active: root.player?.canSeek ?? false
                sourceComponent: StyledSlider {
                    configuration: StyledSlider.Configuration.Wavy
                    highlightColor: root.largeControlColor
                    trackColor: root.useDynamicColors ? blendedColors.colLayer1 : Appearance.colors.colSurfaceContainer
                    handleColor: root.largeControlColor
                    value: root.trackProgress
                    // Nothing to seek to while the player publishes no length.
                    enabled: MprisController.hasTrackLength(root.player)
                    onMoved: MprisController.seekFraction(root.player, value)
                    // QQuickSlider writes `value` itself while the user drags, which destroys
                    // the binding below it. Without this the bar froze where the drag left it
                    // and never followed the track again.
                    onPressedChanged: if (!pressed)
                        value = Qt.binding(() => MprisController.trackProgressOf(root.player))
                }
            }
            Loader {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    right: parent.right
                }
                active: !!root.player && !sliderLoader.active
                sourceComponent: StyledProgressBar {
                    wavy: root.playing
                    highlightColor: root.largeControlColor
                    trackColor: root.useDynamicColors ? blendedColors.colLayer1 : Appearance.colors.colSurfaceContainer
                    value: root.trackProgress
                }
            }
        }

        QuickToggleMorphLayer {
            x: root.pad
            y: root.pad
            width: Math.max(0, root.width - root.pad * 2)
            height: root.tile.scaled(24)
            reveal: Resize.progress(root.wideFace, 0.55, 1)
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(10)
            MaterialSymbol {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "music_note"
                iconSize: root.tile.scaled(Appearance.font.pixelSize.large)
                color: Appearance.colors.colOnLayer2
            }
            RippleButton {
                anchors.right: parent.right
                height: parent.height
                width: Math.min(parent.width * 0.7, implicitWidth)
                buttonRadius: Appearance.rounding.full
                colBackground: root.largeControlColor
                colBackgroundHover: root.useDynamicColors ? blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: root.useDynamicColors ? blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                contentItem: StyledText {
                    text: Audio.sink?.description || Translation.tr("Audio")
                    color: root.largeControlText
                    font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.smallest)
                    elide: Text.ElideRight
                }
                onClicked: GlobalStates.openAudioOutputSettings()
            }
        }

        // ── 2x4: cover, details, transport ───────────────────────────────────
        //
        // The bar's `ring` style stood up: the artwork is masked to the same
        // MaterialShape the rim is drawn in, so the cover and "how far through
        // the track we are" are one object instead of two. Details under it,
        // then a transport row where the play control fills everything the
        // next-track circle leaves. No lyrics here — the horizontal faces
        // already carry them, and a tile this narrow has no room for a line
        // worth reading.
        Item {
            id: portraitFace
            anchors.fill: parent
            visible: root.portrait > 0.001
            opacity: root.portrait

            readonly property real ringSize: Math.max(0, Math.min(portraitCover.width, portraitCover.height))
            // Slim: the bar's ring is 11% of a ~32px thickness, and carrying that
            // fraction onto a 116-174px ring read as a fat band.
            readonly property real ringWeight: Math.max(2, Math.round(ringSize * 0.04))
            readonly property real artSize: Math.max(0, ringSize - ringWeight * 2)

            Item {
                id: portraitCover
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.pad
                anchors.rightMargin: root.pad
                anchors.top: parent.top
                anchors.topMargin: root.portraitPad
                anchors.bottom: portraitMeta.top
                anchors.bottomMargin: root.portraitGap

                // The unplayed rim: the whole shape, dimmed.
                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: portraitFace.ringSize
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimary
                    opacity: 0.22
                }

                // The played rim. A `CircularProgress` only ever draws an arc, so
                // the sweep is done the other way round: paint the whole shape,
                // then reveal the fraction the position has reached with a
                // conical gradient used as a mask. Hard stops either side of the
                // fraction make it a wedge rather than a fade, and 270° starts it
                // at the top — zero degrees is 3 o'clock.
                Item {
                    id: portraitRimInk
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        anchors.centerIn: parent
                        implicitSize: portraitFace.ringSize
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimary
                    }
                }

                Item {
                    id: portraitSweep
                    anchors.fill: parent
                    visible: false

                    // Rebuilt whenever this item changes window, and never kept across a
                    // window that no longer exists.
                    //
                    // ConicalGradient feeds its ShaderEffect from an inline
                    // ShaderEffectSource declared as a *property value*, so that source is
                    // not a child in the visual tree and never gets ItemSceneChange when
                    // the window goes away. The window reference it holds on the gradient
                    // Rectangle is therefore never released, and the Rectangle stays
                    // pointing at a destroyed QQuickWindow - which the next window's
                    // forceUpdate() walks into and segfaults on (addToDirtyList).
                    //
                    // The island's window is destroyed on lock and rebuilt on unlock, so
                    // this fired on every unlock. Tying the effect's lifetime to the window
                    // means the stale item dies with the window instead of outliving it.
                    Loader {
                        anchors.fill: parent
                        active: portraitSweep.Window.window !== null
                        sourceComponent: ConicalGradient {
                            angle: 270
                            gradient: Gradient {
                                GradientStop { position: 0; color: "white" }
                                GradientStop { position: Math.max(0.0001, root.trackProgress); color: "white" }
                                GradientStop { position: Math.min(1, Math.max(0.0001, root.trackProgress) + 0.0001); color: "transparent" }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: portraitRimInk
                    maskSource: portraitSweep
                }

                // The artwork, one size down and cut to the same silhouette.
                Item {
                    id: portraitArtSlot
                    anchors.centerIn: parent
                    width: portraitFace.artSize
                    height: width

                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colSecondaryContainer
                    }

                    Image {
                        id: portraitArt
                        anchors.fill: parent
                        source: root.artSource
                        visible: source !== "" && status !== Image.Error
                        asynchronous: true
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.ceil(portraitArtSlot.width * 2)
                        sourceSize.height: Math.ceil(portraitArtSlot.width * 2)

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: MaterialShape {
                                width: portraitArtSlot.width
                                height: portraitArtSlot.width
                                shape: MaterialShape.Shape.Cookie9Sided
                            }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.artSource === "" || portraitArt.status === Image.Error
                        text: "music_note"
                        fill: 1
                        iconSize: Math.max(10, Math.round(portraitArtSlot.width * 0.55))
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            Column {
                id: portraitMeta
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.pad
                anchors.rightMargin: root.pad
                anchors.bottom: portraitControls.top
                anchors.bottomMargin: root.portraitGap
                spacing: 0

                StyledText {
                    width: parent.width
                    text: root.player?.trackTitle || Translation.tr("Untitled")
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.normal)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.small)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Item {
                id: portraitControls
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.pad
                anchors.rightMargin: root.pad
                anchors.bottomMargin: root.portraitPad
                height: root.controlHeight

                // The play control fills everything this circle leaves.
                RippleButton {
                    id: portraitNext
                    objectName: "quickToggleSharedPortraitNext"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.controlHeight
                    height: root.controlHeight
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    contentItem: MaterialSymbol {
                        text: "skip_next"
                        color: Appearance.colors.colOnSecondaryContainer
                        fill: 1
                        iconSize: root.tile.scaled(24)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (!root.player?.canGoNext)
                            return;
                        artwork.beginChange();
                        root.player.next();
                    }
                }
            }
        }
    }

    // Mpris only emits position on demand for most players, so the ring's sweep and
    // the seekbar both need a ticking clock while their face is on screen.
    Timer {
        running: root.playing && (root.portrait > 0.5 || root.seekReveal > 0.5)
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    Component.onCompleted: LyricsService.initiliazeLyrics()

    // Empty state: the same MaterialShape+icon placeholder language used by the
    // wifi/bluetooth dialogs. `shown` drives a cheap opacity fade; the item
    // unmaps itself (visible: opacity > 0) the moment a player appears, and the
    // whole subtree is torn down with the panel since there is no keep-warm here.
    PagePlaceholder {
        id: emptyPlaceholder
        shown: !root.player
        fillParent: false
        width: parent.width
        height: parent.height
        icon: "music_note"
        iconSize: Resize.mix(root.tile.scaled(26), root.tile.scaled(40), root.wideFace)
        iconPadding: Resize.mix(root.tile.scaled(8), root.tile.scaled(12), root.wideFace)
        title: Translation.tr("No media")
        titlePixelSize: Resize.mix(Appearance.font.pixelSize.small, Appearance.font.pixelSize.normal, root.wideFace)
        shape: MaterialShape.Shape.Cookie7Sided
    }
}
