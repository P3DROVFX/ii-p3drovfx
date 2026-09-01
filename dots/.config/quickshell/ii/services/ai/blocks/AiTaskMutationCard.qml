pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Shared review card for task and calendar mutations. The calendar path uses
 * the same journalled approval boundary as tasks, but never infers an event
 * scope from the button label.
 */
Rectangle {
    id: root

    required property var messageData
    required property var card
    readonly property var preview: root.card?.data?.preview ?? ({})
    readonly property string operation: String(root.preview.operation ?? "")
    readonly property bool calendarMutation: String(root.card?.tool ?? "").startsWith("calendar_")
    readonly property string calendarDetails: [String(root.preview.calendar ?? ""),
        String(root.preview.scopeLabel ?? ""),
        String(root.preview.startDisplay ?? ""), String(root.preview.endDisplay ?? "")]
        .filter(value => value.length > 0).join(" · ")

    implicitHeight: content.implicitHeight + Appearance.rounding.normal
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Appearance.rounding.unsharpenmore
        spacing: Appearance.rounding.unsharpenmore

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: root.calendarMutation
                    ? (root.operation === "delete" ? "event_busy" : (root.operation === "create" ? "event_available" : "edit_calendar"))
                    : (root.operation === "delete" ? "delete" : (root.operation === "complete" ? "task_alt" : "edit_note"))
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.rounding.unsharpenmore / 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.calendarMutation
                        ? (root.operation === "delete" ? Translation.tr("Delete this calendar event?")
                            : (root.operation === "create" ? Translation.tr("Create this calendar event?") : Translation.tr("Move this calendar event?")))
                        : (root.operation === "delete" ? Translation.tr("Delete this task?")
                            : (root.operation === "complete" ? Translation.tr("Complete this task?") : Translation.tr("Update this task?")))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: String(root.preview.title ?? root.preview.taskId ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.calendarMutation ? root.calendarDetails
                        : [String(root.preview.provider?.name ?? root.preview.providerId ?? ""),
                            String(root.preview.accountId ?? ""), String(root.preview.listName ?? "")]
                            .filter(value => value.length > 0).join(" · ")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.calendarMutation
                        ? (String(root.preview.location ?? "").length > 0 || String(root.preview.url ?? "").length > 0 || String(root.preview.notes ?? "").length > 0)
                        : (root.operation === "update" && Object.keys(root.preview.changes ?? {}).length > 0)
                    text: {
                        if (root.calendarMutation) {
                            return [String(root.preview.location ?? ""), String(root.preview.url ?? ""), String(root.preview.notes ?? "")]
                                .filter(value => value.length > 0).join(" · ");
                        }
                        const changes = root.preview.changes ?? ({});
                        return Object.keys(changes).map(key => key + ": " + String(changes[key])).join(" · ");
                    }
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.calendarMutation ? Ai.rejectCalendarMutation(root.messageData) : Ai.rejectTaskMutation(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Discard")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.calendarMutation ? Ai.approveCalendarMutation(root.messageData) : Ai.approveTaskMutation(root.messageData)
                contentItem: StyledText {
                    text: root.operation === "delete" ? Translation.tr("Delete")
                        : (root.calendarMutation && root.operation === "create" ? Translation.tr("Create event") : Translation.tr("Apply"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
