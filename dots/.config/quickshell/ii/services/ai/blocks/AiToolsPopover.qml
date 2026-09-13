import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * What the assistant may reach for, and what it has reached for.
 *
 * The old panel was three modes and nothing else: a single choice that turned
 * everything on together, with no way to say "read my settings but never run
 * a command" and no record afterwards of what had run. Mode is still the top
 * switch, because a model that cannot call functions has nothing below it to
 * configure — but under it every tool carries its own standing answer, and
 * the log says what actually happened.
 */
Item {
    id: root

    signal closed

    readonly property bool functionsMode: Ai.currentTool === "functions"
    readonly property var definitions: {
        const format = Ai.toolbox.apiFormat;
        return Array.from(Ai.toolbox.definitions).filter(def => def.formats.indexOf(format) !== -1 && (!def.needsSearch || Ai.toolbox.searchAvailable));
    }

    implicitHeight: contentColumnLayout.implicitHeight

    /** Each mode gets a face, since the row is wide enough to carry one. */
    readonly property var modeIcons: ({
        "functions": "service_toolbox",
        "search": "travel_explore",
        "none": "block"
    })

    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 2.5)
    readonly property real gap: Appearance.rounding.unsharpenmore
    readonly property real inset: Appearance.rounding.large

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: root.gap
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }

    /** What the model may reach for. One filled, check-marked pill per mode. */
    component ModeOption: RowLayout {
        id: mode

        property string label: ""
        property string description: ""
        property string symbol: ""
        property bool selected: false
        signal triggered

        Layout.fillWidth: true
        spacing: root.gap

        Rectangle {
            id: modePill

            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(root.rowHeight, modeColumn.implicitHeight + root.gap * 2)
            radius: Appearance.rounding.large
            color: mode.selected
                ? (modeMouse.containsPress ? Appearance.colors.colPrimaryActive
                    : modeMouse.containsMouse ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colPrimary)
                : (modeMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                    : modeMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                    : Appearance.colors.colSurfaceContainerHighest)

            readonly property color colOn: mode.selected
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnSurface

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mode.triggered()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.inset
                anchors.rightMargin: root.gap
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: mode.symbol.length > 0
                    text: mode.symbol
                    fill: 1
                    iconSize: 24
                    color: modePill.colOn
                }

                ColumnLayout {
                    id: modeColumn
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: mode.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: modePill.colOn
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: mode.description.length > 0
                        text: mode.description
                        // Two lines at most. A long description used to stretch
                        // its pill to nearly twice the height of the ones beside
                        // it, which broke the row rhythm the whole view is built on.
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: modePill.colOn
                        opacity: 0.75
                        wrapMode: Text.Wrap
                    }
                }

            }
        }

        // Outside the pill, matching the option rows elsewhere in the chat.
        Rectangle {
            Layout.preferredWidth: root.rowHeight
            Layout.preferredHeight: root.rowHeight
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            visible: mode.selected
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

    ColumnLayout {
        id: contentColumnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Without a bottom the column ran past the view and the scroller below
        // inherited an unbounded height, so the last tools were simply cut off
        // with nothing to scroll.
        anchors.bottom: root.height > contentColumnLayout.implicitHeight ? undefined : parent.bottom
        spacing: root.gap

        SectionLabel {
            Layout.topMargin: 0
            text: Translation.tr("What may it reach for?")
        }

        Repeater {
            model: ScriptModel {
                values: Array.from(Ai.availableTools)
            }

            delegate: ModeOption {
                required property var modelData

                symbol: root.modeIcons[modelData] ?? "handyman"
                label: Ai.toolbox.modeLabels[modelData] ?? modelData
                description: Ai.toolbox.modeDescriptions[modelData] ?? ""
                selected: Ai.currentTool === modelData
                onTriggered: Ai.setTool(modelData)
            }
        }

        StyledFlickable {
            Layout.fillWidth: true
            // Fills the view rather than stopping at a panel's worth of height.
            Layout.fillHeight: true
            implicitHeight: scrolledColumnLayout.implicitHeight
            contentWidth: width
            contentHeight: scrolledColumnLayout.implicitHeight
            clip: true

            ColumnLayout {
                id: scrolledColumnLayout
                width: parent.width
                spacing: root.gap

                SectionLabel {
                    visible: root.functionsMode
                    text: Translation.tr("Each tool, and when it may run")
                }

                AiToolPermissionList {
                    visible: root.functionsMode
                    definitions: root.functionsMode ? root.definitions : []
                    density: "compact"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: root.functionsMode
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Show settings changes before applying them")
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledSwitch {
                        checked: Config.options.ai.tools.reviewConfigChanges
                        onCheckedChanged: Config.options.ai.tools.reviewConfigChanges = checked
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: Ai.toolbox.callLog.length > 0
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Recently used")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 4
                        bottomPadding: 4
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: Ai.toolbox.clearLog()

                        contentItem: StyledText {
                            text: Translation.tr("Clear")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: Array.from(Ai.toolbox.callLog).slice(0, 8)
                    }

                    RowLayout {
                        id: logRow
                        required property var modelData

                        readonly property color statusColor: {
                            if (logRow.modelData.status === "failed")
                                return Appearance.m3colors.m3error;
                            if (logRow.modelData.status === "refused")
                                return Appearance.colors.colSubtext;
                            if (logRow.modelData.status === "running")
                                return Appearance.colors.colPrimary;
                            return Appearance.colors.colOnLayer2;
                        }

                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: logRow.modelData.status === "running" ? "progress_activity" : logRow.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: logRow.statusColor
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: logRow.modelData.title
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    text: logRow.modelData.outcome
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: logRow.statusColor
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: logRow.modelData.detail
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
