import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "./widgets"
import "utilities/DockUtilityCatalog.js" as DockUtilityCatalog
import "utilities/UtilityFiles.js" as UtilityFiles

/**
 * The dock's host for one utility widget (see utilities/DockUtilityCatalog.js).
 *
 * Everything the dock asks of a widget lives here once, so a tile only draws
 * its state: drag-to-reorder, the lens scale, the tooltip, files dropped on
 * it, the right-click menu (Square/Wide, Settings, Remove) and the panel a
 * click opens. The tile is loaded synchronously from utilities/<file>Tile.qml
 * and gets this host as `host`; the panel (<file>Panel.qml) gets it too.
 *
 * Tile contract (all optional, see utilities/UtilityTile.qml):
 *   tooltipText, panelSubtitle, panelWidth
 *   menuActions: [{ id, icon, text }]   extra rows on top of the menu
 *   function activate(): bool           a click; false opens the panel
 *   function menuAction(id)
 *   function dropFiles(urls)            for kinds with `drops`
 *   function exportPaths(): [path]      files handed over when the widget is
 *                                       dragged off the dock
 */
Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1
    property string kind: ""
    property bool wide: false

    readonly property var info: DockUtilityCatalog.find(root.kind)
    readonly property string title: root.info ? Translation.tr(root.info.title) : ""
    readonly property string symbol: root.info?.symbol ?? "widgets"
    readonly property bool hasPanel: root.info?.panel ?? false
    readonly property bool acceptsDrops: root.info?.drops ?? false

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    // The body a tile draws in: an icon-sized square, or the card of a wide
    // widget inset like the other dock cards.
    readonly property real bodyWidth: root.wide ? Math.max(0, root.width - root.dotMargin * 2) : root.buttonSize
    readonly property real bodyHeight: root.wide ? Math.max(0, root.height - root.dotMarginV * 2) : root.buttonSize
    readonly property real widgetRadius: (Config.options?.dock?.widgetRadius ?? -1) >= 0
        ? Config.options.dock.widgetRadius
        : (Appearance.rounding.windowRounding + 12)
    readonly property real bodyRadius: root.wide
        ? root.widgetRadius
        : Math.min(root.widgetRadius, Math.round(root.buttonSize * 0.3))

    // The lens's largest enlargement: tiles draw shapes and pictures this
    // much larger so they stay sharp while magnified.
    readonly property real renderScale: root.dockContent?.magnificationRenderScale ?? 1

    // Nothing ticks while the dock is away.
    readonly property bool live: root.dockContent?.dockWidgetsActive ?? true
    readonly property bool hovered: interaction.containsMouse
    property bool dropHovering: false
    readonly property bool panelOpen: panel.active && !panel.isClosing
    readonly property Item tile: tileLoader.item

    readonly property real contentMagnification: root.dockContent ? root.dockContent._getSlotMagScale(root) : 1.0
    scale: root.contentMagnification
    transformOrigin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom

    function openPanel() {
        if (root.hasPanel)
            panel.open();
    }

    function closePanel() {
        panel.close();
    }

    function togglePanel() {
        if (root.panelOpen)
            panel.close();
        else
            root.openPanel();
    }

    function exportFiles() {
        const tile = root.tile;
        if (!tile || typeof tile.exportPaths !== "function")
            return null;
        const paths = tile.exportPaths() ?? [];
        if (paths.length === 0)
            return null;
        return {
            uriList: UtilityFiles.uriList(paths),
            icon: paths.length === 1 && UtilityFiles.isImage(paths[0]) ? "image-x-generic" : "text-x-generic"
        };
    }

    Component.onCompleted: root.dockContent?.registerUtilityHost(root.kind, root)
    onKindChanged: root.dockContent?.registerUtilityHost(root.kind, root)

    function _activate() {
        const tile = root.tile;
        if (tile && typeof tile.activate === "function" && tile.activate())
            return;
        root.togglePanel();
    }

    function _fileUrls(drop) {
        const urls = [];
        for (const url of drop.urls ?? [])
            urls.push(url.toString());
        if (urls.length === 0 && drop.hasText) {
            for (const line of String(drop.text).split(/\r?\n/)) {
                if (line.indexOf("file://") === 0)
                    urls.push(line.trim());
            }
        }
        return urls;
    }

    // ── Hover, click and drag-to-reorder, under the tile ───────────────────
    // A press that travels drags the widget; one that stays is a click. The
    // tile's own buttons sit above and take their presses first.
    MouseArea {
        id: interaction
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        preventStealing: true
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property real pressCoord: 0
        property bool dragActive: false

        onEntered: root.dockContent?.onButtonEntered(root)
        onExited: root.dockContent?.onButtonExited(root)
        onPressed: event => pressCoord = root.isVertical ? event.y : event.x
        onPositionChanged: event => {
            if (!pressed || !(pressedButtons & Qt.LeftButton))
                return;
            const cur = root.isVertical ? event.y : event.x;
            if (!dragActive && Math.abs(cur - pressCoord) > 5 && root.delegateIndex >= 0) {
                dragActive = true;
                root.dockContent?.startItemDrag(root.delegateIndex, interaction, event.x, event.y);
            }
            if (dragActive)
                root.dockContent?.moveItemDrag(interaction, event.x, event.y);
        }
        onReleased: event => {
            if (dragActive) {
                dragActive = false;
                root.dockContent?.endItemDrag();
                return;
            }
            if (event.button === Qt.RightButton)
                widgetMenu.open();
            else if (event.button === Qt.MiddleButton)
                root.togglePanel();
            else
                root._activate();
        }
        onCanceled: {
            if (!dragActive)
                return;
            dragActive = false;
            root.dockContent?.cancelDrag();
        }
    }

    Loader {
        id: tileLoader
        z: 1
        x: (root.width - root.bodyWidth) / 2
        y: (root.height - root.bodyHeight) / 2
        width: root.bodyWidth
        height: root.bodyHeight
        asynchronous: false
        function load() {
            if (!root.info) {
                tileLoader.source = "";
                return;
            }
            tileLoader.setSource(Qt.resolvedUrl("utilities/" + root.info.file + "Tile.qml"), { host: root });
        }
        Component.onCompleted: load()
        Connections {
            target: root
            function onKindChanged() { tileLoader.load(); }
        }
    }

    DropArea {
        anchors.fill: parent
        z: 2
        enabled: root.acceptsDrops
        keys: ["text/uri-list"]
        onEntered: drag => {
            root.dropHovering = true;
            drag.accept(Qt.CopyAction);
        }
        onExited: root.dropHovering = false
        onDropped: drop => {
            root.dropHovering = false;
            const urls = root._fileUrls(drop);
            if (urls.length > 0 && root.tile && typeof root.tile.dropFiles === "function") {
                root.tile.dropFiles(urls);
                drop.accept(Qt.CopyAction);
            }
        }
    }

    DockTooltip {
        parentItem: root
        text: root.tile?.tooltipText || root.title
        showTooltip: interaction.containsMouse && !root.panelOpen && !widgetMenu.active
        tooltipOffset: -root.dotMarginV
    }

    // ── Panel: the full view a click opens ─────────────────────────────────
    DockContextMenuBase {
        id: panel
        anchorItem: root
        headerText: root.title
        headerSubtitle: root.tile?.panelSubtitle ?? ""
        headerSymbol: root.symbol
        menuWidth: root.tile?.panelWidth ?? 340
        contentComponent: root.hasPanel ? panelComponent : null
    }

    Component {
        id: panelComponent
        Loader {
            id: panelLoader
            width: parent?.width ?? 0
            asynchronous: false
            Component.onCompleted: panelLoader.setSource(Qt.resolvedUrl("utilities/" + root.info.file + "Panel.qml"), { host: root })
        }
    }

    // ── Widget menu ─────────────────────────────────────────────────────────
    DockContextMenuBase {
        id: widgetMenu
        anchorItem: root
        headerText: root.title
        headerSubtitle: root.wide ? Translation.tr("Wide widget") : Translation.tr("Square widget")
        headerSymbol: root.symbol
        menuGroups: widgetMenu.menuOpen ? [
            (root.tile?.menuActions ?? []).concat(root.hasPanel ? [
                { id: "__panel", icon: "open_in_full", text: Translation.tr("Open") }
            ] : []),
            root.isVertical ? [] : [
                root.wide
                    ? { id: "__square", icon: "crop_square", text: Translation.tr("Make square") }
                    : { id: "__wide", icon: "crop_16_9", text: Translation.tr("Make wide") }
            ],
            [
                { id: "__settings", icon: "settings", text: Translation.tr("Widget settings") },
                { id: "__remove", icon: "remove_circle", text: Translation.tr("Remove from dock"), destructive: true }
            ]
        ].filter(group => group.length > 0) : []

        onActionTriggered: actionId => {
            widgetMenu.close();
            switch (actionId) {
            case "__panel":
                root.openPanel();
                break;
            case "__square":
                root.dockContent?.setUtilityWide(root.kind, false);
                break;
            case "__wide":
                root.dockContent?.setUtilityWide(root.kind, true);
                break;
            case "__settings":
                GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
                break;
            case "__remove":
                root.dockContent?.removeUtility(root.kind);
                break;
            default:
                if (root.tile && typeof root.tile.menuAction === "function")
                    root.tile.menuAction(actionId);
            }
        }
    }

    // Menus and the panel hold the dock open while they show.
    property int _heldPopups: 0
    function _holdDock(open) {
        if (!root.dockContent)
            return;
        if (open) {
            root._heldPopups++;
            root.dockContent.registerContextMenuOpen();
        } else if (root._heldPopups > 0) {
            root._heldPopups--;
            root.dockContent.registerContextMenuClose();
        }
    }
    Connections {
        target: panel
        function onActiveChanged() { root._holdDock(panel.active); }
    }
    Connections {
        target: widgetMenu
        function onActiveChanged() { root._holdDock(widgetMenu.active); }
    }
    Component.onDestruction: {
        root.dockContent?.unregisterUtilityHost(root.kind, root);
        while (root._heldPopups > 0)
            root._holdDock(false);
    }
}
