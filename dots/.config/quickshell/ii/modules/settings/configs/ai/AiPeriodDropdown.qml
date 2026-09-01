import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The reference's period selector: a thin outlined pill with the label and a
 * chevron, opening a popup with the period options. The border is
 * deliberately part of this one control's design (explicitly sanctioned);
 * everywhere else the bento stays borderless.
 *
 * Stateless by design: `mode` stays bound to the card's own state and
 * changes travel back only through `modeSelected`, so each card owns its
 * period independently. `colText` must be the card's on-surface foreground
 * so the tint and border read correctly on any container color.
 */
ComboBox {
    id: root

    property string mode: ""
    property var options: []
    property color colText: Appearance.colors.colOnPrimaryContainer
    property real dropdownWidth: 148
    property int labelPixelSize: Appearance.font.pixelSize.small

    signal modeSelected(string value)

    hoverEnabled: true
    implicitHeight: 34
    implicitWidth: root.dropdownWidth

    textRole: "label"
    model: root.options
    currentIndex: root.indexOfMode()

    function indexOfMode(): int {
        for (let i = 0; i < root.options.length; ++i)
            if (root.options[i].value === root.mode)
                return i;
        return root.options.length - 1;
    }

    onActivated: index => {
        // `mode` keeps its binding to the card's state; only the visual
        // selection moves here until the card answers via modeSelected.
        root.currentIndex = index;
        root.modeSelected(root.options[index].value);
    }

    background: Rectangle {
        radius: Appearance.rounding.full
        color: root.down && !root.popup.visible
            ? ColorUtils.transparentize(root.colText, 0.78)
            : root.hovered
                ? ColorUtils.transparentize(root.colText, 0.86)
                : ColorUtils.transparentize(root.colText, 0.92)
        border.width: 1
        border.color: ColorUtils.transparentize(root.colText, 0.55)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 8
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.large
        color: root.colText

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: StyledText {
        leftPadding: 14
        rightPadding: 34
        text: root.displayText
        color: root.colText
        font.pixelSize: root.labelPixelSize
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    delegate: ItemDelegate {
        id: optionDelegate

        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: 38

        required property var model
        required property int index
        readonly property bool isSelected: root.currentIndex === optionDelegate.index

        property color bgColor: optionDelegate.isSelected
            ? (optionDelegate.down ? Appearance.colors.colSecondaryContainerActive
                : optionDelegate.hovered ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colSecondaryContainer)
            : (optionDelegate.down ? Appearance.colors.colLayer3Active
                : optionDelegate.hovered ? Appearance.colors.colLayer3Hover
                : ColorUtils.transparentize(Appearance.colors.colLayer3))

        background: Rectangle {
            radius: Appearance.rounding.small
            color: optionDelegate.bgColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        contentItem: RowLayout {
            spacing: 8
            anchors.leftMargin: 10
            anchors.rightMargin: 10

            StyledText {
                Layout.fillWidth: true
                text: optionDelegate.model.label
                color: optionDelegate.isSelected
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer3
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MaterialSymbol {
                visible: optionDelegate.isSelected
                text: "check"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    popup: Popup {
        id: popupRoot

        y: root.height + 4
        width: 176
        height: Math.min(listView.contentHeight + topPadding + bottomPadding, 300)
        padding: 8

        transformOrigin: Item.Top

        enter: Transition {
            SequentialAnimation {
                PropertyAction {
                    target: popupRoot
                    property: "y"
                    value: root.height - 10
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: popupRoot
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardDecel
                    }
                    NumberAnimation {
                        target: popupRoot
                        property: "y"
                        from: root.height - 10
                        to: root.height + 4
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardDecel
                    }
                }
            }
        }

        exit: Transition {
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation {
                        target: popupRoot
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardAccel
                    }
                    NumberAnimation {
                        target: popupRoot
                        property: "y"
                        from: root.height + 4
                        to: root.height - 10
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardAccel
                    }
                }
                PropertyAction {
                    target: popupRoot
                    property: "y"
                    value: root.height + 4
                }
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: StyledListView {
            id: listView

            clip: true
            implicitHeight: contentHeight
            spacing: 2
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }
    }
}
