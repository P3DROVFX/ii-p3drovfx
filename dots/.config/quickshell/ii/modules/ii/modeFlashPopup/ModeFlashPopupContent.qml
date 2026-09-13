import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * The banner itself: the mode's icon in its colour, a title and a line
 * that says why. Slides down from the top edge and back up.
 */
Item {
    id: root

    property bool isOpen: false
    property var payload: null
    property real topMarginValue: 0
    readonly property bool isExitAnimRunning: exitAnim.running

    // The payload is cleared by the engine only when the next one arrives,
    // so the exit animation keeps its text.
    readonly property string colorKey: root.payload?.color ?? ""
    readonly property string icon: root.payload?.icon ?? "tune"
    readonly property string title: root.payload?.title ?? ""
    readonly property string subtitle: root.payload?.subtitle ?? ""

    onIsOpenChanged: {
        if (isOpen) {
            exitAnim.stop();
            entranceAnim.start();
        } else {
            entranceAnim.stop();
            exitAnim.start();
        }
    }

    // A new payload while open: pulse the icon so the change registers.
    onPayloadChanged: {
        if (root.isOpen)
            iconPulse.restart();
    }

    property real horizontalPadding: 18

    implicitWidth: Math.min(520, contentLayout.implicitWidth + 2 * horizontalPadding) + 2 * Appearance.sizes.elevationMargin
    implicitHeight: 64 + 2 * Appearance.sizes.elevationMargin

    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
    }

    StyledRectangularShadow {
        target: contentBackground
        opacity: contentBackground.opacity
        transform: Translate {
            y: contentBackground.yOffset
        }
    }

    Rectangle {
        id: contentBackground

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: root.topMarginValue + Appearance.sizes.elevationMargin
        }

        width: parent.width - 2 * Appearance.sizes.elevationMargin
        height: 64
        radius: Appearance.rounding.full
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer

        readonly property real slideOffset: -(root.topMarginValue + Appearance.sizes.elevationMargin + height + 40)
        opacity: 0
        property real yOffset: slideOffset

        transform: Translate {
            y: contentBackground.yOffset
        }

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "yOffset"
                from: contentBackground.slideOffset
                to: 0
                duration: 480
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0
                to: 1
                duration: 480
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        ParallelAnimation {
            id: exitAnim
            NumberAnimation {
                target: contentBackground
                property: "yOffset"
                to: contentBackground.slideOffset
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
        }

        RowLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: 14

            MaterialShape {
                id: iconShape
                shapeString: "Cookie12Sided"
                color: ModeUi.container(root.colorKey)
                implicitWidth: 44
                implicitHeight: 44

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: 22
                    fill: 1
                    color: ModeUi.onContainer(root.colorKey)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    SequentialAnimation {
        id: iconPulse
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.25
            duration: 120
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.0
            duration: 220
            easing.type: Easing.OutBack
        }
    }
}
