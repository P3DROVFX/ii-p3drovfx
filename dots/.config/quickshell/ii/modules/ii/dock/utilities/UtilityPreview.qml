import QtQuick
import qs.modules.common
import "DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * A utility tile outside the dock (Settings, Edit Mode): the real tile, with
 * this item standing in for the dock host. It reads live state like the dock
 * copy does, but takes no input and opens nothing.
 *
 * Sized like the dock: `buttonSize` is the square face, a wide face spans
 * three slots minus the dot margins, exactly as DockContent lays it out.
 */
Item {
    id: preview

    property string kind: ""
    property bool wide: false
    property real buttonSize: Appearance.sizes.dockButtonSize
    property real dotMargin: Math.max(1, Math.round(preview.buttonSize / 0.85 * 0.2) - 2)
    property bool interactive: false

    // Host contract read by UtilityTile.
    readonly property bool isVertical: false
    readonly property bool live: preview.visible
    readonly property bool hovered: false
    readonly property bool dropHovering: false
    readonly property bool panelOpen: false
    property real renderScale: 1
    readonly property real slotSize: preview.buttonSize + preview.dotMargin * 2
    // The dock host's corner rule (DockUtilityWidget.bodyRadius).
    readonly property real widgetRadius: (Config.options?.dock?.widgetRadius ?? -1) >= 0
        ? Config.options.dock.widgetRadius
        : (Appearance.rounding.windowRounding + 12)
    readonly property real bodyRadius: preview.wide
        ? preview.widgetRadius
        : Math.min(preview.widgetRadius, Math.round(preview.buttonSize * 0.3))
    readonly property Item tile: tileLoader.item
    function openPanel() {}
    function closePanel() {}

    readonly property var info: DockUtilityCatalog.find(preview.kind)

    implicitWidth: preview.wide
        ? preview.slotSize * DockUtilityCatalog.wideSlotsFor(preview.kind) - preview.dotMargin * 2
        : preview.buttonSize
    implicitHeight: preview.buttonSize

    Loader {
        id: tileLoader
        anchors.fill: parent
        asynchronous: false
        enabled: preview.interactive
        function load() {
            if (!preview.info) {
                tileLoader.source = "";
                return;
            }
            tileLoader.setSource(Qt.resolvedUrl(preview.info.file + "Tile.qml"), { host: preview });
        }
        Component.onCompleted: load()
        Connections {
            target: preview
            function onKindChanged() { tileLoader.load(); }
        }
    }
}
