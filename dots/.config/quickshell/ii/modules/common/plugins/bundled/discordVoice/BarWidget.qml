import QtQuick
// The bundled plugin is routed through the native bar adapter to keep one
// geometry owner. This fallback still gives installed-package hosts a status glyph.
Item {
    property bool vertical: false
    implicitWidth: 32
    implicitHeight: 32
    DiscordGlyph {
        anchors.centerIn: parent
        implicitSize: 28
        iconSize: 16
    }
}
