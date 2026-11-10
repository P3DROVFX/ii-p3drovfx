pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The score just changed in a followed game: both crests, the new score, the clock of
 * the match and the play that did it, when the feed says.
 *
 * Only drawn for that moment (see SportsSource); a game in progress is otherwise the
 * glance beside the clock.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.sports : null;
    }
    readonly property var game: root.source ? root.source.liveGame : null

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 16
        spacing: 10

        Crest {
            logo: root.game?.home?.logo ?? ""
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: (root.game?.home?.score ?? "") + " – " + (root.game?.away?.score ?? "")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
            color: Appearance.colors.colOnLayer0
        }

        Crest {
            logo: root.game?.away?.logo ?? ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: (root.game?.home?.name ?? "") + " · " + (root.game?.away?.name ?? "")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.game?.lastPlay || root.game?.status || ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    component Crest: Image {
        required property string logo
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 26
        Layout.preferredHeight: 26
        source: logo
        sourceSize: Qt.size(52, 52)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
    }
}
