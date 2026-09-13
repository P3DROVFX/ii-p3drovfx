pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The Activity tab: what started, ended or ran, grouped by day, with the
 * reason — so a mode that "switched on by itself" can be traced. Entries
 * with skipped actions unfold to show what went wrong.
 */
Item {
    id: root

    property string filter: "all"
    property bool confirmClear: false

    signal requestClose()

    function handleEscape() {
        if (root.confirmClear) {
            root.confirmClear = false;
            return true;
        }
        return false;
    }

    function handleKey(key, modifiers) {
        return false;
    }

    readonly property var entries: {
        const all = Modes.history;
        switch (root.filter) {
        case "modes":
            return all.filter(h => h.kind === "mode");
        case "routines":
            return all.filter(h => h.kind === "routine");
        case "failures":
            return all.filter(h => h.failed && h.failed.length);
        }
        return all;
    }

    // Day headers woven into the list, newest first (the engine's order).
    readonly property var rows: {
        const out = [];
        let lastDay = -1;
        for (const h of root.entries) {
            const day = ModeUi.startOfDay(h.t);
            if (day !== lastDay) {
                out.push({ header: true, label: ModeUi.dayLabel(h.t), t: h.t });
                lastDay = day;
            }
            out.push({ header: false, entry: h });
        }
        return out;
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 4
                spacing: 12

                StyledText {
                    text: Translation.tr("Activity")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                ConfigSelectionArray {
                    currentValue: root.filter
                    onSelected: value => root.filter = value
                    options: [
                        { displayName: Translation.tr("All"), value: "all" },
                        { displayName: Translation.tr("Modes"), value: "modes" },
                        { displayName: Translation.tr("Routines"), value: "routines" },
                        { displayName: Translation.tr("Skipped actions"), value: "failures" }
                    ]
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    visible: !root.confirmClear && Modes.history.length > 0
                    text: root.entries.length === Modes.history.length
                        ? (Modes.history.length === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(Modes.history.length))
                        : Translation.tr("%1 of %2").arg(root.entries.length).arg(Modes.history.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                FooterButton {
                    visible: !root.confirmClear && Modes.history.length > 0
                    buttonIcon: "delete_sweep"
                    buttonText: Translation.tr("Clear")
                    onClicked: root.confirmClear = true
                }

                StyledText {
                    visible: root.confirmClear
                    text: Translation.tr("Forget everything listed here?")
                    color: Appearance.colors.colOnLayer1
                }

                FooterButton {
                    visible: root.confirmClear
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.confirmClear = false
                }

                FooterButton {
                    visible: root.confirmClear
                    buttonIcon: "delete_sweep"
                    buttonText: Translation.tr("Clear")
                    danger: true
                    filled: true
                    onClicked: {
                        root.confirmClear = false;
                        Modes.clearHistory();
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: list
                    anchors.fill: parent
                    visible: root.rows.length > 0
                    clip: true
                    spacing: 2
                    popin: false
                    animateAppearance: false
                    animatePopulate: false
                    model: root.rows

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index

                        readonly property bool header: row.modelData.header === true
                        readonly property var entry: row.modelData.entry ?? null
                        readonly property var def: ModeUi.historyDef(row.entry)
                        readonly property string colorKey: row.def?.color ?? ""
                        readonly property var failed: Array.from(row.entry?.failed ?? [])
                        readonly property bool hasFailed: row.failed.length > 0
                        property bool expanded: false

                        width: list.width
                        implicitHeight: row.header ? (row.index === 0 ? 30 : 40) : card.implicitHeight

                        StyledText {
                            visible: row.header
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                bottom: parent.bottom
                                bottomMargin: 6
                            }
                            text: row.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }

                        Rectangle {
                            id: card
                            visible: !row.header
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                            }
                            implicitHeight: cardColumn.implicitHeight + 16
                            radius: Appearance.rounding.normal
                            color: cardArea.containsMouse && row.hasFailed ? Appearance.colors.colLayer2Hover : "transparent"

                            Behavior on implicitHeight {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            MouseArea {
                                id: cardArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: row.hasFailed
                                cursorShape: Qt.PointingHandCursor
                                onClicked: row.expanded = !row.expanded
                            }

                            ColumnLayout {
                                id: cardColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    topMargin: 8
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        radius: Appearance.rounding.full
                                        color: row.def ? ModeUi.container(row.colorKey) : Appearance.colors.colLayer2

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: row.def?.icon ?? "history"
                                            iconSize: 20
                                            fill: row.entry?.event === "start" ? 1 : 0
                                            color: row.def ? ModeUi.onContainer(row.colorKey) : Appearance.colors.colSubtext
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            StyledText {
                                                text: ModeUi.historyName(row.entry)
                                                elide: Text.ElideRight
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer1
                                            }

                                            StyledText {
                                                text: ModeUi.historyEventText(row.entry).toLowerCase()
                                                color: Appearance.colors.colSubtext
                                            }

                                            Rectangle {
                                                visible: row.entry?.kind === "routine"
                                                implicitWidth: kindText.implicitWidth + 12
                                                implicitHeight: 18
                                                radius: Appearance.rounding.full
                                                color: Appearance.colors.colLayer2

                                                StyledText {
                                                    id: kindText
                                                    anchors.centerIn: parent
                                                    text: Translation.tr("routine")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colSubtext
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: ModeUi.historyWhyText(row.entry)
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                    }

                                    Rectangle {
                                        visible: row.hasFailed
                                        implicitWidth: failedRow.implicitWidth + 14
                                        implicitHeight: 22
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colErrorContainer

                                        RowLayout {
                                            id: failedRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            MaterialSymbol {
                                                text: "warning"
                                                iconSize: 14
                                                color: Appearance.colors.colOnErrorContainer
                                            }

                                            StyledText {
                                                text: row.failed.length === 1 ? Translation.tr("1 skipped")
                                                    : Translation.tr("%1 skipped").arg(row.failed.length)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnErrorContainer
                                            }

                                            MaterialSymbol {
                                                text: row.expanded ? "expand_less" : "expand_more"
                                                iconSize: 14
                                                color: Appearance.colors.colOnErrorContainer
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: ModeUi.clock(row.entry?.t ?? 0)
                                        font.family: Appearance.font.family.numbers
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                // One line per skipped action: "type: reason".
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 48
                                    Layout.bottomMargin: 4
                                    visible: row.expanded && row.hasFailed
                                    spacing: 2

                                    Repeater {
                                        model: row.expanded ? row.failed : []

                                        delegate: RowLayout {
                                            id: failedLine
                                            required property var modelData
                                            readonly property string text: String(failedLine.modelData)
                                            readonly property int colon: failedLine.text.indexOf(":")
                                            readonly property string type: failedLine.colon === -1 ? failedLine.text : failedLine.text.slice(0, failedLine.colon)
                                            readonly property string why: failedLine.colon === -1 ? "" : failedLine.text.slice(failedLine.colon + 1).trim()

                                            Layout.fillWidth: true
                                            spacing: 8

                                            MaterialSymbol {
                                                text: ModeUi.actionIcon(failedLine.type)
                                                iconSize: 16
                                                color: Appearance.colors.colError
                                            }

                                            StyledText {
                                                text: ModeUi.actionLabel(failedLine.type)
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer1
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: failedLine.why
                                                elide: Text.ElideRight
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

                ColumnLayout {
                    visible: root.rows.length === 0
                    anchors.centerIn: parent
                    width: Math.min(440, parent.width - 60)
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: Modes.history.length === 0 ? "history" : "filter_alt_off"
                        iconSize: 48
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (Modes.history.length === 0)
                                return Translation.tr("Nothing has happened yet");
                            if (root.filter === "failures")
                                return Translation.tr("No action was skipped");
                            return Translation.tr("Nothing here for this filter");
                        }
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: {
                            if (Modes.history.length === 0)
                                return Translation.tr("Every time a mode starts or ends, or a routine runs, "
                                + "it is listed here with what caused it.");
                            if (root.filter === "failures")
                                return Translation.tr("Entries whose actions could not all be applied "
                                + "would show up here.");
                            return Translation.tr("Try another filter above.");
                        }
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        visible: Modes.history.length > 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        implicitHeight: 40
                        implicitWidth: allText.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.filter = "all"

                        contentItem: StyledText {
                            id: allText
                            text: Translation.tr("Show everything")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
