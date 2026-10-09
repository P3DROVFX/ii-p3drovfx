pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A `colLayer1` slab with the shape-icon header of the other pages: the title, a subtitle
 * that states the current value and, when `switchable`, the switch that turns the feature
 * on. Turning it off folds the body away (`default` content) instead of leaving dead controls.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 14
    readonly property real iconSize: 24
    readonly property real iconPadding: 12
    readonly property real bodyGap: 16
    readonly property real switchScale: 0.85
    readonly property real disabledOpacity: 0.45

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Cookie9Sided
    property var shapeEngaged: MaterialShape.Shape.Cookie12Sided
    property string title: ""
    property string subtitle: ""
    property bool switchable: false
    property bool checked: true
    default property alias body: bodyColumn.data

    signal toggled(bool value)

    readonly property bool bodyOpen: !root.switchable || root.checked
    // The curve overshoots; a height may, an opacity must not.
    property real reveal: root.bodyOpen ? 1 : 0
    readonly property real revealClamped: Math.max(0, Math.min(1, root.reveal))
    Behavior on reveal {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    opacity: root.enabled ? 1 : root.disabledOpacity
    color: Appearance.colors.colLayer1

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 0

        Item {
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight

            HoverHandler {
                id: headerHover
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.switchable
                cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.toggled(!root.checked)
            }

            RowLayout {
                id: header
                anchors {
                    left: parent.left
                    right: parent.right
                }
                spacing: root.headerSpacing

                MaterialShapeWrappedMaterialSymbol {
                    text: root.symbol
                    iconSize: root.iconSize
                    padding: root.iconPadding
                    fill: root.bodyOpen ? 1 : 0
                    shape: headerHover.hovered ? root.shapeEngaged : root.shapeIdle
                    color: root.bodyOpen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    colSymbol: root.bodyOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.subtitle
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                StyledSwitch {
                    visible: root.switchable
                    Layout.alignment: Qt.AlignVCenter
                    sizeScale: root.switchScale
                    checked: root.checked
                    onToggled: root.toggled(checked)
                }
            }
        }

        Item {
            id: bodyClip
            Layout.fillWidth: true
            Layout.preferredHeight: root.reveal * (bodyColumn.implicitHeight + root.bodyGap)
            visible: root.reveal > 0.001
            clip: true

            ColumnLayout {
                id: bodyColumn
                y: root.bodyGap
                width: parent.width
                opacity: root.revealClamped
                spacing: 8
            }
        }
    }
}
