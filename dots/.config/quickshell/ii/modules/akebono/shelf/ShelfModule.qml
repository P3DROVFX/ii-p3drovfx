import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.dock
import qs.modules.akebono.shelf.widgets
import qs.modules.ii.bar.groups
import qs.modules.ii.bar.registry
import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../ii/bar/widgets/dashboard"

Item {
    id: module
    property var shelf
    required property var modelData
    required property int index
    property var list: []
    property int barSection: 0

    readonly property bool present: modelData.visible !== false
    readonly property string style: widgetRegistry.getStyle(modelData.id)

    Layout.alignment: Qt.AlignVCenter
    visible: present && !(itemLoader.item?.shelfEmpty ?? false)
    implicitWidth: visible ? (itemLoader.item?.implicitWidth ?? 0) : 0
    implicitHeight: visible ? (itemLoader.item?.implicitHeight ?? 0) : 0

    // ── Bar group logic ────────────────────────────────────────────────────────
    // The shelf reuses the bar's own neighbour-aware pill logic (BarGroupTheme):
    // a module squares off the side facing an adjacent module (verysmall) and
    // keeps a full capsule on its outside edge, exactly like a BarComponent on
    // the bar. Colors follow bar appearance settings too (barGroupStyle,
    // barBackgroundStyle) via the same theme instance.
    BarThemes {
        id: groupThemes
    }
    BarWidgetRegistry { id: widgetRegistry }
    property var activeTheme: groupThemes.themes[Config.options.bar.expressiveColorTheme] || groupThemes.themes["content"]

    BarGroupTheme {
        id: groupTheme
        barSection: module.barSection
        list: module.list
        originalIndex: module.index
        isExpressive: false
        highlighted: false
        activated: itemLoader.item?.activated ?? false
        activeTheme: module.activeTheme
        widgetId: module.modelData.id
    }

    HoverHandler {
        id: moduleHover
        enabled: module.present
        cursorShape: undefined
    }

    readonly property var compMap: ({
        "launcher": launcherComp,
        "workspaces": workspacesComp,
        "clock": clockComp,
        "date": dateComp,
        "search": searchComp,
        "visualizer": visualizerComp,
        "network_speed": networkSpeedComp,
        "battery": batteryComp,
        "keyboard_layout": keyboardComp,
        "power": powerComp,
        "active_window": activeWindowComp,
        "bluetooth_devices": bluetoothComp,
        "ai_plan_usage": aiPlanUsageComp,
        "sports": sportsComp,
        "policies_panel_button": policiesComp,
        "privacy_pill": privacyComp,
        "port_watcher": portWatcherComp,
        "util_buttons": utilButtonsComp,
        "system_tray": trayComp,
        "status": statusComp,
        "media": mediaComp,
        "weather": weatherComp,
        "resources": resourcesComp,
        "record": recordComp,
        "screenshare": screenshareComp,
        "timer": timerComp,
        "dashboard_panel_button": dashboardComp,
        "dictation_indicator": dictationComp,
        "phone_scrcpy_indicator": phoneScrcpyComp,
        "shell_update_indicator": shellUpdateComp,
        "mode_indicator": modeIndicatorComp,
        "dock_to_panel": dockToPanelComp
    })

    Loader {
        id: itemLoader
        anchors.centerIn: parent
        active: module.present
        sourceComponent: module.compMap[module.modelData.id] ?? null
        onLoaded: {
            const item = itemLoader.item;
            if (!item)
                return;
            // Same injection the bar's BarComponent performs: widgets that draw
            // their own chip consume the group's neighbour-aware radii and hover
            // state (see BarComponent.qml's groupStartRadius/groupEndRadius
            // bindings). Colours stay on AkebonoAppearance, which already mirrors
            // BarGroupTheme's resolvedBackground per appearance setting.
            if (item.hasOwnProperty("groupStartRadius"))
                item.groupStartRadius = Qt.binding(() => groupTheme.startRadius);
            if (item.hasOwnProperty("groupEndRadius"))
                item.groupEndRadius = Qt.binding(() => groupTheme.endRadius);
            if (item.hasOwnProperty("groupHovered"))
                item.groupHovered = Qt.binding(() => moduleHover.hovered);
        }
    }

    Component {
        id: launcherComp
        ShelfPill {
            id: launcherBtn
            implicitWidth: module.shelf.barHeight * 0.7
            implicitHeight: module.shelf.barHeight * 0.7
            hovered: launcherMouse.containsMouse

            Component.onCompleted: module.shelf.registerLauncherAnchor(launcherBtn)
            Component.onDestruction: module.shelf.unregisterLauncherAnchor(launcherBtn)
            onXChanged: module.shelf.publishLauncher()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "apps"
                iconSize: Math.round(module.shelf.barHeight * 0.4)
                color: Appearance.colors.colOnLayer1
            }
            MouseArea {
                id: launcherMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    module.shelf.publishLauncher();
                    GlobalStates.desktopRunnerOpen = !GlobalStates.desktopRunnerOpen;
                }
            }
        }
    }

    Component {
        id: workspacesComp
        ShelfWorkspaces {
            barHeight: module.shelf.barHeight
            style: module.style
        }
    }

    Component {
        id: clockComp
        ShelfClock {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: trayComp
        ShelfTray {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: dateComp
        ShelfDate {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: searchComp
        ShelfSearch {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: visualizerComp
        ShelfVisualizer {
            barHeight: module.shelf.barHeight
        }
    }

    Component {
        id: networkSpeedComp
        ShelfNetworkSpeed {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
        }
    }

    Component {
        id: batteryComp
        ShelfBattery {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: keyboardComp
        ShelfKeyboardLayout {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: powerComp
        ShelfPower {
            barHeight: module.shelf.barHeight
            style: module.style
        }
    }

    Component {
        id: activeWindowComp
        ShelfActiveWindow {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: bluetoothComp
        ShelfBluetooth {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: aiPlanUsageComp
        ShelfAiPlanUsage {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: sportsComp
        ShelfSports {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: policiesComp
        ShelfPolicies {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: privacyComp
        ShelfPrivacyIndicator {
            barHeight: module.shelf.barHeight
        }
    }

    Component {
        id: portWatcherComp
        ShelfPortWatcher {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: utilButtonsComp
        ShelfUtilButtons {
            barHeight: module.shelf.barHeight
            style: module.style
        }
    }

    Component {
        id: mediaComp
        ShelfMedia {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: weatherComp
        ShelfWeather {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: resourcesComp
        ShelfResources {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: statusComp
        Item {
            id: statusWrap
            readonly property real pillHeight: Math.max(module.shelf.barHeight * 0.7, Appearance.sizes.baseBarHeight)
            implicitWidth: statusHolder.item?.implicitWidth ?? statusWrap.pillHeight
            implicitHeight: statusHolder.item?.implicitHeight ?? statusWrap.pillHeight

            Component.onCompleted: {
                if (module.shelf?.registerStatusAnchor)
                    module.shelf.registerStatusAnchor(statusWrap);
                if (module.shelf?.publishStatus)
                    module.shelf.publishStatus();
            }
            Component.onDestruction: {
                if (module.shelf?.unregisterStatusAnchor)
                    module.shelf.unregisterStatusAnchor(statusWrap);
            }
            onXChanged: if (module.shelf?.publishStatus) module.shelf.publishStatus()

            Loader {
                id: statusHolder
                anchors.centerIn: parent
                sourceComponent: module.style === "expressive" ? statusExpressive
                    : module.style === "orbs" ? statusOrbs
                    : statusDefault
            }

            Component {
                id: statusDefault
                DashboardPanelButton {
                }
            }
            Component {
                id: statusExpressive
                ExpressiveDashboardPanelButton {
                    vertical: false
                }
            }
            Component {
                id: statusOrbs
                OrbsDashboardPanelButton {
                    vertical: false
                }
            }

            MouseArea {
                anchors.fill: parent
                z: 99
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: module.shelf?.toggleQuickSettings()
            }
        }
    }

    Component {
        id: recordComp
        ShelfRecord {
            barHeight: module.shelf.barHeight
        }
    }

    Component {
        id: screenshareComp
        ShelfScreenShare {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
        }
    }

    Component {
        id: timerComp
        ShelfTimer {
            barHeight: module.shelf.barHeight
            style: module.style
        }
    }

    Component {
        id: dashboardComp
        ShelfDashboard {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
            style: module.style
        }
    }

    Component {
        id: dictationComp
        ShelfDictation {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
        }
    }

    Component {
        id: phoneScrcpyComp
        ShelfPhoneScrcpy {
            barHeight: module.shelf.barHeight
        }
    }

    Component {
        id: shellUpdateComp
        ShelfShellUpdate {
            barHeight: module.shelf.barHeight
        }
    }

    Component {
        id: modeIndicatorComp
        ShelfModeIndicator {
            barHeight: module.shelf.barHeight
            shelf: module.shelf
        }
    }

    Component {
        id: dockToPanelComp
        ShelfDockToPanel {
            barHeight: module.shelf.barHeight
        }
    }
}
