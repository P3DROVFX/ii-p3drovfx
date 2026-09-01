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
    readonly property bool needsAction: AiAttentionService.needsAction
    readonly property int elapsedSeconds: primaryAgent ? (primaryAgent.runtime || 0) : 0

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

        // Center / Agent name or count label
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
            text: root.needsAction ? Translation.tr("AI needs your review") : (root.agentCount > 1 ? Translation.tr("%1 agents").arg(root.agentCount) : (root.primaryAgent ? root.primaryAgent.name : Translation.tr("AI Agent")))
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
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 8
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
            model: root.activeAgents
            delegate: Rectangle {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Direct SVG icon tinted Primary color (NO circle background)
                    CustomIcon {
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

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                            text: {
                                if (modelData.model) {
                                    return modelData.model;
                                }
                                if (modelData.pid) {
                                    return "PID: " + modelData.pid;
                                }
                                return Translation.tr("Active");
                            }
                            elide: Text.ElideRight
                        }
                    }

                    // Right Side: Fixed height container to prevent vertical shifting of timer text
                    Item {
                        width: 55
                        height: 34
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        StyledText {
                            id: timerText
                            anchors.top: parent.top
                            anchors.right: parent.right
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                            color: Appearance.colors.colOnSurface
                            text: root.formatTime(modelData.runtime || 0)
                        }

                        // Fixed height visualizer container anchored to bottom
                        Item {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            width: 20
                            height: 10

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        width: 3
                                        height: 3 + (index % 2) * 3
                                        radius: 1.5
                                        color: Appearance.colors.colPrimary
                                        anchors.verticalCenter: parent.verticalCenter

                                        SequentialAnimation on height {
                                            running: root.isExpanded
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
    }

    MouseArea {
        anchors.fill: parent
        onClicked: AiAttentionService.open("sidebar")
    }
}
