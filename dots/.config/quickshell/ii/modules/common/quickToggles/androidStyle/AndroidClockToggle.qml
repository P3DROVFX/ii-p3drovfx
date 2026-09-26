pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * A typographic numbers-only clock widget quick toggle for the Dynamic Island and Quick Panel.
 *
 * Implements the Google Sans Flex die-cut stencil cutout clock design in both:
 * - Horizontal format (2:1, 4:2, 6:3) based on HoriClock
 * - Vertical format (1:2, 2:4, 3:6) based on FlexClock
 *
 * Does not toggle anything on click; purely an information display tile that can be
 * moved, resized proportionally, and arranged in the grid during edit mode.
 */
Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData?.type ?? "clockWidget", root.buttonData?.sizeW, root.buttonData?.sizeH, root.gridColumns)

    property bool editMode: false
    property bool isUnused: false
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null
    property int entranceTrigger: -1

    // Every digit is drawn by dozens of Text copies (faces plus stroke and fringe
    // samples), so a minute change relays out all of them. Hold the time while the
    // tile is off screen - a retained, closed dashboard - and catch up on show.
    property string hoursStr: "12"
    property string minutesStr: "00"
    Binding on hoursStr {
        when: root.visible
        value: String(DateTime.hours ?? "12").padStart(2, "0")
        restoreMode: Binding.RestoreNone
    }
    Binding on minutesStr {
        when: root.visible
        value: String(DateTime.minutes ?? "00").padStart(2, "0")
        restoreMode: Binding.RestoreNone
    }

    readonly property string d0: hoursStr.charAt(0)
    readonly property string d1: hoursStr.charAt(1)
    readonly property string d2: minutesStr.charAt(0)
    readonly property string d3: minutesStr.charAt(1)

    property string tooltipText: hoursStr + ":" + minutesStr
    readonly property bool hovered: false

    readonly property bool hasExplicitGeometry: root.buttonData
        && root.buttonData.layoutX !== undefined
        && root.buttonData.layoutY !== undefined

    Binding on x {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginX : Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginY : Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging || editableItem.resizing ? 100 : 0

    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    implicitWidth: root.baseCellWidth * root.effectiveSizeW + root.cellSpacing * (root.effectiveSizeW - 1)
    implicitHeight: root.baseCellHeight * root.effectiveSizeH + root.cellSpacing * (root.effectiveSizeH - 1)

    readonly property bool isHorizontal: visualButton.width > visualButton.height

    // M3 theme color tokens for quick toggle surface
    readonly property color tintSoft: Appearance.colors.colOnLayer2
    readonly property color tintBold: Appearance.colors.colPrimary

    Rectangle {
        id: visualButton
        width: editableItem.resizing ? editableItem.previewWidth : root.width
        height: editableItem.resizing ? editableItem.previewHeight : root.height
        radius: Config.options.appearance.sharpMode ? 0 : Math.min(width / 2, height / 2, Appearance.rounding.large)
        color: Appearance.colors.colLayer2
        scale: root.isDragging ? 1.05 : 1.0
        opacity: root.isDragging ? 0.95 : 1.0
        clip: true

        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: root.isDragging ? root.dragOffsetY : 0
        }

        Behavior on width {
            enabled: !editableItem.resizing
            animation: Appearance.animation.elementResize.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            enabled: !editableItem.resizing
            animation: Appearance.animation.elementResize.numberAnimation.createObject(visualButton)
        }
        Behavior on scale {
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }

        // =========================================================================
        // HORIZONTAL CLOCK STAGE (HoriClock design: 2:1, 4:2, 6:3)
        // =========================================================================
        Loader {
            active: root.isHorizontal
            anchors.centerIn: parent
            sourceComponent: Item {
                id: horiStage
                anchors.centerIn: parent

                readonly property real horizontalPadding: Math.max(18, Math.round(visualButton.radius * 0.80))
                readonly property real verticalPadding: Math.max(6, Math.round(visualButton.radius * 0.35))

                readonly property real maxAvailableW: Math.max(10, visualButton.width - horizontalPadding * 2)
                readonly property real maxAvailableH: Math.max(10, visualButton.height - verticalPadding * 2)
                // Native bounding box ratio of HoriClock digits + colon is 278.4 / 144 ≈ 1.9333
                readonly property real designRatio: 1.9333

                height: Math.min(maxAvailableH, maxAvailableW / designRatio)
                width: height * designRatio

                readonly property real tileW: width * (0.22 / 0.87)
                readonly property real tileH: height
                readonly property real glyphSize: height * 0.84
                readonly property real posY: 0

                readonly property real pos0X: 0
                readonly property real pos1X: width * (0.17 / 0.87)
                readonly property real colonX: width * (0.43 / 0.87)
                readonly property real pos2X: width * (0.48 / 0.87)
                readonly property real pos3X: width * (0.65 / 0.87)

                readonly property real colonDotSize: Math.max(3, height * 0.09)
                readonly property real colonGap: Math.max(2, height * 0.10)
                readonly property real fringeSize: Math.max(1.5, height * 0.028)

                function ringSamples(count, radius) {
                    let pts = [{ dx: 0, dy: 0 }];
                    for (let i = 0; i < count; i++) {
                        const a = (i / count) * Math.PI * 2;
                        pts.push({ dx: Math.cos(a) * radius, dy: Math.sin(a) * radius });
                    }
                    return pts;
                }
                readonly property var fringeSamples: ringSamples(16, fringeSize)

                component HoriGlyphTile: Text {
                    width: horiStage.tileW
                    height: horiStage.tileH
                    font {
                        family: "Google Sans Flex"
                        weight: 1000
                        bold: true
                        pixelSize: horiStage.glyphSize
                        variableAxes: ({ "wght": 1000 })
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // Layer 0: d0 cut by d1, d2, d3
                Item {
                    id: hLayer0Face
                    anchors.fill: parent
                    visible: false
                    HoriGlyphTile {
                        x: horiStage.pos0X; y: horiStage.posY
                        text: root.d0; color: root.tintSoft
                    }
                }
                Item {
                    id: hLayer0Punch
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: horiStage.fringeSamples
                        Item {
                            required property var modelData
                            anchors.fill: parent
                            HoriGlyphTile { x: horiStage.pos1X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d1; color: "black" }
                            HoriGlyphTile { x: horiStage.pos2X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d2; color: "black" }
                            HoriGlyphTile { x: horiStage.pos3X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d3; color: "black" }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: hLayer0Face
                    maskSource: hLayer0Punch
                    invert: true
                    z: 0
                }

                // Layer 1: d1 cut by d2, d3
                Item {
                    id: hLayer1Face
                    anchors.fill: parent
                    visible: false
                    HoriGlyphTile {
                        x: horiStage.pos1X; y: horiStage.posY
                        text: root.d1; color: root.tintBold
                    }
                }
                Item {
                    id: hLayer1Punch
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: horiStage.fringeSamples
                        Item {
                            required property var modelData
                            anchors.fill: parent
                            HoriGlyphTile { x: horiStage.pos2X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d2; color: "black" }
                            HoriGlyphTile { x: horiStage.pos3X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d3; color: "black" }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: hLayer1Face
                    maskSource: hLayer1Punch
                    invert: true
                    z: 1
                }

                // Layer 2: d2 cut by d3
                Item {
                    id: hLayer2Face
                    anchors.fill: parent
                    visible: false
                    HoriGlyphTile {
                        x: horiStage.pos2X; y: horiStage.posY
                        text: root.d2; color: root.tintBold
                    }
                }
                Item {
                    id: hLayer2Punch
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: horiStage.fringeSamples
                        Item {
                            required property var modelData
                            anchors.fill: parent
                            HoriGlyphTile { x: horiStage.pos3X + modelData.dx; y: horiStage.posY + modelData.dy; text: root.d3; color: "black" }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: hLayer2Face
                    maskSource: hLayer2Punch
                    invert: true
                    z: 2
                }

                // Layer 3: d3 intact
                HoriGlyphTile {
                    x: horiStage.pos3X; y: horiStage.posY
                    text: root.d3; color: root.tintSoft
                    z: 3
                }

                // Colon separator between H1 (d1) and M0 (d2)
                Column {
                    x: horiStage.colonX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: horiStage.colonGap
                    z: 4

                    Rectangle {
                        width: horiStage.colonDotSize
                        height: horiStage.colonDotSize
                        radius: width / 2
                        color: root.tintBold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Rectangle {
                        width: horiStage.colonDotSize
                        height: horiStage.colonDotSize
                        radius: width / 2
                        color: root.tintBold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // =========================================================================
        // VERTICAL CLOCK STAGE (FlexClock design: 1:2, 2:4, 3:6)
        // =========================================================================
        Loader {
            active: !root.isHorizontal
            anchors.centerIn: parent
            sourceComponent: Item {
                id: flexStage
                anchors.centerIn: parent

                readonly property real horizontalPadding: Math.max(6, Math.round(visualButton.radius * 0.25))
                readonly property real verticalPadding: Math.max(6, Math.round(visualButton.radius * 0.25))

                readonly property real maxAvailableW: Math.max(10, visualButton.width - horizontalPadding * 2)
                readonly property real maxAvailableH: Math.max(10, visualButton.height - verticalPadding * 2)
                // Native bounding box ratio of FlexClock 2x2 grid is 0.96 / 1.12 ≈ 0.8571
                readonly property real designRatio: 0.8571

                width: Math.min(maxAvailableW, maxAvailableH * designRatio)
                height: width / designRatio

                readonly property real base: width / 0.96
                readonly property real cellW: base * 0.66
                readonly property real cellH: base * 0.66
                readonly property real glyphPixelSize: base * 0.66

                readonly property real col0X: 0
                readonly property real col1X: base * 0.30
                readonly property real row0Y: 0
                readonly property real row1Y: base * 0.46

                readonly property real strokeWidth: Math.max(1.5, base * 0.020)

                readonly property var strokeOffsets: [
                    { dx: 0, dy: 0 },
                    { dx: -strokeWidth, dy: 0 },
                    { dx: strokeWidth, dy: 0 },
                    { dx: 0, dy: -strokeWidth },
                    { dx: 0, dy: strokeWidth },
                    { dx: -strokeWidth * 0.92, dy: -strokeWidth * 0.38 },
                    { dx: strokeWidth * 0.92, dy: -strokeWidth * 0.38 },
                    { dx: -strokeWidth * 0.92, dy: strokeWidth * 0.38 },
                    { dx: strokeWidth * 0.92, dy: strokeWidth * 0.38 },
                    { dx: -strokeWidth * 0.38, dy: -strokeWidth * 0.92 },
                    { dx: strokeWidth * 0.38, dy: -strokeWidth * 0.92 },
                    { dx: -strokeWidth * 0.38, dy: strokeWidth * 0.92 },
                    { dx: strokeWidth * 0.38, dy: strokeWidth * 0.92 },
                    { dx: -strokeWidth * 0.707, dy: -strokeWidth * 0.707 },
                    { dx: strokeWidth * 0.707, dy: -strokeWidth * 0.707 },
                    { dx: -strokeWidth * 0.707, dy: strokeWidth * 0.707 },
                    { dx: strokeWidth * 0.707, dy: strokeWidth * 0.707 }
                ]

                component FlexDigit: Text {
                    width: flexStage.cellW
                    height: flexStage.cellH
                    font {
                        family: "Google Sans Flex"
                        weight: 1000
                        bold: true
                        pixelSize: flexStage.glyphPixelSize
                        variableAxes: ({ "wght": 1000 })
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // Layer 0: d0 (top-left) cut by d1, d2, d3
                Item {
                    id: fLayer0Source
                    anchors.fill: parent
                    visible: false
                    FlexDigit {
                        x: flexStage.col0X
                        y: flexStage.row0Y
                        text: root.d0
                        color: root.tintSoft
                    }
                }
                Item {
                    id: fLayer0Mask
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: flexStage.strokeOffsets
                        Item {
                            id: fStrokeDel0
                            required property var modelData
                            anchors.fill: parent
                            FlexDigit {
                                x: flexStage.col1X + fStrokeDel0.modelData.dx
                                y: flexStage.row0Y + fStrokeDel0.modelData.dy
                                text: root.d1
                                color: "black"
                            }
                            FlexDigit {
                                x: flexStage.col0X + fStrokeDel0.modelData.dx
                                y: flexStage.row1Y + fStrokeDel0.modelData.dy
                                text: root.d2
                                color: "black"
                            }
                            FlexDigit {
                                x: flexStage.col1X + fStrokeDel0.modelData.dx
                                y: flexStage.row1Y + fStrokeDel0.modelData.dy
                                text: root.d3
                                color: "black"
                            }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: fLayer0Source
                    maskSource: fLayer0Mask
                    invert: true
                    z: 0
                }

                // Layer 1: d1 (top-right) cut by d2, d3
                Item {
                    id: fLayer1Source
                    anchors.fill: parent
                    visible: false
                    FlexDigit {
                        x: flexStage.col1X
                        y: flexStage.row0Y
                        text: root.d1
                        color: root.tintBold
                    }
                }
                Item {
                    id: fLayer1Mask
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: flexStage.strokeOffsets
                        Item {
                            id: fStrokeDel1
                            required property var modelData
                            anchors.fill: parent
                            FlexDigit {
                                x: flexStage.col0X + fStrokeDel1.modelData.dx
                                y: flexStage.row1Y + fStrokeDel1.modelData.dy
                                text: root.d2
                                color: "black"
                            }
                            FlexDigit {
                                x: flexStage.col1X + fStrokeDel1.modelData.dx
                                y: flexStage.row1Y + fStrokeDel1.modelData.dy
                                text: root.d3
                                color: "black"
                            }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: fLayer1Source
                    maskSource: fLayer1Mask
                    invert: true
                    z: 1
                }

                // Layer 2: d2 (bottom-left) cut by d3
                Item {
                    id: fLayer2Source
                    anchors.fill: parent
                    visible: false
                    FlexDigit {
                        x: flexStage.col0X
                        y: flexStage.row1Y
                        text: root.d2
                        color: root.tintBold
                    }
                }
                Item {
                    id: fLayer2Mask
                    anchors.fill: parent
                    visible: false
                    Repeater {
                        model: flexStage.strokeOffsets
                        Item {
                            id: fStrokeDel2
                            required property var modelData
                            anchors.fill: parent
                            FlexDigit {
                                x: flexStage.col1X + fStrokeDel2.modelData.dx
                                y: flexStage.row1Y + fStrokeDel2.modelData.dy
                                text: root.d3
                                color: "black"
                            }
                        }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    source: fLayer2Source
                    maskSource: fLayer2Mask
                    invert: true
                    z: 2
                }

                // Layer 3: d3 (bottom-right) intact
                FlexDigit {
                    x: flexStage.col1X
                    y: flexStage.row1Y
                    text: root.d3
                    color: root.tintSoft
                    z: 3
                }
            }
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
