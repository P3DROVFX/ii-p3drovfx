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
 * One card per gesture, folded to a one-line summary until it is opened. Every change goes
 * straight into `interactions.touchpadGestures.bindings`; TouchpadGestures turns that into the
 * snapshot the compositor registers from.
 *
 * The stored `kind` is the compositor's: "hyprland" and "lua" both run inside Hyprland and are
 * shown together as windows & workspaces, "shell" and "tracked" are one shell action with or
 * without following the fingers.
 */
Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: Config.options?.interactions?.touchpadGestures ?? null

    // ── Layout ───────────────────────────────────────────────────────────────

    /// Wide enough for two pickers side by side.
    readonly property bool wide: root.width >= 680
    readonly property real gap: Appearance.sizes.elevationMargin
    /// Inside a card: at least its corner radius, so nothing crowds the curve.
    readonly property real cardPadding: Appearance.rounding.small
    readonly property real iconBadgeSize: 36
    readonly property real headerButtonSize: 40

    // ── Page state ───────────────────────────────────────────────────────────

    /// The card open for editing, -1 when all are folded.
    property int expandedIndex: -1
    /// What the page changed on its own during the last edit: { "index", "text" } or null.
    property var adjustment: null
    /// The list before the last removal or reset: { "text", "bindings" } or null.
    property var undoState: null
    property bool resetArmed: false

    Timer {
        id: undoTimer
        interval: 10000
        onTriggered: root.undoState = null
    }

    Timer {
        id: disarmTimer
        interval: 6000
        onTriggered: root.resetArmed = false
    }

    // ── Choices ──────────────────────────────────────────────────────────────

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
    readonly property var singleDirections: ["up", "down", "left", "right"]
    /// What each wider direction also covers, for telling a card that a narrower one took part of it.
    readonly property var coveredDirections: ({
        "horizontal": ["left", "right"],
        "vertical": ["up", "down"],
        "swipe": ["up", "down", "left", "right", "horizontal", "vertical"],
        "pinch": ["pinchin", "pinchout"]
    })
    readonly property var modifierNames: ({
        "SUPER": "Super",
        "CTRL": "Ctrl",
        "ALT": "Alt",
        "SHIFT": "Shift"
    })
    readonly property var categoryChoices: [
        { "value": "windows", "name": Translation.tr("Windows & workspaces"), "icon": "select_window" },
        { "value": "shell", "name": Translation.tr("Shell action"), "icon": "widgets" },
        { "value": "command", "name": Translation.tr("Run a command"), "icon": "terminal" },
        { "value": "dispatch", "name": Translation.tr("Hyprland dispatcher"), "icon": "code" }
    ]
    readonly property var speedChoices: [0.5, 0.75, 1, 1.5, 2, 3]

    readonly property var windowActions:
        TouchpadGestures.nativeActions.map(action => Object.assign({ "kind": "hyprland" }, action))
            .concat(TouchpadGestures.luaActions.map(action => Object.assign({ "kind": "lua" }, action)))
    readonly property var shellActions:
        TouchGestureActionRegistry.availableActionsForFamily(PanelFamily.current, false).filter(a => a.id !== "none")
            .map(action => Object.assign({ "kind": "shell" }, action))

    readonly property var defaultBindings: [
        { "fingers": 4, "direction": "swipe", "kind": "hyprland", "action": "move" },
        { "fingers": 4, "direction": "pinch", "kind": "hyprland", "action": "float" },
        { "fingers": 3, "direction": "horizontal", "kind": "hyprland", "action": "workspace" },
        { "fingers": 3, "direction": "up", "kind": "lua", "action": "scratchpadUp" },
        { "fingers": 3, "direction": "down", "kind": "lua", "action": "scratchpadDown" }
    ]

    // ── Helpers ──────────────────────────────────────────────────────────────

    function categoryOf(kind: string): string {
        if (kind === "hyprland" || kind === "lua")
            return "windows";
        if (kind === "shell" || kind === "tracked")
            return "shell";
        return kind;
    }

    function actionsFor(category: string): var {
        if (category === "windows")
            return root.windowActions;
        if (category === "shell")
            return root.shellActions;
        return [];
    }

    function choice(list: var, value: var): var {
        return list.find(item => item.value === value) ?? null;
    }

    function isPinch(direction: string): bool {
        return direction.startsWith("pinch");
    }

    function isSingle(direction: string): bool {
        return root.singleDirections.indexOf(direction) !== -1;
    }

    /// Only the overview and the sidebars have a reveal to hold, and only a swipe one way has
    /// a "how far along".
    function canFollow(binding: var): bool {
        return root.categoryOf(binding.kind) === "shell" && root.isSingle(binding.direction)
            && TouchpadGestures.trackedSurfaces.indexOf(binding.action) !== -1;
    }

    function directionName(direction: string): string {
        return root.choice(root.directionChoices, direction)?.name ?? direction;
    }

    function modsLabel(mods: string): string {
        return TouchpadGestures.modsList(mods).map(key => root.modifierNames[key] ?? key).join(" + ");
    }

    function title(binding: var): string {
        const parts = [Translation.tr("%1 fingers").arg(binding.fingers), root.directionName(binding.direction)];
        if (binding.mods.length > 0)
            parts.push(Translation.tr("holding %1").arg(root.modsLabel(binding.mods)));
        return parts.join(" · ");
    }

    function summary(binding: var): string {
        if (binding.kind === "command")
            return binding.arg.length > 0 ? binding.arg : Translation.tr("No command yet");
        if (binding.kind === "dispatch")
            return binding.arg.length > 0 ? binding.arg : Translation.tr("No dispatcher yet");
        const action = root.actionsFor(root.categoryOf(binding.kind)).find(a => a.id === binding.action);
        const name = action ? Translation.tr(action.name) : binding.action;
        return binding.kind === "tracked" ? Translation.tr("%1, following the fingers").arg(name) : name;
    }

    function shellActionName(id: string): string {
        const action = root.shellActions.find(a => a.id === id);
        return action ? Translation.tr(action.name) : id;
    }

    // ── Editing ──────────────────────────────────────────────────────────────

    function update(index: int, patch: var): void {
        const list = TouchpadGestures.bindings.map(binding => Object.assign({}, binding));
        if (index < 0 || index >= list.length)
            return;
        const before = list[index];
        const entry = Object.assign({}, before, patch);
        const notes = [];

        if (!root.isPinch(entry.direction) && entry.fingers < 3) {
            entry.fingers = 3;
            notes.push(Translation.tr("Changed to 3 fingers: two fingers on the touchpad scroll, so a two-finger swipe never arrives as a gesture."));
        }

        const category = root.categoryOf(entry.kind);
        const actions = root.actionsFor(category);
        if (actions.length > 0 && !actions.some(action => action.id === entry.action)) {
            entry.action = actions[0].id;
            entry.mode = "";
            entry.arg = "";
        }
        if (actions.length === 0)
            entry.action = "";
        // Windows & workspaces mixes Hyprland's own gestures with gestures.lua handlers;
        // the action decides which of the two runs it.
        if (category === "windows")
            entry.kind = actions.find(action => action.id === entry.action)?.kind ?? "hyprland";

        if (entry.kind === "tracked" && !root.canFollow(entry)) {
            entry.kind = "shell";
            if (patch.kind === undefined)
                notes.push(root.isSingle(entry.direction)
                    ? Translation.tr("No longer follows the fingers: only the overview and the sidebars can.")
                    : Translation.tr("No longer follows the fingers: only a swipe straight up, down, left or right can."));
        }

        list[index] = entry;
        root.adjustment = notes.length > 0 ? { "index": index, "text": notes.join(" ") } : null;
        TouchpadGestures.setBindings(list);
    }

    function toggleModifier(index: int, key: string): void {
        const binding = TouchpadGestures.bindings[index];
        if (!binding)
            return;
        let keys = TouchpadGestures.modsList(binding.mods);
        if (key.length === 0)
            keys = [];
        else if (keys.indexOf(key) !== -1)
            keys = keys.filter(held => held !== key);
        else
            keys = keys.concat([key]);
        root.update(index, { "mods": TouchpadGestures.modsString(TouchpadGestures.modsList(keys.join(" "))) });
    }

    function offerUndo(text: string): void {
        root.undoState = { "text": text, "bindings": Array.from(TouchpadGestures.bindings) };
        undoTimer.restart();
    }

    function undo(): void {
        if (!root.undoState)
            return;
        const bindings = root.undoState.bindings;
        root.undoState = null;
        root.adjustment = null;
        root.expandedIndex = -1;
        TouchpadGestures.setBindings(bindings);
    }

    function remove(index: int): void {
        root.offerUndo(Translation.tr("Removed “%1”.").arg(root.title(TouchpadGestures.bindings[index])));
        const list = Array.from(TouchpadGestures.bindings);
        list.splice(index, 1);
        if (root.expandedIndex === index)
            root.expandedIndex = -1;
        else if (root.expandedIndex > index)
            root.expandedIndex -= 1;
        root.adjustment = null;
        TouchpadGestures.setBindings(list);
    }

    /// The first slot nothing is bound to yet, so a new card never starts as a duplicate.
    function add(): void {
        const taken = TouchpadGestures.bindings.map(binding => TouchpadGestures.slotKey(binding));
        let entry = null;
        for (const fingers of [3, 4, 5]) {
            for (const direction of root.singleDirections) {
                const candidate = { "fingers": fingers, "direction": direction, "mods": "" };
                if (entry === null && taken.indexOf(TouchpadGestures.slotKey(candidate)) === -1)
                    entry = candidate;
            }
        }
        entry = Object.assign(entry ?? { "fingers": 3, "direction": "up", "mods": "SUPER" },
            { "kind": "shell", "action": root.shellActions.length > 0 ? root.shellActions[0].id : "overview" });
        root.adjustment = null;
        root.expandedIndex = TouchpadGestures.bindings.length;
        TouchpadGestures.setBindings(Array.from(TouchpadGestures.bindings).concat([entry]));
    }

    /// Two presses: the first only arms it and says what the second will do.
    function reset(): void {
        if (!root.resetArmed) {
            root.resetArmed = true;
            disarmTimer.restart();
            return;
        }
        root.resetArmed = false;
        root.offerUndo(Translation.tr("Gestures set back to the defaults."));
        root.adjustment = null;
        root.expandedIndex = -1;
        TouchpadGestures.setBindings(root.defaultBindings);
    }

    // ── What a card says about itself ────────────────────────────────────────

    function problemText(index: int): string {
        const duplicate = TouchpadGestures.duplicateOf(index);
        if (duplicate !== -1)
            return Translation.tr("Same fingers, keys and direction as gesture %1 above. Only that one will fire.")
                .arg(duplicate + 1);
        const reported = TouchpadGestures.problems[index];
        if (reported === undefined)
            return "";
        if (reported === "shadowed")
            return Translation.tr("Hyprland did not register this gesture: another one already covers the same swipe.");
        return Translation.tr("Hyprland did not register this gesture: %1").arg(reported);
    }

    /// A wider gesture keeps only what narrower ones on the same fingers and keys leave it:
    /// a swipe one way wins over its axis, and an axis over any direction.
    function overlapText(index: int): string {
        const binding = TouchpadGestures.bindings[index];
        const covered = root.coveredDirections[binding?.direction] ?? [];
        if (covered.length === 0)
            return "";
        const parts = [];
        TouchpadGestures.bindings.forEach((other, i) => {
            if (i !== index && other.fingers === binding.fingers && covered.indexOf(other.direction) !== -1
                    && TouchpadGestures.modsKey(other.mods) === TouchpadGestures.modsKey(binding.mods))
                parts.push(Translation.tr("“%1” goes to gesture %2").arg(root.directionName(other.direction)).arg(i + 1));
        });
        if (parts.length === 0)
            return "";
        return Translation.tr("%1, which is more specific. This one handles the rest.").arg(parts.join(", "));
    }

    /// Shell gestures put an open panel away when they swipe back toward its edge, whatever
    /// they are bound to; Hyprland's own never reach the shell.
    function dismissText(binding: var): string {
        if (root.categoryOf(binding.kind) !== "shell" || !root.isSingle(binding.direction))
            return "";
        const surfaces = TouchpadGestures.dismissedBy(binding.direction).map(id => root.shellActionName(id));
        if (surfaces.length === 0)
            return "";
        return Translation.tr("While %1 is open, this swipe puts it away instead.")
            .arg(surfaces.join(Translation.tr(" or ")));
    }

    Component.onCompleted: TouchpadGestures.refreshStatus()

    /// A line of small print with an icon, inside a card.
    component CardNote: RowLayout {
        id: note

        property string icon: "info"
        property string text: ""
        property color color: Appearance.colors.colSubtext

        visible: note.text.length > 0
        Layout.fillWidth: true
        spacing: Appearance.sizes.elevationMargin / 2

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: note.icon
            iconSize: Appearance.font.pixelSize.normal
            color: note.color
        }

        StyledText {
            Layout.fillWidth: true
            text: note.text
            wrapMode: Text.Wrap
            color: note.color
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: root.gap

            RippleButton {
                implicitWidth: root.gap * 4
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
            icon: "gesture"
            title: Translation.tr("Gestures")
            tooltip: Translation.tr("What three, four and five finger swipes and pinches do. Hyprland runs them itself, so they keep working while the shell restarts.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                ConfigSwitch {
                    buttonIcon: "swipe"
                    text: Translation.tr("Enable touchpad gestures")
                    checked: TouchpadGestures.enabled
                    onCheckedChanged: {
                        if (Config.ready && root.opts && checked !== root.opts.enable)
                            root.opts.enable = checked;
                    }
                }

                WarningBox {
                    visible: !TouchpadGestures.supported
                    Layout.fillWidth: true
                    materialIcon: "warning"
                    text: Translation.tr("This machine's Hyprland config is older than this page, so nothing set here reaches the compositor. Install the Hyprland files that ship with the shell; the ones there now are backed up first.")

                    RippleButtonWithIcon {
                        materialIcon: "download"
                        mainText: Translation.tr("Install Hyprland files")
                        buttonRadius: Appearance.rounding.full
                        onClicked: ShellUpdates.launchHyprInstall()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.gap
                    enabled: TouchpadGestures.enabled
                    opacity: enabled ? 1 : 0.5

                    Repeater {
                        model: TouchpadGestures.bindings

                        Rectangle {
                            id: card

                            required property var modelData
                            required property int index

                            readonly property bool expanded: root.expandedIndex === card.index
                            readonly property string category: root.categoryOf(modelData.kind)
                            readonly property var direction: root.choice(root.directionChoices, modelData.direction)
                            readonly property var actions: root.actionsFor(card.category)
                            readonly property var action: card.actions.find(a => a.id === modelData.action) ?? null
                            readonly property string problem: root.problemText(index)
                            readonly property var fingerChoices: root.isPinch(modelData.direction) ? [2, 3, 4, 5] : [3, 4, 5]
                            readonly property var heldKeys: TouchpadGestures.modsList(modelData.mods)
                            /// Keys the page does not offer still show, so a hand-written one is not lost unseen.
                            readonly property var keyChoices: [""].concat(TouchpadGestures.modifierKeys)
                                .concat(card.heldKeys.filter(key => TouchpadGestures.modifierKeys.indexOf(key) === -1))
                            readonly property var speeds: root.speedChoices.indexOf(modelData.scale) !== -1
                                ? root.speedChoices : root.speedChoices.concat([modelData.scale]).sort((a, b) => a - b)
                            readonly property bool wantsText: modelData.kind === "command" || modelData.kind === "dispatch"
                                || (card.action?.arg ?? "") !== ""
                            readonly property bool hasSensitivity: modelData.kind === "tracked"
                                || (modelData.kind === "hyprland" && (card.action?.follows ?? false))

                            Layout.fillWidth: true
                            implicitHeight: cardLayout.implicitHeight + root.cardPadding * 2
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer2
                            border.width: card.problem.length > 0 ? 1 : 0
                            border.color: Appearance.colors.colError

                            ColumnLayout {
                                id: cardLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: root.cardPadding
                                spacing: root.gap

                                // ── Summary row: click to open or fold ──
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: headerRow.implicitHeight

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.expandedIndex = card.expanded ? -1 : card.index
                                    }

                                    RowLayout {
                                        id: headerRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        spacing: root.gap

                                        Rectangle {
                                            implicitWidth: root.iconBadgeSize
                                            implicitHeight: root.iconBadgeSize
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
                                                text: root.title(card.modelData)
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

                                        MaterialSymbol {
                                            visible: card.problem.length > 0
                                            text: "error"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colError
                                        }

                                        IconToolbarButton {
                                            text: "delete"
                                            Layout.preferredHeight: root.headerButtonSize
                                            Layout.preferredWidth: root.headerButtonSize
                                            onClicked: root.remove(card.index)

                                            StyledToolTip {
                                                text: Translation.tr("Remove this gesture")
                                            }
                                        }

                                        MaterialSymbol {
                                            text: card.expanded ? "expand_less" : "expand_more"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                }

                                CardNote {
                                    icon: "error"
                                    text: card.problem
                                    color: Appearance.colors.colError
                                }

                                CardNote {
                                    icon: "auto_fix_high"
                                    text: root.adjustment?.index === card.index ? root.adjustment.text : ""
                                    color: Appearance.colors.colTertiary
                                }

                                CardNote {
                                    icon: "call_split"
                                    text: root.overlapText(card.index)
                                }

                                // ── Editor ──
                                ColumnLayout {
                                    visible: card.expanded
                                    Layout.fillWidth: true
                                    spacing: root.gap

                                    ContentSubsectionLabel {
                                        text: Translation.tr("When")
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: root.wide ? 2 : 1
                                        columnSpacing: root.gap
                                        rowSpacing: root.gap

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
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Repeater {
                                            model: card.keyChoices

                                            SelectionGroupButton {
                                                id: keyButton

                                                required property string modelData
                                                required property int index

                                                leftmost: index === 0
                                                rightmost: index === card.keyChoices.length - 1
                                                buttonIcon: modelData.length === 0 ? "keyboard_off" : ""
                                                buttonText: modelData.length === 0 ? Translation.tr("No key held")
                                                    : Translation.tr("Hold %1").arg(root.modifierNames[modelData] ?? modelData)
                                                toggled: modelData.length === 0 ? card.heldKeys.length === 0
                                                    : card.heldKeys.indexOf(modelData) !== -1
                                                onClicked: root.toggleModifier(card.index, keyButton.modelData)
                                            }
                                        }
                                    }

                                    ContentSubsectionLabel {
                                        text: Translation.tr("Do")
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: root.wide ? 2 : 1
                                        columnSpacing: root.gap
                                        rowSpacing: root.gap

                                        StyledComboBox {
                                            Layout.fillWidth: true
                                            buttonIcon: root.choice(root.categoryChoices, card.category)?.icon ?? "widgets"
                                            model: root.categoryChoices.map(item => item.name)
                                            currentIndex: Math.max(0, root.categoryChoices.findIndex(
                                                item => item.value === card.category))
                                            onActivated: index => {
                                                const category = root.categoryChoices[index].value;
                                                if (category === card.category)
                                                    return;
                                                root.update(card.index, {
                                                    "kind": category === "windows" ? "hyprland" : category,
                                                    "action": "", "mode": "", "arg": ""
                                                });
                                            }
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

                                    ConfigSwitch {
                                        visible: card.category === "shell"
                                            && TouchpadGestures.trackedSurfaces.indexOf(card.modelData.action) !== -1
                                        enabled: root.isSingle(card.modelData.direction)
                                        buttonIcon: "swipe"
                                        text: Translation.tr("Follow the fingers")
                                        description: enabled
                                            ? Translation.tr("Opens as far as the fingers have moved, and settles open or shut when they lift.")
                                            : Translation.tr("Only a swipe straight up, down, left or right can follow the fingers.")
                                        checked: card.modelData.kind === "tracked"
                                        onCheckedChanged: {
                                            if (checked !== (card.modelData.kind === "tracked"))
                                                root.update(card.index, { "kind": checked ? "tracked" : "shell" });
                                        }
                                    }

                                    ColumnLayout {
                                        // Hyprland scales the fingers' travel for its own gestures and
                                        // gestures.lua does the same for a tracked one; the rest fire once.
                                        visible: card.hasSensitivity
                                        Layout.fillWidth: true
                                        spacing: root.gap / 2

                                        ContentSubsectionLabel {
                                            text: Translation.tr("Sensitivity")
                                        }

                                        ConfigSelectionArray {
                                            options: card.speeds.map(speed => ({ "displayName": `${speed}×`, "value": speed }))
                                            currentValue: card.modelData.scale
                                            onSelected: newValue => root.update(card.index, { "scale": newValue })
                                        }

                                        StyledText {
                                            visible: card.modelData.kind === "tracked"
                                            Layout.fillWidth: true
                                            text: Translation.tr("Opens fully after %1 px of finger travel.")
                                                .arg(Math.round(TouchpadGestures.trackedDistance / card.modelData.scale))
                                            wrapMode: Text.Wrap
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }

                                    CardNote {
                                        icon: "undo"
                                        text: root.dismissText(card.modelData)
                                    }
                                }
                            }
                        }
                    }

                    NoticeBox {
                        visible: root.undoState !== null
                        Layout.fillWidth: true
                        materialIcon: "history"
                        text: root.undoState?.text ?? ""

                        RippleButtonWithIcon {
                            materialIcon: "undo"
                            mainText: Translation.tr("Undo")
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.undo()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.gap

                        RippleButtonWithIcon {
                            materialIcon: "add"
                            mainText: Translation.tr("Add a gesture")
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            colText: Appearance.colors.colOnPrimary
                            onClicked: root.add()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        RippleButtonWithIcon {
                            visible: root.resetArmed
                            materialIcon: "close"
                            mainText: Translation.tr("Cancel")
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.resetArmed = false
                        }

                        RippleButtonWithIcon {
                            materialIcon: "restart_alt"
                            mainText: root.resetArmed ? Translation.tr("Replace all with the defaults")
                                : Translation.tr("Restore defaults")
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.resetArmed ? Appearance.m3colors.m3error : "transparent"
                            colText: root.resetArmed ? Appearance.m3colors.m3onError : Appearance.colors.colOnLayer1
                            onClicked: root.reset()
                        }
                    }
                }
            }
        }

        ContentSection {
            visible: TouchpadGestures.bindings.some(binding => binding.kind === "tracked")
            icon: "swipe"
            title: Translation.tr("Panels that follow your fingers")
            tooltip: Translation.tr("How far the fingers travel to open a panel all the way.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap / 2

                ConfigSlider {
                    buttonIcon: "straighten"
                    text: Translation.tr("Travel for a full open")
                    badgeText: Translation.tr("%1 px").arg(Math.round(value))
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
                    text: Translation.tr("A gesture's sensitivity divides this: at 2× the fingers travel half as far. Let go past %1% of the way, or flick, and the panel finishes opening; let go earlier and it goes back.")
                        .arg(Math.round(TouchpadGestures.commitProgress * 100))
                }
            }
        }
    }
}
