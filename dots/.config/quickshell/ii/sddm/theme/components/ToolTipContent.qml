import QtQuick

// The shell's StyledToolTipContent: a small surface that grows open from its bottom edge.
Item {
    id: root
    required property string text
    property bool shown: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    implicitWidth: label.implicitWidth + 2 * root.horizontalPadding
    implicitHeight: label.implicitHeight + 2 * root.verticalPadding

    component FastAnim: NumberAnimation {
        duration: Theme.ms(200)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveEffects
    }

    Rectangle {
        anchors {
            bottom: root.bottom
            horizontalCenter: root.horizontalCenter
        }
        color: Theme.colTooltip
        radius: Theme.roundingVerySmall
        opacity: root.shown ? 1 : 0
        implicitWidth: root.shown ? (label.implicitWidth + 2 * root.horizontalPadding) : 0
        implicitHeight: root.shown ? (label.implicitHeight + 2 * root.verticalPadding) : 0
        clip: true

        Behavior on implicitWidth { FastAnim {} }
        Behavior on implicitHeight { FastAnim {} }
        Behavior on opacity { FastAnim {} }

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Theme.pxSmaller
            font.hintingPreference: Font.PreferNoHinting
            color: Theme.colOnTooltip
        }
    }
}
