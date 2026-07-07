pragma ComponentBehavior: Bound
import qs.modules.ii.bar.core
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.shared
import qs.modules.ii.bar.widgets.weather

// Thin orchestrator — owns only:
//   • screen / monitor sizing props
//   • HyprlandData Connections (sets hasActiveWindows)
//   • BarContext (pure computed state, reads hasActiveWindows)
//   • BarLayout  (left/center/right list splitting)
//   • BarThemes  (active theme)
//   • transparent gradient Rectangle
//   • BarStyleLoader (style dispatch)
//
// Window / autohide / exclusiveZone → bar/core/BarWindow.qml
// Style rendering                   → bar/styles/ via BarStyleLoader
// Computed state                    → bar/core/BarContext.qml
// Layout splitting                  → bar/core/BarLayout.qml
Item {
    id: root

    implicitHeight: Appearance.sizes.barHeight
    height: implicitHeight

    // ── Monitor ───────────────────────────────────────────────────────────────
    property var screen: root.QsWindow.window?.screen
    property int monitorIndex
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    // ── Window tracking (Connections owned here, result fed to ctx) ───────────
    property bool hasActiveWindows: false
    Connections {
        enabled: Config.options.bar.barBackgroundStyle === 2 || (Config.options.bar.barBackgroundStyle === 3 && Config.options.bar.cornerStyle === 1)
        target: HyprlandData
        function onWindowListChanged() {
            const monitorName = root.screen ? root.screen.name : "";
            const monitor = monitorName ? HyprlandData.monitors.find(m => m.name === monitorName) : null;
            const wsId = monitor?.activeWorkspace?.id;
            root.hasActiveWindows = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
        }
    }

    // ── Computed state ────────────────────────────────────────────────────────
    BarContext {
        id: ctx
        screen: root.screen
        hasActiveWindows: root.hasActiveWindows
    }

    // ── Layout splitting ──────────────────────────────────────────────────────
    BarLayout {
        id: layout
    }

    // ── Theme ─────────────────────────────────────────────────────────────────
    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    readonly property real verticalTopOffset: styleLoader.verticalTopOffset
    readonly property real verticalBottomOffset: styleLoader.verticalBottomOffset

    // ── Style dispatch ────────────────────────────────────────────────────────
    BarStyleLoader {
        id: styleLoader
        anchors.fill: parent
        isDynamicIsland: ctx.isDynamicIsland
        showBarBackground: ctx.showBarBackground
        activeTheme: root.activeTheme
        screen: root.screen
        isSearchActiveHere: ctx.isSearchActiveHere
        expectedSearchWidth: ctx.expectedSearchWidth
        frameThickness: ctx.frameThickness
        leftList: layout.leftList
        centerList: layout.centerList
        rightList: layout.rightList
    }
}
