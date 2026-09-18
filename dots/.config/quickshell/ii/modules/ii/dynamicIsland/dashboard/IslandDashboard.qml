pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The island's dashboard: its expanded face when nothing else claims the centre.
 *
 * The island reaches it by expanding while it rests (the clock, or no activity at all)
 * and by paging past the last activity with the wheel. Its size is declared by the
 * surface, not measured here, so the shape can finish its morph before this is built.
 *
 * Placeholder content for now: the engine around it comes first, the pages next.
 */
Item {
    id: dashboard

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "dashboard"
            iconSize: Appearance.font.pixelSize.hugeass
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Dashboard")
            font.pixelSize: Appearance.font.pixelSize.large
            font.bold: true
            color: Appearance.colors.colOnSurface
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Placeholder - pages coming next")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
