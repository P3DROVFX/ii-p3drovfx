import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RippleButton {
    id: root
    required property string materialSymbol
    required property bool current
    property int shortcutIndex: 0
    property bool showShortcut: false
    // Opt-in for crowded bars: inactive tabs shrink to their icon so three
    // labelled tabs still fit a sidebar-width toolbar.
    property bool collapseInactiveLabel: false
    readonly property bool labelCollapsed: root.collapseInactiveLabel && !root.current
    horizontalPadding: root.labelCollapsed ? 10 : 14

    implicitHeight: 40
    implicitWidth: implicitContentWidth + horizontalPadding * 2
    buttonRadius: height / 2

    colBackground: "transparent"
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, root.current ? 0.88 : 0.95)
    colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95)

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.labelCollapsed ? 0 : 6

        Behavior on spacing {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Item {
            id: iconContainer
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22

            MaterialSymbol {
                id: icon
                anchors.centerIn: parent
                iconSize: 22
                text: root.materialSymbol
                fill: root.current ? 1.0 : (root.hovered ? 1.0 : 0.0)
                opacity: root.showShortcut ? 0.0 : 1.0
                scale: root.showShortcut ? 0.5 : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }

            Rectangle {
                id: shortcutBadge
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: Appearance.rounding.full
                color: root.current ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                opacity: root.showShortcut ? 1.0 : 0.0
                scale: root.showShortcut ? 1.0 : 0.5
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: String(root.shortcutIndex)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: root.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
            }
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            clip: true
            width: root.labelCollapsed ? 0 : implicitWidth
            opacity: root.labelCollapsed ? 0 : 1

            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
