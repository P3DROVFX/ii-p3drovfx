import qs
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
import qs.modules.ii.bar.widgets.dockToPanel
import qs.modules.ii.bar.widgets.portWatcher
import qs.modules.ii.bar.widgets.privacy
import qs.modules.ii.bar.widgets.aiPlanUsage
import "widgets/search"
import "widgets/date"

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

    // ── Growth anchor ─────────────────────────────────────────────────────────
    // Which edge a widget stays pinned to while it changes size. Every bar
    // section is anchored to one edge of the bar and lays its widgets out from
    // there, so a widget that grows from its own centre expands *backwards*
    // over the neighbour before it instead of pushing the ones after it. Pin it
    // to the same edge its section is anchored to and the growth reads as a
    // push. Only the genuinely centred group grows both ways.
    //
    //   "leading"  → top (vertical bar) / left (horizontal bar)
    //   "trailing" → bottom (vertical bar) / right (horizontal bar)
    //
    // barSection 0/2 are the edge groups. Section 1 is the centre list, which
    // the styles split into three sub-columns with different anchors, so those
    // set this explicitly.
    property string growthEdge: barSection === 0 ? "leading" : (barSection === 2 ? "trailing" : "center")
    readonly property bool growsFromLeading: rootItem.growthEdge === "leading"
    readonly property bool growsFromTrailing: rootItem.growthEdge === "trailing"
    readonly property bool growsFromCenter: !rootItem.growsFromLeading && !rootItem.growsFromTrailing
    property bool widgetSelfVisible: (modelData && modelData.hasOwnProperty("visible")) ? modelData.visible : true
    property bool highlighted: false

    // An arrival gets the entry animation, a rebuild lands silently. See
    // GlobalStates.isNewBarWidget for why every delegate in a group is recreated
    // when one widget is added or removed.
    //
    // A plain property assigned once, NOT a binding. QML captures dependencies
    // dynamically, including properties read inside a called function — so as a
    // binding this re-evaluated when `barWidgetsIntroduced` or
    // `barLayoutSnapshot` changed, flipped to false a frame later, and stopped
    // `entryAnimation` mid-flight. That left `wrapper.opacity` frozen near zero
    // and `entryTranslation` frozen at 15px: invisible, mispositioned widgets
    // that only came back when something forced a rebuild.
    property bool isNewWidget: false

    Component.onCompleted: {
        rootItem.isNewWidget = GlobalStates.isNewBarWidget(modelData ? modelData.id : "");
        // Deferred on purpose: every delegate in this same build must still read
        // `false` and animate in, so the bar keeps its entrance at startup.
        if (!GlobalStates.barWidgetsIntroduced)
            Qt.callLater(() => GlobalStates.barWidgetsIntroduced = true);
    }

    // ── Smooth Slide and Move Animations ──────────────────────────────────────
    property real oldX: x
    property real oldY: y
    property bool isReady: false
    resources: [
        Translate {
            id: entryTranslation
            // Rests at zero. The entry animation declares its own `from: 15`, so
            // a widget that never animates is simply in place — no binding here
            // can strand a rebuilt widget 15px off, and nothing outside the
            // animation can move it.
            x: 0
            y: 0
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
        running: rootItem.isNewWidget

        // Insurance. An entry animation must never be able to leave a widget
        // invisible or displaced — that is exactly what happened when `running`
        // flipped mid-flight. Whatever stops this, normally or not, the widget
        // ends up where it belongs.
        onStopped: {
            wrapper.opacity = 1;
            entryTranslation.x = 0;
            entryTranslation.y = 0;
        }

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
        duration: Appearance.animation.barResize.duration
        easing.type: Appearance.animation.barResize.type
        easing.bezierCurve: Appearance.animation.barResize.bezierCurve
    }

    NumberAnimation {
        id: moveYAnimation
        target: moveTranslation
        property: "y"
        to: 0
        duration: Appearance.animation.barResize.duration
        easing.type: Appearance.animation.barResize.type
        easing.bezierCurve: Appearance.animation.barResize.bezierCurve
    }

    // Catch-up slide, for a widget that is *teleported* to a new spot: a reorder
    // in Settings, or a neighbour that appeared. It must not fire while a
    // neighbour is animating its size, because there the layout is already
    // moving this widget smoothly — restarting the catch-up every frame turned
    // that smooth push into a lag that compounded down the row. So it only
    // triggers on the first frame of a move, and a move that keeps going is
    // treated as the layout doing its job.
    property bool _slidingWithLayout: false
    Timer {
        id: slideSettle
        interval: 60
        repeat: false
        onTriggered: rootItem._slidingWithLayout = false
    }

    onXChanged: {
        if (rootItem.isReady) {
            let delta = rootItem.oldX - x;
            if (Math.abs(delta) > 1) {
                if (!rootItem._slidingWithLayout) {
                    moveXAnimation.from = moveTranslation.x + delta;
                    moveXAnimation.restart();
                }
                rootItem._slidingWithLayout = true;
                slideSettle.restart();
            }
        }
        rootItem.oldX = x;
    }

    onYChanged: {
        if (rootItem.isReady) {
            let delta = rootItem.oldY - y;
            if (Math.abs(delta) > 1) {
                if (!rootItem._slidingWithLayout) {
                    moveYAnimation.from = moveTranslation.y + delta;
                    moveYAnimation.restart();
                }
                rootItem._slidingWithLayout = true;
                slideSettle.restart();
            }
        }
        rootItem.oldY = y;
    }

    property bool layoutReady: false

    Timer {
        id: readyTimer
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            rootItem.oldX = rootItem.x;
            rootItem.oldY = rootItem.y;
            rootItem.isReady = true;
            rootItem.layoutReady = true;
        }
    }

    // itemLoader.item.visible reads *effective* visibility, so a transient hide of any
    // bar ancestor (e.g. Connect Mode hides the whole bar layer while a window is
    // fullscreen) latches hasLayoutContent — and this widget — off permanently: once
    // rootItem hides itself in response, the loaded item can never read visible again.
    // When the ancestor chain becomes visible again, re-run the startup grace period so
    // the widget gets a frame to report its real visibility.
    Connections {
        target: rootItem.parent
        function onVisibleChanged() {
            if (!rootItem.parent || !rootItem.parent.visible)
                return;
            rootItem.layoutReady = false;
            readyTimer.restart();
        }
    }

    // The same latch also bites a widget that fills in *after* the grace period: the
    // tray only receives its items about a second after startup, long after readyTimer
    // hides this rootItem, and from then on the loaded item can never report visible
    // again. Implicit size keeps changing while hidden, so use it to re-run the grace
    // period once the widget actually has something to show.
    Connections {
        target: itemLoader.item
        function onImplicitWidthChanged() {
            rootItem.unlatchLayout();
        }
        function onImplicitHeightChanged() {
            rootItem.unlatchLayout();
        }
    }

    function unlatchLayout() {
        if (!rootItem.layoutReady || rootItem.hasLayoutContent)
            return;
        // Only when content appeared. Re-running for a widget that just went empty
        // would flip it visible for a frame and bounce off readyTimer forever.
        const loadedItem = itemLoader.item;
        if (!loadedItem || (loadedItem.implicitWidth <= 0 && loadedItem.implicitHeight <= 0))
            return;
        rootItem.layoutReady = false;
        readyTimer.restart();
    }

    // ── Notch Mode Integration ───────────────────────────────────────────────
    property var modeState: null

    readonly property bool isNotchActive: !!modeState && modeState.notchModeEnabled
    readonly property bool isNotchExpanded: !!modeState && modeState.expanded
    readonly property bool isWidgetVisibleInNotch: {
        if (!isNotchActive)
            return true;
        if (isNotchExpanded)
            return true;

        const isAllowed = Config.options.bar.dynamicIsland.notchMode.visibleWidgets.indexOf(modelData.id) !== -1;
        if (!isAllowed)
            return false;

        if (modelData.id === modeState._displayMode)
            return true;

        if (barSection !== 1)
            return false;
        return modelData.id === modeState._displayMode;
    }

    readonly property bool hasLayoutContent: rootItem.widgetSelfVisible && (itemLoader.item ? itemLoader.item.visible : false)
    readonly property real targetWidth: (hasLayoutContent && isWidgetVisibleInNotch && wrapper.implicitWidth > 0) ? wrapper.implicitWidth : 0
    readonly property bool hasActiveLayoutContent: targetWidth > 0

    // Radius boundaries must follow delegates that currently render content,
    // not the persisted layout flags. A configured widget can stay in the
    // model while its loaded component is invisible (for example, an idle timer).
    readonly property bool hasActiveLeftNeighbor: {
        const parentItem = rootItem.parent;
        if (!parentItem || !parentItem.children)
            return false;

        const siblings = parentItem.children;
        for (let i = 0; i < siblings.length; ++i) {
            const sibling = siblings[i];
            if (sibling === rootItem)
                return false;
            if (sibling && sibling.hasOwnProperty("hasActiveLayoutContent") && sibling.hasActiveLayoutContent)
                return true;
        }
        return false;
    }

    readonly property bool hasActiveRightNeighbor: {
        const parentItem = rootItem.parent;
        if (!parentItem || !parentItem.children)
            return false;

        const siblings = parentItem.children;
        let afterSelf = false;
        for (let i = 0; i < siblings.length; ++i) {
            const sibling = siblings[i];
            if (sibling === rootItem) {
                afterSelf = true;
                continue;
            }
            if (afterSelf && sibling && sibling.hasOwnProperty("hasActiveLayoutContent") && sibling.hasActiveLayoutContent)
                return true;
        }
        return false;
    }

    // This box only animates when the widget appears, disappears or changes notch
    // state — a jump between 0 and its full size. Content growth is already
    // animated by the widget itself on Appearance.animation.barResize, and a
    // second animation here would chase a target that is still moving: the box
    // ends up lagging behind its own content, which is what made a widget look
    // like it grew out of its centre no matter where it was anchored.
    property bool boxResizing: false
    Timer {
        id: boxResizeWindow
        interval: Appearance.animation.barResize.duration + 120
        repeat: false
        onTriggered: rootItem.boxResizing = false
    }
    function beginBoxResize() {
        rootItem.boxResizing = true;
        boxResizeWindow.restart();
    }
    // The very first time content shows up is either this widget arriving — worth
    // animating from zero — or the same widget being rebuilt, where growing from
    // zero is exactly the reflow that reads as a flicker.
    property bool _initialSizeSettled: false
    onHasActiveLayoutContentChanged: {
        if (!rootItem._initialSizeSettled) {
            rootItem._initialSizeSettled = true;
            if (!rootItem.isNewWidget)
                return;
        }
        rootItem.beginBoxResize();
    }
    onIsWidgetVisibleInNotchChanged: rootItem.beginBoxResize()
    onIsNotchModeChanged: rootItem.beginBoxResize()

    implicitWidth: rootItem.vertical ? (hasLayoutContent ? Appearance.sizes.baseVerticalBarWidth : 0) : targetWidth
    Behavior on implicitWidth {
        enabled: !rootItem.vertical && rootItem.boxResizing && (!rootItem.isNotchActive || rootItem.isNotchExpanded)
        NumberAnimation {
            duration: rootItem.isNotchActive ? Config.options.bar.dynamicIsland.notchMode.expandAnimDuration : Appearance.animation.barResize.duration
            easing.type: rootItem.isNotchActive ? Easing.BezierSpline : Appearance.animation.barResize.type
            easing.bezierCurve: rootItem.isNotchActive ? Appearance.animationCurves.emphasizedDecel : Appearance.animation.barResize.bezierCurve
        }
    }

    implicitHeight: rootItem.vertical ? (hasLayoutContent ? wrapper.implicitHeight : 0) : wrapper.implicitHeight
    Behavior on implicitHeight {
        enabled: rootItem.vertical && rootItem.boxResizing && (!rootItem.isNotchActive || rootItem.isNotchExpanded)
        NumberAnimation {
            duration: rootItem.isNotchActive ? Config.options.bar.dynamicIsland.notchMode.expandAnimDuration : Appearance.animation.barResize.duration
            easing.type: rootItem.isNotchActive ? Easing.BezierSpline : Appearance.animation.barResize.type
            easing.bezierCurve: rootItem.isNotchActive ? Appearance.animationCurves.emphasizedDecel : Appearance.animation.barResize.bezierCurve
        }
    }

    opacity: targetWidth > 0 ? 1.0 : 0.0
    visible: !rootItem.layoutReady || (hasLayoutContent && (!isNotchMode || opacity > 0.01))

    readonly property bool isNotchMode: isNotchActive && !isNotchExpanded

    states: [
        State {
            name: "visible"
            when: rootItem.isNotchMode && rootItem.isWidgetVisibleInNotch
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
            from: "hidden"
            to: "visible"
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
            from: "visible"
            to: "hidden"
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

    // ── Registry ──────────────────────────────────────────────────────────────
    BarWidgetRegistry {
        id: registry
    }

    // Widget style resolution — single source of truth
    readonly property string widgetStyle: registry.getStyle(modelData.id)
    readonly property bool isExpressiveFromRegistry: widgetStyle === "expressive"
    readonly property bool isMinimal: widgetStyle === "minimal"

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
        if (modelData.id === "music_player" && ["expressive", "neural", "ring", "tonal"].includes(Config.options.bar.styles.media))
            return true;
        if (modelData.id === "workspaces" && Config.options.bar.styles.workspaces === "expressive")
            return true;
        if (modelData.id === "utility_buttons" && Config.options.bar.styles.utilButtons === "expressive")
            return true;
        if (modelData.id === "weather" && (Config.options.bar.styles.weather === "expressive" || Config.options.bar.styles.weather === "horizon" || Config.options.bar.styles.weather === "tessera"))
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
        if (modelData.id === "dictation_indicator")
            return true;
        if (modelData.id === "phone_scrcpy_indicator")
            return true;
        if (modelData.id === "shell_update_indicator")
            return true;
        if (modelData.id === "mode_indicator")
            return true;
        if (modelData.id === "port_watcher" && Config.options.bar.styles.portWatcher === "expressive")
            return true;
        if (modelData.id === "ai_plan_usage" && Config.options.bar.styles.aiPlanUsage === "expressive")
            return true;
        if (modelData.id === "search" && (Config.options.bar.styles.search === "expressive" || Config.options.bar.styles.search === "neural"))
            return true;
        if (modelData.id === "date" && (Config.options.bar.styles.date === "expressive" || Config.options.bar.styles.date === "neural"))
            return true;
        if (modelData.id === "clock" && (Config.options.bar.styles.clock === "neural" || Config.options.bar.styles.clock === "relief"))
            return true;
        // Bare indicator: no group chip, no padding around it.
        if (modelData.id === "privacy_pill")
            return true;
        return false;
    }

    // ── Radius convenience aliases (from upstream/dev) ──────────────────────
    property real startRadius: groupTheme.startRadius
    property real endRadius: groupTheme.endRadius

    // ── Theme ─────────────────────────────────────────────────────────────────
    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.themes[Config.options.bar.expressiveColorTheme] || barThemes.themes["content"]

    // ── BarGroup wrapper ──────────────────────────────────────────────────────
    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        // The cross axis always fills; the growth axis is pinned to the edge
        // this widget's section grows away from (see growthEdge above). Notch
        // mode keeps neither: it positions the wrapper by `x` below.
        anchors {
            top: rootItem.vertical ? (rootItem.growsFromLeading ? parent.top : undefined) : parent.top
            bottom: rootItem.vertical ? (rootItem.growsFromTrailing ? parent.bottom : undefined) : parent.bottom
            left: rootItem.vertical ? parent.left : ((!rootItem.isNotchMode && rootItem.growsFromLeading) ? parent.left : undefined)
            right: rootItem.vertical ? parent.right : ((!rootItem.isNotchMode && rootItem.growsFromTrailing) ? parent.right : undefined)
            verticalCenter: (rootItem.vertical && rootItem.growsFromCenter) ? rootItem.verticalCenter : undefined
            horizontalCenter: (!rootItem.vertical && !rootItem.isNotchMode && rootItem.growsFromCenter) ? rootItem.horizontalCenter : undefined
        }

        x: rootItem.isNotchMode ? (rootItem.parent ? (rootItem.parent.width / 2 - rootItem.x - wrapper.implicitWidth / 2) : 0) : 0

        transform: [entryTranslation, moveTranslation, verticalTranslation]

        readonly property bool itemIsVisible: rootItem.widgetSelfVisible && (itemLoader.item ? itemLoader.item.visible : false)
        readonly property bool paddingless: !itemIsVisible || registry.isPaddingless(modelData.id, rootItem.isExpressive) || rootItem.isMaterial || (modelData.id === "music_player" && rootItem.widgetStyle === "neural" && rootItem.vertical)
        padding: paddingless ? 0 : 5
        leftPadding: paddingless ? 0 : padding
        rightPadding: paddingless ? 0 : padding
        topPadding: rootItem.vertical ? (paddingless ? 0 : padding) : 0
        bottomPadding: rootItem.vertical ? (paddingless ? 0 : padding) : 0

        startRadius: rootItem.startRadius
        endRadius: rootItem.endRadius
        colBackground: (rootItem.isMaterial || rootItem.isExpressive) ? "transparent" : groupTheme.resolvedBackground

        Loader {
            id: itemLoader
            active: true
            sourceComponent: resolveComponent(modelData.id, rootItem.vertical, rootItem.widgetStyle)
            onLoaded: {
                if (item) {
                    rootItem.layoutReady = false;
                    readyTimer.restart();
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
                        } else if (item.Layout !== undefined) {
                            // Square-by-design widgets (icon buttons) follow the bar
                            // width in vertical mode. Two things were wrong with the
                            // old form, `else if (implicitWidth === implicitHeight)
                            // item.height = width`:
                            //
                            //  • It was evaluated once, at load. A widget that has
                            //    not measured itself yet reports 0x0 — "square" by
                            //    that test — and got its height locked to the bar
                            //    width forever. SysTray is `hasItems ? … : 0` and
                            //    the keyboard pill is `visible ? … : 0`, so both
                            //    started there and never recovered.
                            //  • It wrote `height` on an item inside a layout, so
                            //    the layout still reserved implicitHeight while the
                            //    widget rendered at another one. That gap is the
                            //    overlap: the group packed its children by a height
                            //    none of them was actually drawn at.
                            //
                            // Reactive, and through the layout, so what is reserved
                            // is what is drawn.
                            item.Layout.preferredHeight = Qt.binding(() => (item.implicitWidth > 0 && item.implicitWidth === item.implicitHeight) ? item.width : item.implicitHeight);
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
            if (isMin)
                return workspaceCompMinimal;
            if (isExp)
                return workspaceCompExpressive;
            if (style === "dock")
                return workspaceCompDock;
            return workspaceComp;
        case "music_player":
            if (isExp)
                return musicPlayerCompExpressive;
            if (style === "neural")
                return isVert ? neuralMediaCompVert : neuralMediaComp;
            if (style === "ring")
                return ringMediaComp;
            if (style === "tonal")
                return tonalMediaComp;
            return isVert ? musicPlayerCompVert : musicPlayerComp;
        case "system_monitor":
            if (isExp)
                return systemMonitorCompExpressive;
            return isVert ? systemMonitorCompVert : systemMonitorComp;
        case "clock":
            if (isExp)
                return clockCompExpressive;
            if (style === "neural")
                return clockCompNeural;
            if (style === "relief")
                return clockCompRelief;
            return isVert ? clockCompVert : clockComp;
        case "battery":
            if (isExp)
                return batteryCompExpressive;
            return isVert ? batteryCompVert : batteryComp;
        case "keyboard_layout":
            if (isExp)
                return keyboardCompExpressive;
            return isVert ? keyboardCompVert : keyboardComp;
        case "utility_buttons":
            if (isExp)
                return utilityButtonsCompExpressive;
            return utilityButtonsComp;
        case "system_tray":
            if (isExp)
                return systemTrayCompExpressive;
            return systemTrayComp;
        case "active_window":
            if (isExp)
                return activeWindowCompExpressive;
            return activeWindowComp;
        case "weather":
            if (isExp)
                return weatherCompExpressive;
            if (style === "horizon")
                return weatherCompHorizon;
            if (style === "tessera")
                return weatherCompTessera;
            return weatherComp;
        case "policies_panel_button":
            if (isExp)
                return policiesPanelButtonExpressive;
            return policiesPanelButton;
        case "dashboard_panel_button":
            if (isExp)
                return isVert ? dashboardPanelButtonExpressiveVert : dashboardPanelButtonExpressive;
            return isVert ? dashboardPanelButtonVert : dashboardPanelButton;
        case "bluetooth_devices":
            if (isExp)
                return bluetoothCompExpressive;
            return isVert ? bluetoothCompVert : bluetoothComp;
        case "sports":
            if (isExp)
                return sportsCompExpressive;
            return sportsComp;
        case "power":
            if (isExp)
                return powerCompExpressive;
            return powerComp;
        case "date":
            if (isExp)
                return dateCompExpressive;
            if (style === "neural")
                return dateCompNeural;
            return dateComp;
        case "timer":
            return isVert ? timerCompVert : timerComp;
        case "record_indicator":
            return recordIndicatorComp;
        case "dictation_indicator":
            return dictationIndicatorComp;
        case "phone_scrcpy_indicator":
            return phoneScrcpyIndicatorComp;
        case "shell_update_indicator":
            return shellUpdateIndicatorComp;
        case "mode_indicator":
            return modeIndicatorComp;
        case "screen_share_indicator":
            return screenshareIndicatorComp;
        case "dock_to_panel":
            return dockToPanelComp;
        case "port_watcher":
            if (isExp)
                return portWatcherCompExpressive;
            return portWatcherComp;
        case "ai_plan_usage":
            if (isExp)
                return aiPlanUsageCompExpressive;
            return aiPlanUsageComp;
        case "privacy_pill":
            return privacyPillComp;
        case "search":
            if (isExp)
                return searchCompExpressive;
            if (style === "neural")
                return searchCompNeural;
            return searchComp;
        default:
            return null;
        }
    }

    function toggleVisible(visibility) {
        rootItem.widgetSelfVisible = visibility;
        let item = null;
        if (barSection == 0)
            item = Config.options.bar.layouts.left[originalIndex];
        else if (barSection == 1)
            item = Config.options.bar.layouts.center[originalIndex];
        else if (barSection == 2)
            item = Config.options.bar.layouts.right[originalIndex];
        if (item !== undefined && item !== null) {
            if (item.visible !== visibility) {
                item.visible = visibility;
                if (barSection == 0)
                    Config.options.bar.layouts.left = Config.options.bar.layouts.left;
                else if (barSection == 1)
                    Config.options.bar.layouts.center = Config.options.bar.layouts.center;
                else if (barSection == 2)
                    Config.options.bar.layouts.right = Config.options.bar.layouts.right;
            }
        }
    }

    function toggleHighlight(highlight) {
        rootItem.highlighted = highlight;
    }

    // ── Group theme ────────────────────────────────────────────────────────────
    BarGroupTheme {
        id: groupTheme
        barSection: rootItem.barSection
        list: rootItem.list
        originalIndex: rootItem.originalIndex
        isExpressive: rootItem.isExpressive
        highlighted: rootItem.highlighted
        activated: itemLoader.item?.activated ?? false
        activeTheme: rootItem.activeTheme
        widgetId: modelData.id
    }

    // ── Widget Components ─────────────────────────────────────────────────────
    // Default variants
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
        id: dictationIndicatorComp
        DictationIndicator {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: phoneScrcpyIndicatorComp
        PhoneScrcpyIndicator {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: shellUpdateIndicatorComp
        ShellUpdateIndicator {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: modeIndicatorComp
        ModeIndicator {
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
        id: neuralMediaComp
        NeuralMedia {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: neuralMediaCompVert
        Vertical.VerticalNeuralMedia {}
    }
    Component {
        id: ringMediaComp
        RingMedia {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: tonalMediaComp
        TonalMedia {
            vertical: rootItem.vertical
        }
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
        id: dateComp
        DateWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: dateCompExpressive
        ExpressiveDateWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: dateCompNeural
        NeuralDateWidget {
            vertical: rootItem.vertical
        }
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
        id: powerComp
        PowerButton {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: dockToPanelComp
        DockToPanel {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: portWatcherComp
        PortWatcherWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: portWatcherCompExpressive
        ExpressivePortWatcher {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: aiPlanUsageComp
        AiPlanUsageWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: aiPlanUsageCompExpressive
        ExpressiveAiPlanUsage {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: privacyPillComp
        PrivacyPill {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: searchComp
        SearchBarWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: searchCompExpressive
        ExpressiveSearchBarWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: searchCompNeural
        NeuralSearchBarWidget {
            vertical: rootItem.vertical
        }
    }

    // Expressive variants
    Component {
        id: weatherCompExpressive
        ExpressiveWeatherBar {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: weatherCompHorizon
        HorizonWeatherWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: weatherCompTessera
        TesseraWeatherWidget {
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
        id: clockCompNeural
        NeuralClockWidget {
            vertical: rootItem.vertical
        }
    }
    Component {
        id: clockCompRelief
        ReliefClockWidget {
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
        id: workspaceCompDock
        DockWorkspaces {
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
        ExpressivePoliciesPanelButton {
            vertical: rootItem.vertical
        }
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
    Component {
        id: activeWindowCompExpressive
        ExpressiveActiveWindow {
            vertical: rootItem.vertical
        }
    }
}
