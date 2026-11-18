import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property string text
    property bool shown: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    /** Widest the text may run before it wraps; 0 = one line, however long. */
    property real maxTextWidth: 0
    readonly property real textWidth: root.maxTextWidth > 0
        ? Math.min(tooltipTextObject.implicitWidth, root.maxTextWidth) : tooltipTextObject.implicitWidth
    property alias font: tooltipTextObject.font
    implicitWidth: root.textWidth + 2 * root.horizontalPadding
    implicitHeight: tooltipTextObject.height + 2 * root.verticalPadding

    property bool isVisible: backgroundRectangle.implicitHeight > 0

    Rectangle {
        id: backgroundRectangle
        anchors {
            bottom: root.bottom
            horizontalCenter: root.horizontalCenter
        }
        color: Appearance?.colors.colTooltip ?? "#3C4043"
        radius: Appearance?.rounding.verysmall ?? 7
        opacity: shown ? 1 : 0
        implicitWidth: shown ? (root.textWidth + 2 * root.horizontalPadding) : 0
        implicitHeight: shown ? (tooltipTextObject.height + 2 * root.verticalPadding) : 0
        clip: true

        Behavior on implicitWidth {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledText {
            id: tooltipTextObject
            anchors.centerIn: parent
            width: root.textWidth
            text: root.text
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 14
            font.hintingPreference: Font.PreferNoHinting // Prevent shaky text
            color: Appearance?.colors.colOnTooltip ?? "#FFFFFF"
            wrapMode: Text.Wrap
        }
    }   
}

