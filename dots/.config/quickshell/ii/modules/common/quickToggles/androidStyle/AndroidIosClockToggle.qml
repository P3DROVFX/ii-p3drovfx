pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * An iOS Clock quick toggle widget for the Dynamic Island and Quick Panel.
 *
 * Implements the Apple SF Pro Display iOS clock design in both:
 * - Vertical format (1x1, 1x2, 1x3, 1x4, 2x2, 2x3, 2x4, 4x4): Date on top, Hours on top, Minutes on bottom with tight spacing.
 * - Horizontal format (2x1, 3x1, 4x1, 3x2, 4x2): Date on top, single-line "HH:MM" below.
 *
 * Does not toggle anything on click; purely an information display tile that can be
 * moved, resized, and arranged in the grid during edit mode.
 */
Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData?.type ?? "iosClockWidget", root.buttonData?.sizeW, root.buttonData?.sizeH, root.gridColumns)

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

    readonly property string hoursStr: String(DateTime.hours ?? "12").padStart(2, "0")
    readonly property string minutesStr: String(DateTime.minutes ?? "00").padStart(2, "0")

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

    function scaled(value) {
        return QuickToggleMetrics.scaled(root.baseCellHeight, value);
    }

    implicitWidth: root.baseCellWidth * root.effectiveSizeW + root.cellSpacing * (root.effectiveSizeW - 1)
    implicitHeight: root.baseCellHeight * root.effectiveSizeH + root.cellSpacing * (root.effectiveSizeH - 1)

    // ── Config ────────────────────────────────────────────────────────────────
    readonly property var opts: Config.options?.background?.widgets?.clock_ios
    readonly property string clockVariant: opts?.clockFontVariant ?? "bold"
    readonly property string dateVariant: opts?.dateFontVariant ?? "medium"

    // ── SF Pro font variants ──────────────────────────────────────────────────
    readonly property var fontVariantMeta: ({
            "regular": { file: "SFPRODISPLAYREGULAR.OTF", weight: Font.Normal, italic: false },
            "medium": { file: "SFPRODISPLAYMEDIUM.OTF", weight: Font.Medium, italic: false },
            "semibold": { file: "SFPRODISPLAYSEMIBOLDITALIC.OTF", weight: Font.DemiBold, italic: true },
            "bold": { file: "SFPRODISPLAYBOLD.OTF", weight: Font.Bold, italic: false },
            "heavy": { file: "SFPRODISPLAYHEAVYITALIC.OTF", weight: Font.ExtraBold, italic: true },
            "black": { file: "SFPRODISPLAYBLACKITALIC.OTF", weight: Font.Black, italic: true },
            "light": { file: "SFPRODISPLAYLIGHTITALIC.OTF", weight: Font.Light, italic: true },
            "thin": { file: "SFPRODISPLAYTHINITALIC.OTF", weight: Font.Thin, italic: true },
            "ultralight": { file: "SFPRODISPLAYULTRALIGHTITALIC.OTF", weight: Font.ExtraLight, italic: true }
        })

    function variantMeta(variant) {
        return root.fontVariantMeta[variant] ?? root.fontVariantMeta["bold"];
    }

    FontLoader {
        id: clockLoader
        source: "file://" + Directories.assetsPath + "/fonts/sf-pro-display/" + root.variantMeta(root.clockVariant).file
    }
    FontLoader {
        id: dateLoader
        source: "file://" + Directories.assetsPath + "/fonts/sf-pro-display/" + root.variantMeta(root.dateVariant).file
    }

    readonly property var clockMeta: root.variantMeta(root.clockVariant)
    readonly property var dateMeta: root.variantMeta(root.dateVariant)
    readonly property string clockFamily: clockLoader.status === FontLoader.Ready && clockLoader.name ? clockLoader.name : Appearance.font.family.main
    readonly property string dateFamily: dateLoader.status === FontLoader.Ready && dateLoader.name ? dateLoader.name : Appearance.font.family.main

    // ── Time & date strings ───────────────────────────────────────────────────
    readonly property bool use12h: DateTime.use12HourClock
    readonly property string timeString: root.hoursStr + ":" + root.minutesStr
    readonly property string meridiemString: use12h ? DateTime.meridiem : ""
    readonly property string dateString: {
        if (root.effectiveSizeW === 1)
            return (DateTime.dayNameShort ?? "").toUpperCase() + " " + (DateTime.dayOfMonth ?? "");
        if (root.effectiveSizeW === 2 && !root.isVertical)
            return (DateTime.dayNameShort ?? "") + ", " + (DateTime.shortDate ?? "");
        return DateTime.longDate ?? "";
    }

    // When aspect ratio is roughly square or vertical (height >= width * 0.92),
    // use stacked layout (hours on top, minutes on bottom).
    // Otherwise use horizontal layout (date on top, time in single row).
    readonly property bool isVertical: visualButton.height >= visualButton.width * 0.92
    readonly property bool isHorizontal: !isVertical

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

        // =====================================================================
        // VERTICAL STAGE: Date on top, Hours on top, Minutes on bottom
        // =====================================================================
        Item {
            id: verticalStage
            visible: root.isVertical
            anchors.centerIn: parent

            readonly property real padH: Math.max(6, Math.round(visualButton.radius * 0.32))
            readonly property real padV: Math.max(6, Math.round(visualButton.radius * 0.32))
            readonly property real availW: Math.max(10, visualButton.width - padH * 2)
            readonly property real availH: Math.max(10, visualButton.height - padV * 2)

            // Dynamic typography scaling
            readonly property real datePixelSize: Math.max(8, Math.min(16, Math.min(availW * 0.16, availH * 0.12)))
            readonly property real dateHeight: dateTextVert.visible ? dateTextVert.implicitHeight : 0
            readonly property real dateGap: Math.max(0, Math.round(root.scaled(1)))

            readonly property real maxDigitH: Math.max(8, (availH - dateHeight - dateGap) / 2.05)
            readonly property real maxDigitW: Math.max(8, availW / 1.20)
            readonly property real digitPixelSize: Math.max(12, Math.min(maxDigitW, maxDigitH))
            // Compensate for font metrics ascent/descent leading to produce tight iOS lock screen spacing
            readonly property real digitSpacing: -Math.round(digitPixelSize * 0.38)

            implicitWidth: Math.max(hoursText.implicitWidth, minutesWrapper.implicitWidth, dateTextVert.implicitWidth)
            implicitHeight: dateHeight + (dateTextVert.visible ? dateGap : 0) + hoursText.implicitHeight + digitSpacing + minutesWrapper.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Text {
                id: dateTextVert
                visible: root.dateString.length > 0
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateString
                color: Appearance.colors.colSubtext
                font.family: root.dateFamily
                font.pixelSize: verticalStage.datePixelSize
                font.weight: root.dateMeta.weight
                font.italic: root.dateMeta.italic
                font.letterSpacing: 0.02 * verticalStage.datePixelSize
                renderType: Text.QtRendering
            }

            Text {
                id: hoursText
                anchors.top: dateTextVert.visible ? dateTextVert.bottom : parent.top
                anchors.topMargin: dateTextVert.visible ? verticalStage.dateGap : 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hoursStr
                color: Appearance.colors.colOnLayer2
                font.family: root.clockFamily
                font.pixelSize: verticalStage.digitPixelSize
                font.weight: root.clockMeta.weight
                font.italic: root.clockMeta.italic
                font.letterSpacing: -0.03 * verticalStage.digitPixelSize
                renderType: Text.QtRendering
            }

            Item {
                id: minutesWrapper
                anchors.top: hoursText.bottom
                anchors.topMargin: verticalStage.digitSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: minutesText.implicitWidth + (meridiemVert.visible ? meridiemVert.implicitWidth + 2 : 0)
                implicitHeight: minutesText.implicitHeight
                width: implicitWidth
                height: implicitHeight

                Text {
                    id: minutesText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.minutesStr
                    color: Appearance.colors.colOnLayer2
                    font.family: root.clockFamily
                    font.pixelSize: verticalStage.digitPixelSize
                    font.weight: root.clockMeta.weight
                    font.italic: root.clockMeta.italic
                    font.letterSpacing: -0.03 * verticalStage.digitPixelSize
                    renderType: Text.QtRendering
                }

                Text {
                    id: meridiemVert
                    visible: root.meridiemString !== ""
                    anchors.left: minutesText.right
                    anchors.leftMargin: 2
                    anchors.bottom: minutesText.bottom
                    anchors.bottomMargin: verticalStage.digitPixelSize * 0.10
                    text: root.meridiemString
                    color: Appearance.colors.colSubtext
                    font.family: root.dateFamily
                    font.pixelSize: verticalStage.digitPixelSize * 0.28
                    font.weight: root.dateMeta.weight
                    font.italic: root.dateMeta.italic
                    renderType: Text.QtRendering
                }
            }
        }

        // =====================================================================
        // HORIZONTAL STAGE: Date on top, "12:45" single-line below
        // =====================================================================
        Item {
            id: horizontalStage
            visible: root.isHorizontal
            anchors.centerIn: parent

            readonly property real padH: Math.max(8, Math.round(visualButton.radius * 0.35))
            readonly property real padV: Math.max(6, Math.round(visualButton.radius * 0.25))
            readonly property real availW: Math.max(10, visualButton.width - padH * 2)
            readonly property real availH: Math.max(10, visualButton.height - padV * 2)

            readonly property real datePixelSize: Math.max(8, Math.min(16, Math.min(availW * 0.14, availH * 0.22)))
            readonly property real dateHeight: dateTextHori.visible ? dateTextHori.implicitHeight : 0
            readonly property real dateGap: Math.max(0, Math.round(root.scaled(1)))

            readonly property real maxClockH: Math.max(10, (availH - dateHeight - dateGap) * 0.90)
            readonly property real maxClockW: Math.max(10, availW / (root.meridiemString !== "" ? 3.3 : 2.75))
            readonly property real clockPixelSize: Math.max(12, Math.min(maxClockW, maxClockH))
            readonly property real meridiemGap: Math.round(clockPixelSize * 0.10)

            implicitWidth: Math.max(dateTextHori.implicitWidth, clockRow.implicitWidth)
            implicitHeight: dateHeight + (dateTextHori.visible ? dateGap : 0) + clockRow.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Text {
                id: dateTextHori
                visible: root.dateString.length > 0
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateString
                color: Appearance.colors.colSubtext
                font.family: root.dateFamily
                font.pixelSize: horizontalStage.datePixelSize
                font.weight: root.dateMeta.weight
                font.italic: root.dateMeta.italic
                font.letterSpacing: 0.02 * horizontalStage.datePixelSize
                renderType: Text.QtRendering
            }

            Item {
                id: clockRow
                anchors.top: dateTextHori.visible ? dateTextHori.bottom : parent.top
                anchors.topMargin: dateTextHori.visible ? horizontalStage.dateGap : 0
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: timeTextHori.implicitWidth + (meridiemHori.visible ? horizontalStage.meridiemGap + meridiemHori.implicitWidth : 0)
                implicitHeight: timeTextHori.implicitHeight
                width: implicitWidth
                height: implicitHeight

                Text {
                    id: timeTextHori
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.timeString
                    color: Appearance.colors.colOnLayer2
                    font.family: root.clockFamily
                    font.pixelSize: horizontalStage.clockPixelSize
                    font.weight: root.clockMeta.weight
                    font.italic: root.clockMeta.italic
                    font.letterSpacing: -0.02 * horizontalStage.clockPixelSize
                    renderType: Text.QtRendering
                }

                Text {
                    id: meridiemHori
                    visible: root.meridiemString !== ""
                    anchors.left: timeTextHori.right
                    anchors.leftMargin: horizontalStage.meridiemGap
                    anchors.baseline: timeTextHori.baseline
                    text: root.meridiemString
                    color: Appearance.colors.colSubtext
                    font.family: root.clockFamily
                    font.pixelSize: horizontalStage.clockPixelSize * 0.38
                    font.weight: root.clockMeta.weight
                    font.italic: root.clockMeta.italic
                    font.letterSpacing: 0.06 * horizontalStage.clockPixelSize
                    renderType: Text.QtRendering
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
