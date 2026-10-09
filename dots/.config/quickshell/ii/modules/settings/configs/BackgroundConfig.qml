import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.background
import qs.modules.settings.configs.colors
import qs.services

/**
 * Settings → Background.
 *
 * Leads with the wallpaper itself playing the effect being edited (parallax, window blur, a
 * wallpaper change through the real shader), fixed at the top and folding as the page
 * scrolls; hovering a transition tries it on there. Then the two settings that have an amount
 * as dial cards, how a wallpaper changes as chips, the overview design as a grouped list and
 * original sections for video wallpapers, the depth effect, media mode and quality. The depth
 * models, video playback and its set-up live in sub-pages. Search indexes
 * sections/BackgroundOptionsSection.qml.
 */
Item {
    id: backgroundRoot
    anchors.fill: parent

    readonly property real cardGap: 12
    readonly property real tileHeight: 200
    readonly property real heroMinHeight: 230
    readonly property real heroMaxHeight: 320
    readonly property real heroPageRatio: 0.4
    readonly property real heroFoldedHeight: 96
    readonly property int hoverIntentDelay: 280
    readonly property real dialMin: 300
    readonly property real backendMin: 260
    readonly property int zoomMin: 100
    readonly property int zoomMax: 150
    readonly property int zoomDefault: 107
    readonly property int blurMax: 100
    readonly property int blurDefault: 80
    readonly property real shapeScaleMin: 30
    readonly property real shapeScaleMax: 200

    readonly property real heroFullHeight: Math.round(Math.max(heroMinHeight, Math.min(heroMaxHeight, height * heroPageRatio)))
    // Folds exactly as fast as the page scrolls: the content below never jumps.
    readonly property real heroHeight: Math.max(heroFoldedHeight, heroFullHeight - Math.max(0, page.contentY))
    readonly property real heroCollapse: (heroFullHeight - heroHeight) / Math.max(1, heroFullHeight - heroFoldedHeight)
    readonly property var background: Config.options.background
    readonly property bool videoLocked: Wallpapers.videoWallpaperActive
    readonly property bool shellBackend: (background.videoBackend ?? "mpvpaper") === "shell"
    readonly property bool animateChanges: background.animateWallpaperChanges ?? true
    readonly property bool overviewAlways: background.useBackgroundOverviewAlways ?? false
    readonly property bool parallaxOn: background.parallax.enableWorkspace && !videoLocked
    readonly property bool blurOn: background.blurWhenWindowsOpen && !videoLocked
    readonly property int zoomPercent: Math.round((background.parallax.workspaceZoom ?? zoomDefault / 100) * 100)
    readonly property int blurPercent: background.blurWhenWindowsOpenRadius ?? blurDefault
    readonly property string frameVideo: !background.useWallpaperEngine && Wallpapers.isVideoFile(background.wallpaperPath ?? "") ? background.wallpaperPath : ""

    readonly property string heroKind: background.useWallpaperEngine ? Translation.tr("Engine")
        : frameVideo !== "" ? Translation.tr("Video") : Translation.tr("Image")
    readonly property string heroDetail: background.useWallpaperEngine
        ? (background.wallpaperEngineId ? Translation.tr("Workshop item %1").arg(background.wallpaperEngineId) : Translation.tr("Wallpaper Engine"))
        : FileUtils.fileNameForPath(Wallpapers.effectiveWallpaperPath)
    readonly property string defaultImage: `${Directories.assetsPath}/images/default_wallpaper.png`
    readonly property string alternateImage: `${Directories.assetsPath}/images/light_mode_wallpaper.png`
    readonly property string heroSource: fileUrl(background.useWallpaperEngine ? "/tmp/wpe_screenshot.png"
        : frameVideo !== "" ? (background.thumbnailPath || defaultImage)
        : (background.wallpaperPath || defaultImage))
    readonly property string heroAlternate: fileUrl(Wallpapers.recentWallpapers.find(path => path !== background.wallpaperPath && !Wallpapers.isVideoFile(path)) ?? alternateImage)

    // What the hero plays; an option under the pointer is tried on without being chosen.
    property string previewMode: "parallax"
    property var transitionTry: null
    readonly property string previewTransition: transitionTry ?? transitionValue
    readonly property string heroCaption: previewMode === "parallax" ? Translation.tr("Zoom %1%").arg(zoomPercent)
        : previewMode === "blur" ? Translation.tr("Blur %1%").arg(blurPercent)
        : animateChanges ? nameOf(transitions, previewTransition) : Translation.tr("Changes instantly")

    readonly property var transitions: [
        { "value": "", "name": Translation.tr("Crossfade"), "icon": "blur_on" },
        { "value": "random", "name": Translation.tr("Random"), "icon": "shuffle" },
        { "value": "circlePit", "name": Translation.tr("Circle Pit"), "icon": "circle" },
        { "value": "circleSelect", "name": Translation.tr("Circle Select"), "icon": "radio_button_checked" },
        { "value": "magic", "name": Translation.tr("Magic"), "icon": "auto_awesome" },
        { "value": "Peel", "name": Translation.tr("Peel"), "icon": "sticky_note_2" },
        { "value": "transition", "name": Translation.tr("Transition"), "icon": "swap_horiz" },
        { "value": "pixelate", "name": Translation.tr("Pixelate"), "icon": "grid_on" },
        { "value": "stripes", "name": Translation.tr("Stripes"), "icon": "view_column" }
    ]
    readonly property string transitionValue: background.wallpaperAnimation ?? ""
    readonly property string transitionName: nameOf(transitions, transitionValue)

    readonly property var overviewStyles: [
        {
            "value": "gnome",
            "name": Translation.tr("Gnome Like"),
            "icon": "blur_on",
            "shape": MaterialShape.Shape.Cookie9Sided,
            "description": Translation.tr("Zooms the wallpaper out with rounded corners, shadow and a blurred backing.")
        },
        {
            "value": "material-shape",
            "name": Translation.tr("Material Shape"),
            "icon": "shapes",
            "shape": MaterialShape.Shape.Flower,
            "description": Translation.tr("Cuts the wallpaper with a random Material Shape focusing on center widgets with a solid primary container background.")
        },
        {
            "value": "card-lift",
            "name": Translation.tr("Card Lift"),
            "icon": "style",
            "shape": MaterialShape.Shape.Clover4Leaf,
            "description": Translation.tr("Lifts the wallpaper into a rounded card with a blurred/dimmed backing.")
        },
        {
            "value": "camera-push",
            "name": Translation.tr("Camera Push"),
            "icon": "zoom_in",
            "shape": MaterialShape.Shape.SoftBurst,
            "description": Translation.tr("Pushes the camera in with brightness and saturation adjustment; no blur.")
        },
        {
            "value": "desaturate",
            "name": Translation.tr("Desaturate"),
            "icon": "tonality",
            "shape": MaterialShape.Shape.Cookie12Sided,
            "description": Translation.tr("Low-cost preset using desaturation and reduced brightness without blur.")
        },
        {
            "value": "directional",
            "name": Translation.tr("Directional"),
            "icon": "open_in_new",
            "shape": MaterialShape.Shape.Sunny,
            "description": Translation.tr("Adds a small movement away from the configured bar position.")
        }
    ]
    readonly property string overviewValue: {
        const style = background.overviewBackgroundStyle;
        return overviewStyles.some(entry => entry.value === style) ? style : "gnome";
    }
    readonly property string overviewName: nameOf(overviewStyles, overviewValue)

    readonly property int depthModels: DepthEffect.installed.length
    readonly property bool depthOn: background.depthEffect.enable && DepthEffect.anyInstalled

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function fileUrl(path) {
        return String(path).startsWith("file:") ? String(path) : "file://" + path;
    }

    function nameOf(list, value) {
        return (list.find(entry => entry.value === value) ?? list[0]).name;
    }

    function tryEffect(mode) {
        backgroundRoot.previewMode = mode;
        hero.play();
    }

    // A setting being dragged shows its value at once instead of replaying.
    function showLive(mode) {
        backgroundRoot.previewMode = mode;
        hero.settle();
    }

    // Hovering an option tries it on once the pointer rests on it, so passing over a row
    // on the way elsewhere never interrupts what the preview is playing.
    function queueTry(value) {
        hoverIntent.value = value;
        hoverIntent.restart();
    }

    function clearTry() {
        hoverIntent.stop();
        backgroundRoot.transitionTry = null;
    }

    function openSubPage(file) {
        backgroundRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    function openPage(pageId, section) {
        const window = backgroundRoot.QsWindow.window;
        if (!window || window.pageIndexById === undefined)
            return;
        const index = window.pageIndexById(pageId);
        if (index < 0)
            return;
        if (section !== "")
            window.pendingSectionHighlight = section;
        window.currentPage = index;
    }

    function columnsFor(width, minimum) {
        return Math.max(1, Math.min(2, Math.floor((width + backgroundRoot.cardGap) / (minimum + backgroundRoot.cardGap))));
    }

    // ── The wallpaper, live and sticky ────────────────────────────────
    BackgroundPreviewHero {
        id: hero
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: backgroundRoot.heroHeight
        z: 5
        opacity: subPageOverlay.slideProgress
        mode: backgroundRoot.previewMode
        kind: backgroundRoot.heroKind
        detail: backgroundRoot.heroDetail
        caption: backgroundRoot.heroCaption
        source: backgroundRoot.heroSource
        alternate: backgroundRoot.heroAlternate
        zoom: backgroundRoot.zoomPercent / 100
        blurAmount: backgroundRoot.blurPercent / 100
        transitionShader: backgroundRoot.previewTransition
        transitionAnimated: backgroundRoot.animateChanges
        locked: backgroundRoot.videoLocked
        collapse: backgroundRoot.heroCollapse
        onModeRequested: next => backgroundRoot.previewMode = next
        Component.onCompleted: Qt.callLater(hero.play)
    }

    Timer {
        id: hoverIntent
        property var value: null
        interval: backgroundRoot.hoverIntentDelay
        onTriggered: {
            backgroundRoot.transitionTry = hoverIntent.value;
            backgroundRoot.tryEffect("transition");
        }
    }

    ContentPage {
        id: page
        anchors.fill: undefined
        anchors.top: parent.top
        anchors.topMargin: backgroundRoot.heroFoldedHeight + backgroundRoot.cardGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // Room for the open hero, which sits over the top of the page and folds as it scrolls.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: backgroundRoot.heroFullHeight - backgroundRoot.heroFoldedHeight - backgroundRoot.cardGap
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: backgroundRoot.videoLocked
            materialIcon: "movie"
            text: Translation.tr("Video wallpaper active: window blur and parallax are disabled automatically; only the Default zoom style is available.")
        }

        // ── Parallax and window blur ──────────────────────────────────────
        Item {
            id: dials
            Layout.fillWidth: true
            implicitHeight: dialFlow.implicitHeight

            readonly property int columns: backgroundRoot.columnsFor(width, backgroundRoot.dialMin)
            readonly property real cardWidth: Math.floor((width - backgroundRoot.cardGap * (columns - 1)) / columns)
            readonly property real rowHeight: Math.max(parallaxDial.implicitHeight, blurDial.implicitHeight)

            Flow {
                id: dialFlow
                width: parent.width
                spacing: backgroundRoot.cardGap

                BackgroundDialCard {
                    id: parallaxDial
                    width: dials.cardWidth
                    height: dials.columns > 1 ? dials.rowHeight : implicitHeight
                    enabled: !backgroundRoot.videoLocked
                    symbol: "sync_alt"
                    shapeOn: MaterialShape.Shape.Flower
                    title: Translation.tr("Parallax")
                    subtitle: backgroundRoot.parallaxOn ? Translation.tr("Moves with the workspaces") : Translation.tr("Wallpaper stays still")
                    valueText: String(backgroundRoot.zoomPercent)
                    unit: "%"
                    markers: [backgroundRoot.zoomMin + "%", backgroundRoot.zoomMax + "%"]
                    from: backgroundRoot.zoomMin
                    to: backgroundRoot.zoomMax
                    stepSize: 1
                    value: backgroundRoot.zoomPercent
                    checked: backgroundRoot.background.parallax.enableWorkspace
                    onToggled: next => {
                        backgroundRoot.background.parallax.enableWorkspace = next;
                        backgroundRoot.tryEffect("parallax");
                    }
                    onMoved: next => {
                        backgroundRoot.background.parallax.workspaceZoom = next / 100;
                        backgroundRoot.showLive("parallax");
                    }

                    BackgroundActionPill {
                        symbol: "tune"
                        label: Translation.tr("Movement")
                        colContent: parallaxDial.colContent
                        onClicked: backgroundRoot.openSubPage("ParallaxConfig.qml")
                    }
                }

                BackgroundDialCard {
                    id: blurDial
                    width: dials.cardWidth
                    height: dials.columns > 1 ? dials.rowHeight : implicitHeight
                    enabled: !backgroundRoot.videoLocked
                    symbol: "blur_on"
                    shapeOn: MaterialShape.Shape.SoftBurst
                    title: Translation.tr("Window blur")
                    subtitle: Translation.tr("Experimental")
                    valueText: String(backgroundRoot.blurPercent)
                    unit: "%"
                    markers: [Translation.tr("Sharp"), Translation.tr("Frosted")]
                    from: 0
                    to: backgroundRoot.blurMax
                    stepSize: 1
                    value: backgroundRoot.blurPercent
                    checked: backgroundRoot.background.blurWhenWindowsOpen
                    onToggled: next => {
                        backgroundRoot.background.blurWhenWindowsOpen = next;
                        backgroundRoot.tryEffect("blur");
                    }
                    onMoved: next => {
                        backgroundRoot.background.blurWhenWindowsOpenRadius = next;
                        backgroundRoot.showLive("blur");
                    }

                    BackgroundActionPill {
                        symbol: "blur_linear"
                        label: Translation.tr("Window blur settings")
                        colContent: blurDial.colContent
                        onClicked: backgroundRoot.openPage("windows", Translation.tr("Transparency & Blur"))
                    }
                }
            }
        }

        // ── Wallpaper changes ─────────────────────────────────────────────
        BackgroundPane {
            Layout.fillWidth: true
            enabled: !backgroundRoot.videoLocked
            symbol: "animation"
            title: Translation.tr("Wallpaper changes")
            subtitle: backgroundRoot.animateChanges ? backgroundRoot.transitionName : Translation.tr("Changes instantly")
            switchable: true
            checked: backgroundRoot.animateChanges
            onToggled: next => {
                backgroundRoot.background.animateWallpaperChanges = next;
                backgroundRoot.tryEffect("transition");
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: backgroundRoot.transitions

                    delegate: ColorsChip {
                        required property var modelData

                        label: modelData.name
                        symbol: modelData.icon
                        chosen: backgroundRoot.transitionValue === modelData.value
                        onHoveredChanged: hovered ? backgroundRoot.queueTry(modelData.value) : backgroundRoot.clearTry()
                        onClicked: {
                            backgroundRoot.background.wallpaperAnimation = modelData.value;
                            hero.play();
                        }
                    }
                }
            }
        }

        // ── Overview design ───────────────────────────────────────────────
        BackgroundPane {
            Layout.fillWidth: true
            enabled: !backgroundRoot.videoLocked
            symbol: "dashboard_customize"
            shapeIdle: MaterialShape.Shape.Clover4Leaf
            shapeEngaged: MaterialShape.Shape.Flower
            title: Translation.tr("Overview background")
            subtitle: backgroundRoot.overviewAlways
                ? Translation.tr("Always active · %1").arg(backgroundRoot.overviewName)
                : Translation.tr("Only while the overview is open")
            switchable: true
            checked: backgroundRoot.overviewAlways
            onToggled: next => {
                backgroundRoot.background.useBackgroundOverviewAlways = next;
            }

            BackgroundStyleList {
                Layout.fillWidth: true
                options: backgroundRoot.overviewStyles
                currentValue: backgroundRoot.overviewValue
                onSelected: value => {
                    backgroundRoot.background.overviewBackgroundStyle = value;
                    backgroundRoot.background.zoomOutStyle = value === "gnome" ? 0 : 2;
                }
            }

            ConfigSwitch {
                visible: backgroundRoot.overviewValue === "material-shape"
                buttonIcon: "wb_twilight"
                text: Translation.tr("Material Shape drop-shadow")
                checked: backgroundRoot.background.materialShapeShadow === true
                onCheckedChanged: backgroundRoot.background.materialShapeShadow = checked

                StyledToolTip {
                    text: Translation.tr("Renders a subtle outer drop shadow around the material shape mask.")
                }
            }

            ConfigSlider {
                visible: backgroundRoot.overviewValue === "material-shape"
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Material Shape scale (%)")
                usePercentTooltip: true
                from: backgroundRoot.shapeScaleMin
                to: backgroundRoot.shapeScaleMax
                stepSize: 1
                value: Math.round((backgroundRoot.background.materialShapeScale ?? 1.0) * 100)
                onValueChanged: backgroundRoot.background.materialShapeScale = value / 100
            }
        }

        // ── Video wallpapers ──────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Video wallpapers")
            icon: "movie"

            Item {
                id: backends
                Layout.fillWidth: true
                implicitHeight: backendFlow.implicitHeight

                readonly property int columns: backgroundRoot.columnsFor(width, backgroundRoot.backendMin)
                readonly property real cardWidth: Math.floor((width - backgroundRoot.cardGap * (columns - 1)) / columns)

                Flow {
                    id: backendFlow
                    width: parent.width
                    spacing: backgroundRoot.cardGap

                    BackgroundBackendCard {
                        width: backends.cardWidth
                        symbol: "layers"
                        shapeChosen: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("mpvpaper")
                        description: Translation.tr("mpvpaper draws the video on its own layer below the shell. It needs no setup, but image effects (window blur, parallax, overview designs) are turned off while it plays.")
                        pillSymbol: "block"
                        pillText: Translation.tr("Image effects off")
                        chosen: !backgroundRoot.shellBackend
                        onPicked: backgroundRoot.background.videoBackend = "mpvpaper"
                    }

                    BackgroundBackendCard {
                        width: backends.cardWidth
                        symbol: "wallpaper"
                        shapeChosen: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Shell")
                        description: Translation.tr("The shell plays the video inside the wallpaper, so window blur, parallax, the overview zoom and the lock screen effects work with it, and no separate mpvpaper process runs.")
                        pillSymbol: "auto_awesome"
                        pillText: Translation.tr("Image effects on")
                        chosen: backgroundRoot.shellBackend
                        onPicked: backgroundRoot.background.videoBackend = "shell"
                    }
                }
            }

            BackgroundLinkRow {
                Layout.fillWidth: true
                symbol: "tune"
                title: Translation.tr("Playback and set-up")
                summary: Translation.tr("When the video pauses, its size on screen, the libmpv player and the color frame")
                onClicked: backgroundRoot.openSubPage("VideoWallpaperConfig.qml")
            }
        }

        // ── Depth effect ──────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Depth effect")
            icon: "layers"

            ColorsFeatureTile {
                Layout.fillWidth: true
                Layout.preferredHeight: backgroundRoot.tileHeight
                enabled: !backgroundRoot.videoLocked
                opacity: enabled ? 1 : 0.45
                symbol: "layers"
                shapeOn: MaterialShape.Shape.Flower
                title: Translation.tr("Subject in front of widgets")
                summary: backgroundRoot.depthOn
                    ? Translation.tr("Subject in front of widgets · %1 model(s) installed").arg(backgroundRoot.depthModels)
                    : backgroundRoot.depthModels > 0
                        ? Translation.tr("%1 model(s) installed").arg(backgroundRoot.depthModels)
                        : Translation.tr("Cut the subject out so a clock can sit behind a person")
                checked: backgroundRoot.depthOn
                configurable: true
                onConfigureRequested: backgroundRoot.openSubPage("DepthEffectConfig.qml")
                onToggled: value => {
                    if (DepthEffect.anyInstalled)
                        backgroundRoot.background.depthEffect.enable = value;
                    else
                        backgroundRoot.openSubPage("DepthEffectConfig.qml");
                }
            }
        }

        // ── Media mode ────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Media Mode Background")
            icon: "music_note"

            ColorsFeatureTile {
                Layout.fillWidth: true
                Layout.preferredHeight: backgroundRoot.tileHeight
                symbol: "music_note"
                shapeOn: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("Media mode background overlay")
                summary: Translation.tr("A full-screen overlay with lyrics, visualizers and album art while Media Mode is on")
                checked: backgroundRoot.background.mediaMode.showLyrics ?? true
                configurable: true
                onConfigureRequested: backgroundRoot.openSubPage("MediaModeBackgroundConfig.qml")
                onToggled: value => backgroundRoot.background.mediaMode.showLyrics = value
            }

            KeyboardShortcutBox {
                Layout.fillWidth: true
                Layout.topMargin: backgroundRoot.cardGap - 4
                text: Translation.tr("Toggle Media Mode")
                keys: ["Super", "Z"]
            }
        }

        // ── Quality ───────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Wallpaper Quality & Performance")
            icon: "high_quality"

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Downscale wallpaper to reduce VRAM usage")
                enabled: !backgroundRoot.videoLocked
                checked: backgroundRoot.background.scaleLargeWallpapers ?? false
                onCheckedChanged: {
                    backgroundRoot.background.scaleLargeWallpapers = checked;
                }
                StyledToolTip {
                    text: Translation.tr("When enabled, decodes large wallpapers at screen resolution to save VRAM. When disabled (default, like upstream end-4), loads wallpapers at full native resolution for maximum sharpness.")
                }
            }
        }

        ShortcutBox {
            Layout.fillWidth: true
            value: Translation.tr("Desktop Clock Widget settings")
            targetPageId: "widgets"
            targetSectionTitle: Translation.tr("Widget Manager")
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "lockScreen"
                    label: Translation.tr("Lock screen blur")
                    sectionHighlight: Translation.tr("Blur style")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
