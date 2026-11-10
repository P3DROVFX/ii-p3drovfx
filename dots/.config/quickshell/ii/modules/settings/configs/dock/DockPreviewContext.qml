import QtQuick
import qs.modules.common

/**
 * Stands in for DockContent under the real dock buttons and widgets drawn by the
 * Settings preview, the way LockPreviewContext stands in for the lock: the geometry
 * they read is the dock's own (same formulas), and everything they would act on —
 * hover, drags, context menus, the lens — is inert. Lookups that only read go to
 * the live dock when there is one.
 */
QtObject {
    id: root

    /** The live DockContent, for read-only helpers (icons, app data). */
    property var live: null
    /** The preview asks its apps to play an animation: "launch" or "notification". */
    signal attentionRequested(string kind)
    property string dockPos: "bottom"
    readonly property bool isVertical: root.dockPos === "left" || root.dockPos === "right"

    readonly property real dotMargin: (Config.options?.dock?.height ?? 60) * 0.2 - 2
    readonly property real dotMarginV: root.dotMargin
    readonly property real buttonSlotSize: Appearance.sizes.dockButtonSize + root.dotMargin * 2
    readonly property real buttonSlotHeight: Appearance.sizes.dockButtonSize + root.dotMarginV * 2
    readonly property real sportsWidgetSlots: 4

    // No lens, no hover, no drag in a picture.
    readonly property real magnificationRenderScale: 1
    readonly property int magnificationTransformOrigin: root.dockPos === "top" ? Item.Top
        : root.dockPos === "left" ? Item.Left
        : root.dockPos === "right" ? Item.Right : Item.Bottom
    readonly property bool suppressHover: true
    readonly property bool buttonHovered: false
    readonly property var lastHoveredButton: null
    readonly property bool dragging: false
    readonly property bool dockRevealed: false
    readonly property bool dockWindowVisible: true
    /** Widgets load their content (the media widget is behind this in the dock). */
    property bool dockWidgetsActive: true
    readonly property var currentScreen: root.live?.currentScreen ?? null

    readonly property string groupTransitionKind: ""
    readonly property string groupTransitionGroupId: ""
    readonly property var groupTransitionAppIds: []
    readonly property int groupAnimationDuration: 0

    function _getSlotMagScale(slot) { return 1; }
    function onButtonEntered(button) {}
    function onButtonExited(button) {}
    function registerContextMenuOpen(menu) {}
    function registerContextMenuClose(menu) {}
    function startItemDrag() {}
    function moveItemDrag() {}
    function endItemDrag() {}
    function cancelDrag() {}
    function setUtilityWide() {}
    function registerUtilityHost() {}
    function unregisterUtilityHost() {}
    function removeUtility() {}
    function removeAppGroup() {}
    function isGroupExiting() { return false; }
    function isGroupEntryTransition() { return false; }
    function mimeIconFromPath(path) {
        return root.live ? root.live.mimeIconFromPath(path) : "folder";
    }
    function _appDataForId(appId) {
        return root.live ? root.live._appDataForId(appId) : null;
    }
}
