pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * One window card of the workspace grid: the picture, its app chip and the
 * chip's quick actions.
 *
 * The grid hands in the geometry and the corner radii; the card only draws.
 * The picture is masked to the radii, the shadow and the chip sit outside the
 * mask so the card can lift under the pointer and the chip is never clipped.
 */
Item { // Window
    id: root
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    property int windowRounding
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        if (!widgetMonitor || !monitorData) return 1.0;
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        if (!widgetMonitor || !monitorData) return 1.0;
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: Math.max(((windowData ? windowData.at[0] : 0) - (monitorData ? monitorData.x : 0) - (monitorData ? (monitorData.reserved?.[0] ?? 0) : 0)) * widthRatio * root.scale, 0) + xOffset
    property real initY: Math.max(((windowData ? windowData.at[1] : 0) - (monitorData ? monitorData.y : 0) - (monitorData ? (monitorData.reserved?.[1] ?? 0) : 0)) * heightRatio * root.scale, 0) + yOffset
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor ? widgetMonitor.id : 0

    property real targetWindowWidth: (windowData ? windowData.size[0] : 0) * scale * widthRatio
    property real targetWindowHeight: (windowData ? windowData.size[1] : 0) * scale * heightRatio
    property bool hovered: false
    property bool pressed: false

    property bool centerIcons: Config.options.overview.centerIcons
    property bool showIcons: Config.options.overview.showIcons
    property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;
        return Quickshell.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing");
    }
    readonly property string appName: {
        const appClass = root.windowData?.class ?? "";
        const entry = appClass.length > 0 ? DesktopEntries.heuristicLookup(appClass) : null;
        return entry?.name || appClass || Translation.tr("Window");
    }

    property bool indicateXWayland: windowData?.xwayland ?? false

    property bool hyprscrollingEnabled: false
    property int scrollWidth
    property int scrollHeight
    property int scrollX
    property int scrollY

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    // ── State handed in by the grid ─────────────────────────────────────
    /** The window Hyprland has focused: its chip is the primary one. */
    property bool focusedWindow: false
    /** On the monitor's current workspace; the others sit back. */
    property bool onActiveWorkspace: true
    /** Something is being dragged: chips step aside and nothing lifts. */
    property bool interactionsSuppressed: false
    /** A dragged window would trade places with this one. */
    property bool swapTarget: false
    /** The grid's size, so the menu opens towards the room it has. */
    property real gridWidth: 0
    property real gridHeight: 0

    // ── Window menu ─────────────────────────────────────────────────────
    property bool menuOpen: false
    readonly property bool menuHovered: menuLoader.item?.hovered ?? false
    property real menuProgress: root.menuOpen ? 1 : 0
    Behavior on menuProgress {
        enabled: root.animate
        NumberAnimation {
            duration: root.menuOpen ? OverviewStyle.motionMove.duration : OverviewStyle.motionFast.duration
            easing.type: OverviewStyle.motionMove.type
            easing.bezierCurve: root.menuOpen ? OverviewStyle.motionMove.bezierCurve : OverviewStyle.motionFast.bezierCurve
        }
    }
    onInteractionsSuppressedChanged: if (root.interactionsSuppressed) root.menuOpen = false
    onEngagedChanged: {
        if (root.engaged)
            menuCloseTimer.stop();
        else if (root.menuOpen)
            menuCloseTimer.restart();
    }
    Timer {
        id: menuCloseTimer
        interval: OverviewStyle.menuCloseDelay
        onTriggered: root.menuOpen = false
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            root.menuOpen = false;
        }
    }

    readonly property bool recents: OverviewStyle.recents
    readonly property bool engaged: root.recents && (cardHover.hovered || root.menuHovered) && !root.interactionsSuppressed
    readonly property bool dimmed: root.recents && !root.onActiveWorkspace && !root.engaged && !root.pressed
    readonly property bool chipFits: root.width >= OverviewStyle.chipMinCardWidth && root.height >= OverviewStyle.chipMinCardHeight
    readonly property bool chipCompact: root.width < OverviewStyle.chipCompactCardWidth
    readonly property real chipInset: root.chipCompact ? OverviewStyle.chipInsetCompact : OverviewStyle.chipInset
    readonly property bool showFallbackIcon: root.recents && root.showIcons && (!root.chipFits || !windowPreview.hasContent)

    x: hyprscrollingEnabled ? scrollX : initX
    y: hyprscrollingEnabled ? scrollY : initY
    width: !windowData.floating && hyprscrollingEnabled ? scrollWidth : targetWindowWidth
    height: !windowData.floating && hyprscrollingEnabled ? scrollHeight : targetWindowHeight
    opacity: windowData.monitor == widgetMonitorId ? 1 : OverviewStyle.otherMonitorOpacity

    // We have to disable animations in the first frame or else some strange animations shows up
    property bool initialized: false
    Component.onCompleted: Qt.callLater(() => root.initialized = true)
    readonly property bool animate: root.initialized && !root.animationsDisabled

    // Re-capture the frozen ScreencopyView whenever HyprlandData refetches
    // client list and assigns a fresh windowData object (different reference
    // after every `hyprctl clients -j` parse). This is the live recapture hook
    // for retiles that don't emit a movewindowv2 event — e.g. when a sibling
    // window lands on our workspace and Hyprland silently shrinks us to half
    // width. Without this the live:false texture stays letterboxed at the old
    // aspect, producing the "empty space above/below" bug after drops.
    onWindowDataChanged: {
        if (root.initialized && root.visible && root.toplevel && !windowPreview.live)
            recaptureDebounce.restart()
    }

    function requestRecapture() {
        if (root.visible && !windowPreview.live)
            recaptureDebounce.restart()
    }

    // Keep the last frame while search hides the grid, then refresh frozen
    // previews on return. A hidden tile must not keep exporting live windows.
    onVisibleChanged: {
        if (root.visible)
            requestRecapture();
        else
            recaptureDebounce.stop();
    }

    Timer {
        id: recaptureDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (root.visible && !windowPreview.live && root.toplevel && windowPreview.captureSource)
                windowPreview.captureFrame()
        }
    }

    Behavior on x {
        enabled: root.animate
        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: root.animate
        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        enabled: root.animate
        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        enabled: root.animate
        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
    }
    Behavior on topLeftRadius {
        enabled: root.animate
        animation: OverviewStyle.motionMove.numberAnimation.createObject(this)
    }
    Behavior on topRightRadius {
        enabled: root.animate
        animation: OverviewStyle.motionMove.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        enabled: root.animate
        animation: OverviewStyle.motionMove.numberAnimation.createObject(this)
    }
    Behavior on bottomRightRadius {
        enabled: root.animate
        animation: OverviewStyle.motionMove.numberAnimation.createObject(this)
    }

    // ── Actions ─────────────────────────────────────────────────────────
    readonly property string address: root.windowData?.address ?? ""

    function registryAction(id) {
        return WindowActionRegistry.actions.find(action => action.id === id);
    }

    function runAction(id) {
        root.menuOpen = false;
        switch (id) {
        case "screenshot":
            root.takeScreenshot();
            break;
        case "float":
        case "pin":
        case "fullscreen":
            WindowActionRegistry.execute(root.registryAction(id), root.address);
            break;
        case "close":
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${root.address}" })`);
            break;
        case "kill":
            if ((root.windowData?.pid ?? 0) > 0)
                Quickshell.execDetached(["kill", "-KILL", String(root.windowData.pid)]);
            break;
        }
    }

    /**
     * The picture already on the card is the window at its own resolution, so
     * the shot is a grab of the preview at the buffer's size: it works for
     * windows on any workspace without leaving the overview.
     */
    function takeScreenshot() {
        if (!windowPreview.hasContent)
            return;
        const size = windowPreview.sourceSize;
        const target = size.width > 0 ? Qt.size(size.width, size.height) : Qt.size(root.width, root.height);
        windowPreview.grabToImage(result => {
            const temp = `${Directories.screenshotTemp}/overview-${Date.now()}.png`;
            if (!result.saveToFile(temp))
                return;
            const directory = `${FileUtils.trimFileProtocol(Directories.pictures)}/Screenshots`;
            const app = (root.windowData?.class ?? "window").replace(/[^A-Za-z0-9._-]+/g, "-");
            const path = `${directory}/${app}-${Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")}.png`;
            const q = StringUtils.shellSingleQuoteEscape;
            Quickshell.execDetached(["bash", "-c",
                `mkdir -p '${q(directory)}' && mv '${q(temp)}' '${q(path)}' && wl-copy --type image/png < '${q(path)}'`
                + ` && notify-send -a Overview -i '${q(path)}' '${q(Translation.tr("Screenshot saved"))}' '${q(root.appName)}'`]);
            chip.markDone("check");
            flash.restart();
        }, target);
    }

    // ── Card ────────────────────────────────────────────────────────────
    HoverHandler {
        id: cardHover
    }

    StyledRectangularShadow {
        target: card
        visible: root.recents && opacity > 0 && !Config.options.appearance.transparency.popups && !Config.options.appearance.transparency.enable
        radius: Math.max(root.topLeftRadius, root.bottomRightRadius)
        blur: root.engaged ? OverviewStyle.shadowBlurRaised : OverviewStyle.shadowBlur
        opacity: root.dimmed ? 0 : (root.engaged ? OverviewStyle.shadowOpacityRaised : OverviewStyle.shadowOpacity)
        offset: Qt.vector2d(0, root.engaged ? OverviewStyle.shadowOffsetRaised : OverviewStyle.shadowOffset)
        Behavior on blur {
            enabled: root.animate
            animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            enabled: root.animate
            animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
        }
    }

    Item {
        id: card
        anchors.fill: parent
        scale: root.recents && root.pressed ? OverviewStyle.pressScale : 1
        Behavior on scale {
            enabled: root.animate
            animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                topLeftRadius: !root.hyprscrollingEnabled ? root.topLeftRadius : root.windowRounding
                topRightRadius: !root.hyprscrollingEnabled ? root.topRightRadius : root.windowRounding
                bottomLeftRadius: !root.hyprscrollingEnabled ? root.bottomLeftRadius : root.windowRounding
                bottomRightRadius: !root.hyprscrollingEnabled ? root.bottomRightRadius : root.windowRounding
            }
        }

        // Shown until the first frame arrives, and for good with previews off.
        Rectangle {
            anchors.fill: parent
            color: root.recents ? OverviewStyle.colWindowFallback : OverviewStyle.classicColScrollingFallback
            visible: root.hyprscrollingEnabled || (root.recents && !windowPreview.hasContent)
        }

        ScreencopyView {
            id: windowPreview
            anchors.fill: parent
            captureSource: (root.toplevel && Config.options.overview.showWindowPreviews) ? root.toplevel : null
            // Respect the configured capture mode. The transition layer uses the
            // same setting, so a live overview never silently becomes frozen just
            // because the background animation is active.
            live: root.visible && GlobalStates.overviewOpen && Config.options.background.windowZoomLiveCapture

            onLiveChanged: {
                if (!live)
                    root.requestRecapture();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: OverviewStyle.colDim
            opacity: root.dimmed ? OverviewStyle.dimOpacity : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: root.animate
                animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: !root.recents
            color: root.pressed ? OverviewStyle.classicColWindowPressed : root.hovered ? OverviewStyle.classicColWindowHover : "transparent"
        }

        Loader {
            active: !root.recents && root.showIcons
            anchors.fill: parent
            sourceComponent: Item {
                readonly property real baseSize: Math.min(root.targetWindowWidth, root.targetWindowHeight)
                readonly property bool compactMode: Appearance.font.pixelSize.smaller * 4 > root.targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > root.targetWindowWidth
                readonly property real iconSize: baseSize * (compactMode ? OverviewStyle.classicIconRatioCompact
                    : root.centerIcons ? OverviewStyle.classicIconRatioCentered : OverviewStyle.classicIconRatioCorner)

                Image {
                    x: root.centerIcons ? (parent.width - width) / 2 : parent.baseSize * OverviewStyle.classicIconGapRatio
                    y: root.centerIcons ? (parent.height - height) / 2 : parent.baseSize * OverviewStyle.classicIconGapRatio
                    width: parent.iconSize
                    height: parent.iconSize
                    source: root.iconPath
                    // The revision in the size is what makes a new theme redraw; without cache:false
                    // the size going back to one it already used serves the icon from before it.
                    cache: false
                    sourceSize: Qt.size(parent.iconSize + TaskbarApps.iconThemeRevision, parent.iconSize + TaskbarApps.iconThemeRevision)
                    Behavior on width {
                        enabled: !root.animationsDisabled
                        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
                    }
                    Behavior on height {
                        enabled: !root.animationsDisabled
                        animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: OverviewStyle.colSwapTarget
            opacity: root.swapTarget ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: root.animate
                animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
            }

            Loader {
                anchors.centerIn: parent
                active: parent.visible
                sourceComponent: MaterialShapeWrappedMaterialSymbol {
                    shape: MaterialShape.Shape.Cookie9Sided
                    text: "swap_horiz"
                    iconSize: Math.round(Math.min(Appearance.font.pixelSize.hugeass, root.height * 0.2))
                    padding: Math.round(iconSize * 0.45)
                    color: OverviewStyle.colSwapShape
                    colSymbol: OverviewStyle.colOnSwapShape
                }
            }
        }

        Rectangle {
            id: flashRect
            anchors.fill: parent
            color: OverviewStyle.colFlash
            opacity: 0
            visible: opacity > 0

            NumberAnimation {
                id: flash
                target: flashRect
                property: "opacity"
                from: root.animationsDisabled ? 0 : OverviewStyle.flashOpacity
                to: 0
                duration: OverviewStyle.motionMove.duration
                easing.type: Easing.OutCubic
            }
        }

        IconImage {
            id: fallbackIcon
            readonly property real baseSize: Math.min(root.width, root.height)
            visible: root.showFallbackIcon
            anchors.centerIn: parent
            implicitSize: Math.round(baseSize * (root.chipFits ? OverviewStyle.fallbackIconRatio : OverviewStyle.fallbackIconRatio * 2))
            source: root.iconPath
            Behavior on implicitSize {
                enabled: root.animate
                animation: OverviewStyle.motionEnter.numberAnimation.createObject(this)
            }
        }
    }

    // Above the grid's own MouseArea on this card, so the chip and menu get the clicks.
    OverviewWindowChip {
        id: chip
        z: 2
        x: root.chipInset
        y: root.chipInset
        width: implicitWidth
        height: implicitHeight
        visible: root.recents && root.chipFits && opacity > 0
        opacity: root.interactionsSuppressed ? 0 : 1
        Behavior on opacity {
            enabled: root.animate
            animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
        }

        maxWidth: root.width - 2 * root.chipInset
        compact: root.chipCompact
        appName: root.appName
        iconSource: root.iconPath
        focusedWindow: root.focusedWindow
        engaged: root.engaged
        menuOpen: root.menuOpen
        animationsEnabled: root.animate

        onClicked: root.menuOpen = !root.menuOpen
    }

    Loader {
        id: menuLoader
        z: 3
        active: root.recents && (root.menuOpen || root.menuProgress > 0)
        readonly property real menuHeight: item?.implicitHeight ?? 0
        readonly property real menuWidth: OverviewStyle.menuWidth
        readonly property real roomBelow: root.gridHeight - (root.y + chip.y + chip.height + OverviewStyle.menuGap)
        readonly property real roomAbove: root.y + chip.y - OverviewStyle.menuGap
        // Below the chip, else above it, else beside it when the grid is too short for either.
        readonly property string placement: menuLoader.roomBelow >= menuLoader.menuHeight ? "below"
            : menuLoader.roomAbove >= menuLoader.menuHeight ? "above" : "beside"
        readonly property bool upwards: menuLoader.placement === "above"
        readonly property real besideX: {
            const right = chip.x + chip.width + OverviewStyle.menuGap;
            return root.x + right + menuLoader.menuWidth <= root.gridWidth ? right : chip.x - OverviewStyle.menuGap - menuLoader.menuWidth;
        }
        x: Math.max(-root.x, Math.min(menuLoader.placement === "beside" ? menuLoader.besideX : chip.x, root.gridWidth - root.x - menuLoader.menuWidth))
        y: menuLoader.placement === "below" ? chip.y + chip.height + OverviewStyle.menuGap
            : menuLoader.placement === "above" ? chip.y - OverviewStyle.menuGap - menuLoader.menuHeight
            : Math.max(-root.y, Math.min(chip.y, root.gridHeight - root.y - menuLoader.menuHeight))

        sourceComponent: OverviewWindowMenu {
            readonly property alias hovered: menuHover.hovered
            floating: root.windowData?.floating ?? false
            fullscreen: (root.windowData?.fullscreen ?? 0) > 0
            pinned: root.windowData?.pinned ?? false
            canScreenshot: windowPreview.hasContent
            upwards: menuLoader.upwards
            progress: root.menuProgress
            animationsEnabled: root.animate
            onActionTriggered: id => root.runAction(id)

            HoverHandler {
                id: menuHover
            }
        }
    }
}
