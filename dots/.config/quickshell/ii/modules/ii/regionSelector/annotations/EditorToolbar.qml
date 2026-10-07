// Annotation toolbar for the inline region editor. `editor` points back at the
// owning RegionSelection so each button can drive its tool / undo / export state.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Material 3 Expressive floating toolbar. Groups are separated by surfaces and
// gaps, never by rules: history floats bare on the toolbar, the drawing tools
// sit on one tonal track, and the style controls (fill, thickness, colour) on a
// second. The active tool is the toolbar's one primary element: it widens and
// morphs from a circle into a rounded square.
Toolbar {
    id: toolbar

    required property var editor

    readonly property int buttonSize: 40
    readonly property int optionSize: 30
    readonly property bool sharp: Appearance.rounding.scale === 0

    function pill(h) {
        return toolbar.sharp ? 0 : h / 2;
    }

    function activeRadius(h) {
        return toolbar.sharp ? 0 : Math.min(h * 0.3, Appearance.rounding.normal);
    }

    function toggleTool(name) {
        editor.currentTool = editor.currentTool === name ? "none" : name;
    }

    padding: 6
    spacing: 6
    implicitHeight: toolbar.buttonSize + 8 + padding * 2

    // ── History ─────────────────────────────────────────────────────────
    Row {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 2
        spacing: 0

        ToolButton {
            symbol: "undo"
            tip: Translation.tr("Undo") + "  ·  Ctrl+Z"
            enabled: editor.undoStack.length > 0
            onClicked: editor.undo()
        }

        ToolButton {
            symbol: "redo"
            tip: Translation.tr("Redo") + "  ·  Ctrl+Shift+Z"
            enabled: editor.redoStack.length > 0
            onClicked: editor.redo()
        }

    }

    // ── Tools ───────────────────────────────────────────────────────────
    Track {
        // Rectangular region re-crop — drag a fresh selection over the frozen screen.
        ToolButton {
            symbol: "crop_free"
            tip: Translation.tr("Select region")
            toggled: editor.currentTool === "recrop"
            onClicked: toolbar.toggleTool("recrop")
        }

        // Select / pointer — pick, move and restyle existing annotations.
        ToolButton {
            symbol: "arrow_selector_tool"
            tip: Translation.tr("Select")
            toggled: editor.currentTool === "none"
            onClicked: editor.currentTool = "none"
        }

        ToolButton {
            symbol: "edit"
            tip: Translation.tr("Pencil — pen pressure and mouse smoothing, as in live draw") + "  ·  Ctrl+P"
            toggled: editor.currentTool === "pencil"
            onClicked: toolbar.toggleTool("pencil")
        }

        ToolButton {
            symbol: "ink_highlighter"
            tip: Translation.tr("Highlighter — under the other marks") + "  ·  Ctrl+H"
            toggled: editor.currentTool === "highlighter"
            onClicked: toolbar.toggleTool("highlighter")
        }

        ToolButton {
            symbol: "horizontal_rule"
            tip: Translation.tr("Line · Shift snaps to 15°") + "  ·  Ctrl+I"
            toggled: editor.currentTool === "line"
            onClicked: toolbar.toggleTool("line")
        }

        ToolButton {
            symbol: "north_east"
            tip: Translation.tr("Arrow · Shift snaps to 15°") + "  ·  Ctrl+A"
            toggled: editor.currentTool === "arrow"
            onClicked: toolbar.toggleTool("arrow")
        }

        // Screen ruler — drag from A to B to measure the distance in px.
        ToolButton {
            symbol: "straighten"
            tip: Translation.tr("Screen ruler")
            toggled: editor.currentTool === "ruler"
            onClicked: toolbar.toggleTool("ruler")
        }

        // Rectangle, with the extra shapes folded behind a chevron.
        ToolButton {
            symbol: "crop_square"
            tip: Translation.tr("Rectangle · Shift makes a square") + "  ·  Ctrl+R"
            toggled: editor.currentTool === "rect"
            onClicked: {
                toolbar.toggleTool("rect");
                editor.shapePopupVisible = false;
            }
        }

        Drawer {
            open: editor.shapePopupVisible

            // No ellipse glyph in the installed symbol font, so the icon is drawn: an
            // outline in the same weight as the symbols beside it.
            ToolButton {
                id: ellipseButton
                tip: Translation.tr("Ellipse · Shift makes a circle") + "  ·  Ctrl+O"
                toggled: editor.currentTool === "ellipse"
                onClicked: toolbar.toggleTool("ellipse")

                contentItem: Item {
                    Shape {
                        anchors.centerIn: parent
                        width: 22
                        height: 14
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: ellipseButton.colContent
                            strokeWidth: 2
                            fillColor: ellipseButton.toggled ? ellipseButton.colContent : "transparent"

                            PathAngleArc {
                                centerX: 11
                                centerY: 7
                                radiusX: 10
                                radiusY: 6
                                startAngle: 0
                                sweepAngle: 360
                            }
                        }
                    }
                }
            }

            ToolButton {
                symbol: "circle"
                tip: Translation.tr("Circle")
                toggled: editor.currentTool === "circle"
                onClicked: toolbar.toggleTool("circle")
            }

            ToolButton {
                symbol: "star"
                tip: Translation.tr("Star")
                toggled: editor.currentTool === "star"
                onClicked: toolbar.toggleTool("star")
            }

        }

        DrawerHandle {
            open: editor.shapePopupVisible
            tip: editor.shapePopupVisible ? Translation.tr("Less shapes") : Translation.tr("More shapes")
            onClicked: {
                editor.shapePopupVisible = !editor.shapePopupVisible;
                if (editor.shapePopupVisible) {
                    editor.colorPopupVisible = false;
                    editor.lineWidthPopupVisible = false;
                }
            }
        }

        // Live draw's eraser: whatever it rubs over goes, whole.
        ToolButton {
            symbol: "ink_eraser"
            tip: Translation.tr("Eraser") + "  ·  Ctrl+E"
            toggled: editor.currentTool === "eraser"
            onClicked: toolbar.toggleTool("eraser")
        }

        ToolButton {
            symbol: "blur_on"
            tip: Translation.tr("Blur")
            toggled: editor.currentTool === "gaussblur"
            onClicked: toolbar.toggleTool("gaussblur")
        }

        ToolButton {
            symbol: "grid_on"
            tip: Translation.tr("Pixelate")
            toggled: editor.currentTool === "blur"
            onClicked: toolbar.toggleTool("blur")
        }

        // Blur strength — independent of line thickness; only relevant while a
        // blur tool is active, so it folds away otherwise.
        Drawer {
            open: editor.currentTool === "blur" || editor.currentTool === "gaussblur"

            Repeater {
                // [divisor, block size] — bigger divisor = chunkier pixelation
                model: [[12, 5], [24, 9], [48, 14]]

                delegate: OptionButton {
                    id: strengthOption

                    required property var modelData

                    selected: editor.blurStrength === Number(modelData[0])
                    onClicked: editor.blurStrength = Number(modelData[0])

                    contentItem: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: Number(strengthOption.modelData[1])
                            height: width
                            radius: toolbar.sharp ? 0 : Math.min(3, width / 3)
                            color: strengthOption.colContent
                        }

                    }

                }

            }

        }

        ToolButton {
            symbol: "text_fields"
            tip: Translation.tr("Text")
            toggled: editor.currentTool === "text"
            onClicked: toolbar.toggleTool("text")
        }

        ToolButton {
            symbol: "counter_1"
            tip: Translation.tr("Number badge")
            toggled: editor.currentTool === "number"
            onClicked: toolbar.toggleTool("number")
        }

    }

    // ── Style ───────────────────────────────────────────────────────────
    Track {
        // Fill toggle for closed shapes (rectangle / circle / star). A switch,
        // not a tool, so it lights up in the secondary voice.
        ToolButton {
            symbol: "format_color_fill"
            tip: Translation.tr("Fill shapes")
            toggled: editor.fillEnabled
            secondary: true
            onClicked: editor.fillEnabled = !editor.fillEnabled
        }

        // Thickness: the button draws the current stroke.
        ToolButton {
            id: lineWidthBtn

            tip: Translation.tr("Line Thickness") + "  ·  Ctrl+[ ]"
            toggled: editor.lineWidthPopupVisible
            secondary: true
            onClicked: {
                editor.lineWidthPopupVisible = !editor.lineWidthPopupVisible;
                if (editor.lineWidthPopupVisible) {
                    editor.colorPopupVisible = false;
                    editor.shapePopupVisible = false;
                }
            }

            contentItem: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: Math.max(2, Math.min(10, editor.currentLineWidth))
                    radius: toolbar.sharp ? 0 : height / 2
                    color: lineWidthBtn.colContent
                    rotation: -30
                    antialiasing: true

                    Behavior on height {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }

                }

            }

        }

        Drawer {
            open: editor.lineWidthPopupVisible

            Repeater {
                model: editor.lineWidthSteps

                delegate: OptionButton {
                    id: widthOption

                    required property var modelData

                    selected: editor.currentLineWidth === Number(modelData)
                    onClicked: {
                        editor.currentLineWidth = Number(modelData);
                        editor.lineWidthPopupVisible = false;
                    }

                    contentItem: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 16
                            height: Number(widthOption.modelData)
                            radius: toolbar.sharp ? 0 : height / 2
                            color: widthOption.colContent
                        }

                    }

                }

            }

        }

        // Colour: a scalloped swatch of the current colour. It morphs into a
        // softer burst while the palette is open.
        RippleButton {
            id: colorPickerBtn

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: toolbar.buttonSize
            implicitHeight: toolbar.buttonSize
            buttonRadius: toolbar.pill(height)
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            toggled: false
            onClicked: {
                editor.colorPopupVisible = !editor.colorPopupVisible;
                if (editor.colorPopupVisible) {
                    editor.lineWidthPopupVisible = false;
                    editor.shapePopupVisible = false;
                }
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }

            StyledToolTip {
                z: 9999
                text: Translation.tr("Color") + "  ·  Ctrl+1–9"
            }

            // MaterialShape's borderWidth is in normalised units, so the
            // outline that keeps black/white swatches visible is a second,
            // slightly larger shape underneath.
            contentItem: Item {
                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 29
                    shapeString: editor.colorPopupVisible ? "SoftBurst" : "Cookie9Sided"
                    color: Appearance.colors.colOutline
                }

                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 26
                    shapeString: editor.colorPopupVisible ? "SoftBurst" : "Cookie9Sided"
                    color: editor.currentColor
                }

            }

        }

        Drawer {
            open: editor.colorPopupVisible
            spacing: 4

            Repeater {
                model: editor.presetColors

                delegate: RippleButton {
                    id: swatch

                    required property color modelData
                    readonly property bool selected: Qt.colorEqual(editor.currentColor, modelData)

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: selected ? (toolbar.sharp ? 0 : 8) : toolbar.pill(height)
                    colBackground: modelData
                    colBackgroundHover: modelData
                    colRipple: Appearance.colors.colOnSurface
                    rippleEnabled: false
                    onClicked: {
                        editor.currentColor = modelData;
                        editor.colorPopupVisible = false;
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }

                    // Keeps black/white visible on any surface tone.
                    contentItem: Rectangle {
                        anchors.fill: parent
                        radius: swatch.buttonEffectiveRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                    }

                }

            }

        }

    }

    // ── Components ──────────────────────────────────────────────────────

    // A recessed track that holds one group of controls: darker than the
    // toolbar, so tonal selections and hovers read on top of it in any theme.
    component Track: Rectangle {
        default property alias trackData: trackRow.data

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: trackRow.implicitWidth + 8
        implicitHeight: 40 + 8
        radius: (Appearance.rounding.scale === 0 ? 0 : height / 2)
        color: Appearance.colors.colSurfaceContainerLow

        RowLayout {
            id: trackRow

            anchors.centerIn: parent
            spacing: 2
        }

    }

    // Icon button. Idle: transparent circle. Active: filled, a little wider and
    // a rounded square — the shape is the state.
    component ToolButton: RippleButton {
        id: tb

        property string symbol: ""
        property string tip: ""
        property bool secondary: false
        readonly property color colContent: toggled ? (secondary ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary) : Appearance.colors.colOnSurfaceVariant

        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 40
        implicitWidth: toggled && !secondary ? 40 + 12 : 40
        buttonRadius: toggled ? (Appearance.rounding.scale === 0 ? 0 : Math.min(height * 0.3, Appearance.rounding.normal)) : (Appearance.rounding.scale === 0 ? 0 : height / 2)
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: secondary ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
        colBackgroundToggledHover: secondary ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover
        colRippleToggled: secondary ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive

        HoverHandler {
            enabled: tb.enabled
            cursorShape: Qt.PointingHandCursor
        }

        StyledToolTip {
            z: 9999
            text: tb.tip
        }

        Behavior on implicitWidth {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 22
                text: tb.symbol
                fill: tb.toggled ? 1 : 0
                color: tb.colContent
                animateChange: true
            }

        }

    }

    // Small choice inside a drawer (thickness, blur strength).
    component OptionButton: RippleButton {
        id: ob

        property bool selected: false
        readonly property color colContent: selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 30
        implicitHeight: 30
        toggled: selected
        buttonRadius: selected ? (Appearance.rounding.scale === 0 ? 0 : 9) : (Appearance.rounding.scale === 0 ? 0 : height / 2)
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

    }

    // Clipped row that unfolds sideways inside a track.
    component Drawer: Item {
        id: drawer

        property bool open: false
        property alias spacing: drawerRow.spacing
        default property alias drawerData: drawerRow.data

        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 40
        implicitWidth: open ? drawerRow.implicitWidth + 8 : 0
        visible: implicitWidth > 0
        clip: true
        opacity: open ? 1 : 0

        RowLayout {
            id: drawerRow

            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
        }

        Behavior on implicitWidth {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

    }

    // Narrow chevron that opens a drawer; it turns to point back when open.
    component DrawerHandle: RippleButton {
        id: dh

        property bool open: false
        property string tip: ""

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 22
        implicitHeight: 40
        buttonRadius: (Appearance.rounding.scale === 0 ? 0 : width / 2)
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colRipple: Appearance.colors.colSurfaceContainerHighestActive

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        StyledToolTip {
            z: 9999
            text: dh.tip
        }

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 20
                text: "chevron_right"
                color: Appearance.colors.colOnSurfaceVariant
                rotation: dh.open ? 180 : 0

                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

            }

        }

    }

}
