// Annotation toolbar for the inline region editor. `editor` points back at the
// owning RegionSelection so each button can drive its tool / undo / export state.

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Layout mirrors KDE Spectacle's utility bar: history (undo/redo) first, then a
// separator, then the pointer/select tool followed by the drawing tools.
// Copy/Save sit behind a trailing separator for now; they move to the middle
// action bar in a later phase.
Toolbar {
    id: toolbar

    required property var editor

    spacing: 8

    // Undo
    IconToolbarButton {
        text: "undo"
        enabled: editor.undoStack.length > 0
        onClicked: editor.undo()

        StyledToolTip {
            z: 9999
            text: Translation.tr("Undo")
        }

    }

    // Redo
    IconToolbarButton {
        text: "redo"
        enabled: editor.redoStack.length > 0
        onClicked: editor.redo()

        StyledToolTip {
            z: 9999
            text: Translation.tr("Redo")
        }

    }

    ToolbarSeparator {
    }

    // Rectangular region re-crop — drag a fresh selection over the frozen screen.
    IconToolbarButton {
        id: recropBtn

        text: "crop_free"
        toggled: editor.currentTool === "recrop"
        onClicked: editor.currentTool = editor.currentTool === "recrop" ? "none" : "recrop"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Select region")
        }

    }

    // Select / pointer — pick, move and restyle existing annotations.
    IconToolbarButton {
        id: selectBtn

        text: "arrow_selector_tool"
        toggled: editor.currentTool === "none"
        onClicked: editor.currentTool = "none"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Select")
        }

    }

    // Pencil
    IconToolbarButton {
        id: pencilBtn

        text: "edit"
        toggled: editor.currentTool === "pencil"
        onClicked: editor.currentTool = editor.currentTool === "pencil" ? "none" : "pencil"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Pencil")
        }

    }

    // Highlighter
    IconToolbarButton {
        id: highlighterBtn

        text: "ink_highlighter"
        toggled: editor.currentTool === "highlighter"
        onClicked: editor.currentTool = editor.currentTool === "highlighter" ? "none" : "highlighter"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Highlighter")
        }

    }

    // Straight line
    IconToolbarButton {
        id: lineBtn

        text: "horizontal_rule"
        toggled: editor.currentTool === "line"
        onClicked: editor.currentTool = editor.currentTool === "line" ? "none" : "line"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Line")
        }

    }

    // Arrow
    IconToolbarButton {
        id: arrowBtn

        text: "north_east"
        toggled: editor.currentTool === "arrow"
        onClicked: editor.currentTool = editor.currentTool === "arrow" ? "none" : "arrow"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Arrow")
        }

    }

    // Rectangle with shape accordion (extra shapes: star)
    Item {
        id: shapeSelectorContainer

        implicitWidth: shapeRow.implicitWidth
        implicitHeight: Math.max(shapeBtn.implicitHeight, dropdownBtn.implicitHeight)

        Row {
            id: shapeRow

            spacing: 2

            IconToolbarButton {
                id: shapeBtn

                text: "crop_square"
                toggled: editor.currentTool === "rect"
                onClicked: {
                    editor.currentTool = editor.currentTool === "rect" ? "none" : "rect";
                    editor.shapePopupVisible = false;
                }

                StyledToolTip {
                    z: 9999
                    text: Translation.tr("Rectangle")
                }

            }

            Item {
                id: shapeCollapsible

                implicitHeight: shapeBtn.implicitHeight
                clip: true
                implicitWidth: editor.shapePopupVisible ? shapesExpandedRow.implicitWidth : 0
                opacity: editor.shapePopupVisible ? 1 : 0

                Row {
                    id: shapesExpandedRow

                    spacing: 2
                    scale: editor.shapePopupVisible ? 1 : 0.9

                    IconToolbarButton {
                        id: circleBtn

                        text: "circle"
                        toggled: editor.currentTool === "circle"
                        onClicked: editor.currentTool = editor.currentTool === "circle" ? "none" : "circle"

                        StyledToolTip {
                            z: 9999
                            text: Translation.tr("Circle")
                        }

                    }

                    IconToolbarButton {
                        id: starBtn

                        text: "star"
                        toggled: editor.currentTool === "star"
                        onClicked: editor.currentTool = editor.currentTool === "star" ? "none" : "star"

                        StyledToolTip {
                            z: 9999
                            text: Translation.tr("Star")
                        }

                    }


                    Behavior on scale {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }

                    }

                }

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.InOutCubic
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }

                }

            }

            IconToolbarButton {
                id: dropdownBtn

                text: editor.shapePopupVisible ? "chevron_left" : "chevron_right"
                toggled: editor.shapePopupVisible
                onClicked: {
                    editor.shapePopupVisible = !editor.shapePopupVisible;
                    if (editor.shapePopupVisible) {
                        editor.colorPopupVisible = false;
                        editor.lineWidthPopupVisible = false;
                    }
                }

                StyledToolTip {
                    z: 9999
                    text: editor.shapePopupVisible ? Translation.tr("Less shapes") : Translation.tr("More shapes")
                }

            }

        }

    }


    // Fill toggle for closed shapes (rectangle / circle / star)
    IconToolbarButton {
        id: fillBtn

        text: "format_color_fill"
        toggled: editor.fillEnabled
        onClicked: editor.fillEnabled = !editor.fillEnabled

        StyledToolTip {
            z: 9999
            text: Translation.tr("Fill shapes")
        }

    }

    // Blur (soft / gaussian)
    IconToolbarButton {
        id: gaussBlurBtn

        text: "blur_on"
        toggled: editor.currentTool === "gaussblur"
        onClicked: editor.currentTool = editor.currentTool === "gaussblur" ? "none" : "gaussblur"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Blur")
        }

    }

    // Pixelate (blocky)
    IconToolbarButton {
        id: blurBtn

        text: "grid_on"
        toggled: editor.currentTool === "blur"
        onClicked: editor.currentTool = editor.currentTool === "blur" ? "none" : "blur"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Pixelate")
        }

    }

    // Blur strength — independent of line thickness; only relevant while the
    // pixelate tool is active, so it collapses away otherwise.
    Item {
        id: blurStrengthContainer

        visible: editor.currentTool === "blur" || editor.currentTool === "gaussblur"
        implicitWidth: visible ? blurStrengthRow.implicitWidth : 0
        implicitHeight: 32

        Row {
            id: blurStrengthRow

            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                // [divisor, dot size] — bigger divisor = chunkier pixelation
                model: [[12, 5], [24, 9], [48, 14]]

                delegate: RippleButton {
                    required property var modelData

                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    toggled: editor.blurStrength === Number(modelData[0])
                    onClicked: editor.blurStrength = Number(modelData[0])

                    contentItem: Item {
                        anchors.fill: parent

                        Rectangle {
                            anchors.centerIn: parent
                            width: Number(modelData[1])
                            height: Number(modelData[1])
                            radius: 2
                            color: Appearance.colors.colOnLayer1
                        }

                    }

                }

            }

        }

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 250
                easing.type: Easing.InOutCubic
            }

        }

    }

    // Text
    IconToolbarButton {
        id: textBtn

        text: "text_fields"
        toggled: editor.currentTool === "text"
        onClicked: editor.currentTool = editor.currentTool === "text" ? "none" : "text"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Text")
        }

    }

    // Number badge
    IconToolbarButton {
        id: numberBtn

        text: "counter_1"
        toggled: editor.currentTool === "number"
        onClicked: editor.currentTool = editor.currentTool === "number" ? "none" : "number"

        StyledToolTip {
            z: 9999
            text: Translation.tr("Number badge")
        }

    }

    // Line Width Accordion
    Item {
        id: lineWidthSelectorContainer

        implicitWidth: lineWidthRow.implicitWidth
        implicitHeight: 32

        Row {
            id: lineWidthRow

            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            IconToolbarButton {
                id: lineWidthBtn

                toggled: editor.lineWidthPopupVisible
                onClicked: {
                    editor.lineWidthPopupVisible = !editor.lineWidthPopupVisible;
                    if (editor.lineWidthPopupVisible) {
                        editor.colorPopupVisible = false;
                        editor.shapePopupVisible = false;
                    }
                }

                StyledToolTip {
                    z: 9999
                    text: Translation.tr("Line Thickness")
                }

                contentItem: Item {
                    anchors.fill: parent

                    Rectangle {
                        anchors.centerIn: parent
                        width: 20
                        height: Math.max(1, editor.currentLineWidth)
                        color: lineWidthBtn.colText
                        radius: height / 2
                    }

                }

            }

            Item {
                id: lineWidthCollapsible

                implicitHeight: 32
                clip: true
                implicitWidth: editor.lineWidthPopupVisible ? lineWidthExpandedRow.implicitWidth : 0
                opacity: editor.lineWidthPopupVisible ? 1 : 0

                Row {
                    id: lineWidthExpandedRow

                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    scale: editor.lineWidthPopupVisible ? 1 : 0.9

                    Repeater {
                        model: [2, 4, 8]

                        delegate: RippleButton {
                            required property var modelData

                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                editor.currentLineWidth = Number(modelData);
                                editor.lineWidthPopupVisible = false;
                            }

                            contentItem: Item {
                                anchors.fill: parent

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: Number(modelData)
                                    color: Appearance.colors.colOnLayer1
                                    radius: Number(modelData) / 2
                                }

                            }

                        }

                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }

                    }

                }

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.InOutCubic
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }

                }

            }

        }

    }

    // Color Picker Accordion
    Item {
        id: colorSelectorContainer

        implicitWidth: colorRow.implicitWidth
        implicitHeight: 32

        Row {
            id: colorRow

            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            RippleButton {
                id: colorPickerBtn

                implicitWidth: 36
                implicitHeight: 32
                buttonRadius: Appearance.rounding.normal
                toggled: editor.colorPopupVisible
                onClicked: {
                    editor.colorPopupVisible = !editor.colorPopupVisible;
                    if (editor.colorPopupVisible) {
                        editor.lineWidthPopupVisible = false;
                        editor.shapePopupVisible = false;
                    }
                }

                StyledToolTip {
                    z: 9999
                    text: Translation.tr("Color")
                }

                contentItem: Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: width / 2
                    color: editor.currentColor
                    border.width: 1
                    border.color: Appearance.colors.colOutline
                }

            }

            Item {
                id: colorCollapsible

                implicitHeight: 32
                clip: true
                implicitWidth: editor.colorPopupVisible ? colorExpandedRow.implicitWidth : 0
                opacity: editor.colorPopupVisible ? 1 : 0

                Row {
                    id: colorExpandedRow

                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    scale: editor.colorPopupVisible ? 1 : 0.9

                    Repeater {
                        model: editor.presetColors

                        delegate: RippleButton {
                            required property color modelData

                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                editor.currentColor = modelData;
                                editor.colorPopupVisible = false;
                            }

                            contentItem: Rectangle {
                                anchors.fill: parent
                                radius: parent.buttonRadius
                                color: modelData
                                border.width: 1
                                border.color: Appearance.colors.colOutline
                            }

                        }

                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }

                    }

                }

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.InOutCubic
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }

                }

            }

        }

    }

    // Reusable vertical divider (Spectacle-style toolbar separator).
    component ToolbarSeparator: Rectangle {
        implicitWidth: 1
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter
        color: Appearance.colors.colOutlineVariant
    }

}
