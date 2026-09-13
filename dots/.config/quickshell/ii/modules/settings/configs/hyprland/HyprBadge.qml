import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/// The small pill the hub's rows use for a word about themselves - who set an option, how many
/// settings behind a door were changed. Takes no room while it has nothing to say.
Rectangle {
    id: root

    property string text: ""

    visible: root.text !== ""
    implicitHeight: 22
    implicitWidth: label.implicitWidth + 14
    radius: Appearance.rounding.full
    color: Appearance.colors.colSecondaryContainer

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnSecondaryContainer
    }
}
