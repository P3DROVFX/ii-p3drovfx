pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import Quickshell
import Quickshell.Hyprland

/**
 * Index workspaces.
 *
 * No shape anywhere: the workspaces are numerals, and the one you are on is
 * simply much bigger than the rest — a page index. Weight, size and opacity do
 * all the work, which makes this the one style where an unusual numeral system
 * (Greek, Roman, counting rods) is the design rather than a decoration on it.
 *
 *   active    large, bold, accent
 *   occupied  small, legible
 *   empty     small, faint
 *
 * Every slot is the same fixed width, measured off the largest label the row
 * can hold. Sizing each slot to its own numeral would make the row jump every
 * time the big numeral moved — and on a numeral system where 10 is two glyphs,
 * jump again at ten.
 */
Item {
    id: root

    property bool vertical: false

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")
    property real blur: root.scratchpadOpen ? 1 : 0

    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int activeWsId: root.monitor?.activeWorkspace?.id ?? (root.workspaceOffset + 1)
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window && root.QsWindow.window.screen ? Quickshell.screens.indexOf(root.QsWindow.window.screen) : 0
    readonly property int workspaceOffset: root.useWorkspaceMap ? (root.workspaceMap[root.monitorIndex] ?? 0) : 0

    // ── Type ─────────────────────────────────────────────────────────────────
    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    readonly property real activePixelSize: Math.max(12, Math.round(root.thickness * 0.52))
    readonly property real restPixelSize: Math.max(8, Math.round(root.thickness * 0.3))
    // How far the hovered numeral lifts. It travels inside the slot it already
    // has, so the row cannot reflow under the pointer.
    readonly property real hoverLift: Math.round(root.thickness * 0.08)

    // The widest label at active size, so a slot never has to grow for its own
    // content. Measured, not guessed: a counting-rod ten is two glyphs wide and
    // a Roman eighteen is four.
    readonly property real slot: Math.max(
        Math.round(root.thickness * 0.46),
        Math.ceil(widestMetrics.implicitWidth) + Math.round(root.thickness * 0.14))

    readonly property real rowLength: root.slot * Math.max(1, root.visibleWsModel.length)

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.rowLength
    implicitHeight: root.vertical ? root.rowLength : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on blur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    function labelFor(wsId) {
        const map = Config.options?.bar.workspaces.numberMap ?? [];
        return (map[wsId - 1] || wsId).toString();
    }

    readonly property string widestLabel: {
        let widest = "";
        for (const wsId of root.visibleWsModel) {
            const label = root.labelFor(wsId);
            if (label.length > widest.length)
                widest = label;
        }
        return widest === "" ? "0" : widest;
    }

    // Measured, never drawn.
    StyledText {
        id: widestMetrics
        visible: false
        text: root.widestLabel
        font.family: Appearance.font.family.numbers
        font.pixelSize: root.activePixelSize
        font.weight: Font.Bold
    }

    // ── Which workspaces are on show ─────────────────────────────────────────
    readonly property int startWsId: {
        if (root.dynamicWorkspaces)
            return root.workspaceOffset + 1;
        let activeVal = root.activeWsId;
        if (activeVal <= root.workspaceOffset)
            activeVal = root.workspaceOffset + 1;
        if (root.useWorkspaceMap && root.workspaceMap.length > root.monitorIndex + 1) {
            const nextMonitorStart = root.workspaceMap[root.monitorIndex + 1];
            if (activeVal > nextMonitorStart)
                activeVal = nextMonitorStart;
        }
        const page = Math.floor((activeVal - root.workspaceOffset - 1) / root.workspacesShown);
        return Math.max(0, page) * root.workspacesShown + 1 + root.workspaceOffset;
    }

    readonly property var visibleWsModel: {
        if (!root.dynamicWorkspaces)
            return Array.from({
                length: root.workspacesShown
            }, (_, i) => root.startWsId + i);

        const list = [];
        const nextMonitorStart = root.workspaceMap[root.monitorIndex + 1]
            ?? (root.workspaceOffset + root.workspacesShown);
        for (const ws of Hyprland.workspaces.values) {
            if (ws.id < 1)
                continue;
            if (root.useWorkspaceMap && (ws.id < root.workspaceOffset + 1 || ws.id > nextMonitorStart))
                continue;
            if (!list.includes(ws.id))
                list.push(ws.id);
        }
        if (root.activeWsId > 0 && !list.includes(root.activeWsId)) {
            if (!root.useWorkspaceMap
                || (root.activeWsId >= root.workspaceOffset + 1 && root.activeWsId <= nextMonitorStart))
                list.push(root.activeWsId);
        }
        list.sort((a, b) => a - b);
        return list;
    }

    property var workspaceOccupied: ({})
    function updateOccupied() {
        const occupied = {};
        for (const ws of Hyprland.workspaces.values)
            occupied[ws.id] = true;
        root.workspaceOccupied = occupied;
    }

    Component.onCompleted: root.updateOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateOccupied();
        }
    }

    // ── The index ────────────────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(content)
        }

        Repeater {
            model: root.visibleWsModel

            delegate: Item {
                id: slotItem

                required property int index
                required property int modelData
                readonly property int wsId: slotItem.modelData
                readonly property bool isActive: slotItem.wsId === root.activeWsId
                readonly property bool isOccupied: root.workspaceOccupied[slotItem.wsId] ?? false

                x: root.vertical ? 0 : slotItem.index * root.slot
                y: root.vertical ? slotItem.index * root.slot : 0
                width: root.vertical ? parent.width : root.slot
                height: root.vertical ? root.slot : parent.height

                HoverHandler {
                    id: numeralHover
                    cursorShape: Qt.PointingHandCursor
                }

                StyledText {
                    id: numeral
                    anchors.centerIn: parent
                    // Lifts inside its own slot, so the row never reflows.
                    anchors.verticalCenterOffset: numeralHover.hovered && !slotItem.isActive
                        ? -root.hoverLift
                        : 0

                    text: root.labelFor(slotItem.wsId)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: slotItem.isActive ? root.activePixelSize : root.restPixelSize
                    font.weight: slotItem.isActive ? Font.Bold : (slotItem.isOccupied ? Font.DemiBold : Font.Normal)
                    font.features: ({
                        "tnum": 1
                    })

                    color: (slotItem.isActive || numeralHover.hovered)
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnLayer1
                    opacity: {
                        if (slotItem.isActive)
                            return Config.options.bar.workspaces.activeIndicatorOpacity / 100;
                        if (numeralHover.hovered)
                            return 1.0;
                        return slotItem.isOccupied ? 0.75 : 0.32;
                    }

                    Behavior on font.pixelSize {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on anchors.verticalCenterOffset {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(numeral)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + slotItem.wsId + "' })")
                }
            }
        }
    }

    // ── Scratchpad ───────────────────────────────────────────────────────────
    Loader {
        anchors.centerIn: parent
        active: root.scratchpadOpen
        visible: active

        sourceComponent: MaterialShape {
            implicitSize: Math.round(root.thickness * 0.52)
            shapeString: "Flower"
            color: Appearance.colors.colTertiary
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wheel.accepted = true;
            if (root.dynamicWorkspaces) {
                Hyprland.dispatch(wheel.angleDelta.y > 0
                    ? "hl.dsp.focus({workspace = 'r-1'})"
                    : "hl.dsp.focus({workspace = 'r+1'})");
                return;
            }
            const nextId = root.activeWsId + (wheel.angleDelta.y > 0 ? -1 : 1);
            if (nextId < 1)
                return;
            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
        }
    }
}
