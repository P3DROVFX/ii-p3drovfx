pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The way into one of the dock's sub-pages, as a slab: a shape icon that morphs
 * under the pointer, the title in the title face, a line that says what is set
 * now, and the live contents as glyphs. `count` (≥ 0) stands beside the title in
 * condensed digits — the one number the sub-page is about.
 */
RippleButton {
    id: root

    property string symbol: ""
    property var shapeRest: MaterialShape.Shape.Cookie9Sided
    property var shapeHover: MaterialShape.Shape.Cookie12Sided
    property string title: ""
    property string summary: ""
    /** Material symbols for what is on now; the row hides when empty. */
    property var glyphs: []
    property int count: -1
    property string countLabel: ""

    implicitHeight: column.implicitHeight + 40
    buttonRadius: Appearance.rounding.verylarge
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    contentItem: Item {
        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    text: root.symbol
                    iconSize: 24
                    padding: 12
                    fill: 1
                    shape: root.hovered ? root.shapeHover : root.shapeRest
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
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
                        text: root.summary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                // The number, tall and condensed, over what it counts.
                ColumnLayout {
                    visible: root.count >= 0
                    spacing: -4
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: String(root.count)
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                        font.pixelSize: 40
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.countLabel
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    text: "chevron_right"
                    iconSize: 22
                    color: Appearance.colors.colSubtext
                    Layout.leftMargin: 2
                    // Leans toward the sub-page under the pointer.
                    transform: Translate {
                        x: root.hovered ? 3 : 0
                        Behavior on x {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: root.glyphs.length > 0
                spacing: 6
                Repeater {
                    model: root.glyphs
                    delegate: Rectangle {
                        required property string modelData
                        width: 32
                        height: 32
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: parent.modelData
                            iconSize: 17
                            fill: 1
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }
}
