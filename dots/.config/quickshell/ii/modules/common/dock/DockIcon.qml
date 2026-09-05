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
    property real iconOpacity: isRunning ? 1.0 : (Config.options.dock.dimInactiveIcons ? 0.55 : 1.0)

    readonly property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;

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

    MaterialShape {
        id: adaptiveBackground
        anchors.fill: parent
        shapeString: Config.options.dock.shapeMask
        visible: Config.options.dock.enableShapeMask && !root.isThemedIcon
        color: root.isRunning ? Appearance.colors.colPrimaryContainer
            : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.6)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Item {
        id: iconContent
        anchors.fill: parent
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
            backer.sourceSize: Qt.size(parent.width + TaskbarApps.iconThemeRevision,
                parent.height + TaskbarApps.iconThemeRevision)

            layer.enabled: Config.options.dock.enableShapeMask && root.isThemedIcon
            layer.effect: OpacityMask {
                maskSource: adaptiveBackground
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Desaturate {
            anchors.fill: parent
            source: baseIcon
            desaturation: 0.8
            visible: !root.isRunning && !Config.options.dock.monochromeIcons && Config.options.dock.dimInactiveIcons
            opacity: baseIcon.opacity
        }
    }

    Loader {
        active: Config.options.dock.monochromeIcons
        anchors.fill: iconContent
        sourceComponent: Item {
            Desaturate {
                id: monochromeSource
                anchors.fill: parent
                source: baseIcon
                desaturation: 0.8
                visible: false
            }
            ColorOverlay {
                anchors.fill: parent
                source: monochromeSource
                color: ColorUtils.transparentize(Appearance.colors.colPrimary,
                    Config.options.appearance.iconTintPercentage)
            }
        }
    }
}
