import qs.modules.common
import QtQuick

Rectangle {
    id: root
    property string key

    /**
     * Shrinks the label to fit a cap sized from outside, instead of letting the
     * label size the cap.
     *
     * The default is the other way round — a key is as wide as what is written
     * on it — which is right for a legend in a list. It is wrong for a picture
     * of a real keyboard, where the caps are the size the hardware says and
     * "RShift" has to get on one anyway.
     */
    property bool fitText: false
    property real minimumPixelSize: 7

    property real horizontalPadding: 6
    property real verticalPadding: 1
    property real borderWidth: 1
    property real extraBottomBorderWidth: 2
    property color borderColor: Appearance.colors.colOnLayer0
    property real borderRadius: 5
    property real pixelSize: Appearance.font.pixelSize.smaller
    property color keyColor: Appearance.m3colors.m3surfaceContainerLow
    property color textColor: Appearance.m3colors.m3onBackground
    implicitWidth: keyFace.implicitWidth + borderWidth * 2
    implicitHeight: keyFace.implicitHeight + borderWidth * 2 + extraBottomBorderWidth
    radius: borderRadius
    color: borderColor

    Rectangle {
        id: keyFace
        anchors {
            fill: parent
            topMargin: borderWidth
            leftMargin: borderWidth
            rightMargin: borderWidth
            bottomMargin: extraBottomBorderWidth + borderWidth
        }
        // Deriving the face from the label while the label is being fitted to
        // the face would be a loop, so a fitted key takes its size from outside
        // and nothing else.
        implicitWidth: root.fitText ? 0 : keyText.implicitWidth + horizontalPadding * 2
        implicitHeight: root.fitText ? 0 : keyText.implicitHeight + verticalPadding * 2
        color: keyColor
        radius: borderRadius - borderWidth

        StyledText {
            id: keyText
            anchors.centerIn: root.fitText ? undefined : parent
            anchors.fill: root.fitText ? parent : undefined
            anchors.leftMargin: root.horizontalPadding
            anchors.rightMargin: root.horizontalPadding
            anchors.topMargin: root.verticalPadding
            anchors.bottomMargin: root.verticalPadding
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            // `pixelSize` is the ceiling once fitting is on: the label is drawn
            // as large as the cap allows, and no larger than it would have been.
            fontSizeMode: root.fitText ? Text.Fit : Text.FixedSize
            minimumPixelSize: root.minimumPixelSize
            font.family: Appearance.font.family.monospace
            font.pixelSize: root.pixelSize
            color: root.textColor
            text: key
        }
    }
}
