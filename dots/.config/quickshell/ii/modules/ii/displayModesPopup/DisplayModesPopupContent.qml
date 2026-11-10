pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models.hyprland

/**
 * The display modes card: where the screens are, and what they show.
 *
 * Modes are the Win+P set — extend, duplicate (every other screen mirrors one source),
 * or only one screen on. A change is written through MonitorConfigOption, the same
 * hyprmon path the Displays settings page uses, so the two never disagree.
 */
Item {
    id: root

    signal dismissed

    /**
     * Drawn on a host's surface rather than as a floating card of its own; see
     * LocalSendPopupContent.hosted for why.
     */
    property bool hosted: false
    readonly property real surfaceMargin: root.hosted ? 0 : Appearance.sizes.elevationMargin

    readonly property real cardWidth: 392
    readonly property real contentPadding: 18

    implicitWidth: root.cardWidth + 2 * root.surfaceMargin
    implicitHeight: contentLayout.implicitHeight + root.contentPadding * 2 + 2 * root.surfaceMargin

    readonly property bool isHovered: rootHover.hovered || stage.dragName !== ""

    HoverHandler {
        id: rootHover
    }

    // Static, unscaled item for the window input mask.
    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
    }

    // ── Data ─────────────────────────────────────────────────────────────────
    MonitorConfigOption {
        id: monitorConfig
        onMonitorsChanged: {
            if (root.awaitingFetch) {
                root.awaitingFetch = false;
                root.applying = false;
            }
        }
    }

    readonly property var monitors: monitorConfig.monitors || []
    readonly property int screenCount: root.monitors.length
    readonly property bool multi: root.screenCount > 1

    /// "extend", "duplicate" or "only"; with `modeTarget` the source or the lone screen.
    readonly property string mode: {
        const mirroring = root.monitors.find(m => m && !m.disabled && m.mirrorOf && m.mirrorOf !== "none");
        if (mirroring)
            return "duplicate";
        const active = root.monitors.filter(m => m && !m.disabled);
        if (root.multi && active.length === 1)
            return "only";
        return "extend";
    }
    readonly property string modeTarget: {
        if (root.mode === "duplicate")
            return root.monitors.find(m => m && !m.disabled && m.mirrorOf && m.mirrorOf !== "none").mirrorOf;
        if (root.mode === "only")
            return root.monitors.find(m => m && !m.disabled).name;
        return "";
    }

    /// The screen a new duplicate copies: the built-in panel if there is one.
    readonly property string defaultSource: {
        const builtIn = root.monitors.find(m => m && root.isBuiltIn(m.name));
        if (builtIn)
            return builtIn.name;
        return Hyprland.focusedMonitor?.name ?? (root.monitors[0]?.name ?? "");
    }

    function isBuiltIn(name) {
        return /^(eDP|LVDS|DSI)/.test(name || "");
    }

    function screenLabel(m) {
        if (!m)
            return "";
        if (root.isBuiltIn(m.name))
            return Translation.tr("Built-in display");
        const desc = (m.description || "").replace(/\s*\(.*\)\s*$/, "").trim();
        return desc.length > 0 ? desc : m.name;
    }

    // ── Applying ─────────────────────────────────────────────────────────────
    property bool applying: false
    property bool awaitingFetch: false

    Timer {
        id: applyingTimeout
        interval: 6000
        onTriggered: {
            root.applying = false;
            root.awaitingFetch = false;
        }
    }

    function commit(list) {
        if (!list.some(m => !m.disabled))
            return;
        monitorConfig.monitors = list;
        monitorConfig.save();
        root.applying = true;
        root.awaitingFetch = true;
        applyingTimeout.restart();
    }

    function setExtend() {
        const list = root.monitors.map(m => Object.assign({}, m));
        const placed = [];
        const free = [];
        for (const m of list) {
            const wasOwnPicture = !m.disabled && (!m.mirrorOf || m.mirrorOf === "none");
            m.disabled = false;
            m.mirrorOf = "none";
            (wasOwnPicture ? placed : free).push(m);
        }
        // Screens that were off or mirroring come back to the right of the desk.
        const rect = m => ({ x: m.x, y: m.y, w: monitorConfig.logicalWidth(m), h: monitorConfig.logicalHeight(m) });
        const overlaps = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
        for (const m of free) {
            if (placed.length > 0 && placed.some(p => overlaps(rect(m), rect(p)))) {
                const right = Math.max(...placed.map(p => p.x + monitorConfig.logicalWidth(p)));
                m.x = right;
                m.y = Math.min(...placed.map(p => p.y));
            }
            placed.push(m);
        }
        root.commit(list);
    }

    function setDuplicate(source) {
        root.commit(root.monitors.map(m => Object.assign({}, m, {
            disabled: false,
            mirrorOf: m.name === source ? "none" : source
        })));
    }

    function setOnly(name) {
        root.commit(root.monitors.map(m => Object.assign({}, m, {
            disabled: m.name !== name,
            mirrorOf: "none"
        })));
    }

    function applyArrangement(positions) {
        root.commit(root.monitors.map(m => positions[m.name] ? Object.assign({}, m, positions[m.name]) : Object.assign({}, m)));
    }

    // ── Dismissal ────────────────────────────────────────────────────────────
    Timer {
        id: dismissTimer
        interval: 8000
        running: !root.isHovered && !root.applying
        onTriggered: root.dismissed()
    }

    // ── Entrance: one scalar, every piece reads its slice ───────────────────
    property real reveal: 0
    NumberAnimation on reveal {
        from: 0
        to: 1
        duration: Appearance.reducedMotion ? 0 : Appearance.animation.popupEnter.duration * 2
        running: true
    }
    function slice(slot) {
        const lead = 0.12, span = 0.5, step = 0.07;
        const t = Math.max(0, Math.min(1, (root.reveal - lead * (slot > 0 ? 1 : 0) - step * slot) / span));
        return t * t * (3 - 2 * t);
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
        radius: Appearance.rounding.large
        color: root.hosted ? "transparent"
            : (Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer)

        // Hosted, the island plays the arrival; standalone the card fades and drops in.
        opacity: root.hosted ? 1 : Math.min(1, root.reveal * 5)
        transform: Translate {
            y: root.hosted ? 0 : (1 - root.slice(0)) * -10
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.contentPadding
            }
            spacing: 14

            // ═══ Header ═══
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                opacity: root.slice(0)

                MaterialShapeWrappedMaterialSymbol {
                    text: "desktop_windows"
                    iconSize: 22
                    padding: 10
                    shape: root.applying ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Displays")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge + 2
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.applying ? Translation.tr("Applying…")
                            : root.screenCount === 1 ? Translation.tr("1 screen connected")
                            : Translation.tr("%1 screens connected").arg(root.screenCount)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: {
                        GlobalStates.openSettingsPage("displays");
                        root.dismissed();
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "settings"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: Translation.tr("Display settings")
                    }
                }
            }

            // ═══ Arrangement ═══
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                opacity: root.slice(1)

                DisplayArrangementStage {
                    id: stage
                    anchors.fill: parent
                    monitors: root.monitors
                    draggable: root.mode === "extend" && root.multi && !root.applying
                    logicalWidth: m => monitorConfig.logicalWidth(m)
                    logicalHeight: m => monitorConfig.logicalHeight(m)
                    onArranged: positions => root.applyArrangement(positions)
                }

                StyledText {
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: 4
                    }
                    visible: stage.draggable
                    opacity: stage.dragName === "" ? 0.75 : 0
                    text: Translation.tr("Drag a screen to rearrange")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            // Only one screen: nothing to choose between.
            RowLayout {
                Layout.fillWidth: true
                visible: !root.multi && root.screenCount > 0
                spacing: 10
                opacity: root.slice(2)

                MaterialSymbol {
                    text: "cable"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Connect another screen to extend or duplicate")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            // ═══ Modes ═══
            StyledText {
                Layout.topMargin: 2
                visible: root.multi
                text: Translation.tr("Project")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
                opacity: root.slice(2)
            }

            ColumnLayout {
                id: modeGroup
                Layout.fillWidth: true
                visible: root.multi
                spacing: 3

                readonly property var entries: {
                    const list = [
                        { mode: "extend", target: "", icon: "view_column", shape: MaterialShape.Shape.Cookie7Sided,
                          title: Translation.tr("Extend"), detail: Translation.tr("Every screen is its own space") },
                        { mode: "duplicate", target: "", icon: "content_copy", shape: MaterialShape.Shape.Clover4Leaf,
                          title: Translation.tr("Duplicate"), detail: Translation.tr("Every screen shows the same picture") }
                    ];
                    for (const m of root.monitors) {
                        if (!m)
                            continue;
                        list.push({
                            mode: "only", target: m.name,
                            icon: root.isBuiltIn(m.name) ? "laptop" : "monitor",
                            shape: root.isBuiltIn(m.name) ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Cookie12Sided,
                            title: Translation.tr("Only %1").arg(m.name),
                            detail: root.screenLabel(m)
                        });
                    }
                    return list;
                }

                Repeater {
                    model: root.multi ? modeGroup.entries : []

                    delegate: ModeRow {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        entry: modelData
                        slot: 3 + index
                        isFirst: index === 0
                        isLast: index === modeGroup.entries.length - 1
                        selected: modelData.mode === root.mode
                            && (modelData.mode !== "only" || modelData.target === root.modeTarget)
                        onClicked: {
                            if (root.applying || selected)
                                return;
                            if (modelData.mode === "extend")
                                root.setExtend();
                            else if (modelData.mode === "duplicate")
                                root.setDuplicate(root.defaultSource);
                            else
                                root.setOnly(modelData.target);
                        }
                    }
                }
            }

            // ═══ Mirror source: which screen the others copy ═══
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.multi && root.mode === "duplicate"
                spacing: 8

                StyledText {
                    text: Translation.tr("Mirror the picture of")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.mode === "duplicate" ? root.monitors : []

                        delegate: RippleButton {
                            id: sourceChip
                            required property var modelData
                            readonly property bool current: modelData.name === root.modeTarget

                            implicitHeight: 34
                            implicitWidth: chipRow.implicitWidth + 28
                            buttonRadius: sourceChip.current ? Appearance.rounding.small : Appearance.rounding.full
                            toggled: sourceChip.current
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
                            onClicked: {
                                if (!root.applying && !sourceChip.current)
                                    root.setDuplicate(modelData.name);
                            }

                            contentItem: Item {
                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        text: sourceChip.current ? "check" : (root.isBuiltIn(sourceChip.modelData.name) ? "laptop" : "monitor")
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: sourceChip.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: sourceChip.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: sourceChip.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A mode: shape icon, title, one line of detail. The group is one shape —
    // outer corners large, joins small — and the chosen row becomes a pill.
    component ModeRow: RippleButton {
        id: row

        property var entry
        property int slot: 0
        property bool isFirst: false
        property bool isLast: false
        property bool selected: false

        readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)
        readonly property real rOuter: Appearance.rounding.large
        readonly property real rJoin: Appearance.rounding.verysmall

        implicitHeight: 62
        toggled: row.selected
        topLeftRadius: row.selected ? row.rFull : (row.isFirst ? row.rOuter : row.rJoin)
        topRightRadius: row.selected ? row.rFull : (row.isFirst ? row.rOuter : row.rJoin)
        bottomLeftRadius: row.selected ? row.rFull : (row.isLast ? row.rOuter : row.rJoin)
        bottomRightRadius: row.selected ? row.rFull : (row.isLast ? row.rOuter : row.rJoin)

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive

        // The cascade drives opacity and visualScale; scale is the button's own.
        opacityBehaviorEnabled: root.reveal >= 1
        opacity: (row.enabled ? 1 : 0.4) * root.slice(row.slot)
        visualScale: 0.965 + 0.035 * root.slice(row.slot)

        readonly property color colContent: row.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

        contentItem: RowLayout {
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                Layout.leftMargin: 6
                text: row.entry ? row.entry.icon : ""
                iconSize: 20
                padding: 9
                // Shape is state: a plain circle until this is the mode in use.
                shape: row.selected && row.entry ? row.entry.shape : MaterialShape.Shape.Circle
                color: row.selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                colSymbol: row.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.title : ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: row.selected ? Font.Bold : Font.DemiBold
                    color: row.colContent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.detail : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.colContent
                    opacity: 0.75
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                Layout.rightMargin: 10
                text: "check"
                iconSize: Appearance.font.pixelSize.larger
                color: row.colContent
                opacity: row.selected ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
