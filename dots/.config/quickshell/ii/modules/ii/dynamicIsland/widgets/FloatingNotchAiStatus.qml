import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var activeAgents: AiStatusService.agents
    readonly property int agentCount: AiStatusService.agentCount
    readonly property var primaryAgent: AiStatusService.primaryAgent
    /**
     * The first session's icon: the bubble's glance shows the primary agent, which is
     * the first row (see AuxiliaryBubble's heroes).
     */
    readonly property var heroItems: root.isExpanded && agentRows.count > 0 && agentRows.itemAt(0)
        ? [agentRows.itemAt(0).agentIcon] : []
    readonly property bool needsAction: AiAttentionService.needsAction
    // The service holds a one-second clock and derives the elapsed time from the turn's
    // start, so the agent list itself can stay untouched between samples.
    readonly property int elapsedSeconds: AiStatusService.runtimeFor(primaryAgent)

    function formatTime(secs) {
        const totalSecs = secs || 0;
        const mins = Math.floor(totalSecs / 60);
        const s = totalSecs % 60;
        const hrs = Math.floor(totalSecs / 3600);
        if (hrs > 0) {
            const rMins = mins % 60;
            return String(hrs).padStart(2, '0') + ":" + String(rMins).padStart(2, '0') + ":" + String(s).padStart(2, '0');
        }
        return String(mins).padStart(2, '0') + ":" + String(s).padStart(2, '0');
    }

    function resolveIconPath(iconName) {
        let name = iconName || "google-gemini-symbolic.svg";
        if (!name.endsWith(".svg")) {
            name += ".svg";
        }
        return name;
    }

    readonly property string primaryTimeText: formatTime(elapsedSeconds)

    /** The states where work is actually in flight, and the only ones that animate. */
    readonly property var busyStates: ["working", "thinking", "streaming", "tool", "compacting", "running"]

    /**
     * What the expanded card needs, from the agent list alone.
     *
     * The card used to be whatever the registry declared - 200 px, sized for a list -
     * so one agent, the usual case, left well over half of it empty. The bubble hosting
     * this face sizes itself to this number instead. It is a pure function of how many
     * agents there are, never of the card's own height, so the two can never chase each
     * other.
     */
    readonly property int expandedRowHeight: 56
    readonly property int expandedRowSpacing: 6
    readonly property real preferredExpandedHeight: {
        const rows = Math.max(1, root.agentCount);
        const content = rows * root.expandedRowHeight + (rows - 1) * root.expandedRowSpacing;
        // The column's margins, the header, and the gap below it.
        return Math.min(320, 20 + 18 + root.expandedRowSpacing + content);
    }

    // ==========================================
    // 1. CONTRACTED MODE (Clean SVG Icons + Timer)
    // ==========================================
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 6
        visible: !root.isExpanded

        // Icons stack (Direct SVG icon tinted with Primary color - NO background circle)
        Row {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: root.activeAgents
                delegate: CustomIcon {
                    required property var modelData

                    width: 18
                    height: 18
                    source: root.resolveIconPath(modelData.icon)
                    colorize: true
                    color: Appearance.colors.colPrimary
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                }
            }
        }

        // Centre: what the agent is doing. The name is the icon's job - a pill this
        // narrow can say one thing, and "Running Bash" is the thing worth saying.
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: root.needsAction ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            text: {
                if (!root.primaryAgent)
                    return Translation.tr("AI Agent");
                // Several at work is a count. One of them asking for something, or
                // just finished, is why the island is showing this at all - and that
                // one leads the list - so it is the thing to say.
                const state = root.primaryAgent.state ?? "";
                const subject = root.primaryAgent.requiresAttention === true
                    || root.busyStates.indexOf(state) === -1;
                if (root.agentCount > 1 && !subject)
                    return Translation.tr("%1 agents").arg(root.agentCount);
                return AiStatusService.statusLabel(root.primaryAgent);
            }
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Right Timer
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.numbers
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
            color: Appearance.colors.colOnSurface
            text: root.primaryTimeText
        }
    }

    // ==========================================
    // 2. EXPANDED MODE (Multi-Agent List Card)
    // ==========================================
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 6
        visible: root.isExpanded

        // Header: Title
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            CustomIcon {
                width: 18
                height: 18
                source: "google-gemini-symbolic.svg"
                colorize: true
                color: Appearance.colors.colPrimary
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: root.agentCount > 1 ? Translation.tr("Active AI Sessions (%1)").arg(root.agentCount) : Translation.tr("Active AI Session")
            }
        }

        // List of all active agents
        Repeater {
            id: agentRows
            model: root.activeAgents
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property Item agentIcon: rowIcon

                Layout.fillWidth: true
                /**
                 * The card is sized to the rows (see `preferredExpandedHeight`), so a
                 * row asks for its natural height and only gives way when a long list
                 * has run the card into its cap.
                 */
                Layout.fillHeight: true
                Layout.preferredHeight: root.expandedRowHeight
                Layout.minimumHeight: 46
                Layout.maximumHeight: 72
                radius: Appearance.rounding.small
                color: rowClick.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                    : Appearance.colors.colSurfaceContainerHighest

                // A session in a terminal is somewhere: clicking its row goes there.
                // The built-in chat has no window, so its row leaves the click to the
                // card, which opens the sidebar as before.
                MouseArea {
                    id: rowClick
                    anchors.fill: parent
                    enabled: (modelData.pid ?? 0) > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AiStatusService.focusAgent(modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Direct SVG icon tinted Primary color (NO circle background)
                    CustomIcon {
                        id: rowIcon
                        width: 22
                        height: 22
                        source: root.resolveIconPath(modelData.icon)
                        colorize: true
                        color: Appearance.colors.colPrimary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Agent details
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: 6
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                                text: modelData.name || Translation.tr("AI Agent")
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                height: 14
                                width: sourceText.implicitWidth + 8
                                radius: 7
                                color: modelData.source === "internal" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

                                StyledText {
                                    id: sourceText
                                    anchors.centerIn: parent
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: modelData.source === "internal" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                    text: modelData.source === "internal" ? "Built-in" : "CLI"
                                }
                            }
                        }

                        /**
                         * What it is doing, and what that has cost so far.
                         *
                         * This line used to read "PID: 223709", which told the user
                         * nothing they could act on. The state comes from the CLI's own
                         * hooks and the counts from its transcript, so both are real
                         * rather than inferred.
                         */
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                            /**
                             * Two different numbers, named rather than arrowed: the
                             * context is what the window holds (mostly cached reads,
                             * hundreds of thousands of tokens by mid-session) and the
                             * output is what this turn has generated. Shown as bare
                             * arrows they read as one number disagreeing with the
                             * CLI's own footer.
                             */
                            text: {
                                const status = AiStatusService.statusLabel(modelData);
                                const metrics = AiStatusService.metricsFor(modelData);
                                const context = AiStatusService.formatTokens(metrics.tokensIn);
                                const out = AiStatusService.formatTokens(metrics.tokensOut);
                                const parts = [status];
                                if (context !== "")
                                    parts.push(Translation.tr("%1 ctx").arg(context));
                                if (out !== "")
                                    parts.push(Translation.tr("%1 out").arg(out));
                                return parts.join("  ·  ");
                            }
                            elide: Text.ElideRight
                        }
                    }

                    /**
                     * Elapsed time with the activity bars beneath it, as one block.
                     *
                     * They used to sit in a fixed 55x34 box, the time pinned to its top
                     * and the bars to its bottom, which left a gap between them and made
                     * the row look unfinished at any other height. Measured, centred and
                     * right-aligned, they read as one thing and the row can be any size.
                     */
                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: 3

                        StyledText {
                            id: timerText
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                            color: Appearance.colors.colOnSurface
                            text: root.formatTime(AiStatusService.runtimeFor(modelData))
                        }

                        /**
                         * The bars live in a slot of their own, declared at their full
                         * height and width.
                         *
                         * They animate their height, and a Row measures itself from its
                         * children, so the column above kept being re-laid out as they
                         * breathed and the clock drifted up and down with them. Held in
                         * a fixed box the animation is purely a repaint, and the digits
                         * sit still.
                         */
                        Item {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 3 * 3 + 2 * 3
                            Layout.preferredHeight: 9

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        width: 3
                                        height: 3 + (index % 2) * 3
                                        radius: 1.5
                                        color: root.needsAction ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOnSurfaceVariant
                                        anchors.verticalCenter: parent.verticalCenter

                                        // Only while something is actually running: a
                                        // finished turn that keeps twitching reads as
                                        // still working, and it costs frames for nothing.
                                        SequentialAnimation on height {
                                            running: root.isExpanded && root.busyStates.indexOf(modelData.state) !== -1
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 3; to: 9; duration: 250 + index * 80; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 9; to: 3; duration: 250 + index * 80; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // A long list capped by the card leaves nothing here; a short one is already
        // exactly as tall as its rows. Present so the column never stretches a row.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    MouseArea {
        anchors.fill: parent
        // Beneath the rows, so a row that knows where its session is gets the click.
        z: -1
        onClicked: AiAttentionService.open("sidebar")
    }
}
