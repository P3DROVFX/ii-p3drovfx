pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** "Phone keyboard ready · type from the PC"; a click opens the Phone tab's pad. */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneKeyboard : null;
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        spacing: 10

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "keyboard"
            fill: 1
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("Phone keyboard ready · type from the PC")
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.source?.dismiss();
            GlobalStates.openPhoneKeyboard();
        }
    }
}
