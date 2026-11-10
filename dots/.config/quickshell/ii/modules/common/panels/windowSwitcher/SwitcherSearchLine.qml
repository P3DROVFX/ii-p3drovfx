import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Over the windows while they are narrowed down: the app Alt+` keeps to, what has been typed,
 * and how many windows match it. Keeps its last text while it fades out, so it does not empty
 * before it goes. Shared by the island and the panel.
 */
Row {
    id: line

    property real maxWidth: 400

    readonly property bool searching: WindowSwitcher.query.length > 0
    readonly property bool narrowed: WindowSwitcher.appFilter !== ""
    property string shownQuery: ""
    property string shownApp: ""
    property string shownAppClass: ""

    Connections {
        target: WindowSwitcher
        function onQueryChanged() {
            if (WindowSwitcher.query.length > 0)
                line.shownQuery = WindowSwitcher.query;
        }
        function onAppFilterChanged() {
            if (WindowSwitcher.appFilter !== "") {
                line.shownApp = WindowSwitcher.appFilterName;
                line.shownAppClass = WindowSwitcher.appFilter;
            }
        }
    }

    spacing: 8

    // Alt+`: whose windows these are.
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: line.narrowed || (!line.searching && line.shownApp !== "")
        spacing: 6
        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            source: {
                const _ = TaskbarApps.iconThemeRevision;
                return Quickshell.iconPath(AppSearch.guessIcon(line.shownAppClass), "image-missing");
            }
            sourceSize: Qt.size(18, 18)
            asynchronous: true
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: line.shownApp
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer0
        }
    }

    MaterialSymbol {
        anchors.verticalCenter: parent.verticalCenter
        visible: line.searching || !line.narrowed
        text: "search"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colPrimary
    }
    StyledText {
        id: queryText
        anchors.verticalCenter: parent.verticalCenter
        visible: line.searching || !line.narrowed
        width: Math.min(implicitWidth, Math.max(40, line.maxWidth - 160))
        elide: Text.ElideLeft
        text: line.searching ? WindowSwitcher.query : line.shownQuery
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer0
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: line.searching && WindowSwitcher.count > 0
        text: WindowSwitcher.count === 1 ? Translation.tr("1 match") : Translation.tr("%1 matches").arg(WindowSwitcher.count)
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
}
