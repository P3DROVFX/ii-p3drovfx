import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.bar.weather

import qs.modules.ii.verticalBar as Vertical

Item {
    id: rootItem

    property int barSection // 0: left, 1: center, 2: right
    property var list
    required property var modelData
    required property int index
    property var originalIndex: index
    property bool vertical: false
    property bool highlighted: false

    implicitWidth: wrapper.implicitWidth
    implicitHeight: wrapper.implicitHeight

    function toggleVisible(visibility) {
        visible = visibility;
        let item = null;
        if (barSection == 0)
            item = Config.options.bar.layouts.left[originalIndex];
        else if (barSection == 1)
            item = Config.options.bar.layouts.center[originalIndex];
        else if (barSection == 2)
            item = Config.options.bar.layouts.right[originalIndex];

        if (item !== undefined && item !== null) {
            item.visible = visibility;
        }
    }

    function toggleHighlight(highlight) {
        rootItem.highlighted = highlight
    }

    property var compMap: ({ // [horizontal, vertical, expressiveHorizontal, expressiveVertical]
            "workspaces": [workspaceComp, workspaceComp, workspaceCompExpressive, workspaceCompExpressive, workspaceCompMinimal, workspaceCompMinimal],
            "music_player": [musicPlayerComp, musicPlayerCompVert, musicPlayerCompExpressive, musicPlayerCompExpressive],
            "system_monitor": [systemMonitorComp, systemMonitorCompVert, systemMonitorCompExpressive, systemMonitorCompExpressive],
            "clock": [clockComp, clockCompVert, clockCompExpressive, clockCompExpressive],
            "battery": [batteryComp, batteryCompVert, batteryCompExpressive, batteryCompExpressive],
            "utility_buttons": [utilityButtonsComp, utilityButtonsComp, utilityButtonsCompExpressive, utilityButtonsCompExpressive],
            "system_tray": [systemTrayComp, systemTrayComp, systemTrayComp, systemTrayComp],
            "active_window": [activeWindowComp, activeWindowComp],
            "date": [dateCompVert, dateCompVert],
            "record_indicator": [recordIndicatorComp, recordIndicatorComp],
            "screen_share_indicator": [screenshareIndicatorComp, screenshareIndicatorComp],
            "timer": [timerComp, timerCompVert],
            "weather": [weatherComp, weatherComp, weatherCompExpressive, weatherCompExpressive],
            "policies_panel_button": [policiesPanelButton, policiesPanelButton, policiesPanelButtonExpressive, policiesPanelButtonExpressive],
            "dashboard_panel_button": [dashboardPanelButton, dashboardPanelButtonVert, dashboardPanelButtonExpressive, dashboardPanelButtonExpressiveVert],
            "bluetooth_devices": [bluetoothComp, bluetoothCompVert, bluetoothCompExpressive, bluetoothCompExpressive],
            "keyboard_layout": [keyboardComp, keyboardCompVert, keyboardCompExpressive, keyboardCompExpressive],
            "sports": [sportsComp, sportsComp, sportsCompExpressive, sportsCompExpressive],
            "power": [powerComp, powerComp, powerCompExpressive, powerCompExpressive]
        })

    readonly property bool isMinimal: {
        if (modelData.id === "workspaces" && Config.options.bar.styles.workspaces === "minimal")
            return true;
        return false;
    }

    readonly property bool isExpressive: {
        if (modelData.id === "clock" && Config.options.bar.styles.clock === "expressive")
            return true;
        if (modelData.id === "music_player" && Config.options.bar.styles.media === "expressive")
            return true;
        if (modelData.id === "workspaces" && Config.options.bar.styles.workspaces === "expressive")
            return true;
        if (modelData.id === "utility_buttons" && Config.options.bar.styles.utilButtons === "expressive")
            return true;
        if (modelData.id === "weather" && Config.options.bar.styles.weather === "expressive")
            return true;
        if (modelData.id === "dashboard_panel_button" && Config.options.bar.styles.dashboard === "expressive")
            return true;
        if (modelData.id === "system_monitor" && Config.options.bar.styles.resources === "expressive")
            return true;
        if (modelData.id === "policies_panel_button" && Config.options.bar.styles.policies === "expressive")
            return true;
        if (modelData.id === "power" && Config.options.bar.styles.power === "expressive")
            return true;
        if (modelData.id === "battery" && Config.options.bar.styles.battery === "expressive")
            return true;
        if (modelData.id === "system_tray" && Config.options.bar.styles.systray === "expressive")
            return true;
        if (modelData.id === "bluetooth_devices" && Config.options.bar.styles.bluetooth === "expressive")
            return true;
        if (modelData.id === "keyboard_layout" && Config.options.bar.styles.keyboard === "expressive")
            return true;
        if (modelData.id === "sports" && Config.options.bar.styles.sports === "expressive")
            return true;
        return false;
    }

    property list<string> primaryBackgroundComps: ["timer", "record_indicator", "screen_share_indicator"] // components that are mostly indicators

    property real startRadius: {
        if (barGroupStyle === 1)
            return Appearance.rounding.windowRounding;
        if (barSection === 0) {
            if (originalIndex == 0)
                return Appearance.rounding.full;
            return Appearance.rounding.verysmall;
        } else if (barSection === 2) {
            let hasVisibleLeft = list.slice(0, originalIndex).some(item => item.visible !== false);
            return hasVisibleLeft ? Appearance.rounding.verysmall : Appearance.rounding.full;
        } else { // barSection 1
            if (list.length === 1)
                return Appearance.rounding.full;
            let hasVisibleLeft = list.slice(0, originalIndex).some(item => item.visible !== false);
            return hasVisibleLeft ? Appearance.rounding.verysmall : Appearance.rounding.full;
        }
    }

    property real endRadius: {
        if (barGroupStyle === 1)
            return Appearance.rounding.windowRounding;
        if (barSection === 2) {
            if (originalIndex == list.length - 1)
                return Appearance.rounding.full;
            return Appearance.rounding.verysmall;
        } else if (barSection === 0) {
            let hasVisibleRight = list.slice(originalIndex + 1).some(item => item.visible !== false);
            return hasVisibleRight ? Appearance.rounding.verysmall : Appearance.rounding.full;
        } else { // barSection 1
            if (list.length === 1)
                return Appearance.rounding.full;
            let hasVisibleRight = list.slice(originalIndex + 1).some(item => item.visible !== false);
            return hasVisibleRight ? Appearance.rounding.verysmall : Appearance.rounding.full;
        }
    }

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.themes[Config.options.bar.expressiveColorTheme] || barThemes.themes["content"]

    readonly property int barGroupStyle: Config.options.bar.barGroupStyle
    readonly property int barBackgroundStyle: Config.options.bar.barBackgroundStyle
    property color colBackground: Config.options.bar.expressiveColors ? activeTheme.componentBackground : (barGroupStyle == 0 ? Appearance.colors.colLayer1 : (barGroupStyle == 1 && barBackgroundStyle == 1) ? Appearance.colors.colLayer1 : (barGroupStyle == 1) ? Appearance.m3colors.m3surfaceContainerLow : "transparent")

    property color colBackgroundHighlight: {
        if (Config.options.bar.expressiveColors)
            return activeTheme.highlight;
        if (modelData.id === "sports")
            return barGroupStyle == 2 ? "transparent" : Appearance.colors.colPrimaryContainer;
        return Appearance.colors.colPrimary;
    }

    property color colOnBackgroundHighlight: {
        if (Config.options.bar.expressiveColors)
            return ColorUtils.getContrastingTextColor(colBackgroundHighlight);
        if (modelData.id === "sports")
            return barGroupStyle == 2 ? Appearance.colors.colOnSurface : Appearance.colors.colOnPrimaryContainer;
        return Appearance.colors.colOnPrimary;
    }

    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        anchors {
            verticalCenter: rootItem.vertical ? rootItem.verticalCenter : undefined
            horizontalCenter: rootItem.vertical ? undefined : rootItem.horizontalCenter
        }

        padding: (rootItem.isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker) || modelData.id === "dashboard_panel_button" || modelData.id === "policies_panel_button") ? 0 : 5
        leftPadding: (rootItem.isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker)) ? 0 : padding
        rightPadding: (rootItem.isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker)) ? 0 : padding
        topPadding: (rootItem.isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker)) ? 0 : padding
        bottomPadding: (rootItem.isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker)) ? 0 : padding
        startRadius: rootItem.startRadius
        endRadius: rootItem.endRadius
        colBackground: (isExpressive || (modelData.id === "system_monitor" && Config.options.bar.resources.showDocker)) ? "transparent" : ((itemLoader.item?.activated || rootItem.highlighted) ? rootItem.colBackgroundHighlight : rootItem.colBackground)

        Loader {
            id: itemLoader
            active: true
            sourceComponent: {
                let comps = compMap[modelData.id];
                if (!comps)
                    return null;
                let isVert = vertical ? 1 : 0;
                let isExpressive = rootItem.isExpressive;
                let isMinimal = rootItem.isMinimal;

                if (isMinimal && comps.length > 4 && comps[isVert + 4]) {
                    return comps[isVert + 4];
                }
                if (isExpressive && comps.length > 2 && comps[isVert + 2]) {
                    return comps[isVert + 2];
                }
                return comps[isVert];
            }
            onLoaded: {
                if (item && item.hasOwnProperty("onActivatedColor")) {
                    item.onActivatedColor = Qt.binding(() => rootItem.colOnBackgroundHighlight);
                }
            }
        }
    }

    Component {
        id: weatherComp
        WeatherBar {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: timerComp
        TimerWidget {}
    }
    Component {
        id: timerCompVert
        Vertical.VerticalTimerWidget {}
    }

    Component {
        id: screenshareIndicatorComp
        ScreenShareIndicator {}
    }

    Component {
        id: recordIndicatorComp
        RecordIndicator {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: activeWindowComp
        ActiveWindow {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: systemMonitorComp
        Resources {}
    }
    Component {
        id: systemMonitorCompVert
        Vertical.Resources {}
    }

    Component {
        id: musicPlayerCompVert
        Vertical.VerticalMedia {}
    }
    Component {
        id: musicPlayerComp
        Media {}
    }

    Component {
        id: utilityButtonsComp
        UtilButtons {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: batteryComp
        BatteryIndicator {}
    }
    Component {
        id: batteryCompVert
        Vertical.BatteryIndicator {}
    }

    Component {
        id: clockCompVert
        Vertical.VerticalClockWidget {}
    }
    Component {
        id: clockComp
        ClockWidget {}
    }

    Component {
        id: systemTrayComp
        SysTray {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: dateCompVert
        Vertical.VerticalDateWidget {}
    }

    Component {
        id: workspaceComp
        Workspaces {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: policiesPanelButton
        PoliciesPanelButton {
            startRadius: rootItem.startRadius
            endRadius: rootItem.endRadius
        }
    }

    Component {
        id: dashboardPanelButton
        DashboardPanelButton {
            startRadius: rootItem.startRadius
            endRadius: rootItem.endRadius
        }
    }
    Component {
        id: dashboardPanelButtonVert
        VerticalDashboardPanelButton {
            startRadius: rootItem.startRadius
            endRadius: rootItem.endRadius
        }
    }

    Component {
        id: bluetoothComp
        BluetoothDevicesWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: bluetoothCompVert
        Vertical.VerticalBluetoothDevicesWidget {}
    }
    Component {
        id: keyboardComp
        KeyboardLayoutWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: keyboardCompVert
        Vertical.VerticalKeyboardLayoutWidget {}
    }
    Component {
        id: sportsComp
        Sports {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: weatherCompExpressive
        ExpressiveWeatherBar {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: musicPlayerCompExpressive
        ExpressiveMedia {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: utilityButtonsCompExpressive
        ExpressiveUtilButtons {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: clockCompExpressive
        ExpressiveClockWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: workspaceCompMinimal
        MinimalWorkspaces {
            vertical: rootItem.vertical
        }
    }

    Component {
        id: workspaceCompExpressive
        ExpressiveWorkspaces {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: systemMonitorCompExpressive
        ExpressiveResources {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: policiesPanelButtonExpressive
        ExpressivePoliciesPanelButton {}
    }
    Component {
        id: dashboardPanelButtonExpressive
        ExpressiveDashboardPanelButton {
            vertical: false
        }
    }
    Component {
        id: dashboardPanelButtonExpressiveVert
        ExpressiveDashboardPanelButton {
            vertical: true
        }
    }
    Component {
        id: powerComp
        PowerButton {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: powerCompExpressive
        ExpressivePowerButton {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: batteryCompExpressive
        ExpressiveBattery {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: systemTrayCompExpressive
        ExpressiveSystemTray {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: bluetoothCompExpressive
        ExpressiveBluetoothDevices {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: keyboardCompExpressive
        ExpressiveKeyboardLayout {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: sportsCompExpressive
        ExpressiveSports {
            vertical: rootItem.vertical
        }
    }
}
