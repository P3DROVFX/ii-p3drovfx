import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.bar.shared
import qs.modules.ii.bar.registry
import qs.modules.ii.bar.groups

Item {
    id: rootItem

    z: rootItem.isBeingDragged ? 1000 : (rootItem.highlighted ? 10 : 1)
    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical
    // Edit Mode's drop preview: the room this widget stands aside to open.
    // Margins rather than width, so the space belongs to the gap and not to
    // the widget - nothing inside it moves or restyles while the row parts.
    Layout.leftMargin: rootItem.vertical ? 0 : rootItem.editGapBefore
    Layout.rightMargin: rootItem.vertical ? 0 : rootItem.editGapAfter
    Layout.topMargin: rootItem.vertical ? rootItem.editGapBefore : 0
    Layout.bottomMargin: rootItem.vertical ? rootItem.editGapAfter : 0

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

    // ── Control center anchor ─────────────────────────────────────────────────
    // The control center drops from the dashboard button, whichever style draws it.
    // Only a layer-shell bar publishes (a PanelWindow has `exclusiveZone`): a live
    // preview of a bar style in a floating window must not steal the anchor.
    readonly property var hostWindow: rootItem.QsWindow.window ?? null
    readonly property string dashboardAnchorScreen: {
        if (modelData?.id !== "dashboard_panel_button")
            return "";
        const win = rootItem.hostWindow;
        if (!win || win.exclusiveZone === undefined)
            return "";
        return String(win.screen?.name ?? "");
    }
    property string publishedAnchorScreen: ""
    onDashboardAnchorScreenChanged: rootItem.publishDashboardAnchor()
    function publishDashboardAnchor() {
        if (rootItem.publishedAnchorScreen === rootItem.dashboardAnchorScreen)
            return;
        GlobalStates.clearDashboardAnchor(rootItem.publishedAnchorScreen, rootItem);
        rootItem.publishedAnchorScreen = rootItem.dashboardAnchorScreen;
        GlobalStates.setDashboardAnchor(rootItem.publishedAnchorScreen, rootItem);
    }
    Component.onDestruction: GlobalStates.clearDashboardAnchor(rootItem.publishedAnchorScreen, rootItem)

    Component.onCompleted: {
        rootItem.publishDashboardAnchor();
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
            x: 0
            y: 0
        },
        Translate {
            id: moveTranslation
        },
        Translate {
            id: offsetTranslation
            x: rootItem.vertical ? 0 : (rootItem.isBeingDragged ? rootItem.dragOffset : rootItem.reorderShift)
            y: (rootItem.isNotchMode && !rootItem.isWidgetVisibleInNotch)
                ? -20
                : (rootItem.vertical ? (rootItem.isBeingDragged ? rootItem.dragOffset : rootItem.reorderShift) : 0)
            Behavior on y {
                enabled: rootItem.isNotchActive
                NumberAnimation {
                    duration: rootItem.isNotchMode ? 320 : 0
                    easing.type: Easing.OutCubic
                }
            }
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
        function onVisibleChanged() {
            Qt.callLater(rootItem.syncLoadedItemVisible);
        }
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

    // A widget that hides itself when it has nothing to say still reports that
    // through `toggleVisible`, which is a *stored* flag - it is written back to
    // the layout. Edit Mode must not touch it: the arrangement of the bar has
    // nothing to do with whether a recording is running. So the mode is ORed in
    // here instead, and each widget that wants to be arrangeable while idle
    // draws itself as though it were active. One that stays blank is still
    // skipped, exactly as before.
    readonly property bool selfVisibleOrEditing: rootItem.widgetSelfVisible || GlobalStates.editMode
    // Not a binding: `item.visible` is effective visibility, so it follows this
    // component's own `visible`, which is decided from `hasLayoutContent` - reading
    // it straight was a binding loop on `hasLayoutContent`/`editPlaceholderShown`.
    // Synced a turn later, and only while this component shows: hidden, the item
    // reads invisible whatever it would draw.
    property bool loadedItemVisible: false
    function syncLoadedItemVisible() {
        const loadedItem = itemLoader.item;
        if (!loadedItem) {
            rootItem.loadedItemVisible = false;
            return;
        }
        if (rootItem.visible)
            rootItem.loadedItemVisible = loadedItem.visible;
    }
    onVisibleChanged: Qt.callLater(rootItem.syncLoadedItemVisible)
    // A widget drawing nothing is invisible to the layout, and in the mode that
    // left it with no drag handle, no badge and no catalogue row - unreachable
    // in every direction. The stand-in chip gives it a body while the mode is
    // on; the widget itself is untouched (see BarEditPlaceholder).
    readonly property bool editPlaceholderShown: GlobalStates.editMode
        && rootItem.editController !== null && !rootItem.loadedItemVisible
    readonly property bool hasLayoutContent: rootItem.selfVisibleOrEditing
        && (rootItem.loadedItemVisible || rootItem.editPlaceholderShown)
    // A finger cannot reliably hit a 24px-wide indicator. Narrow widgets are padded out
    // to the minimum touch target on a touch-first family; wide ones are untouched, and a
    // widget with no content stays at zero so it still collapses out of the layout
    // entirely instead of leaving a 48px hole.
    //
    // The minimum is the bar's own plate size, not the 48px touch target. The bar is
    // already at least 48px tall on a touch-first family, and a round button fills its
    // plate at `baseBarHeight - 8`; widening those to 48 added 4px of empty space on each
    // side of every button, so the gaps between widgets and to the bar's ends grew while
    // the space above and below stayed 4px.
    readonly property real touchMinimumWidth: (PanelFamily.touchFirst && !rootItem.vertical)
        ? Appearance.sizes.baseBarHeight - 8 : 0

    /// Whether this widget draws something, measured without its paddings — the edge
    /// test below feeds those paddings, and a neighbour's check reading them back would
    /// be a binding loop.
    readonly property bool edgeContentPresent: rootItem.hasLayoutContent && rootItem.isWidgetVisibleInNotch
        && (itemLoader.implicitWidth > 0 || editPlaceholder.implicitWidth > 0)

    function hasContentSibling(before) {
        const parentItem = rootItem.parent;
        if (!parentItem || !parentItem.children)
            return false;
        let afterSelf = false;
        for (const sibling of parentItem.children) {
            if (sibling === rootItem) {
                if (before)
                    return false;
                afterSelf = true;
                continue;
            }
            if ((before || afterSelf) && sibling && sibling.hasOwnProperty("edgeContentPresent") && sibling.edgeContentPresent)
                return true;
        }
        return false;
    }

    /// First widget of the left section / last of the right one: its outer side is the
    /// bar's edge, whose gap the style sets, so any widening goes inward instead.
    readonly property bool atBarStart: !rootItem.vertical && rootItem.barSection === 0 && !rootItem.hasContentSibling(true)
    readonly property bool atBarEnd: !rootItem.vertical && rootItem.barSection === 2 && !rootItem.hasContentSibling(false)
    readonly property real targetWidth: (hasLayoutContent && isWidgetVisibleInNotch && wrapper.implicitWidth > 0)
        ? Math.max(wrapper.implicitWidth, rootItem.touchMinimumWidth) : 0
    readonly property bool hasActiveLayoutContent: targetWidth > 0

    // Radius boundaries must follow delegates that currently render content,
    // not the persisted layout flags. A configured widget can stay in the
    // model while its loaded component is invisible (for example, an idle timer).
    readonly property bool hasActiveLeftNeighbor: {
        if (!rootItem.isDefault || !rootItem.hasActiveLayoutContent)
            return false;

        const parentItem = rootItem.parent;
        if (!parentItem || !parentItem.children)
            return false;

        let closestVisibleSibling = null;
        for (const sibling of parentItem.children) {
            if (sibling === rootItem)
                break;
            if (sibling && sibling.hasOwnProperty("hasActiveLayoutContent") && sibling.hasActiveLayoutContent) {
                closestVisibleSibling = sibling;
            }
        }

        if (!closestVisibleSibling)
            return false;

        return Boolean(closestVisibleSibling.hasOwnProperty("isDefault") ? closestVisibleSibling.isDefault : false);
    }

    readonly property bool hasActiveRightNeighbor: {
        if (!rootItem.isDefault || !rootItem.hasActiveLayoutContent)
            return false;

        const parentItem = rootItem.parent;
        if (!parentItem || !parentItem.children)
            return false;

        let afterSelf = false;
        let closestVisibleSibling = null;
        for (const sibling of parentItem.children) {
            if (sibling === rootItem) {
                afterSelf = true;
                continue;
            }
            if (afterSelf && sibling && sibling.hasOwnProperty("hasActiveLayoutContent") && sibling.hasActiveLayoutContent) {
                closestVisibleSibling = sibling;
                break;
            }
        }

        if (!closestVisibleSibling)
            return false;

        return Boolean(closestVisibleSibling.hasOwnProperty("isDefault") ? closestVisibleSibling.isDefault : false);
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

    opacity: (rootItem.isNotchMode && !rootItem.isWidgetVisibleInNotch)
        ? 0.0
        : ((rootItem.vertical ? (rootItem.hasLayoutContent && wrapper.implicitHeight > 0) : targetWidth > 0)
            ? (rootItem.isBeingDragged ? 0.94 : 1.0) : 0.0)
    Behavior on opacity {
        enabled: !Appearance.reducedMotion && (GlobalStates.editMode || rootItem.isNotchActive)
        NumberAnimation {
            duration: rootItem.isNotchMode ? 280 : Appearance.animation.barResize.duration
            easing.type: rootItem.isNotchMode ? Easing.OutQuad : Appearance.animation.barResize.type
            easing.bezierCurve: rootItem.isNotchMode ? [] : Appearance.animation.barResize.bezierCurve
        }
    }
    visible: !rootItem.layoutReady || (hasLayoutContent && (!isNotchMode || opacity > 0.01))

    readonly property bool isNotchMode: isNotchActive && !isNotchExpanded
    // ─────────────────────────────────────────────────────────────────────────

    // Widget style resolution — shared BarWidgetRegistry singleton
    readonly property string widgetStyle: BarWidgetRegistry.getStyle(modelData.id)
    readonly property bool isExpressiveFromRegistry: widgetStyle === "expressive"
    readonly property bool isMinimal: widgetStyle === "minimal"
    readonly property bool isMaterial: BarWidgetRegistry.isMaterial(modelData.id)
    readonly property bool isExpressive: BarWidgetRegistry.isExpressive(modelData.id)
    readonly property bool isDefault: !rootItem.isExpressive && !rootItem.isMaterial && !rootItem.isMinimal && (rootItem.widgetStyle === "default" || rootItem.widgetStyle === "classic")

    // ── Radius convenience aliases (from upstream/dev) ──────────────────────
    property real startRadius: groupTheme.startRadius
    property real endRadius: groupTheme.endRadius

    // ── Theme (shared singleton) ──────────────────────────────────────────────
    readonly property var activeTheme: BarWidgetRegistry.activeTheme

    // ── BarGroup wrapper ──────────────────────────────────────────────────────
    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        width: rootItem.vertical ? rootItem.width : (rootItem.targetWidth > 0 ? rootItem.targetWidth : wrapper.implicitWidth)
        height: rootItem.vertical ? (rootItem.hasLayoutContent ? wrapper.implicitHeight : 0) : rootItem.height
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

        transform: [entryTranslation, moveTranslation, offsetTranslation]

        readonly property bool itemIsVisible: rootItem.selfVisibleOrEditing && rootItem.loadedItemVisible
        readonly property bool paddingless: !itemIsVisible || BarWidgetRegistry.isPaddingless(modelData.id, rootItem.isExpressive) || rootItem.isMaterial || (modelData.id === "music_player" && rootItem.widgetStyle === "neural" && rootItem.vertical)
        padding: paddingless ? 0 : 5
        // A touch-first bar widens anything narrower than its plate. The widget itself
        // keeps its size and the grid lays it out from the left, so all of that extra
        // width used to land on its right and read as a margin on one side. It is split
        // between both paddings instead — except at the bar's ends, where the outer side
        // is the bar's edge gap and the whole extra goes inward. Measured from the loaded
        // item, not the wrapper: the wrapper's width already includes these paddings.
        readonly property real touchExtra: rootItem.touchMinimumWidth > 0
            ? Math.max(0, rootItem.touchMinimumWidth - itemLoader.implicitWidth - (paddingless ? 0 : padding * 2))
            : 0
        leftPadding: (paddingless ? 0 : padding)
            + (rootItem.atBarStart ? 0 : (rootItem.atBarEnd ? touchExtra : touchExtra / 2))
        rightPadding: (paddingless ? 0 : padding)
            + (rootItem.atBarEnd ? 0 : (rootItem.atBarStart ? touchExtra : touchExtra / 2))
        topPadding: rootItem.vertical ? (paddingless ? 0 : padding) : 0
        bottomPadding: rootItem.vertical ? (paddingless ? 0 : padding) : 0

        startRadius: rootItem.startRadius
        endRadius: rootItem.endRadius
        colBackground: (rootItem.isMaterial || rootItem.isExpressive) ? "transparent" : groupTheme.resolvedBackground

        Loader {
            id: itemLoader
            active: true
            Component.onCompleted: {
                rootItem._itemLoaderReady = true;
                rootItem.syncItemLoader();
            }
            onItemChanged: Qt.callLater(rootItem.syncLoadedItemVisible)
            onLoaded: {
                if (item) {
                    rootItem.layoutReady = false;
                    readyTimer.restart();
                    if (item.hasOwnProperty("onActivatedColor")) {
                        item.onActivatedColor = Qt.binding(() => groupTheme.colOnBackgroundHighlight);
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

        // The stand-in for a widget with nothing to draw. Invisible when it is
        // not needed, not merely inactive: a layout counts an item with no size
        // as an item and spaces the row around it.
        Loader {
            id: editPlaceholder
            active: rootItem.editPlaceholderShown
            visible: rootItem.editPlaceholderShown
            Layout.alignment: rootItem.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            function syncSource() {
                if (active && source.toString() === "") {
                    setSource(Qt.resolvedUrl("BarEditPlaceholder.qml"), {
                        vertical: Qt.binding(() => rootItem.vertical),
                        widgetId: Qt.binding(() => modelData.id)
                    });
                }
            }
            Component.onCompleted: syncSource()
            onActiveChanged: syncSource()
        }
    }

    // ── Component resolution ──────────────────────────────────────────────────
    // Resolves each widget slot via the shared BarWidgetRegistry singleton so
    // Loader.setSource only compiles and instantiates the active widget.
    readonly property var resolvedSpec: BarWidgetRegistry.resolveWidgetSpec(modelData?.id ?? "", rootItem.vertical, rootItem.widgetStyle)
    property string _loadedWidgetUrl: ""
    property bool _itemLoaderReady: false

    onResolvedSpecChanged: rootItem.syncItemLoader()

    function syncItemLoader() {
        if (!rootItem._itemLoaderReady)
            return;
        const spec = rootItem.resolvedSpec;
        if (!spec || !spec.url) {
            if (rootItem._loadedWidgetUrl !== "") {
                rootItem._loadedWidgetUrl = "";
                itemLoader.source = "";
            }
            return;
        }
        if (spec.url === rootItem._loadedWidgetUrl)
            return;
        rootItem._loadedWidgetUrl = spec.url;
        const props = {};
        if (spec.props === "vertical" || spec.props === "verticalAndRadii")
            props.vertical = Qt.binding(() => rootItem.vertical);
        if (spec.props === "radii" || spec.props === "verticalAndRadii") {
            props.startRadius = Qt.binding(() => rootItem.startRadius);
            props.endRadius = Qt.binding(() => rootItem.endRadius);
        }
        itemLoader.setSource(Qt.resolvedUrl(spec.url), props);
    }

    function toggleVisible(visibility) {
        rootItem.widgetSelfVisible = visibility;
        if (visibility)
            rootItem.unlatchLayout();
        Qt.callLater(rootItem.syncLoadedItemVisible);
        // Widgets call this from Component.onCompleted, i.e. while the style's
        // Repeater is still building from the layout list. Re-assigning that list
        // right away re-runs the list binding mid-build (a binding loop), so the
        // persisted flag is written on the next tick. The closure only touches
        // Config: the delegate may be gone by then.
        const section = barSection;
        const index = originalIndex;
        Qt.callLater(() => {
            const layouts = Config.options.bar.layouts;
            let item = null;
            if (section == 0)
                item = layouts.left[index];
            else if (section == 1)
                item = layouts.center[index];
            else if (section == 2)
                item = layouts.right[index];
            if (item === undefined || item === null || item.visible === visibility)
                return;
            item.visible = visibility;
            if (section == 0)
                layouts.left = layouts.left;
            else if (section == 1)
                layouts.center = layouts.center;
            else if (section == 2)
                layouts.right = layouts.right;
        });
    }

    // ── Edit Mode overlay ─────────────────────────────────────────────────
    // The bar's controller sits on the content root; found by walking up, so
    // every style and both orientations get it from this one insertion.
    readonly property var editController: {
        let p = rootItem.parent;
        while (p) {
            if (p.barEditController !== undefined)
                return p.barEditController;
            p = p.parent;
        }
        return null;
    }

    // ── Settings preview ──────────────────────────────────────────────────
    // Settings' live bar (BarPreviewStage) can try a group style on its own copy of the
    // bar without touching the config; found by walking up, null on the real bar. Widgets
    // read `rootItem.groupStyle` instead of the config for the same reason.
    readonly property var previewOverrides: {
        let p = rootItem.parent;
        while (p) {
            if (p.barPreviewOverrides !== undefined)
                return p.barPreviewOverrides;
            p = p.parent;
        }
        return null;
    }
    readonly property int groupStyle: (rootItem.previewOverrides?.groupStyle ?? -1) >= 0
        ? rootItem.previewOverrides.groupStyle : Config.options.bar.barGroupStyle

    // ── Edit Mode drop preview ─────────────────────────────────────────────
    readonly property bool isBeingDragged: rootItem.editController !== null
        && rootItem.editController.dragActive
        && rootItem.editController.dragSlot !== null
        && rootItem.editController.dragSlot.barComponent === rootItem

    readonly property real reorderShiftTarget: rootItem.editController
        ? rootItem.editController.reorderShift(rootItem.barSection, rootItem.originalIndex) : 0
    property real reorderShift: rootItem.reorderShiftTarget
    Behavior on reorderShift {
        enabled: !Appearance.reducedMotion && GlobalStates.editMode
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }

    readonly property real dragOffset: rootItem.isBeingDragged && rootItem.editController
        ? rootItem.editController.dragOffset : 0

    // External drop preview gaps (from catalogue drawer)
    readonly property real editGapBeforeTarget: (rootItem.editController && rootItem.editController.externalActive)
        ? rootItem.editController.gapBefore(rootItem.barSection, rootItem.originalIndex) : 0
    readonly property real editGapAfterTarget: (rootItem.editController && rootItem.editController.externalActive)
        ? rootItem.editController.gapAfter(rootItem.barSection, rootItem.originalIndex) : 0
    property real editGapBefore: rootItem.editGapBeforeTarget
    Behavior on editGapBefore {
        enabled: !Appearance.reducedMotion && GlobalStates.editMode
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }
    property real editGapAfter: rootItem.editGapAfterTarget
    Behavior on editGapAfter {
        enabled: !Appearance.reducedMotion && GlobalStates.editMode
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }

    readonly property bool editLifted: false

    Loader {
        parent: wrapper
        anchors.fill: parent
        z: 5
        active: GlobalStates.editMode && (GlobalStates.editProgress > 0.85 || Appearance.reducedMotion) && rootItem.hasLayoutContent && rootItem.editController !== null
        function syncSource() {
            if (active && source.toString() === "") {
                setSource(Qt.resolvedUrl("BarEditSlot.qml"), {
                    controller: Qt.binding(() => rootItem.editController),
                    bucket: Qt.binding(() => rootItem.barSection),
                    storedIndex: Qt.binding(() => rootItem.originalIndex),
                    widgetId: Qt.binding(() => modelData.id),
                    barComponent: rootItem,
                    // The hole beside this widget AS IT IS RIGHT NOW. The controller
                    // draws the drop indicator in it and cannot see the animated
                    // margin from where it sits, so the widget hands it over.
                    gapBefore: Qt.binding(() => rootItem.editGapBefore),
                    gapAfter: Qt.binding(() => rootItem.editGapAfter)
                });
            }
        }
        Component.onCompleted: syncSource()
        onActiveChanged: syncSource()
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
        barGroupStyle: rootItem.groupStyle
        hasActiveLeftNeighbor: rootItem.hasActiveLeftNeighbor
        hasActiveRightNeighbor: rootItem.hasActiveRightNeighbor
        isDefault: rootItem.isDefault
    }
}
