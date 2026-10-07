pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The tray's small menus, one at a time (`kind`):
 *
 *   share  what to do with the drawing — copy it, copy the screen with it, save it as a
 *          transparent PNG or as SVG, file it in Notes, screenshot
 *   shape  line, arrow, rectangle, ellipse
 *   ink    the palette, when the tray is too narrow to show it
 *
 * The share menu is a column of rows that each say what they do and the key that does
 * it; the other two are a single row of the same round tools the tray uses.
 */
Rectangle {
    id: root

    property string kind: ""
    property var palette: []
    property string currentColor: ""
    property string currentTool: "pen"
    property bool hasInk: false

    signal action(string name)
    signal toolPicked(string tool)
    signal colorPicked(string color)

    implicitWidth: (root.kind === "share" ? shareColumn.implicitWidth : rowLayout.implicitWidth) + 16
    implicitHeight: (root.kind === "share" ? shareColumn.implicitHeight : rowLayout.implicitHeight) + 16
    radius: root.kind === "share" ? Appearance.rounding.large : Appearance.rounding.full
    color: Appearance.m3colors.m3surfaceContainer

    // ── Share ───────────────────────────────────────────────────────────────
    ColumnLayout {
        id: shareColumn
        visible: root.kind === "share"
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.kind === "share" ? [
                { name: "copy", symbol: "content_copy", text: Translation.tr("Copy the drawing"), detail: Translation.tr("Transparent, cropped to the ink"), keys: ["Ctrl", "C"], needsInk: true },
                { name: "copyScreen", symbol: "screenshot_monitor", text: Translation.tr("Copy the screen with it"), detail: Translation.tr("Everything you see, toolbar left out"), keys: ["Ctrl", "Shift", "C"], needsInk: false },
                { name: "exportPng", symbol: "image", text: Translation.tr("Save as PNG"), detail: Translation.tr("Transparent, in Pictures/Drawings"), keys: ["Ctrl", "Shift", "S"], needsInk: true },
                { name: "exportSvg", symbol: "shapes", text: Translation.tr("Save as SVG"), detail: Translation.tr("Vector, sharp at any size"), keys: ["Ctrl", "Alt", "S"], needsInk: true },
                { name: "save", symbol: "note_add", text: Translation.tr("Save to Notes"), detail: Translation.tr("As a sketch note, and clear the screen"), keys: ["Ctrl", "S"], needsInk: true },
                { name: "screenshot", symbol: "photo_camera", text: Translation.tr("Screenshot"), detail: Translation.tr("Saved to Pictures/Screenshots too"), keys: [], needsInk: false }
            ] : []

            delegate: RippleButton {
                id: row
                required property var modelData
                required property int index
                readonly property bool first: row.index === 0
                readonly property bool last: row.index === 5

                Layout.preferredWidth: 340
                implicitHeight: 56
                focusPolicy: Qt.NoFocus
                enabled: !row.modelData.needsInk || root.hasInk
                // Joined rows: round where the group ends, nearly square where rows meet.
                topLeftRadius: row.first ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                topRightRadius: row.first ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                bottomLeftRadius: row.last ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                bottomRightRadius: row.last ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.action(row.modelData.name)

                contentItem: RowLayout {
                    spacing: 12
                    opacity: row.enabled ? 1 : 0.4

                    MaterialSymbol {
                        Layout.leftMargin: 6
                        text: row.modelData.symbol
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: row.modelData.text
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.detail
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    KeyHint {
                        Layout.rightMargin: 4
                        visible: row.modelData.keys.length > 0
                        keys: row.modelData.keys
                        pixelSize: 10
                        surface: Appearance.m3colors.m3surfaceContainerHigh
                        onSurface: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }

    // ── Shapes and inks ─────────────────────────────────────────────────────
    RowLayout {
        id: rowLayout
        visible: root.kind === "shape" || root.kind === "ink"
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.kind === "shape" ? [
                { tool: "line", symbol: "horizontal_rule", text: Translation.tr("Line"), key: "Ctrl+I" },
                { tool: "arrow", symbol: "arrow_outward", text: Translation.tr("Arrow"), key: "Ctrl+A" },
                { tool: "rect", symbol: "rectangle", text: Translation.tr("Rectangle"), key: "Ctrl+R" },
                { tool: "ellipse", symbol: "circle", text: Translation.tr("Ellipse"), key: "Ctrl+O" }
            ] : []

            delegate: DrawToolButton {
                required property var modelData
                useDynamicRadius: true
                groupHorizontal: true
                symbol: modelData.symbol
                active: root.currentTool === modelData.tool
                tooltipText: modelData.text + " · " + Translation.tr("Shift snaps")
                shortcut: modelData.key
                onTriggered: root.toolPicked(modelData.tool)
            }
        }

        Repeater {
            model: root.kind === "ink" ? root.palette : []

            delegate: Item {
                id: swatch
                required property string modelData
                required property int index
                readonly property bool current: root.currentColor === swatch.modelData
                implicitWidth: 40
                implicitHeight: 40

                Rectangle {
                    anchors.centerIn: parent
                    width: swatch.current ? 34 : (inkHover.hovered ? 30 : 27)
                    height: width
                    radius: swatch.current ? Appearance.rounding.small : width / 2
                    color: swatch.modelData

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: swatch.current
                        text: "check"
                        iconSize: Appearance.font.pixelSize.normal
                        color: ColorUtils.getContrastingTextColor(swatch.modelData)
                    }
                }

                HoverHandler {
                    id: inkHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    acceptedDevices: PointerDevice.AllDevices
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.colorPicked(swatch.modelData)
                }

                StyledToolTip {
                    requireOverlay: false
                    extraVisibleCondition: inkHover.hovered
                    text: Translation.tr("Ink %1").arg(swatch.modelData.toUpperCase()) + (swatch.index < 9 ? `  ·  Ctrl+${swatch.index + 1}` : "")
                }
            }
        }
    }
}
