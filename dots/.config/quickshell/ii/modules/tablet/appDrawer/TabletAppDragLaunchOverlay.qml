pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tablet.windows
import "TabletDropLayout.js" as DropLayout

/**
 * An app held in the drawer and dragged out: the drawer steps aside and the desktop shows
 * where the app will open.
 *
 * Drawn inside the drawer's own surface, not a new one. The finger that picked the tile up
 * is grabbed by this surface for as long as it is down, and a Wayland grab does not move to
 * another surface mid-gesture — so the drawer fades its content to nothing, keeps its input,
 * and paints the preview itself.
 *
 * The preview is TabletDropLayout's prediction for the target workspace: the windows already
 * there, where they will be pushed, and the new one. On drop the prediction is made true
 * rather than hoped for — the window it split is focused and the side preselected before the
 * app launches.
 *
 * Holding the finger at a side edge charges an indicator and turns to the neighbouring
 * workspace, the way Android turns the page under a widget being dragged. The turn is drawn
 * here, not asked of Hyprland: switching the real workspace mid-drag ended a mouse drag on
 * the spot (seen live — the release arrived with the switch), so the neighbour is previewed
 * over its wallpaper and becomes the real workspace only on drop. Dropping on the pill at the
 * top cancels and brings the drawer back.
 */
