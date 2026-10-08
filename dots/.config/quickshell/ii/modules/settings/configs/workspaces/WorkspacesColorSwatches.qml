pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * The colour treatments as swatches painted in their own active-indicator pair:
 * each shows a workspace number on its fill. The chosen one turns into a cookie
 * and spins in; the name of the one in focus reads underneath.
 */
ColumnLayout {
    id: root

    property string currentValue: "primary"
    property var names: ({})

    readonly property real swatchSize: 46
    readonly property real swatchGap: 10
    readonly property real hoverGrow: 1.1
    readonly property string chosenShape: "Cookie9Sided"
    readonly property string restShape: "Circle"
    readonly property real chosenTurn: 40

    property string tried: ""

    signal selected(string value)

    spacing: 10

    Flow {
        Layout.fillWidth: true
        spacing: root.swatchGap

        Repeater {
            model: Catalog.COLOR_MODES

            delegate: Item {
                id: swatch
                required property string modelData
                readonly property bool chosen: root.currentValue === swatch.modelData

                width: root.swatchSize
                height: root.swatchSize

                BarWidgetPalette {
                    id: tone
                    colorMode: swatch.modelData
                }

                MaterialShape {
                    anchors.fill: parent
                    shapeString: swatch.chosen ? root.chosenShape : root.restShape
                    color: tone.colBackground
                    rotation: swatch.chosen ? root.chosenTurn : 0
                    scale: swatchArea.containsMouse ? root.hoverGrow : 1
                    Behavior on rotation {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colOutline
                    opacity: swatch.modelData.indexOf("neutral") === 0 && !swatch.chosen ? 0.5 : 0
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: swatch.chosen ? "check" : ""
                    visible: swatch.chosen
                    iconSize: 20
                    fill: 1
                    color: tone.colOnBackground
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: !swatch.chosen
                    text: "1"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Black
                    color: tone.colOnBackground
                }

                MouseArea {
                    id: swatchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(swatch.modelData)
                    onContainsMouseChanged: {
                        if (swatchArea.containsMouse)
                            root.tried = swatch.modelData;
                        else if (root.tried === swatch.modelData)
                            root.tried = "";
                    }
                }
            }
        }
    }

    RowLayout {
        spacing: 6
        MaterialSymbol {
            text: root.tried !== "" ? "visibility" : "palette"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colPrimary
        }
        StyledText {
            text: root.names[root.tried !== "" ? root.tried : root.currentValue] ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
    }
}
