import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import "TimetableHelpers.js" as H

/** One selectable event in the right sidebar's grouped day browser. */
RippleButton {
    id: root

    required property var eventData
    readonly property bool sports: root.eventData?.sportEvent === true
    readonly property bool rowAllDay: CalendarService.isAllDayEvent(root.eventData)
    readonly property bool cancelled: String(root.eventData?.status ?? "").toUpperCase() === "CANCELLED"

    signal activated

    implicitHeight: 62
    buttonRadius: Appearance.rounding.small
    colBackground: root.sports ? Appearance.colors.colTertiaryContainer : Appearance.m3colors.m3surfaceContainerHighest
    colBackgroundHover: root.sports ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
    onClicked: root.activated()

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Rectangle {
            visible: !root.sports
            Layout.preferredWidth: 4
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            radius: Appearance.rounding.full
            color: H.chipColor(root.eventData, Appearance.colors, GoogleCalendarService.colorForEvent(root.eventData))
        }

        MaterialShapeWrappedMaterialSymbol {
            visible: root.sports
            text: "sports_score"
            iconSize: Appearance.font.pixelSize.normal
            padding: 8
            shape: MaterialShape.Shape.Cookie6Sided
            color: Appearance.colors.colTertiary
            colSymbol: Appearance.colors.colOnTertiary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.eventData?.content ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Bold
                font.strikeout: root.cancelled
                color: root.sports ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                Layout.fillWidth: true
                text: root.rowAllDay ? Translation.tr("All day") : H.eventRangeText(root.eventData, Config.options?.time.format)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: root.sports ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MaterialSymbol {
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.large
            color: root.sports ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
        }
    }
}
