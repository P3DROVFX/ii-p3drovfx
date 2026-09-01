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
    readonly property string builtInThemeCommand: `jq -r '.primary, .primary_container, .secondary' ${builtInThemeFilePath}`

    property bool customTheme: false
    readonly property string customThemeFilePath: customThemeDirectory + "/" + colorScheme + ".json"
    readonly property string customThemeCommand: `jq -r '.primary, .primary_container, .secondary' ${customThemeFilePath}`

    readonly property string wallpaperPath: (Config.options && Config.options.background && Config.options.background.wallpaperPath)
        ? Config.options.background.wallpaperPath : ""
    readonly property string activeWallpaperPath: {
        if (Config.options && Config.options.background && Config.options.background.useWallpaperEngine)
            return "/tmp/wpe_screenshot.png";
        return wallpaperPath;
    }
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/colors/generate_colors_material.py`)
    readonly property string resolvedScheme: colorScheme === "scheme-auto"
        ? "scheme-tonal-spot" : colorScheme
    readonly property string fullCommand: activeWallpaperPath !== ""
        ? `${scriptPath} --path "${activeWallpaperPath}" --scheme ${resolvedScheme} --preview`
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

    property bool isWidgetScheme: false
    property bool widgetSchemeToggled: false
    readonly property bool toggled: isWidgetScheme
        ? widgetSchemeToggled
        : Config.options.appearance.palette.type === colorScheme
    property bool expressiveSelection: false
    readonly property bool sharpMode: Config.options.appearance.sharpMode

    colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: toggled
        ? Appearance.colors.colPrimaryContainerHover
        : Appearance.colors.colLayer2Hover
    colRipple: toggled
        ? Appearance.colors.colPrimaryContainerActive
        : Appearance.colors.colLayer2Active

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
    readonly property bool useWpe: (Config.options && Config.options.background)
        ? Config.options.background.useWallpaperEngine : false

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
        if (root.loadFromCache())
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

    onShouldLoadChanged: Qt.callLater(root.startColorFetch)
    onWallpaperPathChanged: root.refetchColors()
    onWpeIdChanged: root.refetchColors()
    onUseWpeChanged: root.refetchColors()

    Connections {
        target: ThemePreviewCache
        enabled: root.shouldLoad && !root.usePreviewColors

        function onCacheChanged(path) {
            if (path === root.presetPath)
                root.applySwatch(ThemePreviewCache.get(path));
        }

        function onWallpaperPreviewsChanged() {
            if (root.customTheme || root.builtInTheme)
                return;
            root.applySwatch(ThemePreviewCache.wallpaperPreview(root.colorScheme));
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
                        root.tertiaryColor = data.secondary || "transparent";
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
        text: root.colorSchemeDisplayName
    }

    Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            visible: !root.loaded
            elide: Text.ElideRight
            text: root.colorSchemeDisplayName
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnPrimaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
        }

        Canvas {
            id: myCanvas
            anchors.centerIn: parent
            anchors.margins: 8
            implicitWidth: root.implicitHeight - 16
            implicitHeight: root.implicitHeight - 16
            antialiasing: true

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