Item {
    id: root

    required property string screenName

    property bool active: false
    /// `{ name, appId, systemIcon, launch }` from the drawer.
    property var info: null
    property real pointerX: 0
    property real pointerY: 0

    /// How far the drawer's own content has stepped aside, 0 to 1.
    property real fade: 0
    property bool fadeAnimated: true
    Behavior on fade {
        enabled: root.fadeAnimated
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    /// Off for the first frame of a drag or a page turn, so rects start where they belong
    /// instead of sliding in from wherever the last layout left them.
    property bool animateRects: false

    // ── Where ───────────────────────────────────────────────────────────────
    readonly property var monitor: (HyprlandData.monitors ?? []).find(m => String(m?.name ?? "") === root.screenName) ?? null
    readonly property real originX: Number(root.monitor?.x ?? 0)
    readonly property real originY: Number(root.monitor?.y ?? 0)
    /// The workspace actually on screen.
    readonly property int workspaceId: Number(root.monitor?.activeWorkspace?.id ?? 1)
    /// The workspace the drop goes to: the one on screen, or one reached by an edge turn.
    property int targetWorkspace: 1
    readonly property bool previewingOther: (root.active || landingTimer.running) && root.targetWorkspace !== root.workspaceId
    readonly property var area: TabletWindowActions.usableArea(root.monitor)

    property var layoutOptions: ({ layout: "dwindle", splitRatio: 1, mfact: 0.55, newStatus: "slave" })

    /// Read at the start of every drag: layout options change with the user's config, and
    /// nothing here would otherwise hear about it.
    Process {
        id: layoutProbe
        command: ["bash", "-c", "for o in general:layout dwindle:default_split_ratio master:mfact master:new_status; do hyprctl -j getoption $o | tr -d '\\n'; echo; done"]
        stdout: StdioCollector {
            id: layoutCollector
            onStreamFinished: {
                const values = layoutCollector.text.split("\n").filter(line => line.trim().length > 0).map(line => {
                    try {
                        const parsed = JSON.parse(line);
                        return parsed.str ?? parsed.float ?? parsed.int;
                    } catch (e) {
                        return undefined;
                    }
                });
                root.layoutOptions = {
                    layout: String(values[0] ?? "dwindle"),
                    splitRatio: Number(values[1] ?? 1),
                    mfact: Number(values[2] ?? 0.55),
                    newStatus: String(values[3] ?? "slave")
                };
            }
        }
    }

    readonly property var targetWindows: {
        if (!root.active)
            return [];
        return (HyprlandData.windowList ?? []).filter(w => w
            && Number(w.workspace?.id ?? -1) === root.targetWorkspace
            && !((w.fullscreen ?? 0) > 0)
            && w.hidden !== true && w.mapped !== false);
    }

    readonly property var tiledWindows: root.targetWindows.filter(w => !w.floating)
        .map(w => ({ address: w.address, cls: w.class ?? "", x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1] }))

    /// Floating windows do not move for a tiled drop, but on a previewed workspace they are
    /// part of what the user is looking at.
    readonly property var floatingWindows: root.targetWindows.filter(w => w.floating)
        .map(w => ({ address: w.address, cls: w.class ?? "", x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1] }))

    readonly property var plan: {
        if (!root.active || !root.area)
            return null;
        const settings = Config.options?.tablet?.windows;
        const a = root.area;
        const floatWidth = Math.round(a.width * Math.max(20, Math.min(100, settings?.floatWidthPercent ?? 62)) / 100);
        const floatHeight = Math.round(a.height * Math.max(20, Math.min(100, settings?.floatHeightPercent ?? 68)) / 100);
        return DropLayout.planDrop({
            point: { x: root.pointerX + root.originX, y: root.pointerY + root.originY },
            area: a,
            gapsIn: Appearance.effectiveGapsIn,
            gapsOut: Appearance.gapsOut,
            layout: root.layoutOptions.layout,
            windows: root.tiledWindows,
            splitRatio: root.layoutOptions.splitRatio,
            mfact: root.layoutOptions.mfact,
            newStatus: root.layoutOptions.newStatus,
            floating: (settings?.floatMode ?? "off") !== "off",
            floatRect: {
                x: Math.round(a.x + (a.width - floatWidth) / 2),
                y: Math.round(a.y + (a.height - floatHeight) / 2),
                width: floatWidth,
                height: floatHeight
            }
        });
    }

    /// The last plan stays on screen for a beat after the drop, so the preview hands over
    /// to the real window instead of vanishing before it has mapped.
    property var frozenPlan: null
    property var frozenFloating: []
    readonly property var shownPlan: root.active ? root.plan : (landingTimer.running ? root.frozenPlan : null)
    readonly property var shownFloating: root.active ? root.floatingWindows : (landingTimer.running ? root.frozenFloating : [])

    Timer {
        id: landingTimer
        interval: 420
    }

    // ── Cancel target ───────────────────────────────────────────────────────
    readonly property real pillTop: (root.area ? root.area.y - root.originY : 0) + 24
    /// A fixed zone rather than the pill's own geometry: the pill's width follows its text,
    /// and its text follows whether the finger is over it.
    readonly property bool overCancel: root.active
        && root.pointerY <= root.pillTop + 52 + 36
        && Math.abs(root.pointerX - root.width / 2) <= 220

    // ── Edge page turn ──────────────────────────────────────────────────────
    readonly property real edgeZone: Math.max(Appearance.sizes.minimumTouchTarget + 16, Math.round(root.width * 0.04))
    readonly property int edgeSide: !root.active ? 0
        : (root.pointerX <= root.edgeZone ? -1 : (root.pointerX >= root.width - root.edgeZone ? 1 : 0))
    readonly property bool canGoBack: root.targetWorkspace > 1
    readonly property bool canGoForward: root.targetWorkspace < 99
    readonly property int armedSide: (root.edgeSide === -1 && root.canGoBack) || (root.edgeSide === 1 && root.canGoForward)
        ? root.edgeSide : 0
    property real edgeCharge: 0

    NumberAnimation {
        id: chargeAnimation
        target: root
        property: "edgeCharge"
        from: 0
        to: 1
        duration: Math.max(200, Config.options?.tablet?.appDrawer?.edgeSwitchDelay ?? 600)
        onFinished: root.turnPage()
    }

    /// Held at the edge after a page turn: the next one comes, after a pause.
    Timer {
        id: repeatDelay
        interval: 450
        onTriggered: {
            if (root.active && root.armedSide !== 0)
                chargeAnimation.start();
        }
    }

    onArmedSideChanged: {
        chargeAnimation.stop();
        repeatDelay.stop();
        root.edgeCharge = 0;
        if (root.armedSide !== 0)
            chargeAnimation.start();
    }

    /// The page slides in from the side it was turned towards.
    property real pageShift: 0
    property real pageOpacity: 1

    ParallelAnimation {
        id: pageAnimation
        NumberAnimation {
            target: root
            property: "pageShift"
            to: 0
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "pageOpacity"
            to: 1
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    function turnPage() {
        if (!root.active || root.armedSide === 0)
            return;
        const side = root.armedSide;
        root.animateRects = false;
        root.targetWorkspace = Math.max(1, Math.min(99, root.targetWorkspace + side));
        pageAnimation.stop();
        root.pageShift = side * Math.round(root.width * 0.18);
        root.pageOpacity = 0;
        pageAnimation.start();
        Qt.callLater(() => root.animateRects = true);
        root.edgeCharge = 0;
        repeatDelay.restart();
    }

    // ── Gesture ─────────────────────────────────────────────────────────────
    function begin(info, x, y) {
        root.info = info;
        root.pointerX = x;
        root.pointerY = y;
        root.targetWorkspace = root.workspaceId;
        layoutProbe.running = true;
        HyprlandData.updateMonitors();
        HyprlandData.updateWindowList();
        landingTimer.stop();
        pageAnimation.stop();
        root.pageShift = 0;
        root.pageOpacity = 1;
        root.animateRects = false;
        root.fadeAnimated = true;
        root.fade = 1;
        root.active = true;
        Qt.callLater(() => root.animateRects = true);
    }

    function move(x, y) {
        if (!root.active)
            return;
        root.pointerX = x;
        root.pointerY = y;
    }

    function end(x, y) {
        if (!root.active)
            return;
        if (x >= 0 && y >= 0) {
            root.pointerX = x;
            root.pointerY = y;
        }
        const canceled = x < 0 || root.overCancel;
        const plan = root.plan;
        const target = root.targetWorkspace;

        chargeAnimation.stop();
        repeatDelay.stop();
        root.edgeCharge = 0;
        root.frozenPlan = canceled ? null : plan;
        root.frozenFloating = canceled ? [] : root.floatingWindows;
        if (!canceled)
            landingTimer.restart();
        root.active = false;

        if (canceled) {
            // Back to the drawer, which never closed.
            root.fade = 0;
            return;
        }

        // The drawer still holds the keyboard, and Hyprland will not focus the window the
        // plan splits until it lets go — so let go first, and place the app a beat later.
        root.releasingKeyboard = true;
        GlobalStates.appDrawerOpen = false;
        placementTimer.pending = { target: target, plan: plan, info: root.info };
        placementTimer.restart();
    }

    /// Set on drop; the drawer window reads it to give up keyboard focus.
    property bool releasingKeyboard: false

    Timer {
        id: placementTimer
        interval: 140
        property var pending: null
        onTriggered: root.commitDrop(placementTimer.pending)
    }

    function commitDrop(pending) {
        if (!pending)
            return;
        placementTimer.pending = null;
        if (pending.target !== root.workspaceId)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${pending.target} })`);
        const plan = pending.plan;
        if (plan && plan.mode === "dwindle" && plan.targetAddress.length > 0) {
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${plan.targetAddress}" })`);
            Hyprland.dispatch(`hl.dsp.layout("preselect ${plan.direction}")`);
        }
        pending.info?.launch?.();
    }

    /// The drawer finished closing: its content can come back for the next open.
    function resetFade() {
        root.fadeAnimated = false;
        root.fade = 0;
        root.fadeAnimated = true;
        root.releasingKeyboard = false;
    }

    // ── Drawing ─────────────────────────────────────────────────────────────
    readonly property bool shown: root.shownPlan !== null

    // Another workspace is being previewed: its wallpaper covers the one on screen, whose
    // windows would otherwise show through a preview of somewhere else.
    Image {
        anchors.fill: parent
        source: Config.options?.background?.wallpaperPath ?? ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(root.width, root.height)
        opacity: root.previewingOther ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: root.active ? 0.3 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
        }
    }

    /// Everything that belongs to the target workspace, so a page turn slides it as one.
    Item {
        id: page
        anchors.fill: parent
        opacity: root.pageOpacity
        transform: Translate {
            x: root.pageShift
        }

        // The windows already on the workspace, where the drop will leave them.
        Repeater {
            model: ScriptModel {
                objectProp: "address"
                values: root.shownPlan?.windows ?? []
            }

            delegate: Rectangle {
                id: existing
                required property var modelData

                readonly property var entry: (root.shownPlan?.windows ?? []).find(w => w.address === existing.modelData.address) ?? existing.modelData
                readonly property var target: root.overCancel ? existing.entry.from : existing.entry.to
                readonly property bool isSplitTarget: root.shownPlan?.targetAddress === existing.modelData.address && !root.overCancel
                /// Starts on the real window and slides to where the drop will put it.
                property bool settled: false
                readonly property var place: existing.settled ? existing.target : existing.entry.from

                x: existing.place.x - root.originX
                y: existing.place.y - root.originY
                width: existing.place.width
                height: existing.place.height
                radius: Appearance.rounding.windowRounding
                color: existing.isSplitTarget ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                opacity: root.active ? 0.95 : 0

                Component.onCompleted: Qt.callLater(() => existing.settled = true)

                Behavior on x {
                    enabled: root.animateRects
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(existing)
                }
                Behavior on y {
                    enabled: root.animateRects
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(existing)
                }
                Behavior on width {
                    enabled: root.animateRects
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(existing)
                }
                Behavior on height {
                    enabled: root.animateRects
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(existing)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(existing)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(existing)
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.round(Math.max(24, Math.min(72, Math.min(parent.width, parent.height) * 0.3)))
                    source: Quickshell.iconPath(AppSearch.guessIcon(existing.modelData.cls), "image-missing")
                }
            }
        }

        Repeater {
            model: ScriptModel {
                objectProp: "address"
                values: root.shownFloating
            }

            delegate: Rectangle {
                id: floater
                required property var modelData
                x: floater.modelData.x - root.originX
                y: floater.modelData.y - root.originY
                width: floater.modelData.width
                height: floater.modelData.height
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer1
                opacity: root.active ? 0.95 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(floater)
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.round(Math.max(24, Math.min(64, Math.min(parent.width, parent.height) * 0.3)))
                    source: Quickshell.iconPath(AppSearch.guessIcon(floater.modelData.cls), "image-missing")
                }
            }
        }

        // The app being dropped, in the space it will take.
        Rectangle {
            id: incoming
            readonly property var target: root.shownPlan?.incoming ?? null
            readonly property real startSize: 72

            x: incoming.target ? incoming.target.x - root.originX : root.pointerX - incoming.startSize / 2
            y: incoming.target ? incoming.target.y - root.originY : root.pointerY - incoming.startSize / 2
            width: incoming.target ? incoming.target.width : incoming.startSize
            height: incoming.target ? incoming.target.height : incoming.startSize
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colPrimaryContainer
            opacity: root.shown && !root.overCancel ? 1 : 0
            visible: opacity > 0

            Behavior on x {
                enabled: root.animateRects
                animation: Appearance.animation.elementMove.numberAnimation.createObject(incoming)
            }
            Behavior on y {
                enabled: root.animateRects
                animation: Appearance.animation.elementMove.numberAnimation.createObject(incoming)
            }
            Behavior on width {
                enabled: root.animateRects
                animation: Appearance.animation.elementMove.numberAnimation.createObject(incoming)
            }
            Behavior on height {
                enabled: root.animateRects
                animation: Appearance.animation.elementMove.numberAnimation.createObject(incoming)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(incoming)
            }

            Column {
                id: incomingLabel
                anchors.centerIn: parent
                spacing: 12
                width: parent.width - 32
                // Gives way to the icon under the finger instead of stacking a second copy
                // of the same icon right beside it.
                readonly property real fingerDistance: Math.hypot(
                    root.pointerX - (incoming.x + incoming.width / 2),
                    root.pointerY - 56 - (incoming.y + incoming.height / 2))
                opacity: root.active ? Math.max(0, Math.min(1, (incomingLabel.fingerDistance - 60) / 120)) : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(incomingLabel)
                }

                AppGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Math.round(Math.max(32, Math.min(96, Math.min(incoming.width, incoming.height) * 0.28)))
                    appId: root.info?.appId ?? ""
                    systemIcon: root.info?.systemIcon ?? ""
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: incoming.height > 180
                    text: root.info?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    // ── Edges ───────────────────────────────────────────────────────────────
    Repeater {
        model: [-1, 1]

        delegate: Item {
            id: edge
            required property int modelData
            readonly property bool available: edge.modelData === 1 ? root.canGoForward : root.canGoBack
            readonly property bool armed: root.armedSide === edge.modelData
            readonly property color glow: Appearance.colors.colPrimary

            y: 0
            height: root.height
            width: root.edgeZone * 2
            x: edge.modelData < 0 ? 0 : root.width - edge.width
            opacity: !root.active || !edge.available ? 0 : 1

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(edge)
            }

            // A glow from the screen edge, stronger once the finger is in it.
            Rectangle {
                anchors.fill: parent
                opacity: edge.armed ? 1 : 0.45
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: edge.modelData < 0 ? ColorUtils.applyAlpha(edge.glow, 0.42) : "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: edge.modelData < 0 ? "transparent" : ColorUtils.applyAlpha(edge.glow, 0.42)
                    }
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(edge)
                }
            }

            Item {
                id: knob
                readonly property real size: 56
                width: knob.size
                height: knob.size
                x: edge.modelData < 0 ? 20 : edge.width - knob.size - 20
                // Below the finger while armed: above it is where the carried icon rides.
                y: edge.armed
                    ? Math.max(root.pillTop + 90, Math.min(root.height - knob.size - 140, root.pointerY + 20))
                    : (root.height - knob.size) / 2

                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(knob)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                }

                // Fills from the centre as the page turn charges.
                Rectangle {
                    anchors.centerIn: parent
                    width: knob.size * (edge.armed ? root.edgeCharge : 0)
                    height: width
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: edge.modelData < 0 ? "chevron_left" : "chevron_right"
                    iconSize: 30
                    color: edge.armed && root.edgeCharge > 0.5 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }

                Rectangle {
                    anchors.top: parent.bottom
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: edgeLabel.implicitWidth + 20
                    height: edgeLabel.implicitHeight + 10
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer1
                    opacity: edge.armed ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(edge)
                    }

                    StyledText {
                        id: edgeLabel
                        anchors.centerIn: parent
                        text: Math.max(1, root.targetWorkspace + edge.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    // ── Status and cancel ───────────────────────────────────────────────────
    Rectangle {
        id: statusPill
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.pillTop + (root.active ? 0 : -16)
        height: 52
        width: statusRow.implicitWidth + 40
        radius: Appearance.rounding.full
        color: root.overCancel ? Appearance.colors.colError : Appearance.colors.colLayer1
        opacity: root.active ? 1 : 0
        visible: opacity > 0

        Behavior on y {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(statusPill)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(statusPill)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(statusPill)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(statusPill)
        }

        Row {
            id: statusRow
            anchors.centerIn: parent
            spacing: 10

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.overCancel ? "close" : "space_dashboard"
                iconSize: 22
                color: root.overCancel ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.overCancel ? Translation.tr("Release to cancel") : (Translation.tr("Workspace") + " " + root.targetWorkspace)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.overCancel ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.overCancel
                text: Translation.tr("Hold at an edge to switch")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    // The icon under the finger, lifted above it so the finger does not hide what it holds.
    Item {
        id: carried
        width: 72
        height: 72
        x: Math.max(8, Math.min(root.width - carried.width - 8, root.pointerX - carried.width / 2))
        y: Math.max(8, root.pointerY - carried.height - 20)
        opacity: root.active ? 1 : 0
        // Shrinks over the cancel target: the one place where letting go does nothing.
        scale: root.overCancel ? 0.8 : 1

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(carried)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(carried)
        }

        AppGlyph {
            anchors.fill: parent
            size: carried.width
            appId: root.info?.appId ?? ""
            systemIcon: root.info?.systemIcon ?? ""
        }
    }

    // Takes what it draws as properties: an inline component does not see this file's ids.
    component AppGlyph: Item {
        id: glyph
        property real size: 64
        property string appId: ""
        property string systemIcon: ""
        implicitWidth: glyph.size
        implicitHeight: glyph.size

        IconImage {
            anchors.fill: parent
            visible: glyph.systemIcon.length === 0
            source: glyph.appId.length > 0 ? Quickshell.iconPath(AppSearch.guessIcon(glyph.appId), "image-missing") : ""
        }

        Rectangle {
            anchors.fill: parent
            visible: glyph.systemIcon.length > 0
            radius: width * 0.28
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                text: glyph.systemIcon
                iconSize: Math.round(glyph.size * 0.52)
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
