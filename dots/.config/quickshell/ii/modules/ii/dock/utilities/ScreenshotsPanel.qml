import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The latest captures, ready to drag into any app; take a new one or open the folder. */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var files: panel.tile?.feed?.recent ?? []

    spacing: 8

    FileGrid {
        Layout.fillWidth: true
        visible: panel.files.length > 0
        files: panel.files
        columnsWanted: 2
        imagesOnly: true
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.files.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("No screenshots yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "screenshot_region"
            label: Translation.tr("Take screenshot")
            onClicked: {
                panel.host?.closePanel();
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "screenshot"]);
            }
        }
        ClockButton {
            Layout.fillWidth: true
            symbol: "folder_open"
            label: Translation.tr("Open folder")
            onClicked: {
                Quickshell.execDetached(["xdg-open", panel.tile?.folder ?? ""]);
                panel.host?.closePanel();
            }
        }
    }
}
