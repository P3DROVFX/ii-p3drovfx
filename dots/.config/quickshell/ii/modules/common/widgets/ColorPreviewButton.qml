import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root

    readonly property string builtInThemeDirectory: Directories.defaultThemes
    readonly property string customThemeDirectory: Directories.customThemes

    property string colorScheme: "scheme-auto"
    property string colorSchemeDisplayName: ""

    property bool builtInTheme: false
    readonly property string builtInThemeFilePath: builtInThemeDirectory + "/" + colorScheme + ".json"
    readonly property string builtInThemeCommand: `jq -r '.primary, .primary_container, (.tertiary // .secondary)' ${builtInThemeFilePath}`

    property bool customTheme: false
    readonly property string customThemeFilePath: customThemeDirectory + "/" + colorScheme + ".json"
    readonly property string customThemeCommand: `jq -r '.primary, .primary_container, (.tertiary // .secondary)' ${customThemeFilePath}`

    // The image the shell is actually showing - which is the shipped default
    // when the user has not chosen a wallpaper yet, not "no wallpaper". Without
    // that resolution the command below comes out empty on a first install and
    // startColorFetch() returns before consulting any cache, which is what left
    // these buttons blank. See Wallpapers.effectiveWallpaperPath.
    readonly property string activeWallpaperPath: Wallpapers.effectiveWallpaperPath
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/colors/generate_colors_material.py`)
    // scheme-auto is passed through: the script resolves it from the image the
    // same way switchwall does, instead of always previewing tonal spot.
    readonly property string fullCommand: activeWallpaperPath !== ""
        ? `${scriptPath} --path "${activeWallpaperPath}" --scheme ${colorScheme} --preview`
        : ""

    // Widget color previews receive their colors directly and do not need a
    // process. Keep this interface compatible with WidgetsConfig.qml.
    property color previewPrimary: "transparent"
    property color previewSecondary: "transparent"
    property color previewTertiary: "transparent"
    property bool usePreviewColors: false
    property color primaryColor: usePreviewColors ? previewPrimary : "transparent"
    property color secondaryColor: usePreviewColors ? previewSecondary : "transparent"
    property color tertiaryColor: usePreviewColors ? previewTertiary : "transparent"

    property bool loaded: usePreviewColors
    property bool shouldLoad: false
    // The name stands in only when the colours do not come: shown while they
    // load, it flashes a grid of labels before the swatches replace them.
    property bool showNameFallback: false
    onLoadedChanged: {
        if (root.loaded)
            root.showNameFallback = false;
    }

    Timer {
        interval: 1500
        running: root.shouldLoad && !root.loaded
        onTriggered: root.showNameFallback = true
    }
    property bool _cacheHeld: false

    function releasePreviewCache() {
        if (!root._cacheHeld)
            return;
        root._cacheHeld = false;
        ThemePreviewCache.relinquish();
    }

    Component.onDestruction: root.releasePreviewCache()

    property bool isWidgetScheme: false
    property bool widgetSchemeToggled: false
    readonly property bool toggled: isWidgetScheme
        ? widgetSchemeToggled
        : Config.options.appearance.palette.type === colorScheme
    property bool expressiveSelection: false
    readonly property bool sharpMode: Config.options.appearance.sharpMode

    // The chosen swatch sits on the secondary container, a quieter fill than
    // primary, and carries the primary ring around its circle. Driven by this
    // file's `toggled`: it shadows RippleButton's, whose toggled colours never
    // apply here.
    colBackground: root.toggled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: root.toggled ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
    colBackgroundActive: root.toggled ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
    colRipple: root.toggled ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active

    /// Hosts that already print the hovered scheme's name turn the tooltip off.
    property bool showTooltip: true

    /// Space between the swatch and the selection ring, and the ring's stroke.
    property real ringGap: 2
    property real ringWidth: 2.5

    buttonRadius: Appearance.rounding.small

    scale: (root.down ? 0.96 : (root.hovered ? 1.01 : 1.0))
        * (root.expressiveSelection && root.toggled ? 1.03 : 1.0)

    Layout.fillWidth: true
    implicitHeight: 64

    // Preset files are copied in through a temporary name so the shell's file
    // watcher can never observe a half-written colors.json.
    function applyPresetFile(themeFilePath) {
        const themePath = FileUtils.trimFileProtocol(themeFilePath);
        const targetPath = FileUtils.trimFileProtocol(Directories.generatedMaterialThemePath);
        const recolor = FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/recolor_icons.py`);
        let command = `cp "${themePath}" "${targetPath}.tmp" && mv "${targetPath}.tmp" "${targetPath}"`;
        if (Config.options.appearance.icons.enableThemed)
            command += ` && python3 "${recolor}"`;
        Quickshell.execDetached(["bash", "-c", command]);
    }

    onClicked: {
        if (isWidgetScheme)
            return;

        Config.options.appearance.palette.type = colorScheme;

        if (customTheme) {
            root.applyPresetFile(customThemeFilePath);
        } else if (builtInTheme) {
            root.applyPresetFile(builtInThemeFilePath);
        } else {
            Config.options.appearance.palette.accentColor = "";
            Config.saveOptionsNow();
            // Pass the scheme on the command line: the script otherwise reads it
            // back from config.json, which may not have hit the disk yet and
            // would silently regenerate the previously selected scheme.
            Quickshell.execDetached(["bash", "-c",
                `${Directories.wallpaperSwitchScriptPath} --noswitch --type ${colorScheme}`]);
        }
    }

    readonly property string effectiveCommand: customTheme
        ? customThemeCommand
        : builtInTheme ? builtInThemeCommand : fullCommand

    readonly property string wpeId: (Config.options && Config.options.background)
        ? Config.options.background.wallpaperEngineId : ""

    readonly property string presetPath: customTheme
        ? FileUtils.trimFileProtocol(customThemeFilePath)
        : builtInTheme ? FileUtils.trimFileProtocol(builtInThemeFilePath) : ""

    function applySwatch(swatch) {
        if (!swatch)
            return false;
        root.primaryColor = swatch.primary;
        root.secondaryColor = swatch.secondary;
        root.tertiaryColor = swatch.tertiary;
        root.loaded = true;
        myCanvas.requestPaint();
        return true;
    }

    // A settings page holds dozens of swatches. Reading them from the shared
    // caches keeps the page free of one subprocess per swatch; the process
    // below stays as a fallback for entries the caches cannot serve.
    function loadFromCache() {
        if (usePreviewColors || !shouldLoad)
            return true;

        if (customTheme || builtInTheme) {
            if (root.presetPath === "")
                return false;
            if (root.applySwatch(ThemePreviewCache.get(root.presetPath)))
                return true;
            ThemePreviewCache.request(root.presetPath);
            return true;
        }

        return root.applySwatch(ThemePreviewCache.wallpaperPreview(root.colorScheme));
    }

    // Deferred so `effectiveCommand` (and therefore the process command) has
    // already been re-evaluated: starting the fetch straight from the source
    // change handler could relaunch the process with the previous wallpaper and
    // leave the swatch showing stale colors until the page is rebuilt.
    function startColorFetch() {
        if (usePreviewColors || !shouldLoad || effectiveCommand === "")
            return;
        if (!root._cacheHeld) {
            root._cacheHeld = true;
            ThemePreviewCache.acquire();
        }
        if (root.loadFromCache())
            return;
        // One generation for the whole grid rather than one process per swatch.
        // It only declines when it cannot help, and then this owns the fallback.
        // Preset swatches read a fixed JSON file and never have anything to
        // generate, so they go straight through.
        if (!root.customTheme && !root.builtInTheme && ThemePreviewCache.ensureWallpaperPreviews())
            return;
        colorFetchProcess.running = false;
        colorFetchProcess.running = true;
    }

    // Preset swatches read a fixed JSON file, so only wallpaper-derived schemes
    // have anything to recompute when the source image changes.
    function refetchColors() {
        if (!shouldLoad || customTheme || builtInTheme)
            return;
        root.loaded = false;
        Qt.callLater(root.startColorFetch);
    }

    onShouldLoadChanged: {
        if (!root.shouldLoad) {
            colorFetchProcess.running = false;
            root.releasePreviewCache();
        } else {
            Qt.callLater(root.startColorFetch);
        }
    }
    onUsePreviewColorsChanged: {
        if (root.usePreviewColors) {
            colorFetchProcess.running = false;
            root.releasePreviewCache();
        } else {
            Qt.callLater(root.startColorFetch);
        }
    }

    // Wallpaper Engine can swap the video behind the same screenshot path, so
    // the id matters even though the path does not change with it.
    onWpeIdChanged: root.refetchColors()

    // The image itself, rather than the raw config value: choosing or clearing a
    // wallpaper and the switch to or from Wallpaper Engine all land here.
    Connections {
        target: Wallpapers
        function onEffectiveWallpaperPathChanged() {
            root.refetchColors();
        }
    }

    // A preset swatch follows the cache through a binding. Listening for
    // `cacheChanged` alone left a few swatches of a freshly built grid on their
    // name forever: the read finished and the signal went out, but that
    // button's Connections never ran.
    readonly property var presetSwatch: root._cacheHeld && root.presetPath !== ""
        ? (ThemePreviewCache.revision, ThemePreviewCache.get(root.presetPath)) : null
    onPresetSwatchChanged: {
        if (root.presetSwatch && !root.loaded)
            root.applySwatch(root.presetSwatch);
    }

    Connections {
        target: root._cacheHeld ? ThemePreviewCache : null

        function onWallpaperPreviewsChanged() {
            if (root.customTheme || root.builtInTheme)
                return;
            root.applySwatch(ThemePreviewCache.wallpaperPreview(root.colorScheme));
        }

        function onWallpaperPreviewsGenerationFailed() {
            if (root.customTheme || root.builtInTheme)
                return;
            // The shared generation is marked as already attempted, so this
            // reaches the per-swatch process instead of asking for another one.
            root.refetchColors();
        }
    }

    Process {
        id: colorFetchProcess
        running: false
        command: ["bash", "-c", root.effectiveCommand]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (root.customTheme || root.builtInTheme) {
                        const colors = this.text.trim().split("\n");
                        root.primaryColor = colors[0] || "transparent";
                        root.secondaryColor = colors[1] || "transparent";
                        root.tertiaryColor = colors[2] || "transparent";
                    } else {
                        const data = JSON.parse(this.text);
                        root.primaryColor = data.primary || "transparent";
                        root.secondaryColor = data.primary_container || "transparent";
                        root.tertiaryColor = data.tertiary || data.secondary || "transparent";
                    }

                    root.loaded = true;
                    myCanvas.requestPaint();
                } catch (error) {
                    console.warn("[ColorPreviewButton] Preview parse failed:", error);
                }
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.showTooltip
        text: root.colorSchemeDisplayName
    }

    Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            visible: !root.loaded && root.showNameFallback
            elide: Text.ElideRight
            text: root.colorSchemeDisplayName
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }

        // Selection: a primary ring standing `ringGap` off the swatch.
        Rectangle {
            id: selectionRing
            anchors.centerIn: myCanvas
            width: myCanvas.width + (root.ringGap + root.ringWidth) * 2
            height: width
            radius: root.sharpMode ? 0 : width / 2
            color: "transparent"
            border.width: root.ringWidth
            border.color: Appearance.colors.colPrimary
            opacity: root.toggled && root.loaded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Canvas {
            id: myCanvas
            anchors.centerIn: parent
            // Sized from the button's real box: grids that set a height through
            // Layout would otherwise get a swatch sized for the implicit one.
            readonly property real side: Math.max(8, Math.round(Math.min(root.width, root.height) - 16))
            width: side
            height: side
            antialiasing: true
            // A swatch can arrive before the canvas has a context or while its
            // grid is hidden; that request is lost, so paint again once it can.
            onWidthChanged: requestPaint()
            onAvailableChanged: if (available) requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                const centerX = width / 2;
                const centerY = height / 2;
                const radius = width / 2;

                ctx.reset();

                if (root.sharpMode) {
                    ctx.fillStyle = root.primaryColor;
                    ctx.fillRect(0, 0, width, centerY);

                    ctx.fillStyle = root.secondaryColor;
                    ctx.fillRect(centerX, centerY, centerX, centerY);

                    ctx.fillStyle = root.tertiaryColor;
                    ctx.fillRect(0, centerY, centerX, centerY);
                } else {
                    ctx.beginPath();
                    ctx.fillStyle = root.primaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, Math.PI, 0, false);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.fillStyle = root.secondaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, 0, Math.PI / 2, false);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.fillStyle = root.tertiaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, Math.PI / 2, Math.PI, false);
                    ctx.fill();
                }
            }
        }
    }
}
