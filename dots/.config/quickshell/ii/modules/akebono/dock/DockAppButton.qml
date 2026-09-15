import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.akebono
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

Item {
    id: root
    required property var appEntry
    required property var dockApps
    property real slotX: 0
    property int iconSize: 36
    property bool dragging: false
    property bool spawned: false
    property bool fadeIn: false
    property bool ready: false

    Component.onCompleted: {
        root.fadeIn = root.dockApps.isNew(root.appEntry.appId);
        if (!root.fadeIn)
            root.spawned = true;
        Qt.callLater(() => {
            root.spawned = true;
            root.ready = true;
        });
    }

    readonly property bool running: root.appEntry.toplevels.length > 0
    readonly property bool active: root.appEntry.toplevels.some(t => t.activated === true)
    readonly property var desktopEntry: DesktopEntries.applications.values.length > 0 ? (DesktopEntries.byId(root.appEntry.appId) ?? DesktopEntries.heuristicLookup(root.appEntry.appId)) : null

    readonly property var hyprClients: root.appEntry.toplevels
        .map(t => HyprlandData.clientForToplevel(t))
        .filter(c => c)
    readonly property bool minimized: root.running && root.hyprClients.length > 0
        && root.hyprClients.every(c => AkebonoStash.isStashed(c))

    function minimizeApp() {
        for (const c of root.hyprClients)
            AkebonoStash.minimize(c.address);
    }
    function restoreApp() {
        for (const c of root.hyprClients)
            AkebonoStash.restore(c.address);
    }

    z: root.dragging ? 2 : 1
    opacity: root.spawned ? 1 : 0
    Behavior on opacity {
        enabled: root.fadeIn
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on x {
        enabled: root.ready && !root.dragging
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Binding {
        target: root
        property: "x"
        value: root.slotX
        when: !root.dragging
    }

    transformOrigin: Item.Bottom
    scale: appMouseArea.containsMouse && !root.dragging ? 1.1 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    IconImage {
        id: appIcon
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        implicitSize: root.iconSize
        source: Quickshell.iconPath(AppSearch.guessIcon(root.appEntry.appId), "image-missing")
    }

    Loader {
        active: Config.options.dock.monochromeIcons
        anchors.fill: appIcon
        sourceComponent: Item {
            Desaturate {
                id: desaturatedIcon
                visible: false
                anchors.fill: parent
                source: appIcon
                desaturation: 0.8
            }
            ColorOverlay {
                anchors.fill: desaturatedIcon
                source: desaturatedIcon
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
            }
        }
    }

    Rectangle {
        visible: root.running
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        implicitWidth: root.minimized ? 7 : (root.active ? 11 : 5)
        implicitHeight: root.minimized ? 7 : 5
        radius: height / 2
        color: root.minimized ? "transparent"
            : root.active ? Appearance.colors.colPrimary
            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
        border.width: root.minimized ? 1.5 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
        Behavior on implicitWidth {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on implicitHeight {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: appMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.target: root
        drag.axis: Drag.XAxis
        drag.threshold: 6
        onEntered: {
            if (!root.dragging) root.dockApps.bumpRequested(root.x + root.width / 2, root.appEntry);
        }
        onExited: {
            if (!root.dragging) root.dockApps.bumpCleared();
        }
        onPositionChanged: {
            if (drag.active) {
                root.dragging = true;
                root.dockApps.moveTo(root.appEntry.appId, root.x);
            }
        }
        onReleased: mouse => {
            if (root.dragging) {
                root.dragging = false;
                root.dockApps.commit();
            } else if (mouse.button === Qt.RightButton) {
                root.dockApps.menuRequested(root.x + root.width / 2, root.appEntry);
            } else if (mouse.button === Qt.MiddleButton) {
                root.desktopEntry?.execute();
            } else if (!root.running) {
                root.desktopEntry?.execute();
            } else if (root.dockApps.minimizeFocused && root.minimized) {
                root.restoreApp();
            } else if (root.dockApps.minimizeFocused && root.active) {
                root.minimizeApp();
            } else {
                root.appEntry.toplevels[root.appEntry.toplevels.length - 1].activate();
            }
        }
    }

    WheelHandler {
        onWheel: (event) => root.dockApps.scrollRequested(event.angleDelta.y < 0 ? 1 : -1, root.appEntry)
    }
}
