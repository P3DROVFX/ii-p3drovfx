pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property var parsed: null
    signal createRequested()

    implicitHeight: parsed ? content.implicitHeight + Appearance.sizes.elevationMargin * 2 : 0
    visible: parsed !== null

    RippleButton {
        anchors.fill: parent
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive
        onClicked: root.createRequested()

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            spacing: Appearance.sizes.elevationMargin

            MaterialSymbol {
                text: "add_circle"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Create %1").arg(String(root.parsed?.title ?? ""))
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.parsed
                        ? Qt.formatDateTime(root.parsed.start, "ddd dd MMM · hh:mm") + "–" + Qt.formatTime(root.parsed.end, "hh:mm")
                        : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
