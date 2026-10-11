import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The shell's Material 3 expressive toolbar: a pill of buttons with a soft shadow.
Item {
    id: root

    property real padding: 3
    property alias colBackground: background.color
    property alias spacing: toolbarLayout.spacing
    default property alias toolbarData: toolbarLayout.data
    property alias radius: background.radius
    readonly property real contentWidth: toolbarLayout.implicitWidth
    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight
    width: implicitWidth
    height: implicitHeight

    RectangularShadow {
        anchors.fill: background
        radius: background.radius
        blur: 0.9 * Theme.elevationMargin
        offset: Qt.vector2d(0.0, 1.0)
        spread: 1
        color: Theme.colShadow
        cached: true
        visible: !Theme.transparency
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: Theme.m3surfaceContainer
        implicitHeight: Theme.toolbarHeight
        implicitWidth: toolbarLayout.implicitWidth + root.padding * 2
        radius: Theme.sharpMode ? Theme.roundingFull : height / 2

        RowLayout {
            id: toolbarLayout
            spacing: 4
            anchors {
                fill: parent
                margins: root.padding
            }
        }
    }
}
