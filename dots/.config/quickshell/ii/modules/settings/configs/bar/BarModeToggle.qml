pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A two-way choice as one track with a primary pill that slides to the chosen side. Each
 * side names its option in the title face with a one-line caption; the icon shape of the
 * chosen side morphs. A side that cannot be chosen shows a lock and fades.
 *
 * options: [{ value, label, caption, icon, shape, enabled }]
 */
Rectangle {
    id: root

    readonly property real pad: 4
    readonly property real sidePadding: 14
    readonly property real iconSize: 20
    readonly property real iconPadding: 9

    property var options: []
    property var currentValue: null
    signal selected(var value)

    readonly property int currentIndex: Math.max(0, root.options.findIndex(option => option.value === root.currentValue))
    readonly property real halfWidth: (width - root.pad * 2) / Math.max(1, root.options.length)

    implicitHeight: 80
    radius: Math.min(height / 2, Appearance.rounding.full)
    color: Appearance.colors.colLayer1

    Rectangle {
        id: indicator
        x: root.pad + root.halfWidth * root.currentIndex
        y: root.pad
        width: root.halfWidth
        height: root.height - root.pad * 2
        radius: Math.min(height / 2, Appearance.rounding.full)
        color: Appearance.colors.colPrimary
        Behavior on x {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    Repeater {
        model: root.options

        delegate: Item {
            id: side
            required property var modelData
            required property int index
            readonly property bool chosen: side.index === root.currentIndex
            readonly property bool available: side.modelData.enabled !== false
            readonly property color colContent: side.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

            x: root.pad + root.halfWidth * side.index
            y: root.pad
            width: root.halfWidth
            height: root.height - root.pad * 2
            opacity: side.available || side.chosen ? 1 : 0.45

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                enabled: side.available && !side.chosen
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.selected(side.modelData.value)
            }

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, Appearance.rounding.full)
                color: Appearance.colors.colOnLayer1
                opacity: area.containsMouse ? 0.06 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: root.sidePadding - root.pad
                    rightMargin: root.sidePadding
                }
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    text: side.available || side.chosen ? side.modelData.icon : "lock"
                    iconSize: root.iconSize
                    padding: root.iconPadding
                    fill: 1
                    shape: side.chosen ? (side.modelData.shape ?? MaterialShape.Shape.Cookie9Sided)
                        : area.containsMouse ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                    color: side.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: side.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -1

                    StyledText {
                        Layout.fillWidth: true
                        text: side.modelData.label
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: side.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: side.modelData.caption ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: side.colContent
                        opacity: 0.8
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
