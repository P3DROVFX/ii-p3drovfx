pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The row of chips above the composer.
 *
 * Everything the chat can be told to do with a slash command has a chip here,
 * and the chips never go away: the old provider row and model combo were only
 * shown on an empty chat, which is exactly when nobody needs to switch. The
 * commands stay as an accelerator, not as the only way in.
 *
 * Popovers are drawn into `overlayParent` — the transcript above the bar — so
 * they open upward, over the messages, and a click anywhere on the transcript
 * closes them. Nothing here creates a Wayland surface of its own.
 */
Item {
    id: root

    /** Where popovers are drawn. They anchor to its bottom, above this bar. */
    property Item overlayParent: null
    property string commandPrefix: "/"
    property var inputField: null

    signal newChatRequested

    /** Below this the chips drop their labels and keep icons and values. */
    readonly property bool compact: root.width < 360

    property string activePopover: ""

    /** Set while the regenerate picker is open, so it knows what to redo. */
    property string regenerateMessageId: ""

    /**
     * Which view to return to, so a control opened from the More list goes
     * back to that list rather than all the way out to the transcript.
     */
    property string viewReturnTo: ""

    /**
     * Which way the next view arrives from: 1 going deeper, -1 coming back.
     * Sliding both directions from the right made stepping back out of a
     * control feel like stepping into another one.
     */
    property int viewDirection: 1

    function openView(name: string, returnTo: string) {
        root.viewDirection = 1;
        root.viewReturnTo = returnTo;
        root.activePopover = name;
    }

    function goBack() {
        if (root.viewReturnTo.length > 0) {
            const previous = root.viewReturnTo;
            root.viewDirection = -1;
            root.viewReturnTo = "";
            root.activePopover = previous;
            return;
        }
        root.closePopover();
    }

    function togglePopover(name: string) {
        root.viewDirection = 1;
        root.viewReturnTo = "";
        root.activePopover = (root.activePopover === name) ? "" : name;
    }

    function closePopover() {
        root.viewReturnTo = "";
        root.activePopover = "";
    }

    function openKeyManager() {
        root.activePopover = "keys";
    }

    function openShortcuts() {
        root.viewDirection = 1;
        root.viewReturnTo = "";
        root.activePopover = "shortcuts";
    }

    /** The tool catalog and example prompts — the same canvas as "Keys". */
    function openCapabilities() {
        root.viewDirection = 1;
        root.viewReturnTo = "";
        root.activePopover = "capabilities";
    }

    /** Opens the model list for one answer only, without changing the chat's. */
    function openRegenerate(messageId: string) {
        root.regenerateMessageId = messageId;
        root.activePopover = "regenerate";
    }

    readonly property var currentModel: Ai.currentModelEntry
    readonly property bool toolsUsable: root.currentModel?.tools ?? false

    readonly property var thinkingLabels: ({
            "off": Translation.tr("Off"),
            "low": Translation.tr("Low"),
            "medium": Translation.tr("Medium"),
            "high": Translation.tr("High")
        })
    readonly property var thinkingShortLabels: ({
            "off": Translation.tr("Off"),
            "low": Translation.tr("Low"),
            "medium": Translation.tr("Med"),
            "high": Translation.tr("High")
        })

    function promptName(path: string): string {
        const base = String(path ?? "").split("/").pop();
        return base.replace(/\.(md|txt|prompt)$/i, "");
    }

    readonly property string personaChipLabel: {
        if (Ai.promptOverride.length > 0)
            return Translation.tr("This chat");
        if (Ai.currentPersona)
            return Ai.currentPersona.name;
        return Translation.tr("Default");
    }

    readonly property string personaChipTooltip: {
        if (Ai.promptOverride.length > 0)
            return Translation.tr("This chat has its own prompt");
        if (!Ai.currentPersona)
            return Translation.tr("How it should answer\nAlso %1persona NAME").arg(root.commandPrefix);
        if (Ai.personaModified)
            return Translation.tr("Persona: %1 — settings changed since").arg(Ai.currentPersona.name);
        return Translation.tr("Persona: %1").arg(Ai.currentPersona.name);
    }

    function modelChipTooltip(): string {
        const model = root.currentModel;
        if (!model)
            return Translation.tr("No model selected");
        const provider = Ai.providers[model.providerId] ?? null;
        const lines = [
            Translation.tr("Model: %1").arg(String(model.name ?? model.title ?? "")),
            Translation.tr("Provider: %1").arg(String(provider?.name ?? model.providerId ?? ""))
        ];
        const window = Number(model.contextWindow ?? 0);
        if (window > 0)
            lines.push(Translation.tr("Context: %1 tokens").arg(String(window)));
        if (Ai.catalog.isModelLocal(model)) {
            lines.push(Translation.tr("Price: local — no API cost"));
        } else if (String(model.promptPrice ?? "").length > 0 || String(model.completionPrice ?? "").length > 0) {
            const input = model.promptPriceIsFree ? Translation.tr("free") : String(model.promptPrice ?? "—");
            const output = model.completionPriceIsFree ? Translation.tr("free") : String(model.completionPrice ?? "—");
            lines.push(Translation.tr("Price / 1M: in %1 · out %2").arg(input).arg(output));
        }
        const capabilities = [];
        if (model.thinking)
            capabilities.push(Translation.tr("reasoning"));
        if (model.vision)
            capabilities.push(Translation.tr("vision"));
        if (model.attachments)
            capabilities.push(Translation.tr("files"));
        if (model.tools)
            capabilities.push(Translation.tr("tools"));
        if (model.builtinSearch)
            capabilities.push(Translation.tr("web search"));
        if (capabilities.length > 0)
            lines.push(Translation.tr("Capabilities: %1").arg(capabilities.join(", ")));
        lines.push(Translation.tr("Also %1model MODEL").arg(root.commandPrefix));
        return lines.join("\n");
    }

    /**
     * Every chip, in the order it gives way. The list is read twice — once by
     * the bar, once by the overflow menu — and the order is the priority: what
     * wraps off the first row is what the menu holds.
     */
    readonly property var chipModel: [
        {
            "key": "projects",
            "symbol": "folder_special",
            "label": Ai.currentProject?.name ?? Translation.tr("None"),
            "tooltip": Translation.tr("Projects — a prompt and a folder for related chats"),
            "available": true,
            "caret": true
        },
        {
            "key": "memory",
            "symbol": "psychology",
            "label": Translation.tr("%1 facts").arg(AiMemory?.facts?.length ?? 0),
            "tooltip": Translation.tr("What the assistant remembers about you between chats"),
            "available": true,
            "caret": true
        },
        {
            // Saved chats. Doubles as the name of the one on screen, which is
            // otherwise nowhere to be seen.
            "key": "sessions",
            "symbol": "forum",
            "label": (Ai.sessionTitle ?? "").length > 0 ? Ai.sessionTitle : Translation.tr("Chats"),
            "caret": false,
            "tooltip": Translation.tr("Saved chats\nAlso %1load NAME").arg(root.commandPrefix)
        },
        {
            "key": "newChat",
            "symbol": "add_comment",
            "caret": false,
            "sidePadding": 8,
            "tooltip": Translation.tr("New chat (Ctrl+Shift+O)")
        },
        {
            // The one chip that keeps its label at every width: which model is
            // answering is the thing worth knowing.
            "key": "model",
            "symbol": root.currentModel?.materialIcon ?? "wand_stars",
            "customIcon": root.currentModel?.icon ?? "",
            "label": root.currentModel?.title ?? Translation.tr("No model"),
            "alwaysLabel": true,
            "tooltip": root.modelChipTooltip()
        },
        {
            "key": "thinking",
            "symbol": "neurology",
            "label": root.thinkingShortLabels[Ai.thinkingLevel] ?? Ai.thinkingLevel ?? "",
            "available": Ai.currentModelThinks ?? false,
            "tooltip": (Ai.currentModelThinks ?? false) ? Translation.tr("How hard to think\nAlso %1think LEVEL").arg(root.commandPrefix) : Translation.tr("%1 does not think out loud").arg(root.currentModel?.title ?? Translation.tr("This model"))
        },
        {
            "key": "tools",
            "symbol": "service_toolbox",
            "label": Ai.toolbox?.modeLabels?.[Ai.currentTool] ?? Ai.currentTool ?? "",
            "available": root.toolsUsable,
            "tooltip": root.toolsUsable ? Translation.tr("Tools: %1\nAlso %2tool TOOL").arg(Ai.currentTool).arg(root.commandPrefix) : Translation.tr("%1 has no tool support").arg(root.currentModel?.title ?? Translation.tr("This model"))
        },
        {
            // Persona: prompt, model, thinking and temperature saved together.
            // The old chip named a prompt file, which said nothing about what
            // the file would do.
            "key": "prompt",
            "symbol": Ai.currentPersona?.icon ?? "assignment",
            "label": root.personaChipLabel,
            "dot": (Ai.personaModified ?? false) && (Ai.promptOverride ?? "").length === 0,
            "tooltip": root.personaChipTooltip
        },
        {
            // Nothing else says whether the model in use can be reached at all
            // until a message fails.
            "key": "keys",
            "symbol": (Ai.currentModelHasApiKey ?? false) ? "key" : "key_off",
            "label": (Ai.currentModelHasApiKey ?? false) ? Translation.tr("Key") : Translation.tr("No key"),
            "caret": false,
            "tooltip": (Ai.currentModelHasApiKey ?? false) ? Translation.tr("API keys\nAlso %1key").arg(root.commandPrefix) : Translation.tr("%1 needs an API key").arg(root.currentModel?.title ?? Translation.tr("This model"))
        },
        {
            "key": "advanced",
            "symbol": "tune",
            "label": Translation.tr("Advanced"),
            "caret": false,
            "tooltip": Translation.tr("Temperature, output length, context")
        },
        {
            // Slash accelerator, kept as a hint that the commands still exist.
            "key": "slash",
            "label": root.commandPrefix,
            "alwaysLabel": true,
            "caret": false,
            "sidePadding": 8,
            "tooltip": Translation.tr("Commands")
        }
    ]

    function chipEntry(key: string): var {
        return (root.chipModel ?? []).find(entry => entry?.key === key) ?? null;
    }

    /** Whether a chip's view is the one currently filling the canvas. */
    function chipOpened(key: string): bool {
        return root.activePopover === key;
    }

    function activateChip(key: string) {
        const entry = root.chipEntry(key);
        if (entry && !(entry.available ?? true))
            return;
        // Only the chips that do something other than open a popover put the
        // open one away first. Clearing it for all of them made every chip
        // reopen on the second press instead of closing.
        if (key === "newChat") {
            root.closePopover();
            root.newChatRequested();
            return;
        }
        if (key === "slash") {
            root.closePopover();
            if (!root.inputField)
                return;
            root.inputField.text = root.commandPrefix;
            root.inputField.cursorPosition = root.inputField.text.length;
            root.inputField.forceActiveFocus();
            return;
        }
        root.togglePopover(key);
    }

    /**
     * The chips with a slot of their own in the bar. The row is a fixed set of
     * controls now rather than a flow that measured what fell off it, so what
     * the overflow button holds is decided here instead of by the width.
     */
    readonly property var barKeys: {
        const allowed = ["keys", "advanced", "sessions", "newChat", "model", "thinking", "tools", "prompt", "projects", "memory", "slash"];
        const configured = Array.from(Config.options.sidebar.ai.barKeys ?? [])
            .map(key => String(key))
            .filter((key, index, all) => allowed.indexOf(key) >= 0 && all.indexOf(key) === index);
        return configured.length > 0 ? configured : ["keys", "advanced", "sessions", "newChat"];
    }

    /**
     * What each control is, as opposed to what it currently holds. A chip in
     * the bar had room for only one of the two and showed the value; a row has
     * room for both.
     */
    /**
     * A row is wide enough for an icon; some chips never had one because a
     * chip that small showed either a glyph or a value, not both.
     */
    readonly property var controlIcons: ({
        "model": "network_intelligence",
        "slash": "terminal",
        "advanced": "tune",
        "sessions": "history",
        "keys": "key"
    })

    readonly property var controlTitles: ({
        "model": Translation.tr("Model"),
        "thinking": Translation.tr("Thinking"),
        "tools": Translation.tr("Tools"),
        "prompt": Translation.tr("Persona"),
        "slash": Translation.tr("Commands"),
        "advanced": Translation.tr("Sampling & limits"),
        "sessions": Translation.tr("Saved chats"),
        "keys": Translation.tr("API keys"),
        "ollamaModels": Translation.tr("Ollama models"),
        "shortcuts": Translation.tr("Keys"),
        "capabilities": Translation.tr("Capabilities"),
        "memory": Translation.tr("What it remembers"),
        "diagnostics": Translation.tr("Assistant diagnostics"),
        "projects": Translation.tr("Projects")
    })

    readonly property var overflowKeys: (root.chipModel ?? [])
        .filter(entry => root.barKeys.indexOf(entry?.key) === -1)
        .map(entry => entry?.key)

    /**
     * Controls are square to the height the bar was given, so the surface that
     * hosts this bar owns the scale and the two never disagree about it.
     */
    readonly property real controlExtent: root.height > 0
        ? root.height
        : Math.round(Appearance.font.pixelSize.huge * 2)
    readonly property real controlSpacing: Appearance.rounding.verysmall
    /** How far a canvas view travels on its way in, and the transcript on its way out. */
    readonly property real canvasSlideDistance: Appearance.font.pixelSize.huge * 1.5
    /**
     * Breathing room inside a canvas view. These used to be panels a few
     * pixels wider than their text; filling the middle rectangle, they need
     * the same inset the rest of the sidebar's cards give their content.
     */
    readonly property real canvasContentPadding: Appearance.rounding.large

    implicitHeight: root.controlExtent

    /**
     * One chip. Everything it shows comes from an entry in `chipModel`, so the
     * bar and the overflow menu draw the same control from the same source
     * rather than declaring it twice and drifting apart.
     */
    component ControlChip: RippleButton {
        id: chip

        property var entry: null
        readonly property string chipKey: chip.entry?.key ?? ""
        readonly property string symbol: chip.entry?.symbol ?? ""
        readonly property string customIconSource: chip.entry?.customIcon ?? ""
        readonly property string label: chip.entry?.label ?? ""
        readonly property bool showCaret: chip.entry?.caret ?? true
        readonly property string tooltipText: chip.entry?.tooltip ?? ""
        readonly property real sidePadding: chip.entry?.sidePadding ?? 10
        readonly property bool opened: root.chipOpened(chip.chipKey)
        /** Set by the overflow menu, where there is room and no icon to guess from. */
        property bool forceLabel: false
        /** Labels go first when there is no room, unless the chip is the model. */
        readonly property bool showLabel: chip.forceLabel || (chip.entry?.alwaysLabel ?? false) || !root.compact
        /**
         * A chip whose setting does not apply to the model in use is dimmed
         * but stays alive: disabling it would take the tooltip away too, and
         * the tooltip is the part that says why.
         */
        readonly property bool available: chip.entry?.available ?? true
        implicitHeight: 30
        leftPadding: chip.sidePadding
        rightPadding: chip.sidePadding
        // The icon's line box is taller than what Button's default vertical
        // padding leaves behind, and a layout cannot shrink under its own
        // minimum: the row was laid out at full height from the top of the
        // content rect and spilled downwards, taking the label with it.
        topPadding: 0
        bottomPadding: 0
        buttonRadius: height / 2
        toggled: chip.opened
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colRipple: Appearance.colors.colLayer2Active
        opacity: chip.available ? 1 : 0.5
        onClicked: root.activateChip(chip.chipKey)

        contentItem: RowLayout {
            id: chipRowLayout
            spacing: 5

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: chip.customIconSource.length > 0
                visible: active
                sourceComponent: CustomIcon {
                    source: chip.customIconSource
                    width: Appearance.font.pixelSize.larger
                    height: Appearance.font.pixelSize.larger
                    colorize: true
                    color: chip.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: chip.customIconSource.length === 0 && chip.symbol.length > 0
                visible: active
                sourceComponent: MaterialSymbol {
                    text: chip.symbol
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: chip.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 150
                visible: chip.showLabel && chip.label.length > 0
                text: chip.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                animateChange: true
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: chip.showCaret
                text: "keyboard_arrow_down"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: chip.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                rotation: chip.opened ? 180 : 0

                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        Rectangle {
            // A persona whose model or thinking was changed by hand is no
            // longer quite that persona; the dot says so.
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            visible: chip.entry?.dot ?? false
            implicitWidth: 6
            implicitHeight: 6
            radius: width / 2
            color: Appearance.m3colors.m3tertiary
        }

        StyledToolTip {
            text: chip.tooltipText
        }
    }

    /** One popover's worth of choices: a title, then a row per option. */
    /**
     * A list of choices, in the same shapes the rest of the canvas uses: one
     * large pill per option, the one in use filled and check-marked.
     */
    component OptionList: ColumnLayout {
        id: optionList

        property string title: ""
        property string footnote: ""
        property var options: []

        signal chosen(string key)

        spacing: root.canvasRowSpacing

        StyledText {
            Layout.fillWidth: true
            visible: optionList.title.length > 0
            text: optionList.title
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: optionsColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: optionsColumn
                width: parent.width
                spacing: root.canvasRowSpacing

                Repeater {
                    model: optionList.options

                    delegate: CanvasOption {
                        required property var modelData

                        symbol: modelData.symbol ?? ""
                        label: modelData.label ?? ""
                        description: modelData.description ?? ""
                        selected: modelData.selected ?? false
                        available: modelData.enabled ?? true
                        onTriggered: optionList.chosen(modelData.key)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: optionList.footnote.length > 0
            text: optionList.footnote
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
    }

    /**
     * One row, always. Chips that do not fit are laid out below it and hidden
     * there, and the last chip opens them as a menu — the old row scrolled
     * sideways, which hid them behind a gesture nothing announced.
     */
    /** Row metrics for the canvas views: big shapes, big type, real insets. */
    readonly property real canvasRowHeight: Math.round(Appearance.font.pixelSize.huge * 2.5)
    readonly property real canvasRowSpacing: Appearance.rounding.unsharpenmore

    /** The round control a canvas view uses for its way back. */
    component CanvasCircleButton: Rectangle {
        id: circleButton

        property string symbol: ""
        property string accessibleName: ""
        signal triggered

        Layout.preferredWidth: root.canvasRowHeight
        Layout.preferredHeight: root.canvasRowHeight
        radius: height / 2
        Accessible.name: circleButton.accessibleName
        color: circleButtonMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : circleButtonMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSurfaceContainerHighest

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        MouseArea {
            id: circleButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: circleButton.triggered()
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: circleButton.symbol
            fill: 1
            iconSize: 24
            color: Appearance.colors.colOnSurface
        }
    }

    /**
     * A choice in a canvas view. The pill carries the choice; the mark of
     * which one is in use sits in its own circle beside it, the way the chat
     * rows keep their menu button outside the row's shape.
     */
    component CanvasOption: RowLayout {
        id: canvasOption

        property string symbol: ""
        property string label: ""
        property string description: ""
        property bool selected: false
        property bool available: true
        signal triggered

        Layout.fillWidth: true
        spacing: root.canvasRowSpacing

        Rectangle {
            id: optionPill

            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(root.canvasRowHeight, optionColumn.implicitHeight + root.canvasRowSpacing * 2)
            radius: Appearance.rounding.large
            opacity: canvasOption.available ? 1 : 0.45

            color: canvasOption.selected
                ? (optionMouse.containsPress ? Appearance.colors.colPrimaryActive
                    : optionMouse.containsMouse ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colPrimary)
                : (optionMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                    : optionMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                    : Appearance.colors.colSurfaceContainerHighest)

            readonly property color colOn: canvasOption.selected
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnSurface

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MouseArea {
                id: optionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: canvasOption.available
                onClicked: canvasOption.triggered()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.canvasContentPadding
                anchors.rightMargin: root.canvasContentPadding
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: canvasOption.symbol.length > 0
                    text: canvasOption.symbol
                    fill: 1
                    iconSize: 24
                    color: optionPill.colOn
                }

                ColumnLayout {
                    id: optionColumn
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: canvasOption.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: optionPill.colOn
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: canvasOption.description.length > 0
                        text: canvasOption.description
                        // Two lines at most. A long description used to stretch
                        // its pill to nearly twice the height of the ones beside
                        // it, which broke the row rhythm the whole view is built on.
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: optionPill.colOn
                        opacity: 0.75
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // Outside the pill, not inside it.
        Rectangle {
            Layout.preferredWidth: root.canvasRowHeight
            Layout.preferredHeight: root.canvasRowHeight
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            visible: canvasOption.selected
            color: Appearance.colors.colPrimaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                fill: 1
                iconSize: 24
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }

    /**
     * One entry in a canvas view. Same silhouette as the device rows in the
     * dashboard's Bluetooth and Wi-Fi dialogs: a full-height pill, a filled
     * icon, a bold label, the value it currently holds, and a chevron.
     */
    component CanvasRow: Rectangle {
        id: canvasRow

        property string symbol: ""
        property string label: ""
        property string valueText: ""
        property bool available: true
        signal triggered

        Layout.fillWidth: true
        Layout.preferredHeight: root.canvasRowHeight
        radius: height / 2
        opacity: canvasRow.available ? 1 : 0.5
        color: canvasRowMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : canvasRowMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSurfaceContainerHighest

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        MouseArea {
            id: canvasRowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: canvasRow.triggered()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.canvasContentPadding
            anchors.rightMargin: root.canvasContentPadding
            spacing: 12

            MaterialSymbol {
                text: canvasRow.symbol
                fill: 1
                iconSize: 24
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: canvasRow.label
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                visible: canvasRow.valueText.length > 0
                text: canvasRow.valueText
                font.pixelSize: Appearance.font.pixelSize.small
                font.bold: true
                color: Appearance.colors.colOnSurface
                opacity: 0.7
                elide: Text.ElideRight
            }

            MaterialSymbol {
                text: "chevron_right"
                fill: 1
                iconSize: 24
                color: Appearance.colors.colSubtext
            }
        }
    }

    /**
     * A round, icon-only control. Its label, tooltip, availability and open
     * state all still come from `chipModel`, so the bar and the overflow menu
     * remain two renderings of one source.
     */
    component ToolButton: RippleButton {
        id: toolButton

        property string chipKey: ""
        readonly property var entry: root.chipEntry(toolButton.chipKey)
        readonly property bool opened: root.chipOpened(toolButton.chipKey)
        readonly property bool available: toolButton.entry?.available ?? true
        property string symbolOverride: ""
        property string tooltipOverride: ""

        implicitWidth: root.controlExtent
        implicitHeight: root.controlExtent
        buttonRadius: Appearance.rounding.full
        toggled: toolButton.opened
        opacity: toolButton.available ? 1 : 0.5
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colRipple: Appearance.colors.colLayer2Active
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        onClicked: root.activateChip(toolButton.chipKey)

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: toolButton.symbolOverride.length > 0
                ? toolButton.symbolOverride
                : (toolButton.entry?.symbol ?? "")
            iconSize: Appearance.font.pixelSize.larger
            fill: 1
            color: toolButton.opened
                ? Appearance.colors.colOnPrimaryContainer
                : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: toolButton.tooltipOverride.length > 0
                ? toolButton.tooltipOverride
                : (toolButton.entry?.tooltip ?? "")
        }
    }

    /**
     * The bar: what a chat is set to on the left, what it does with the chat
     * on the right. The gap between the two groups is the whole spare width,
     * so the right-hand controls stay pinned to the edge at any size.
     */
    RowLayout {
        id: controlRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.controlSpacing

        ToolButton {
            id: keysButton
            chipKey: "keys"
        }

        // Temperature reads at a glance instead of behind the popover it opens.
        RippleButton {
            id: temperatureButton

            readonly property var entry: root.chipEntry("advanced")
            readonly property bool opened: root.chipOpened("advanced")
            readonly property bool samplingHonoured: Ai.currentModelEntry?.samplingParams ?? true
            readonly property bool isExpanded: (GlobalStates?.policiesExtended ?? false) || root.width >= 420
            readonly property string tempText: temperatureButton.samplingHonoured
                ? String(Number(Ai.temperature.toFixed(2)))
                : Translation.tr("Auto")

            implicitHeight: root.controlExtent
            implicitWidth: temperatureButton.isExpanded
                ? (temperatureRow.implicitWidth + root.controlExtent * 0.7)
                : root.controlExtent
            buttonRadius: Appearance.rounding.full
            leftPadding: temperatureButton.isExpanded ? (root.controlExtent * 0.35) : 0
            rightPadding: temperatureButton.isExpanded ? (root.controlExtent * 0.35) : 0
            topPadding: 0
            bottomPadding: 0
            toggled: temperatureButton.opened
            opacity: temperatureButton.samplingHonoured ? 1 : 0.5
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colBackgroundActive: Appearance.colors.colLayer2Active
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.activateChip("advanced")

            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            contentItem: RowLayout {
                id: temperatureRow
                anchors.centerIn: parent
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "thermostat"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: temperatureButton.opened
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                }

                StyledText {
                    id: temperatureLabel
                    Layout.alignment: Qt.AlignVCenter
                    visible: temperatureButton.isExpanded
                    text: temperatureButton.tempText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: temperatureButton.opened
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                    animateChange: true
                }
            }

            StyledToolTip {
                text: {
                    const desc = temperatureButton.entry?.tooltip ?? Translation.tr("Temperature, output length, context");
                    if (!temperatureButton.isExpanded) {
                        return Translation.tr("Temperature: %1\n%2").arg(temperatureButton.tempText).arg(desc);
                    }
                    return desc;
                }
            }
        }

        // What this chat has cost so far. An indicator, not a control: it
        // says something, nothing happens when it is pressed, and it takes no
        // room at all until there is a number to show.
        Rectangle {
            id: tokenIndicator

            // What the chat has cost, or — before anyone has been charged for
            // anything — what the next request would carry, counted here.
            readonly property int spent: Ai.sessionTokenTotal
            readonly property bool estimated: tokenIndicator.spent <= 0
            readonly property int total: tokenIndicator.estimated ? Ai.estimatedContextTokens : tokenIndicator.spent
            readonly property bool costMode: Config.options.ai.showOpenRouterSessionCost
            readonly property real sessionCost: Ai.sessionOpenRouterCost
            readonly property bool perSecond: Config.options.ai.showTokensPerSecond
            readonly property real rate: Ai.lastAnswerTokensPerSecond
            readonly property int window: Ai.currentModelEntry?.contextWindow ?? 0
            readonly property real fraction: tokenIndicator.window > 0
                ? Math.min(1, Math.max(Ai.estimatedContextTokens, Ai.tokenCount.total) / tokenIndicator.window)
                : 0
            // A window filling up is the one thing here worth a colour: past
            // three quarters the oldest turns are about to be dropped.
            readonly property color tint: tokenIndicator.costMode || tokenIndicator.perSecond
                ? Appearance.colors.colOnLayer2
                : (tokenIndicator.fraction >= 0.75 ? Appearance.m3colors.m3tertiary : Appearance.colors.colOnLayer2)

            visible: tokenIndicator.costMode
                ? tokenIndicator.sessionCost >= 0
                : (tokenIndicator.perSecond ? tokenIndicator.rate > 0 : tokenIndicator.total > 0)
            implicitHeight: root.controlExtent
            implicitWidth: tokenRow.implicitWidth + root.controlExtent * 0.7
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            MouseArea {
                id: tokenHover
                anchors.fill: parent
                hoverEnabled: true
            }

            RowLayout {
                id: tokenRow
                anchors.centerIn: parent
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: tokenIndicator.costMode ? "payments"
                        : (tokenIndicator.perSecond ? "speed" : (tokenIndicator.fraction >= 0.75 ? "data_alert" : "token"))
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: tokenIndicator.tint

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: tokenIndicator.costMode
                        ? Ai.formatOpenRouterCost(tokenIndicator.sessionCost)
                        : (tokenIndicator.perSecond
                            ? Ai.formatTokensPerSecond(tokenIndicator.rate)
                            : ((tokenIndicator.estimated ? "~" : "") + Ai.shortTokenCount(tokenIndicator.total)))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: tokenIndicator.tint
                    animateChange: true
                }
            }

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: tokenHover.containsMouse
                text: {
                    let lines = [
                        Translation.tr("OpenRouter session cost: %1").arg(Ai.formatOpenRouterCost(tokenIndicator.sessionCost)),
                        Translation.tr("Latest answer speed: %1").arg(Ai.formatTokensPerSecond(tokenIndicator.rate)),
                        Translation.tr("Total chat tokens: %1").arg((tokenIndicator.estimated ? "~" : "") + String(tokenIndicator.total))
                    ];
                    if (Ai.prunedTurnCount > 0)
                        lines.push(Translation.tr("%1 earlier turns are no longer sent").arg(String(Ai.prunedTurnCount)));
                    if (Ai.tokenCount.input > 0 || Ai.tokenCount.output > 0)
                        lines.push(Translation.tr("Last turn — in: %1, out: %2").arg(String(Math.max(0, Ai.tokenCount.input))).arg(String(Math.max(0, Ai.tokenCount.output))));
                    if (tokenIndicator.window > 0)
                        lines.push(Translation.tr("%1% of the %2 token window").arg(String(Math.round(tokenIndicator.fraction * 100))).arg(String(tokenIndicator.window)));
                    return lines.join("\n");
                }
            }
        }

        // The spare width lives here, which is what splits the two groups.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
        }

        ToolButton {
            id: sessionsButton
            chipKey: "sessions"
            // The bar has no room for the session's name, so the icon says
            // what the control is for rather than what it currently holds.
            symbolOverride: "history"
        }

        ToolButton {
            id: newChatButton
            chipKey: "newChat"
        }

        ToolButton {
            id: moreButton
            chipKey: "more"
            symbolOverride: "more_vert"
            tooltipOverride: Translation.tr("More controls")
        }
    }

    /**
     * Everything a control opens now takes over the canvas instead of floating
     * a panel over it. There is no scrim and nothing is anchored to the bar:
     * the view slides in from the right while the transcript leaves to the
     * left, so the middle rectangle reads as one surface swapping its content.
     */
    readonly property bool viewOpen: root.activePopover.length > 0

    Loader {
        id: canvasViewLoader
        parent: root.overlayParent ?? root
        anchors.fill: parent
        z: 100
        active: root.viewOpen

        sourceComponent: Item {
            id: canvasView

            readonly property bool modelCatalogueOpen: canvasContentLoader.item?.modelCatalogueOpen ?? false
            readonly property bool modelCatalogueCanRefresh: canvasContentLoader.item?.modelCatalogueCanRefresh ?? false
            readonly property string modelCatalogueTitle: canvasContentLoader.item?.modelCatalogueTitle ?? ""

            opacity: 0
            transform: Translate {
                id: canvasViewTransform
                x: root.canvasSlideDistance
            }

            Component.onCompleted: canvasViewEnter.start()

            ParallelAnimation {
                id: canvasViewEnter

                NumberAnimation {
                    target: canvasView
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }

                NumberAnimation {
                    target: canvasViewTransform
                    property: "x"
                    from: root.canvasSlideDistance
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            MouseArea {
                // The transcript is still behind this view during the cross
                // fade; without this it would take the clicks meant for the
                // list on top of it.
                anchors.fill: parent
                onWheel: wheel => wheel.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.canvasContentPadding
                spacing: root.canvasRowSpacing

                // One header for every view, so none of them has to build its
                // own way out and they cannot drift apart.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: root.canvasRowSpacing
                    // Wider than the row gap: the button is a control and the
                    // title is a heading, and they were reading as one lump.
                    spacing: root.canvasContentPadding

                    CanvasCircleButton {
                        symbol: "arrow_back"
                        accessibleName: canvasView.modelCatalogueOpen
                            ? Translation.tr("Back to model providers")
                            : Translation.tr("Close this view")
                        onTriggered: {
                            const picker = canvasContentLoader.item;
                            if (canvasView.modelCatalogueOpen && picker) {
                                picker.closeModelCatalogue();
                                return;
                            }
                            root.goBack();
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: canvasView.modelCatalogueOpen
                            ? canvasView.modelCatalogueTitle
                            : root.controlTitles[root.activePopover]
                                ?? (root.activePopover === "more" ? Translation.tr("More controls") : "")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.bold: true
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    CanvasCircleButton {
                        visible: canvasView.modelCatalogueCanRefresh
                        symbol: "refresh"
                        accessibleName: Translation.tr("Refresh model list")
                        onTriggered: {
                            const picker = canvasContentLoader.item;
                            if (picker)
                                picker.refreshModelCatalogue();
                        }
                    }
                }

                Loader {
                    id: canvasContentLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // The view Item is built once and then only swaps what it
                    // holds, so stepping between controls animated nothing.
                    // This gives the content the same entrance the view itself
                    // gets when it first arrives over the transcript.
                    transform: Translate {
                        id: canvasContentTransform
                    }

                    Connections {
                        target: root

                        function onActivePopoverChanged() {
                            if (root.activePopover.length > 0)
                                canvasContentEnter.restart();
                        }
                    }

                    ParallelAnimation {
                        id: canvasContentEnter

                        NumberAnimation {
                            target: canvasContentLoader
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        NumberAnimation {
                            target: canvasContentTransform
                            property: "x"
                            from: root.canvasSlideDistance * root.viewDirection
                            to: 0
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }

                    sourceComponent: {
                        if (root.activePopover === "model")
                            return modelPickerComponent;
                        if (root.activePopover === "ollamaModels")
                            return ollamaModelsComponent;
                        if (root.activePopover === "regenerate")
                            return regenerateComponent;
                        if (root.activePopover === "thinking")
                            return thinkingComponent;
                        if (root.activePopover === "tools")
                            return toolsComponent;
                        if (root.activePopover === "prompt")
                            return promptComponent;
                        if (root.activePopover === "sessions")
                            return sessionsComponent;
                        if (root.activePopover === "keys")
                            return keysComponent;
                        if (root.activePopover === "shortcuts")
                            return shortcutsComponent;
                        if (root.activePopover === "capabilities")
                            return capabilitiesComponent;
                        if (root.activePopover === "diagnostics")
                            return diagnosticsComponent;
                        if (root.activePopover === "projects")
                            return projectsComponent;
                        if (root.activePopover === "more")
                            return moreComponent;
                        return advancedComponent;
                    }
                }
            }
        }
    }

    Component {
        id: modelPickerComponent
        AiModelPickerPopover {
            hostOwnsCatalogueHeader: true
            fillOpenRouterAvailableHeight: true
            onPicked: modelId => {
                Ai.setModel(modelId, false);
                root.closePopover();
            }
        }
    }

    Component {
        id: ollamaModelsComponent
        AiOllamaModelsPage {
            active: true
            showHeader: false
            fillAvailableHeight: true
        }
    }

    Component {
        id: thinkingComponent
        OptionList {
            title: Translation.tr("How hard should it think?")
            footnote: Ai.currentModelAlwaysThinks ? Translation.tr("%1 always reasons — the lowest it goes is Low.").arg(Ai.currentModelEntry?.title ?? "") : ""
            options: Ai.thinkingLevels.map(level => ({
                        key: level,
                        label: root.thinkingLabels[level] ?? level,
                        selected: Ai.thinkingLevel === level,
                        enabled: !(level === "off" && Ai.currentModelAlwaysThinks)
                    }))
            onChosen: key => {
                Ai.setThinkingLevel(key);
                root.closePopover();
            }
        }
    }

    Component {
        id: toolsComponent
        AiToolsPopover {
            onClosed: root.closePopover()
        }
    }

    Component {
        id: regenerateComponent
        AiModelPickerPopover {
            hostOwnsCatalogueHeader: true
            fillOpenRouterAvailableHeight: true
            onPicked: modelId => {
                Ai.regenerateWith(root.regenerateMessageId, modelId);
                root.regenerateMessageId = "";
                root.closePopover();
            }
        }
    }

    Component {
        id: promptComponent
        PersonaLibrary {
            onClosed: root.closePopover()
        }
    }

    Component {
        id: sessionsComponent
        SessionList {
            onCloseRequested: root.closePopover()
        }
    }

    Component {
        id: keysComponent
        AiApiKeyManager {
            onClosed: root.closePopover()
        }
    }

    Component {
        id: shortcutsComponent
        ChatShortcutSheet {}
    }

    Component {
        id: capabilitiesComponent
        AiCapabilitiesSheet {
            onPromptChosen: text => {
                root.closePopover();
                if (!root.inputField)
                    return;
                root.inputField.text = text;
                root.inputField.cursorPosition = root.inputField.text.length;
                root.inputField.forceActiveFocus();
            }
        }
    }

    Component {
        id: diagnosticsComponent
        AiDiagnosticsPage {}
    }

    Component {
        id: memoryComponent
        AiMemoryView {
            onClosed: root.goBack()
        }
    }

    Component {
        id: projectsComponent
        AiProjectView {
            onClosed: root.goBack()
        }
    }

    Component {
        id: advancedComponent
        ChatAdvancedPopover {}
    }

    Component {
        // The controls without a slot in the bar. Each row says what it is and
        // what it currently holds, and opens its own view in this same canvas.
        id: moreComponent
        ColumnLayout {
            spacing: root.canvasRowSpacing

            Repeater {
                model: root.overflowKeys

                delegate: CanvasRow {
                    required property string modelData

                    readonly property var entry: root.chipEntry(modelData)

                    symbol: (entry?.symbol ?? "").length > 0
                        ? entry.symbol
                        : (root.controlIcons[modelData] ?? "tune")
                    label: root.controlTitles[modelData] ?? modelData
                    valueText: entry?.label ?? ""
                    available: entry?.available ?? true
                    onTriggered: root.openView(modelData, "more")
                }
            }

            CanvasRow {
                Layout.fillWidth: true
                symbol: "download"
                label: Translation.tr("Ollama models")
                valueText: Translation.tr("Browse and pull")
                onTriggered: root.openView("ollamaModels", "more")
            }

            CanvasRow {
                Layout.fillWidth: true
                symbol: "monitor_heart"
                label: Translation.tr("Assistant diagnostics")
                valueText: Translation.tr("Test what the chat needs")
                onTriggered: root.openView("diagnostics", "more")
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
