pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Settings -> Touch & Gestures -> Touchpad gestures.
 *
 * One card per gesture. Every change goes straight into
 * `interactions.touchpadGestures.bindings`; TouchpadGestures turns that into the snapshot
 * the compositor registers from.
 */
Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: Config.options?.interactions?.touchpadGestures ?? null

    readonly property var directionChoices: [
        { "value": "up", "name": Translation.tr("Swipe up"), "icon": "arrow_upward" },
        { "value": "down", "name": Translation.tr("Swipe down"), "icon": "arrow_downward" },
        { "value": "left", "name": Translation.tr("Swipe left"), "icon": "arrow_back" },
        { "value": "right", "name": Translation.tr("Swipe right"), "icon": "arrow_forward" },
        { "value": "horizontal", "name": Translation.tr("Swipe left or right"), "icon": "swap_horiz" },
        { "value": "vertical", "name": Translation.tr("Swipe up or down"), "icon": "swap_vert" },
        { "value": "swipe", "name": Translation.tr("Swipe in any direction"), "icon": "open_with" },
        { "value": "pinchin", "name": Translation.tr("Spread fingers apart"), "icon": "zoom_out_map" },
        { "value": "pinchout", "name": Translation.tr("Pinch fingers together"), "icon": "zoom_in_map" },
        { "value": "pinch", "name": Translation.tr("Pinch either way"), "icon": "pinch" }
    ]
    readonly property var modifierChoices: [
        { "value": "", "name": Translation.tr("No key held") },
        { "value": "SUPER", "name": "Super" },
        { "value": "CTRL", "name": "Ctrl" },
        { "value": "ALT", "name": "Alt" },
        { "value": "SHIFT", "name": "Shift" }
    ]
    readonly property var kindChoices: [
        { "value": "hyprland", "name": Translation.tr("Windows & workspaces"), "icon": "select_window" },
        { "value": "tracked", "name": Translation.tr("Shell panel that follows your fingers"), "icon": "swipe" },
        { "value": "shell", "name": Translation.tr("Shell action"), "icon": "widgets" },
        { "value": "lua", "name": Translation.tr("Scratchpad"), "icon": "inventory_2" },
        { "value": "command", "name": Translation.tr("Run a command"), "icon": "terminal" },
        { "value": "dispatch", "name": Translation.tr("Hyprland dispatcher"), "icon": "code" }
    ]
    readonly property var speedChoices: [0.5, 0.75, 1, 1.5, 2, 3]

    readonly property var shellActions:
        TouchGestureActionRegistry.availableActionsForFamily(PanelFamily.current, false).filter(a => a.id !== "none")
    readonly property var trackedActions: root.shellActions.filter(a => TouchpadGestures.trackedSurfaces.indexOf(a.id) !== -1)

    function actionsFor(kind: string): var {
        if (kind === "hyprland")
            return TouchpadGestures.nativeActions;
        if (kind === "lua")
            return TouchpadGestures.luaActions;
        if (kind === "tracked")
            return root.trackedActions;
        if (kind === "shell")
            return root.shellActions;
        return [];
    }

    function choice(list: var, value: var): var {
        return list.find(item => item.value === value) ?? null;
    }

    function isPinch(direction: string): bool {
        return direction.startsWith("pinch");
    }

    function update(index: int, patch: var): void {
        const list = TouchpadGestures.bindings.map(binding => Object.assign({}, binding));
        if (index < 0 || index >= list.length)
            return;
        Object.assign(list[index], patch);
        const entry = list[index];

        // A two-finger swipe is scrolling; it never arrives as a gesture.
        if (!root.isPinch(entry.direction) && entry.fingers < 3)
            entry.fingers = 3;
        // Only a swipe in one direction has a "how far along" to follow.
        if (entry.kind === "tracked" && ["up", "down", "left", "right"].indexOf(entry.direction) === -1)
            entry.kind = "shell";
        const actions = root.actionsFor(entry.kind);
        if (actions.length > 0 && !actions.some(action => action.id === entry.action)) {
            entry.action = actions[0].id;
            entry.mode = "";
        }
        if (actions.length === 0)
            entry.action = "";
        TouchpadGestures.setBindings(list);
    }

    function remove(index: int): void {
        const list = Array.from(TouchpadGestures.bindings);
        list.splice(index, 1);
        TouchpadGestures.setBindings(list);
    }

    /// The first slot nothing is bound to yet, so a new card never starts as a duplicate.
    function add(): void {
        const taken = TouchpadGestures.bindings.map(binding => TouchpadGestures.slotKey(binding));
        let entry = null;
        for (const fingers of [3, 4, 5]) {
            for (const direction of ["up", "down", "left", "right"]) {
                const candidate = { "fingers": fingers, "direction": direction, "mods": "" };
                if (entry === null && taken.indexOf(TouchpadGestures.slotKey(candidate)) === -1)
                    entry = candidate;
            }
        }
        entry = Object.assign(entry ?? { "fingers": 3, "direction": "up", "mods": "SUPER" },
            { "kind": "shell", "action": root.shellActions.length > 0 ? root.shellActions[0].id : "overview" });
        TouchpadGestures.setBindings(Array.from(TouchpadGestures.bindings).concat([entry]));
    }

    function reset(): void {
        TouchpadGestures.setBindings([
            { "fingers": 4, "direction": "swipe", "kind": "hyprland", "action": "move" },
            { "fingers": 4, "direction": "pinch", "kind": "hyprland", "action": "float" },
            { "fingers": 3, "direction": "horizontal", "kind": "hyprland", "action": "workspace" },
            { "fingers": 3, "direction": "up", "kind": "lua", "action": "scratchpadUp" },
            { "fingers": 3, "direction": "down", "kind": "lua", "action": "scratchpadDown" }
        ]);
    }

    function problemText(index: int): string {
        const duplicate = TouchpadGestures.duplicateOf(index);
        if (duplicate !== -1)
            return Translation.tr("Same fingers, key and direction as gesture %1 above. Only that one will fire.")
                .arg(duplicate + 1);
        const reported = TouchpadGestures.problems[index];
        if (reported === undefined)
            return "";
        if (reported === "shadowed")
            return Translation.tr("Another gesture already covers this swipe, so Hyprland did not register it.");
        return Translation.tr("Hyprland did not register this gesture: %1").arg(reported);
    }

    function summary(binding: var): string {
        if (binding.kind === "command")
            return binding.arg.length > 0 ? binding.arg : Translation.tr("No command yet");
        if (binding.kind === "dispatch")
            return binding.arg.length > 0 ? binding.arg : Translation.tr("No dispatcher yet");
        const action = root.actionsFor(binding.kind).find(a => a.id === binding.action);
        return action ? Translation.tr(action.name) : binding.action;
    }

    Component.onCompleted: TouchpadGestures.refreshStatus()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Touchpad Gestures")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "touchpad_mouse"
            title: Translation.tr("Touchpad gestures")
            tooltip: Translation.tr("What three, four and five finger swipes and pinches do.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "swipe"
                    text: Translation.tr("Enable touchpad gestures")
                    checked: root.opts?.enable ?? true
                    onCheckedChanged: {
                        if (Config.ready && root.opts && checked !== root.opts.enable)
                            root.opts.enable = checked;
                    }
                }

                NoticeBox {
                    visible: !TouchpadGestures.supported
                    Layout.fillWidth: true
                    materialIcon: "warning"
                    text: Translation.tr("The Hyprland config on this machine is older than this page: it has no hyprland/gestures.lua, so nothing set here reaches the compositor. Install the Hyprland files that ship with the shell (the update command's --hypr option) and reload.")
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Hyprland runs these itself, so window and workspace gestures keep working while the shell is restarting. A swipe in one direction wins over the same fingers on a whole axis, and an axis wins over \"any direction\".")
                }
            }
        }

        ContentSection {
            icon: "gesture"
            title: Translation.tr("Gestures")
            tooltip: Translation.tr("Each card is one gesture: how many fingers, which way, and what it does.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                enabled: root.opts?.enable ?? true
                opacity: enabled ? 1 : 0.5

                Repeater {
                    model: TouchpadGestures.bindings

                    Rectangle {
                        id: card

                        required property var modelData
                        required property int index

                        readonly property var direction: root.choice(root.directionChoices, modelData.direction)
                        readonly property var actions: root.actionsFor(modelData.kind)
                        readonly property var action: card.actions.find(a => a.id === modelData.action) ?? null
                        readonly property string problem: root.problemText(index)
                        readonly property var fingerChoices: root.isPinch(modelData.direction) ? [2, 3, 4, 5] : [3, 4, 5]
                        readonly property var modifiers: root.choice(root.modifierChoices, modelData.mods)
                            ? root.modifierChoices
                            : root.modifierChoices.concat([{ "value": modelData.mods, "name": modelData.mods }])
                        readonly property var speeds: root.speedChoices.indexOf(modelData.scale) !== -1
                            ? root.speedChoices : root.speedChoices.concat([modelData.scale])
                        readonly property bool wantsText: modelData.kind === "command" || modelData.kind === "dispatch"
                            || (card.action?.arg ?? "") !== ""

                        Layout.fillWidth: true
                        implicitHeight: cardLayout.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2

                        ColumnLayout {
                            id: cardLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer3

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: Appearance.font.pixelSize.normal
                                        text: card.direction?.icon ?? "swipe"
                                        color: Appearance.m3colors.m3primary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("%1 fingers · %2").arg(card.modelData.fingers)
                                            .arg(card.direction?.name ?? card.modelData.direction)
                                            + (card.modelData.mods.length > 0 ? ` · ${card.modelData.mods}` : "")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.summary(card.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                IconToolbarButton {
                                    text: "delete"
                                    Layout.preferredHeight: 40
                                    Layout.preferredWidth: 40
                                    onClicked: root.remove(card.index)

                                    StyledToolTip {
                                        text: Translation.tr("Remove this gesture")
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.width >= 680 ? 3 : 1
                                columnSpacing: 8
                                rowSpacing: 8

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    buttonIcon: "back_hand"
                                    model: card.fingerChoices.map(count => Translation.tr("%1 fingers").arg(count))
                                    currentIndex: Math.max(0, card.fingerChoices.indexOf(card.modelData.fingers))
                                    onActivated: index => root.update(card.index, { "fingers": card.fingerChoices[index] })
                                }

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    buttonIcon: card.direction?.icon ?? "swipe"
                                    model: root.directionChoices.map(item => item.name)
                                    currentIndex: Math.max(0, root.directionChoices.indexOf(card.direction))
                                    onActivated: index => root.update(card.index,
                                        { "direction": root.directionChoices[index].value })
                                }

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    buttonIcon: "keyboard"
                                    model: card.modifiers.map(item => item.name)
                                    currentIndex: Math.max(0, card.modifiers.findIndex(
                                        item => item.value === card.modelData.mods))
                                    onActivated: index => root.update(card.index, { "mods": card.modifiers[index].value })
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.width >= 680 ? 2 : 1
                                columnSpacing: 8
                                rowSpacing: 8

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    buttonIcon: root.choice(root.kindChoices, card.modelData.kind)?.icon ?? "widgets"
                                    model: root.kindChoices.map(item => item.name)
                                    currentIndex: Math.max(0, root.kindChoices.findIndex(
                                        item => item.value === card.modelData.kind))
                                    onActivated: index => root.update(card.index, { "kind": root.kindChoices[index].value })
                                }

                                StyledComboBox {
                                    visible: card.actions.length > 0
                                    Layout.fillWidth: true
                                    buttonIcon: card.action?.icon ?? "block"
                                    model: card.actions.map(item => Translation.tr(item.name))
                                    currentIndex: Math.max(0, card.actions.indexOf(card.action))
                                    onActivated: index => root.update(card.index,
                                        { "action": card.actions[index].id, "mode": "", "arg": "" })
                                }
                            }

                            MaterialTextField {
                                visible: card.wantsText
                                Layout.fillWidth: true
                                wrapMode: TextEdit.NoWrap
                                placeholderText: card.modelData.kind === "command" ? Translation.tr("Command to run")
                                    : card.modelData.kind === "dispatch" ? "hl.dsp.window.close()"
                                    : card.action?.arg === "zoom" ? Translation.tr("Zoom level, for example 2")
                                    : Translation.tr("Special workspace name (empty for the default one)")
                                text: card.modelData.arg
                                onEditingFinished: {
                                    if (text !== card.modelData.arg)
                                        root.update(card.index, { "arg": text });
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.width >= 680 ? 2 : 1
                                columnSpacing: 8
                                rowSpacing: 8

                                StyledComboBox {
                                    id: modePicker

                                    readonly property var modes: card.modelData.kind === "hyprland" ? (card.action?.modes ?? []) : []
                                    readonly property var labels: ({
                                        "": card.modelData.action === "float" ? Translation.tr("Toggle floating")
                                            : Translation.tr("Toggle the zoom"),
                                        "float": Translation.tr("Always float"),
                                        "tile": Translation.tr("Always tile"),
                                        "fullscreen": Translation.tr("Fullscreen"),
                                        "maximize": Translation.tr("Maximise, keeping the bar"),
                                        "mult": Translation.tr("Multiply the zoom each time"),
                                        "live": Translation.tr("Zoom with the pinch")
                                    })

                                    visible: modes.length > 0
                                    Layout.fillWidth: true
                                    buttonIcon: "tune"
                                    model: modes.map(mode => modePicker.labels[mode] ?? mode)
                                    currentIndex: Math.max(0, modes.indexOf(card.modelData.mode))
                                    onActivated: index => root.update(card.index, { "mode": modePicker.modes[index] })
                                }

                                StyledComboBox {
                                    // Hyprland scales the fingers' travel for its own gestures and
                                    // gestures.lua does the same for a tracked one; the rest fire once.
                                    visible: card.modelData.kind === "tracked"
                                        || (card.modelData.kind === "hyprland" && (card.action?.follows ?? false))
                                    Layout.fillWidth: true
                                    buttonIcon: "speed"
                                    model: card.speeds.map(speed => Translation.tr("Sensitivity ×%1").arg(speed))
                                    currentIndex: Math.max(0, card.speeds.indexOf(card.modelData.scale))
                                    onActivated: index => root.update(card.index, { "scale": card.speeds[index] })
                                }
                            }

                            StyledText {
                                visible: card.problem.length > 0
                                Layout.fillWidth: true
                                text: card.problem
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colError
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "add"
                    mainText: Translation.tr("Add a gesture")
                    onClicked: root.add()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Back to the default gestures")
                    onClicked: root.reset()
                }
            }
        }

        ContentSection {
            icon: "swipe"
            title: Translation.tr("Panels that follow your fingers")
            tooltip: Translation.tr("How far the fingers travel to open a panel all the way.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSlider {
                    buttonIcon: "straighten"
                    text: Translation.tr("Travel for a full open")
                    usePercentTooltip: false
                    from: 100
                    to: 600
                    stepSize: 10
                    value: root.opts?.trackedDistance ?? 280
                    onValueChanged: {
                        if (Config.ready && root.opts && Math.round(value) !== root.opts.trackedDistance)
                            root.opts.trackedDistance = Math.round(value);
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Let go past the halfway mark, or flick, and the panel finishes opening; let go early and it goes back. With a panel already out, swiping it back toward its edge puts it away, whatever that swipe is bound to.")
                }
            }
        }
    }
}
