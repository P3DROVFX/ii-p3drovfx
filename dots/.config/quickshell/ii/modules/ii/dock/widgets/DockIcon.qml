import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property string appId: ""
    property var desktopEntry: null
    property bool isRunning: true
    property real iconOpacity: isRunning ? 1.0 : (Config.options.dock.dimInactiveIcons ? 0.55 : 1.0)

    readonly property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;
        let iconStr = root.desktopEntry && root.desktopEntry.icon ? root.desktopEntry.icon : TaskbarApps.getCachedIcon(root.appId);
        return Quickshell.iconPath(iconStr, "image-missing").toString();
    }

    // Detect if the icon is truly from the active system theme dynamically
    readonly property bool isThemedIcon: {
        const path = iconPath.toString();
        
        // 1. If it's a generic fallback or missing icon, it's NOT themed
        if (path.includes("image-missing") || path.includes("application-x-executable") || path.includes("application-octet-stream")) return false;
        
        // 2. If it's in a known fallback directory, it's NOT themed
        if (path.includes("/hicolor/") || path.includes("/pixmaps/")) return false;
        
        // 3. Dynamic check: if the path contains "Mkos-Big-Sur" (the known active theme)
        // This is more reliable as themed icons for this pack are stored in that specific path.
        if (path.includes("Mkos-Big-Sur")) return true;

        return false;
    }

    // DEBUG: Log the paths to help identify why some icons are not being detected
    // Timer { running: true; interval: 5000; onTriggered: console.log("[DockIcon]", root.appId, root.iconPath) }

    MaterialShape {
        id: adaptiveBg
        anchors.fill: parent
        shapeString: Config.options.dock.shapeMask
        visible: Config.options.dock.enableShapeMask && !root.isThemedIcon
        color: Appearance.colors.colPrimaryContainer

        Behavior on color {
            ColorAnimation { duration: 200 }
        }
    }

    Item {
        id: iconContentWrapper
        anchors.fill: parent
        // Apply margins only for non-themed (irregular) icons when adaptive mode is on
        readonly property real adaptiveMargin: (Config.options.dock.enableShapeMask && !root.isThemedIcon) ? root.width * 0.18 : 0
        anchors.margins: adaptiveMargin

        IconImage {
            id: baseIcon
            anchors.fill: parent
            source: root.iconPath
            visible: !Config.options.dock.monochromeIcons
            opacity: root.iconOpacity

            // Force reload when icon theme regenerates
            backer.sourceSize: Qt.size(parent.width + TaskbarApps.iconThemeRevision, parent.height + TaskbarApps.iconThemeRevision)

            layer.enabled: Config.options.dock.enableShapeMask && root.isThemedIcon
            layer.effect: OpacityMask {
                maskSource: adaptiveBg
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
        anchors.fill: parent
        sourceComponent: Item {
            Desaturate {
                id: monoDesat
                anchors.fill: parent
                source: baseIcon
                desaturation: 0.8
                visible: false
            }
            ColorOverlay {
                anchors.fill: parent
                source: monoDesat
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
            }
        }
    }
}
