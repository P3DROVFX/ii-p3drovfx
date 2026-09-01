import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TabButton {
    id: root

    property bool toggled: TabBar.tabBar.currentIndex === TabBar.index
    property string buttonIcon
    property real buttonIconRotation: 0
    property string buttonText
    property bool _isInitialized: false
    Component.onCompleted: _isInitialized = true

    property bool expanded: false
    property bool showToggledHighlight: true
    // Keep the intrinsic size independent from root.width. When an expanded
    // button fills a layout, visualWidth may use root.width for the painted
    // highlight, but feeding that value back into the content item's
    // implicitWidth creates a width -> visualWidth -> implicitWidth loop.
    readonly property real contentWidth: root.baseSize + 20 + itemText.implicitWidth
    readonly property real visualWidth: {
        return root.expanded && root.fillExpandedWidth ? Math.max(root.width, root.contentWidth) : (root.expanded ? root.contentWidth : root.baseSize);
    }

    property real baseSize: 56
    property real baseHighlightHeight: 32
    property real iconSize: 24
    property real groupSpacing: 0
    property bool useDynamicRadius: false
    property bool groupFirst: false
    property bool groupLast: false
    property bool fillExpandedWidth: false
    property int textPixelSize: 14
    property color colBackground: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1)
    property color colBackgroundHover: Appearance.colors.colLayer1Hover
    property color colBackgroundActive: Appearance.colors.colLayer1Active
    property color colBackgroundToggled: Appearance.colors.colSecondaryContainer
    property color colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
    property color colRipple: Appearance.colors.colLayer1Active
    property color colRippleToggled: Appearance.colors.colSecondaryContainerActive
    property color colText: Appearance.colors.colOnLayer1
    property color colTextToggled: Appearance.m3colors.m3onSecondaryContainer
    property real highlightCollapsedTopMargin: 8
    padding: 0

    // The navigation item’s target area always spans the full width of the
    // nav rail, even if the item container hugs its contents.
    Layout.fillWidth: true
    Layout.topMargin: root.groupSpacing
    // implicitWidth: contentItem.implicitWidth
    implicitHeight: baseSize

    background: null
    PointingHandInteraction {}

    // Real stuff
    contentItem: Item {
        id: buttonContent
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: root.expanded && root.fillExpandedWidth ? parent.right : undefined
        }

        implicitWidth: root.expanded ? root.contentWidth : root.baseSize
        implicitHeight: root.expanded ? itemIconBackground.implicitHeight : itemIconBackground.implicitHeight + itemText.implicitHeight

        Rectangle {
            id: itemBackground
            anchors.top: itemIconBackground.top
            anchors.left: itemIconBackground.left
            anchors.bottom: itemIconBackground.bottom
            width: root.expanded && root.fillExpandedWidth ? buttonContent.width : root.visualWidth
            implicitWidth: root.visualWidth
            readonly property real fullRadius: Math.min(height / 2, Appearance.rounding.large)
            readonly property real topRadius: root.groupFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
            readonly property real bottomRadius: root.groupLast ? Appearance.rounding.large : Appearance.rounding.verysmall

            topLeftRadius: root.useDynamicRadius ? ((root.toggled || root.down) ? fullRadius : topRadius) : Appearance.rounding.full
            topRightRadius: root.useDynamicRadius ? ((root.toggled || root.down) ? fullRadius : topRadius) : Appearance.rounding.full
            bottomLeftRadius: root.useDynamicRadius ? ((root.toggled || root.down) ? fullRadius : bottomRadius) : Appearance.rounding.full
            bottomRightRadius: root.useDynamicRadius ? ((root.toggled || root.down) ? fullRadius : bottomRadius) : Appearance.rounding.full
            color: root.toggled && root.showToggledHighlight ? (root.down ? root.colBackgroundToggledActive : root.hovered ? root.colBackgroundToggledHover : root.colBackgroundToggled) : (root.down ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground)

            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemBackground
                    anchors.top: buttonContent.top
                    anchors.left: buttonContent.left
                    anchors.bottom: buttonContent.bottom
                }
                PropertyChanges {
                    target: itemBackground
                    implicitWidth: root.visualWidth
                }
            }
            transitions: Transition {
                enabled: root._isInitialized

                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                PropertyAnimation {
                    target: itemBackground
                    property: "implicitWidth"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on topLeftRadius {
                enabled: root.useDynamicRadius
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on topRightRadius {
                enabled: root.useDynamicRadius
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on bottomLeftRadius {
                enabled: root.useDynamicRadius
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on bottomRightRadius {
                enabled: root.useDynamicRadius
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Item {
            id: itemIconBackground
            implicitWidth: root.baseSize
            implicitHeight: root.baseHighlightHeight
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            MaterialSymbol {
                id: navRailButtonIcon
                rotation: root.buttonIconRotation
                anchors.centerIn: parent
                iconSize: root.iconSize
                fill: toggled ? 1 : 0
                font.weight: (toggled || root.hovered) ? Font.DemiBold : Font.Normal
                text: buttonIcon
                color: toggled ? root.colTextToggled : root.colText

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledText {
            id: itemText
            states: [
                State {
                    name: "expanded"
                    when: root.expanded
                    AnchorChanges {
                        target: itemText
                        anchors {
                            top: undefined
                            horizontalCenter: undefined
                            left: itemIconBackground.right
                            verticalCenter: itemIconBackground.verticalCenter
                        }
                    }
                },
                State {
                    name: "minimized"
                    when: !root.expanded
                    AnchorChanges {
                        target: itemText
                        anchors {
                            left: undefined
                            verticalCenter: undefined
                            top: itemIconBackground.bottom
                            horizontalCenter: itemIconBackground.horizontalCenter
                        }
                    }
                }
            ]
            transitions: Transition {
                enabled: root._isInitialized

                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            text: buttonText
            font.pixelSize: root.textPixelSize
            color: root.toggled ? root.colTextToggled : root.colText
        }
    }
}
