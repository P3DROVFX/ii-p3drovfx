pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

RippleButton {
    id: root

    required property var event
    property bool selected: false
    property bool showDate: false
    signal activated

    implicitHeight: content.implicitHeight + Appearance.sizes.elevationMargin * 2
    buttonRadius: Appearance.rounding.normal
    readonly property color eventColor: root.event?.color || Appearance.colors.colPrimary
    colBackground: root.selected
        ? Appearance.colors.colPrimaryContainer
        : ColorUtils.mix(root.eventColor, Appearance.colors.colSurfaceContainerHigh, 0.30)
    colBackgroundHover: root.selected
        ? Appearance.colors.colPrimaryContainerHover
        : ColorUtils.mix(root.eventColor, Appearance.colors.colSurfaceContainerHighestHover, 0.30)
    colRipple: root.selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
    onClicked: root.activated()

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        spacing: Appearance.sizes.elevationMargin

        Item {
            Layout.preferredWidth: Appearance.sizes.elevationMargin / 2
            Layout.fillHeight: true
            implicitHeight: Math.max(title.implicitHeight, subtitle.implicitHeight)

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : root.eventColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: title
                Layout.fillWidth: true
                text: String(root.event?.content ?? root.event?.title ?? "")
                elide: Text.ElideRight
                font.strikeout: String(root.event?.status ?? "") === "cancelled"
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }

            StyledText {
                id: subtitle
                Layout.fillWidth: true
                readonly property string datePrefix: root.showDate
                    ? Qt.formatDate(root.event?.startDate ?? new Date(), "ddd dd MMM") + " · "
                    : ""
                text: datePrefix + (root.event?.allDay
                    ? Translation.tr("All day")
                    : Qt.formatTime(root.event?.startDate ?? new Date(), "hh:mm") + "–" + Qt.formatTime(root.event?.endDate ?? new Date(), "hh:mm"))
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            }
        }

        ConfiguredKeyHint {
            visible: root.selected && Config.options.search.appearance.showKeyHints
            actionId: "activate"
            fallbackKeys: ["↵"]
            surface: Appearance.colors.colPrimaryContainer
            onSurface: Appearance.colors.colOnPrimaryContainer
        }

        MaterialSymbol {
            visible: String(root.event?.url ?? "").length > 0
            text: "open_in_new"
            iconSize: Appearance.font.pixelSize.small
            color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
        }
    }
}
