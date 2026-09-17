pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

/**
 * Index workspaces.
 *
 * No shape anywhere: the workspaces are numerals, and the one you are on is
 * simply much bigger than the rest — a page index. Weight, size and opacity do
 * all the work, which makes this the one style where an unusual numeral system
 * (Greek, Roman, counting rods) is the design rather than a decoration on it.
 *
 *   active    large, bold, accent
 *   occupied  small, legible
 *   empty     small, faint
 *
 * Every slot is the same fixed width, measured off the largest label the row
 * can hold. Sizing each slot to its own numeral would make the row jump every
 * time the big numeral moved — and on a numeral system where 10 is two glyphs,
 * jump again at ten.
 */
Item {
    id: root

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    property bool vertical: false

    WorkspaceBarModel {
        id: wsModel
        screen: root.QsWindow.window?.screen ?? null
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    property real blur: root.scratchpadOpen ? 1 : 0

    // ── Type ─────────────────────────────────────────────────────────────────
    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    readonly property real activePixelSize: Math.max(12, Math.round(root.thickness * 0.52))
    readonly property real restPixelSize: Math.max(8, Math.round(root.thickness * 0.3))
    // How far the hovered numeral lifts. It travels inside the slot it already
    // has, so the row cannot reflow under the pointer.
    readonly property real hoverLift: Math.round(root.thickness * 0.08)

    // The widest label at active size, so a slot never has to grow for its own
    // content. Measured, not guessed: a counting-rod ten is two glyphs wide and
    // a Roman eighteen is four.
    readonly property real slot: Math.max(
        Math.round(root.thickness * 0.46),
        Math.ceil(widestMetrics.implicitWidth) + Math.round(root.thickness * 0.14))

    readonly property real rowLength: root.slot * Math.max(1, wsModel.visibleIds.length)

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.rowLength
    implicitHeight: root.vertical ? root.rowLength : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on blur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    readonly property string widestLabel: {
        let widest = "";
        for (const wsId of wsModel.visibleIds) {
            const label = wsModel.labelFor(wsId);
            if (label.length > widest.length)
                widest = label;
        }
        return widest === "" ? "0" : widest;
    }

    // Measured, never drawn.
    StyledText {
        id: widestMetrics
        visible: false
        text: root.widestLabel
        font.family: Appearance.font.family.numbers
        font.pixelSize: root.activePixelSize
        font.weight: Font.Bold
    }

    // ── The index ────────────────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(content)
        }

        Repeater {
            model: wsModel.visibleIds

            delegate: Item {
                id: slotItem

                required property int index
                required property int modelData
                readonly property int wsId: slotItem.modelData
                readonly property bool isActive: slotItem.wsId === wsModel.activeId
                readonly property bool isOccupied: wsModel.occupied[slotItem.wsId] === true

                x: root.vertical ? 0 : slotItem.index * root.slot
                y: root.vertical ? slotItem.index * root.slot : 0
                width: root.vertical ? parent.width : root.slot
                height: root.vertical ? root.slot : parent.height

                HoverHandler {
                    id: numeralHover
                    cursorShape: Qt.PointingHandCursor
                }

                StyledText {
                    id: numeral
                    anchors.centerIn: parent
                    // Lifts inside its own slot, so the row never reflows.
                    anchors.verticalCenterOffset: numeralHover.hovered && !slotItem.isActive
                        ? -root.hoverLift
                        : 0

                    text: wsModel.labelFor(slotItem.wsId)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: slotItem.isActive ? root.activePixelSize : root.restPixelSize
                    font.weight: slotItem.isActive ? Font.Bold : (slotItem.isOccupied ? Font.DemiBold : Font.Normal)
                    font.features: ({
                        "tnum": 1
                    })

                    color: (slotItem.isActive || numeralHover.hovered)
                        ? widgetPalette.colBackground
                        : (slotItem.isOccupied ? widgetPalette.colOnContainer : widgetPalette.colBare)
                    opacity: {
                        if (slotItem.isActive)
                            return Config.options.bar.workspaces.activeIndicatorOpacity / 100;
                        if (numeralHover.hovered)
                            return 1.0;
                        return slotItem.isOccupied ? 0.75 : 0.32;
                    }

                    Behavior on font.pixelSize {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on anchors.verticalCenterOffset {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(numeral)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(numeral)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wsModel.focus(slotItem.wsId)
                }
            }
        }
    }

    // ── Scratchpad ───────────────────────────────────────────────────────────
    Loader {
        anchors.centerIn: parent
        active: root.scratchpadOpen
        visible: active

        sourceComponent: MaterialShape {
            implicitSize: Math.round(root.thickness * 0.52)
            shapeString: "Flower"
            color: widgetPalette.colAccent
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wheel.accepted = true;
            wsModel.scroll(wheel.angleDelta.y);
        }
    }
}
