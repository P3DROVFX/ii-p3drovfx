import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

/**
 * Shared adaptive application icon used by every dock family.
 *
 * The icon source and its Material shape mask are intentionally shared with the ii dock:
 * favourite apps belong to the user, not to one panel family, so an app must not gain a
 * different visual identity merely because the active shell changes. This lives in its own
 * explicitly registered module: Quickshell's generated common-widgets registry is created at
 * startup and cannot safely discover a new public type during a hot reload.
 */
Item {
    id: root

    property string appId: ""
    property var desktopEntry: null
    property bool isRunning: true
    // Largest scale a parent transform will draw this icon at. Decode for it
    // once so magnification stays sharp; keep it constant while animating.
    property real renderScale: 1
    property real iconOpacity: isRunning ? 1.0 : (Config.options.dock.dimInactiveIcons ? 0.55 : 1.0)

    readonly property bool isShellApp: root.desktopEntry?.isShellApp === true
    readonly property string shellMaterialIcon: String(root.desktopEntry?.materialIcon ?? "")

    // Match the active ii-icon-pack plate shape when ii-icon-pack is in use;
    // otherwise respect dock.shapeMask (when enabled) or fall back to Circle.
    readonly property string resolvedShellShape: {
        if (Config.options.dock.enableShapeMask)
            return Config.options.dock.shapeMask;
        const theme = String(Config.options?.appearance?.icons?.iconTheme ?? "");
        const usesIiPack = theme === "ii-icon-pack" || theme === "DynamicTheme" || IiIconPack.installed;
        const raw = usesIiPack ? String(Config.options?.appearance?.icons?.iiPack?.shape ?? "").trim().toLowerCase() : "";
        if (!raw)
            return "Circle";
        const entry = (IiIconPack.shapes ?? []).find(s => String(s?.key ?? "").toLowerCase() === raw);
        if (entry && entry.materialShape)
            return String(entry.materialShape);
        const map = {
            "circle": "Circle",
            "squircle": "Square",
            "square": "Square",
            "teardrop": "Arch",
            "arch": "Arch",
            "slanted": "Slanted",
            "cookie4": "Cookie4Sided",
            "cookie6": "Cookie6Sided",
            "cookie7": "Cookie7Sided",
            "cookie9": "Cookie9Sided",
            "cookie12": "Cookie12Sided",
            "clover4": "Clover4Leaf",
            "clover8": "Clover8Leaf",
            "sunny": "Sunny",
            "verysunny": "VerySunny",
            "flower": "Flower",
            "gem": "Gem",
            "pentagon": "Pentagon",
            "diamond": "Diamond",
            "puffy": "Puffy",
            "burst": "Burst",
            "softburst": "SoftBurst",
            "heart": "Heart"
        };
        return map[raw] ?? "Circle";
    }

    readonly property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;
        if (root.isShellApp)
            return "";

        if (root.desktopEntry && root.desktopEntry.icon) {
            let path = Quickshell.iconPath(root.desktopEntry.icon, true).toString();
            if (path !== "" && !path.includes("image-missing"))
                return path;
        }

        if (root.appId) {
            let guessed = TaskbarApps.getCachedIcon(root.appId);
            if (guessed && guessed !== "image-missing") {
                let path = Quickshell.iconPath(guessed, true).toString();
                if (path !== "" && !path.includes("image-missing"))
                    return path;
            }
        }

        if (root.desktopEntry && root.desktopEntry.icon) {
            let guessed = AppSearch.guessIcon(root.desktopEntry.icon);
            if (guessed && guessed !== "image-missing") {
                let path = Quickshell.iconPath(guessed, true).toString();
                if (path !== "" && !path.includes("image-missing"))
                    return path;
            }
        }

        let fallback = root.desktopEntry?.icon || root.appId || "image-missing";
        return Quickshell.iconPath(fallback, "image-missing").toString();
    }

    readonly property bool isThemedIcon: {
        const path = root.iconPath.toString();
        if (path.includes("image-missing") || path.includes("application-x-executable") || path.includes("application-octet-stream"))
            return false;
        if (path.includes("/hicolor/") || path.includes("/pixmaps/"))
            return false;
        return path.includes("Mkos-Big-Sur");
    }

    Loader {
        id: adaptiveBackgroundLoader
        anchors.fill: parent
        active: Config.options.dock.enableShapeMask || root.isShellApp
        sourceComponent: MaterialShape {
            anchors.fill: parent
            shapeString: root.isShellApp ? root.resolvedShellShape : Config.options.dock.shapeMask
            visible: root.isShellApp || !root.isThemedIcon
            color: Appearance.colors.colPrimaryContainer
            opacity: root.iconOpacity
        }
    }

    MaterialSymbol {
        visible: root.isShellApp && root.shellMaterialIcon.length > 0
        anchors.centerIn: parent
        text: root.shellMaterialIcon
        iconSize: Math.round(Math.min(root.width, root.height) * 0.54)
        color: Config.options.dock.monochromeIcons
            ? Appearance.colors.colPrimary
            : Appearance.colors.colOnPrimaryContainer
        opacity: root.iconOpacity
    }

    Item {
        id: iconContent
        anchors.fill: parent
        visible: !root.isShellApp
        readonly property real adaptiveMargin: Config.options.dock.enableShapeMask && !root.isThemedIcon
            ? root.width * 0.18 : 0
        anchors.margins: adaptiveMargin

        IconImage {
            id: baseIcon
            anchors.fill: parent
            source: root.iconPath
            visible: !Config.options.dock.monochromeIcons
            opacity: root.iconOpacity
            asynchronous: false
            backer.cache: false
            backer.sourceSize: Qt.size(Math.ceil(parent.width * root.renderScale) + TaskbarApps.iconThemeRevision,
                Math.ceil(parent.height * root.renderScale) + TaskbarApps.iconThemeRevision)
            backer.mipmap: root.renderScale > 1

            layer.enabled: Config.options.dock.enableShapeMask && root.isThemedIcon && adaptiveBackgroundLoader.item !== null
            layer.textureSize: Qt.size(Math.ceil(width * root.renderScale), Math.ceil(height * root.renderScale))
            layer.effect: OpacityMask {
                maskSource: adaptiveBackgroundLoader.item
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Loader {
            anchors.fill: parent
            active: !root.isRunning && !Config.options.dock.monochromeIcons && Config.options.dock.dimInactiveIcons
            sourceComponent: MultiEffect {
                anchors.fill: parent
                source: baseIcon
                saturation: -0.8
                opacity: baseIcon.opacity
            }
        }
    }

    Loader {
        active: Config.options.dock.monochromeIcons && !root.isShellApp
        anchors.fill: iconContent
        sourceComponent: MultiEffect {
            anchors.fill: parent
            source: baseIcon
            saturation: -0.8
            colorization: 1.0 - Config.options.appearance.iconTintPercentage
            colorizationColor: Appearance.colors.colPrimary
        }
    }
}
