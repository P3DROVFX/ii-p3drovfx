import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.bar.widgets.weather
import qs.modules.ii.bar.shared
import qs.modules.ii.bar.registry
import qs.modules.ii.bar.groups

// Widget subdir imports (bar/widgets/<group>/)
import qs.modules.ii.bar.widgets.workspaces
import qs.modules.ii.bar.widgets.clock
import qs.modules.ii.bar.widgets.media
import qs.modules.ii.bar.widgets.battery
import qs.modules.ii.bar.widgets.bluetooth
import qs.modules.ii.bar.widgets.resources
import qs.modules.ii.bar.widgets.keyboard
import qs.modules.ii.bar.widgets.tray
import qs.modules.ii.bar.widgets.sports
import qs.modules.ii.bar.widgets.activeWindow
import qs.modules.ii.bar.widgets.dashboard
import qs.modules.ii.bar.widgets.power
import qs.modules.ii.bar.widgets.utilButtons
import qs.modules.ii.bar.widgets.policies
import qs.modules.ii.bar.widgets.timer
import qs.modules.ii.bar.widgets.indicators

import qs.modules.ii.verticalBar as Vertical

Item {
    id: rootItem

    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical

    property int barSection // 0: left, 1: center, 2: right
    property var list
    required property var modelData
    required property int index
    property var originalIndex: index
    property bool vertical: false
    property bool highlighted: false
    property color groupBgColor: (groupTheme.activated || groupTheme.highlighted) ? groupTheme.colBackgroundHighlight : groupTheme.colBackground
    property real groupStartRadius: groupTheme.startRadius
    property real groupEndRadius: groupTheme.endRadius

    // ── Smooth Slide and Move Animations ──────────────────────────────────────
    property real oldX: x
    property real oldY: y
    property bool isReady: false
    resources: [
        Translate {
            id: entryTranslation
            x: rootItem.vertical ? 15 : 0
            y: rootItem.vertical ? 0 : 15
        },
        Translate {
            id: moveTranslation
        },
        Translate {
            id: verticalTranslation
            y: 0
        }
    ]

    ParallelAnimation {
        id: entryAnimation
        running: true
        NumberAnimation {
            target: entryTranslation
            property: rootItem.vertical ? "x" : "y"
            from: rootItem.vertical ? 15 : 15
            to: 0
            duration: 400
            easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: wrapper
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        id: moveXAnimation
        target: moveTranslation
        property: "x"
        to: 0
        duration: 350
        easing.type: Easing.OutExpo
    }

    NumberAnimation {
        id: moveYAnimation
        target: moveTranslation
        property: "y"
        to: 0
        duration: 350
        easing.type: Easing.OutExpo
    }

    onXChanged: {
        if (rootItem.isReady) {
            let delta = rootItem.oldX - x;
            if (Math.abs(delta) > 1) {
                moveXAnimation.from = moveTranslation.x + delta;
                moveXAnimation.restart();
            }
        }
        rootItem.oldX = x;
    }

    onYChanged: {
        if (rootItem.isReady) {
            let delta = rootItem.oldY - y;
            if (Math.abs(delta) > 1) {
                moveYAnimation.from = moveTranslation.y + delta;
                moveYAnimation.restart();
            }
        }
        rootItem.oldY = y;
    }

    Timer {
        id: readyTimer
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            rootItem.oldX = rootItem.x;
            rootItem.oldY = rootItem.y;
            rootItem.isReady = true;
        }
    }

    // ── Notch Mode Integration ───────────────────────────────────────────────
    property var modeState: null

    readonly property bool isNotchActive: !!modeState && modeState.notchModeEnabled
    readonly property bool isNotchExpanded: !!modeState && modeState.expanded
    readonly property bool isWidgetVisibleInNotch: {
        if (!isNotchActive) return true;
        if (isNotchExpanded) return true;
        
        const isAllowed = Config.options.bar.dynamicIsland.notchMode.visibleWidgets.indexOf(modelData.id) !== -1;
        if (!isAllowed) return false;

        if (modelData.id === modeState._displayMode) return true;

        if (barSection !== 1) return false;
        return modelData.id === modeState._displayMode;
    }

    readonly property real targetWidth: isWidgetVisibleInNotch ? wrapper.implicitWidth : 0

    implicitWidth: targetWidth
    Behavior on implicitWidth {
        enabled: !rootItem.isNotchActive || rootItem.isNotchExpanded
        NumberAnimation {
            duration: rootItem.isNotchActive ? Config.options.bar.dynamicIsland.notchMode.expandAnimDuration : 250
            easing.type: rootItem.isNotchActive ? Easing.BezierSpline : Easing.OutBack
            easing.bezierCurve: rootItem.isNotchActive ? Appearance.animationCurves.emphasizedDecel : null
        }
    }

    opacity: 1.0
    visible: opacity > 0.01

    readonly property bool isNotchMode: isNotchActive && !isNotchExpanded

    states: [
        State {
            name: "visible"
            when: !rootItem.isNotchMode || rootItem.isWidgetVisibleInNotch
            PropertyChanges {
                target: verticalTranslation
                y: 0
            }
            PropertyChanges {
                target: rootItem
                opacity: 1.0
            }
        },
        State {
            name: "hidden"
            when: rootItem.isNotchMode && !rootItem.isWidgetVisibleInNotch
            PropertyChanges {
                target: verticalTranslation
                y: -20
            }
            PropertyChanges {
                target: rootItem
                opacity: 0.0
            }
        }
    ]

    transitions: [
        Transition {
            from: "hidden"; to: "visible"
            ParallelAnimation {
                NumberAnimation {
                    target: verticalTranslation
                    property: "y"
                    duration: rootItem.isNotchMode ? 350 : 0
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: rootItem
                    property: "opacity"
                    duration: rootItem.isNotchMode ? 300 : 150
                    easing.type: Easing.OutQuad
                }
            }
        },
        Transition {
            from: "visible"; to: "hidden"
            ParallelAnimation {
                NumberAnimation {
                    target: verticalTranslation
                    property: "y"
                    duration: rootItem.isNotchMode ? 300 : 0
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: rootItem
                    property: "opacity"
                    duration: rootItem.isNotchMode ? 250 : 150
                    easing.type: Easing.OutQuad
                }
            }
        }
    ]
    // ─────────────────────────────────────────────────────────────────────────

    implicitHeight: wrapper.implicitHeight

    // ── Registry ──────────────────────────────────────────────────────────────
    BarWidgetRegistry { id: registry }

    // Widget style resolution — single source of truth
    readonly property string widgetStyle: registry.getStyle(modelData.id)
    readonly property bool isExpressiveFromRegistry: widgetStyle === "expressive"
    readonly property bool isMinimal:    widgetStyle === "minimal"

    // ── Explicit style checks (HEAD) – keep them for maximum compatibility ──
    readonly property bool isMaterial: {
        if (modelData.id === "clock" && Config.options.bar.styles.clock === "material") {
            return true;
        }
        if (modelData.id === "keyboard_layout" && Config.options.bar.styles.keyboard === "material") {
            return true;
        }
        if (modelData.id === "battery" && Config.options.bar.styles.battery === "material") {
            return true;
        }
        return false;
    }
    readonly property bool isExpressive: {
        if (modelData.id === "clock" && Config.options.bar.styles.clock === "expressive")
            return true;
        if (modelData.id === "music_player" && (Config.options.bar.styles.media === "expressive" || Config.options.bar.styles.media === "neural"))
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
        if (modelData.id === "active_window" && Config.options.bar.styles.activeWindow === "expressive")
            return true;
        if (modelData.id === "record_indicator")
            return true;
        if (modelData.id === "phone_scrcpy_indicator")
            return true;
        return false;
    }

    // ── Radius convenience aliases (from upstream/dev) ──────────────────────
    property real startRadius: groupTheme.startRadius
    property real endRadius:   groupTheme.endRadius

    // ── Theme ─────────────────────────────────────────────────────────────────
    BarThemes { id: barThemes }
    property var activeTheme: barThemes.themes[Config.options.bar.expressiveColorTheme] || barThemes.themes["content"]

    // ── BarGroup wrapper ──────────────────────────────────────────────────────
    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        anchors {
            top: rootItem.vertical ? undefined : parent.top
            bottom: rootItem.vertical ? undefined : parent.bottom
            left: rootItem.vertical ? parent.left : undefined
            right: rootItem.vertical ? parent.right : undefined
            verticalCenter: rootItem.vertical ? rootItem.verticalCenter : undefined
            horizontalCenter: (rootItem.isNotchMode || rootItem.vertical) ? undefined : rootItem.horizontalCenter
        }

        x: rootItem.isNotchMode
            ? (rootItem.parent ? (rootItem.parent.width / 2 - rootItem.x - wrapper.implicitWidth / 2) : 0)
            : 0

        transform: [
            entryTranslation,
            moveTranslation,
            verticalTranslation
        ]

        readonly property bool paddingless: registry.isPaddingless(modelData.id, rootItem.isExpressive) || rootItem.isMaterial
            || (modelData.id === "music_player" && rootItem.widgetStyle === "neural" && rootItem.vertical)
        padding:       paddingless ? 0 : 5
        leftPadding:   paddingless ? 0 : padding
        rightPadding:  paddingless ? 0 : padding
        topPadding:    rootItem.vertical ? (paddingless ? 0 : padding) : 0
        bottomPadding: rootItem.vertical ? (paddingless ? 0 : padding) : 0

        startRadius: rootItem.startRadius
        endRadius:   rootItem.endRadius
        colBackground: (rootItem.isMaterial || rootItem.isExpressive) ? "transparent" : groupTheme.resolvedBackground

        Loader {
            id: itemLoader
            active: true
            sourceComponent: resolveComponent(modelData.id, rootItem.vertical, rootItem.widgetStyle)
            onLoaded: {
                if (item) {
                    if (item.hasOwnProperty("onActivatedColor")) {
                        item.onActivatedColor = Qt.binding(() => groupTheme.colOnBackgroundHighlight);
                    }
                    if (item.hasOwnProperty("groupBgColor")) {
                        item.groupBgColor = Qt.binding(() => rootItem.groupBgColor);
                    }
                    if (item.hasOwnProperty("groupStartRadius")) {
                        item.groupStartRadius = Qt.binding(() => rootItem.groupStartRadius);
                    }
                    if (item.hasOwnProperty("groupEndRadius")) {
                        item.groupEndRadius = Qt.binding(() => rootItem.groupEndRadius);
                    }
                    if (!rootItem.vertical) {
                        if (item.Layout !== undefined && item.Layout.fillHeight) {
                            item.height = Qt.binding(() => itemLoader.height);
                        }
                    } else {
                        if (item.Layout !== undefined && item.Layout.fillWidth) {
                            item.width = Qt.binding(() => itemLoader.width);
                        } else if (wrapper.paddingless) {
                            item.width = Qt.binding(() => Appearance.sizes.verticalBarWidth - 8);
                        }

                        if (item.Layout !== undefined && item.Layout.fillHeight) {
                            item.height = Qt.binding(() => itemLoader.height);
                        } else if (item.implicitWidth === item.implicitHeight) {
                            item.height = Qt.binding(() => item.width);
                        }
                    }
                }
            }
            Layout.fillHeight: item ? ((item.Layout !== undefined && item.Layout.fillHeight) || false) : false
            Layout.fillWidth: item ? ((item.Layout !== undefined && item.Layout.fillWidth) || false) : false
            Layout.alignment: rootItem.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }

    // ── Component resolution ──────────────────────────────────────────────────
    // Replaces compMap JS object. Adding a new widget: add one case here +
    // add the Component definition below + add getStyle() entry in registry.
    function resolveComponent(id, isVert, style) {
        const isExp = style === "expressive";
        const isMin = style === "minimal";
        switch (id) {
            case "workspaces":
                if (isMin) return workspaceCompMinimal;
                if (isExp) return workspaceCompExpressive;
                if (style === "dock") return workspaceCompDock;
                return workspaceComp;
            case "music_player":
                if (isExp) return musicPlayerCompExpressive;
                if (style === "neural") return isVert ? neuralMediaCompVert : neuralMediaComp;
                return isVert ? musicPlayerCompVert : musicPlayerComp;
            case "system_monitor":
                if (isExp) return systemMonitorCompExpressive;
                return isVert ? systemMonitorCompVert : systemMonitorComp;
            case "clock":
                if (isExp) return clockCompExpressive;
                return isVert ? clockCompVert : clockComp;
            case "battery":
                if (isExp) return batteryCompExpressive;
                return isVert ? batteryCompVert : batteryComp;
            case "keyboard_layout":
                if (isExp) return keyboardCompExpressive;
                return isVert ? keyboardCompVert : keyboardComp;
            case "utility_buttons":
                if (isExp) return utilityButtonsCompExpressive;
                return utilityButtonsComp;
            case "system_tray":
                if (isExp) return systemTrayCompExpressive;
                return systemTrayComp;
            case "active_window":
                if (isExp) return activeWindowCompExpressive;
                return activeWindowComp;
            case "weather":
                if (isExp) return weatherCompExpressive;
                return weatherComp;
            case "policies_panel_button":
                if (isExp) return policiesPanelButtonExpressive;
                return policiesPanelButton;
            case "dashboard_panel_button":
                if (isExp) return isVert ? dashboardPanelButtonExpressiveVert : dashboardPanelButtonExpressive;
                return isVert ? dashboardPanelButtonVert : dashboardPanelButton;
            case "bluetooth_devices":
                if (isExp) return bluetoothCompExpressive;
                return isVert ? bluetoothCompVert : bluetoothComp;
            case "sports":
                if (isExp) return sportsCompExpressive;
                return sportsComp;
            case "power":
                if (isExp) return powerCompExpressive;
                return powerComp;
            case "date":          return dateCompVert;
            case "timer":         return isVert ? timerCompVert : timerComp;
            case "record_indicator":        return recordIndicatorComp;
            case "phone_scrcpy_indicator":  return phoneScrcpyIndicatorComp;
            case "screen_share_indicator":  return screenshareIndicatorComp;
            default:              return null;
        }
    }

    // ── Visibility helpers ────────────────────────────────────────────────────
    function toggleVisible(visibility) {
        if (visible !== visibility) visible = visibility;
        let item = null;
        if (barSection == 0)      item = Config.options.bar.layouts.left[originalIndex];
        else if (barSection == 1) item = Config.options.bar.layouts.center[originalIndex];
        else if (barSection == 2) item = Config.options.bar.layouts.right[originalIndex];
        if (item !== undefined && item !== null) {
            if (item.visible !== visibility) item.visible = visibility;
        }
    }

    function toggleHighlight(highlight) {
        rootItem.highlighted = highlight;
    }

    // ── Group theme ────────────────────────────────────────────────────────────
    BarGroupTheme {
        id: groupTheme
        barSection:    rootItem.barSection
        list:          rootItem.list
        originalIndex: rootItem.originalIndex
        isExpressive:  rootItem.isExpressive
        highlighted:   rootItem.highlighted
        activated:     itemLoader.item?.activated ?? false
        activeTheme:   rootItem.activeTheme
        widgetId:      modelData.id
    }

    // ── Widget Components ─────────────────────────────────────────────────────
    // Default variants
    Component { id: weatherComp;           WeatherBar          { vertical: rootItem.vertical } }
    Component { id: timerComp;             TimerWidget         {} }
    Component { id: timerCompVert;         Vertical.VerticalTimerWidget {} }
    Component { id: screenshareIndicatorComp; ScreenShareIndicator {} }
    Component { id: recordIndicatorComp;   RecordIndicator     { vertical: rootItem.vertical } }
    Component { id: phoneScrcpyIndicatorComp; PhoneScrcpyIndicator { vertical: rootItem.vertical } }
    Component { id: activeWindowComp;      ActiveWindow        { vertical: rootItem.vertical } }
    Component { id: systemMonitorComp;     Resources           {} }
    Component { id: systemMonitorCompVert; Vertical.Resources  {} }
    Component { id: musicPlayerCompVert;   Vertical.VerticalMedia {} }
    Component { id: musicPlayerComp;       Media               {} }
    Component { id: neuralMediaComp;       NeuralMedia         { vertical: rootItem.vertical } }
    Component { id: neuralMediaCompVert;   Vertical.VerticalNeuralMedia {} }
    Component { id: utilityButtonsComp;    UtilButtons         { vertical: rootItem.vertical } }
    Component { id: batteryComp;           BatteryIndicator    {} }
    Component { id: batteryCompVert;       Vertical.BatteryIndicator {} }
    Component { id: clockCompVert;         Vertical.VerticalClockWidget {} }
    Component { id: clockComp;             ClockWidget         {} }
    Component { id: systemTrayComp;        SysTray             { vertical: rootItem.vertical } }
    Component { id: dateCompVert;          Vertical.VerticalDateWidget {} }
    Component { id: workspaceComp;         Workspaces          { vertical: rootItem.vertical } }
    Component { id: policiesPanelButton;   PoliciesPanelButton { startRadius: rootItem.startRadius; endRadius: rootItem.endRadius } }
    Component { id: dashboardPanelButton;  DashboardPanelButton { startRadius: rootItem.startRadius; endRadius: rootItem.endRadius } }
    Component { id: dashboardPanelButtonVert; VerticalDashboardPanelButton { startRadius: rootItem.startRadius; endRadius: rootItem.endRadius } }
    Component { id: bluetoothComp;         BluetoothDevicesWidget { vertical: rootItem.vertical } }
    Component { id: bluetoothCompVert;     Vertical.VerticalBluetoothDevicesWidget {} }
    Component { id: keyboardComp;          KeyboardLayoutWidget { vertical: rootItem.vertical } }
    Component { id: keyboardCompVert;      Vertical.VerticalKeyboardLayoutWidget {} }
    Component { id: sportsComp;            Sports              { vertical: rootItem.vertical } }
    Component { id: powerComp;             PowerButton         { vertical: rootItem.vertical } }

    // Expressive variants
    Component { id: weatherCompExpressive;        ExpressiveWeatherBar       { vertical: rootItem.vertical } }
    Component { id: musicPlayerCompExpressive;    ExpressiveMedia            { vertical: rootItem.vertical } }
    Component { id: utilityButtonsCompExpressive; ExpressiveUtilButtons      { vertical: rootItem.vertical } }
    Component { id: clockCompExpressive;          ExpressiveClockWidget      { vertical: rootItem.vertical } }
    Component { id: workspaceCompMinimal;         MinimalWorkspaces          { vertical: rootItem.vertical } }
    Component { id: workspaceCompExpressive;      ExpressiveWorkspaces       { vertical: rootItem.vertical } }
    Component { id: workspaceCompDock;            DockWorkspaces             { vertical: rootItem.vertical } }
    Component { id: systemMonitorCompExpressive;  ExpressiveResources        { vertical: rootItem.vertical } }
    Component { id: policiesPanelButtonExpressive; ExpressivePoliciesPanelButton { vertical: rootItem.vertical } }
    Component { id: dashboardPanelButtonExpressive;     ExpressiveDashboardPanelButton { vertical: false } }
    Component { id: dashboardPanelButtonExpressiveVert; ExpressiveDashboardPanelButton { vertical: true } }
    Component { id: powerCompExpressive;          ExpressivePowerButton      { vertical: rootItem.vertical } }
    Component { id: batteryCompExpressive;        ExpressiveBattery          { vertical: rootItem.vertical } }
    Component { id: systemTrayCompExpressive;     ExpressiveSystemTray       { vertical: rootItem.vertical } }
    Component { id: bluetoothCompExpressive;      ExpressiveBluetoothDevices { vertical: rootItem.vertical } }
    Component { id: keyboardCompExpressive;       ExpressiveKeyboardLayout   { vertical: rootItem.vertical } }
    Component { id: sportsCompExpressive;         ExpressiveSports           { vertical: rootItem.vertical } }
    Component { id: activeWindowCompExpressive;   ExpressiveActiveWindow     { vertical: rootItem.vertical } }
}