import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "FootballFormat.js" as Format

// Match state as a pill: live in the tertiary voice (persistent status),
// finished in the neutral secondary container, upcoming as the kickoff time.
Rectangle {
    id: root

    property var match: null
    property real pillHeight: 24
    property int textSize: FootballStyle.textSmaller

    readonly property bool live: root.match?.state === "in"
    readonly property bool finished: root.match?.state === "post"

    implicitHeight: root.pillHeight
    implicitWidth: label.implicitWidth + (root.live ? 26 : 16)
    radius: root.pillHeight / 2
    color: root.live ? FootballStyle.colTertiaryContainer : FootballStyle.colSecondaryContainer

    Rectangle {
        visible: root.live
        width: 6
        height: 6
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        x: 9
        color: FootballStyle.colOnTertiaryContainer
    }

    StyledText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: root.live ? 19 : 8
        text: Format.statusText(root.match, Translation.tr("Live"))
        font.pixelSize: root.textSize
        font.weight: Font.Bold
        color: root.live ? FootballStyle.colOnTertiaryContainer : FootballStyle.colOnSecondaryContainer
    }
}
