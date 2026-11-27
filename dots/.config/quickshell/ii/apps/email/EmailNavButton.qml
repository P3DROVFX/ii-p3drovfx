import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

GroupButton {
    id: root

    // Position in group (set by parent)
    property bool isFirst: false
    property bool isLast: false

    // Visual config
    property string iconName: ""
    property string label: ""

    property string badgeText: ""
    property color badgeColor: Appearance.colors.colSecondary
    property color badgeTextColor: Appearance.colors.colOnSecondary

    Layout.fillWidth: true
    Layout.fillHeight: false
    baseHeight: 56
    bounce: false

    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover

    // Radius logic: first gets large top, last gets large bottom, middle gets verysmall
    property real _activeRadius: Appearance.rounding.full
    property real _topRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
    property real _bottomRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

    background: Rectangle {
        id: btnBg
        antialiasing: true
        color: root.color
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        topLeftRadius: (root.toggled || root.down) ? root._activeRadius : root._topRadius
        topRightRadius: (root.toggled || root.down) ? root._activeRadius : root._topRadius
        bottomLeftRadius: (root.toggled || root.down) ? root._activeRadius : root._bottomRadius
        bottomRightRadius: (root.toggled || root.down) ? root._activeRadius : root._bottomRadius

        Behavior on topLeftRadius {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on topRightRadius {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on bottomLeftRadius {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on bottomRightRadius {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: btnBg.width
                height: btnBg.height
                topLeftRadius: btnBg.topLeftRadius
                topRightRadius: btnBg.topRightRadius
                bottomLeftRadius: btnBg.bottomLeftRadius
                bottomRightRadius: btnBg.bottomRightRadius
                antialiasing: true
            }
        }

        Item {
            id: ripple
            x: 0
            y: 0
            width: ripple.rippleSize
            height: ripple.rippleSize
            opacity: 0
            visible: rippleSize > 0
            property real rippleSize: 0
            property real rippleCenterX: 0
            property real rippleCenterY: 0

            transform: Translate {
                x: ripple.rippleCenterX - ripple.rippleSize / 2
                y: ripple.rippleCenterY - ripple.rippleSize / 2
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Appearance.colors.colPrimaryActive
                    }
                    GradientStop {
                        position: 0.4
                        color: "transparent"
                    }
                }
            }
        }

        NumberAnimation {
            id: rippleFade
            target: ripple
            property: "opacity"
            to: 0
            duration: 2400
            easing.type: Easing.OutQuart
        }

        SequentialAnimation {
            id: rippleAnim
            property real cx
            property real cy
            property real r
            PropertyAction {
                target: ripple
                property: "rippleCenterX"
                value: rippleAnim.cx
            }
            PropertyAction {
                target: ripple
                property: "rippleCenterY"
                value: rippleAnim.cy
            }
            PropertyAction {
                target: ripple
                property: "rippleSize"
                value: 0
            }
            PropertyAction {
                target: ripple
                property: "opacity"
                value: 0.55
            }
            NumberAnimation {
                target: ripple
                property: "rippleSize"
                from: 0
                to: rippleAnim.r * 2
                duration: 1200
                easing.type: Easing.OutQuart
            }
        }

        Connections {
            target: root.mouseArea
            function onPressed(event) {
                var d = (ox, oy) => ox * ox + oy * oy;
                rippleAnim.cx = event.x;
                rippleAnim.cy = event.y;
                rippleAnim.r = Math.sqrt(Math.max(d(0, 0), d(root.width, 0), d(0, root.height), d(root.width, root.height)));
                rippleFade.complete();
                rippleAnim.restart();
            }
            function onReleased(event) {
                rippleFade.restart();
            }
            function onCanceled(event) {
                rippleFade.restart();
            }
        }
    }

    scale: down ? 0.95 : hovered ? 1.02 : 1.0
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    contentItem: Item {
        implicitHeight: 56
        anchors.fill: parent
        RowLayout {
            spacing: 12
            anchors.centerIn: parent

            MaterialSymbol {
                text: root.iconName
                iconSize: Appearance.font.pixelSize.huge
                fill: root.toggled ? 1 : 0
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: root.toggled ? Font.DemiBold : Font.Normal
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }
        }

        Rectangle {
            visible: root.badgeText !== ""
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: Appearance.rounding.full
            color: root.badgeColor
            antialiasing: true

            StyledText {
                id: badgeTextItem
                anchors.centerIn: parent
                text: root.badgeText
                font.family: Appearance.font.family.main
                font.pixelSize: root.badgeText.length > 3 ? 9 : (root.badgeText.length > 2 ? 10 : Appearance.font.pixelSize.smallie)
                font.weight: Font.Bold
                color: root.badgeTextColor
            }
        }
    }
}
