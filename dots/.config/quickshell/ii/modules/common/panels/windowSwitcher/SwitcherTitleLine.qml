import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * The selected window, said in full under the switcher: its icon, its app, its title - the
 * part a search matched picked out. Centred, at most `maxWidth` wide; the title gives way
 * first. Shared by the island and the panel.
 */
Item {
    id: line

    required property var entry
    property real maxWidth: 400

    readonly property string appName: line.entry?.appName || line.entry?.appClass || ""
    readonly property string title: line.entry?.toplevel?.title || line.entry?.title || ""
    /// An app whose title is just its name says it once.
    readonly property bool showTitle: line.title !== "" && line.title.toLowerCase() !== line.appName.toLowerCase()

    implicitWidth: row.width
    implicitHeight: 22

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Image {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            visible: line.entry !== null
            source: {
                const _ = TaskbarApps.iconThemeRevision;
                return Quickshell.iconPath(AppSearch.guessIcon(line.entry?.appClass ?? ""), "image-missing");
            }
            sourceSize: Qt.size(18, 18)
            asynchronous: true
        }
        StyledText {
            id: appText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, line.maxWidth * 0.4)
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: Logic.highlighted(line.appName, WindowSwitcher.query, Appearance.colors.colPrimary)
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            id: dot
            anchors.verticalCenter: parent.verticalCenter
            visible: line.showTitle
            text: "·"
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: line.showTitle
            width: Math.max(0, Math.min(implicitWidth,
                line.maxWidth - icon.width - appText.width - dot.width - row.spacing * 3))
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: Logic.highlighted(line.title, WindowSwitcher.query, Appearance.colors.colPrimary)
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer0
        }
    }
}
