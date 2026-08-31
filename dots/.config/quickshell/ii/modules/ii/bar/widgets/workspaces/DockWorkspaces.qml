import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

Item {
    id: root

    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical

    // ── Design tokens (matching DocktoPanel) ──────────────────────────────
    property real iconSize:     23
    property real btnSize:      28
    property real btnSpacing:   2
    property bool vertical:     false

    // ── Workspace tracking (preserved from original) ──────────────────────
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)

    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")
    property real blur: scratchpadOpen ? 1 : 0

    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: {
        if (!monitor || !monitor.name) return 0;
        let idx = HyprlandData.monitors.findIndex(mon => mon.name === monitor.name);
        return idx !== -1 ? idx : 0;
    }
    readonly property int workspaceOffset: useWorkspaceMap ? (workspaceMap.length > monitorIndex ? workspaceMap[monitorIndex] : monitorIndex * 10) : 0

    readonly property int startWsId: {
        if (dynamicWorkspaces) return workspaceOffset + 1;
        let activeVal = root.activeWsId;
        if (activeVal <= workspaceOffset) activeVal = workspaceOffset + 1;
        if (useWorkspaceMap && workspaceMap.length > monitorIndex + 1) {
            let nextMonitorStart = workspaceMap[monitorIndex + 1];
            if (activeVal > nextMonitorStart) activeVal = nextMonitorStart;
        }
        let page = Math.floor((activeVal - workspaceOffset - 1) / workspacesShown);
        return Math.max(0, page) * workspacesShown + 1 + workspaceOffset;
    }

    property var workspaceOccupied: ({})

    function updateOccupied() {
        let occupied = {};
        for (let ws of Hyprland.workspaces.values)
            occupied[ws.id] = true;
        workspaceOccupied = occupied;
    }

    property var workspaceWindows: ({})

    function updateWorkspaceWindows() {
        let windows = {};
        for (let win of HyprlandData.windowList) {
            if (!win.workspace || win.workspace.id < 1) continue;
            if (win.monitor !== root.monitorIndex) continue;
            if (!windows[win.workspace.id]) windows[win.workspace.id] = [];
            if (windows[win.workspace.id].length < 3) {
                windows[win.workspace.id].push({
                    icon: Quickshell.iconPath(AppSearch.guessIcon(win.class), "image-missing"),
                    class: win.class,
                    title: win.title
                });
            }
        }
        root.workspaceWindows = windows;
    }

    property var visibleWsModel: []
    property string _prevModelKey: ""

    function rebuildModel() {
        let list;
        if (!dynamicWorkspaces) {
            list = Array.from({length: workspacesShown}, (_, i) => startWsId + i);
        } else {
            let l = [];
            const monitorWsStart = workspaceOffset + 1;
            const monitorWsEnd = workspaceOffset + workspacesShown;
            for (let ws of Hyprland.workspaces.values) {
                if (ws.id < 1) continue;
                if (useWorkspaceMap) {
                    const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                    if (ws.id < workspaceOffset + 1 || ws.id > nextMonitorStart) continue;
                } else {
                    if (ws.id < monitorWsStart || ws.id > monitorWsEnd) continue;
                }
                if (!l.includes(ws.id)) l.push(ws.id);
            }
            if (activeWsId > 0 && !l.includes(activeWsId)) {
                if (useWorkspaceMap) {
                    const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                    if (activeWsId >= workspaceOffset + 1 && activeWsId <= nextMonitorStart) l.push(activeWsId);
                } else {
                    if (activeWsId >= monitorWsStart && activeWsId <= monitorWsEnd) l.push(activeWsId);
                }
            }
            l.sort((a, b) => a - b);
            list = l;
        }
        let key = JSON.stringify(list);
        if (key !== root._prevModelKey) {
            root.visibleWsModel = list;
            root._prevModelKey = key;
        }
    }

    Component.onCompleted: {
        updateOccupied();
        updateWorkspaceWindows();
        rebuildModel();
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateOccupied();
            updateWorkspaceWindows();
            rebuildModel();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateOccupied();
            rebuildModel();
        }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            updateWorkspaceWindows();
        }
    }
    Connections {
        target: TaskbarApps
        function onIconThemeRevisionChanged() {
            updateWorkspaceWindows();
        }
    }

    onStartWsIdChanged: rebuildModel()

    // ── Random shape support (Workspaces.qml pattern) ────────────────────
    property var shapesList: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]
    property string currentRandomShape: "Circle"
    property real randomRotation: 0

    function updateRandomShape() {
        if (!Config.options.bar.workspaces.useRandomShapeForActiveIndicator) return;
        let nextShape = currentRandomShape;
        let attempts = 0;
        while (nextShape === currentRandomShape && attempts < 10) {
            let randIdx = Math.floor(Math.random() * shapesList.length);
            nextShape = shapesList[randIdx];
            attempts++;
        }
        currentRandomShape = nextShape;
        randomRotation = randomRotation + 90;
    }

    onActiveWsIdChanged: {
        updateRandomShape();
    }

    // ── Active indicator computed position ───────────────────────────────
    readonly property int activeIndex: {
        for (let i = 0; i < root.visibleWsModel.length; i++) {
            if (root.visibleWsModel[i] === root.activeWsId) return i;
        }
        return -1;
    }

    readonly property real flowX: root.vertical ? 0 : (pill.width - flow.implicitWidth) / 2
    readonly property real flowY: root.vertical ? (pill.height - flow.implicitHeight) / 2 : 0

    readonly property real indicatorPosX: root.vertical
        ? (pill.width - root.btnSize) / 2
        : root.flowX + root.activeIndex * (root.btnSize + root.btnSpacing)
    readonly property real indicatorPosY: root.vertical
        ? root.flowY + root.activeIndex * (root.btnSize + root.btnSpacing)
        : (pill.height - root.btnSize) / 2

    // ── Implicit size (DocktoPanel style) ─────────────────────────────────
    implicitWidth:  vertical ? root.btnSize : pill.implicitWidth
    implicitHeight: vertical ? pill.implicitHeight : root.btnSize

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Behavior on blur {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // ── Blur + dim wrapper (dimmed/blurred as a whole when scratchpad is open) ──
    Item {
        id: contentContainer
        anchors.fill: parent
        z: 0
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

        // ── Container pill (transparent, like DocktoPanel) ────────────────
        Rectangle {
            id: pill
            anchors.centerIn: parent
            color: "transparent"
            radius: Appearance.rounding.full

            implicitWidth:  flow.implicitWidth + (root.vertical ? 0 : 4)
            implicitHeight: flow.implicitHeight + (root.vertical ? 4 : 0)

            Behavior on implicitWidth {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }

            // ── Active workspace indicator ───────────────────────────────
            Loader {
                id: activeIndicatorLoader
                x: root.indicatorPosX
                y: root.indicatorPosY
                width: root.btnSize
                height: root.btnSize
                visible: Config.options.bar.workspaces.dockShowActiveIndicator && root.activeIndex >= 0
                active: Config.options.bar.workspaces.dockShowActiveIndicator && root.activeIndex >= 0

                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                sourceComponent: (Config.options.bar.workspaces.useMaterialShapeForActiveIndicator || Config.options.bar.workspaces.useRandomShapeForActiveIndicator)
                    ? materialShapeComp : rectangleComp

                Component {
                    id: rectangleComp
                    Rectangle {
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                    }
                }

                Component {
                    id: materialShapeComp
                    MaterialShape {
                        anchors.fill: parent
                        transformOrigin: Item.Center
                        shapeString: Config.options.bar.workspaces.useRandomShapeForActiveIndicator
                            ? root.currentRandomShape
                            : Config.options.bar.workspaces.activeIndicatorShape
                        color: Appearance.colors.colPrimary
                        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                        rotation: Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? root.randomRotation : 0
                        Behavior on rotation {
                            RotationAnimation {
                                duration: 350
                                direction: RotationAnimation.Clockwise
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }

            Flow {
                id: flow
                anchors.centerIn: parent
                flow:    root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                spacing: root.btnSpacing

                Repeater {
                    id: repeater
                    model: root.visibleWsModel

                    delegate: Item {
                        id: wsItem
                        required property int index
                        required property var modelData

                        readonly property int wsId: modelData
                        readonly property bool isActive: wsId === root.activeWsId
                        readonly property bool isOccupied: root.workspaceOccupied[wsId] ?? false
                        readonly property var wsWindows: root.workspaceWindows[wsId] ?? []
                        readonly property string icon: wsWindows.length > 0 ? wsWindows[0].icon : ""

                        width:  root.btnSize
                        height: root.btnSize

                        // ── Hover effect (scale) ─────────────────────────────
                        readonly property real baseScale: Config.options.bar.workspaces.dockHoverEffect
                            ? (wsItem.isActive ? 1.0 : 0.9)
                            : 1.0

                        scale: wsItem.baseScale * (Config.options.bar.workspaces.dockHoverEffect && wsButton.hovered && !wsItem.isActive ? 1.08 : 1.0)
                        Behavior on scale {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }

                        // ── Scratchpad dimming ──────────────────────────────
                        opacity: root.scratchpadOpen && !wsItem.isActive ? 0.35 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 110 } }

                        RippleButton {
                            id: wsButton
                            anchors.fill: parent
                            buttonRadius: Appearance.rounding.small
                            hoverEnabled: true

                            onClicked: {
                                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsItem.wsId + "' })");
                            }

                            contentItem: Item {
                                anchors.centerIn: parent

                                // ── Icon wrapper (for shape mask) ──────────
                                Item {
                                    id: iconWrapper
                                    anchors.centerIn: parent
                                    width: root.iconSize
                                    height: root.iconSize

                                    // ── Workspace icon (first window) ──────
                                    IconImage {
                                        id: wsIcon
                                        anchors.centerIn: parent
                                        source: wsItem.icon
                                        implicitSize: root.iconSize
                                        visible: wsItem.icon !== ""
                                            && Config.options.bar.workspaces.dockShowAppIcons

                                        // Force reload when the icon theme regenerates. Resolved on this
                                        // thread: the shared icon loader is not safe to read from Qt's
                                        // image thread while the theme is changing under it.
                                        asynchronous: false
                                        backer.cache: false
                                        backer.sourceSize: Qt.size(root.iconSize + TaskbarApps.iconThemeRevision,
                                                                   root.iconSize + TaskbarApps.iconThemeRevision)
                                    }

                                    // ── Monochrome tint (DocktoPanel pattern) ──
                                    Loader {
                                        active: Config.options.bar.workspaces.monochromeIcons
                                            && wsItem.icon !== ""
                                            && Config.options.bar.workspaces.dockShowAppIcons
                                        anchors.fill: wsIcon
                                        sourceComponent: Item {
                                            Desaturate {
                                                id: desat
                                                visible: false
                                                anchors.fill: parent
                                                source: wsIcon
                                                desaturation: 0.8
                                            }
                                            ColorOverlay {
                                                anchors.fill: desat
                                                source: desat
                                                color: ColorUtils.transparentize(
                                                    Appearance.colors.colPrimary,
                                                    1.0 - (Config.options.appearance.iconTintPercentage ?? 0.6)
                                                )
                                            }
                                        }
                                    }

                                    // ── Shape mask for icons ───────────────
                                    layer.enabled: Config.options.appearance.icons.enableShapeMask
                                        && wsItem.icon !== ""
                                        && Config.options.bar.workspaces.dockShowAppIcons
                                    layer.effect: OpacityMask {
                                        maskSource: MaterialShape {
                                            anchors.fill: parent
                                            shapeString: Config.options.appearance.icons.shapeMask
                                            visible: false
                                        }
                                    }
                                }

                                // ── Fallback dot for empty workspaces ────────
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: (wsItem.icon === "" || !Config.options.bar.workspaces.dockShowAppIcons)
                                        ? (wsItem.isActive ? 7 : 5)
                                        : 0
                                    height: width
                                    radius: width / 2
                                    color: wsItem.isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                    visible: wsItem.icon === "" || !Config.options.bar.workspaces.dockShowAppIcons

                                    Behavior on width {
                                        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 150
                                        }
                                    }
                                }

                                // ── Window count dots ─────────────────────────
                                Flow {
                                    id: windowDotsFlow
                                    visible: Config.options.bar.workspaces.dockShowWindowDots
                                    flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                                    spacing: 2
                                    anchors {
                                        left:   root.vertical ? iconWrapper.right    : undefined
                                        top:    root.vertical ? undefined            : iconWrapper.bottom
                                        leftMargin:  root.vertical ? 1  : 0
                                        topMargin:   root.vertical ? 0  : 1
                                        horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                        verticalCenter:   root.vertical ? parent.verticalCenter : undefined
                                    }

                                    Repeater {
                                        model: Math.min(wsItem.wsWindows.length, 3)

                                        delegate: Rectangle {
                                            required property int index
                                            radius: Appearance.rounding.full
                                            implicitWidth:  root.vertical
                                                ? 2
                                                : wsItem.wsWindows.length <= 3 ? 4 : 2
                                            implicitHeight: root.vertical
                                                ? (wsItem.wsWindows.length <= 3 ? 4 : 2)
                                                : 2
                                            color: wsItem.isActive
                                                ? Appearance.colors.colPrimary
                                                : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } // pill

        // Position helper (invisible, inside blur container)
        Item {
            id: positionHelper
            readonly property Item activeItem: flow.children[0]
                ? (() => {
                    let items = flow.children;
                    for (let i = 0; i < items.length; i++) {
                        if (items[i] && items[i].isActive) return items[i];
                    }
                    return null;
                })()
                : null

            x: activeItem ? activeItem.x + flow.x + pill.x : 0
            y: activeItem ? activeItem.y + flow.y + pill.y : 0
            width: activeItem ? activeItem.width : root.btnSize
            height: activeItem ? activeItem.height : root.btnSize
            visible: false
        }

    } // contentContainer

    // Active workspace overlay (above blur, same position, kept sharp)
    Item {
        id: activeOverlay
        z: 10

        x: positionHelper.x
        y: positionHelper.y
        width: positionHelper.width
        height: positionHelper.height

        readonly property bool _show: root.scratchpadOpen && positionHelper.activeItem !== null
        readonly property var _activeWsWindows: root.workspaceWindows[root.activeWsId] ?? []
        readonly property string _activeIcon: _activeWsWindows.length > 0 ? _activeWsWindows[0].icon : ""

        visible: _show
        opacity: _show ? 1.0 : 0.0
        scale: _show ? 1.1 : 1.0
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Item {
            id: overlayIconWrapper
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize

            IconImage {
                id: overlayIcon
                anchors.centerIn: parent
                source: activeOverlay._activeIcon
                implicitSize: root.iconSize
                visible: activeOverlay._activeIcon !== "" && Config.options.bar.workspaces.dockShowAppIcons

                // Force reload when the icon theme regenerates. Resolved on this thread: the
                // shared icon loader is not safe to read from Qt's image thread while the
                // theme is changing under it.
                asynchronous: false
                backer.cache: false
                backer.sourceSize: Qt.size(root.iconSize + TaskbarApps.iconThemeRevision,
                                           root.iconSize + TaskbarApps.iconThemeRevision)

                layer.enabled: Config.options.appearance.icons.enableShapeMask
                layer.effect: OpacityMask {
                    maskSource: overlayIconMask
                }
            }

            MaterialShape {
                id: overlayIconMask
                anchors.fill: overlayIcon
                shapeString: Config.options.appearance.icons.shapeMask
                visible: false
            }

            Rectangle {
                anchors.centerIn: parent
                width: (activeOverlay._activeIcon === "" || !Config.options.bar.workspaces.dockShowAppIcons) ? 7 : 0
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimary
                visible: activeOverlay._activeIcon === "" || !Config.options.bar.workspaces.dockShowAppIcons
            }
        }
    }

    // ── Root MouseArea for right-click, back, scroll (NOT left-click) ────
    // Left-click is handled per-slot by RippleButton above.
    MouseArea {
        anchors.fill: parent
        z: 4
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.RightButton | Qt.BackButton

        onPressed: event => {
            if (event.button === Qt.RightButton) {
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            } else if (event.button === Qt.BackButton) {
                Hyprland.dispatch("hl.dsp.workspace.toggle_special(\"special\")");
            }
        }

        onWheel: wheel => {
            wheel.accepted = true;
            if (root.dynamicWorkspaces) {
                if (wheel.angleDelta.y > 0) Hyprland.dispatch("hl.dsp.focus({workspace = 'r-1'})");
                else Hyprland.dispatch("hl.dsp.focus({workspace = 'r+1'})");
            } else {
                let nextId = root.activeWsId + (wheel.angleDelta.y > 0 ? -1 : 1);
                if (nextId < 1) return;
                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
            }
        }
    }
}
