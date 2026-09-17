import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string text: ""
    property string icon
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to
    /// A small pill after the label, for a word about the row. Takes no room while empty.
    property string badgeText: ""

    Layout.fillWidth: true
    // A settings row is one tap target. Floor it at the Material minimum on a
    // touch-first family rather than fixing the height, so rows that are already
    // taller keep their size.
    implicitHeight: Math.max(rowLayout.implicitHeight + 32,
        PanelFamily.touchFirst ? Appearance.sizes.minimumTouchTarget + 12 : 0)

    color: Appearance.colors.colLayer2

    HoverHandler {
        id: hoverHandler
    }
    property bool hovered: hoverHandler.hovered

    readonly property GroupPosition groupPosition: GroupPosition {
        item: root
    }
    readonly property int itemIndex: groupPosition.index

    readonly property int totalItems: groupPosition.count

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool isPressed: spinBoxWidget.up.pressed || spinBoxWidget.down.pressed

    readonly property bool prevIsPressed: groupPosition.previousPressed

    readonly property bool nextIsPressed: groupPosition.nextPressed

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p) return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        visible: opacity > 0
    }

    ScrollAnimate {}

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Loader {
            active: root.icon && root.icon.length > 0
            visible: active
            Layout.alignment: Qt.AlignVCenter
            opacity: root.enabled ? 1 : 0.4

            sourceComponent: MaterialShapeWrappedMaterialSymbol {
                text: root.icon
                readonly property bool isActive: spinBoxWidget.activeFocus || spinBoxWidget.up.pressed || spinBoxWidget.down.pressed
                shape: isActive ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Circle
                iconSize: 18
                padding: 6
                color: isActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                colSymbol: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3

                Behavior on color {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on colSymbol {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }

        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnLayer2
            opacity: root.enabled ? 1 : 0.4
        }

        Rectangle {
            visible: root.badgeText.length > 0
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 22
            implicitWidth: badgeLabel.implicitWidth + 14
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer

            StyledText {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.badgeText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledSpinBox {
            id: spinBoxWidget
            Layout.fillWidth: false
        }
    }
}
