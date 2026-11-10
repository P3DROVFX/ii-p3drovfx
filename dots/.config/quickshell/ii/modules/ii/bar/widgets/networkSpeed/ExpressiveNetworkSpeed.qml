import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Network speed — expressive bar style.
 *
 * Four designs, one readout, one palette:
 *
 *   capsule  A container pill with a filled disc carrying each arrow.
 *   split    Two connected segments, download and upload on different surfaces.
 *   graph    A mirrored live plot on a plate, the numbers beside it.
 *   rows     Download over upload, one aligned line each in a single pill.
 *
 * The widget is paddingless in the bar, so each design paints its own surface.
 * Colour comes from `BarWidgetPalette` only — every pair is a real Material
 * pair, and `colorMode` swaps the whole family. There is no popup, so nothing
 * here is "active": the only reaction to the pointer is the hover tone (and the
 * seam opening in `split`).
 */
MouseArea {
    id: root

    property bool vertical: false

    NetworkSpeedReadout {
        id: speed
    }

    BarWidgetPalette {
        id: scheme
        colorMode: Config.options?.bar?.networkSpeed?.colorMode ?? "primary"
    }

    readonly property string variant: {
        const v = Config.options?.bar?.networkSpeed?.expressiveVariant;
        return v === "split" || v === "graph" || v === "rows" ? v : "capsule";
    }
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property real pillRadius: (typeof rootItem !== "undefined" ? rootItem.groupStyle : Config.options.bar.barGroupStyle) === 1
        ? Appearance.rounding.windowRounding : Appearance.rounding.full

    // One driver for the slot and the surface both — see AGENTS.md §6.1.
    // The loaded design reports its natural length; the Loader's own size only
    // follows the animation of it.
    readonly property real targetLength: root.vertical
        ? (content.item?.implicitHeight ?? 0)
        : (content.item?.implicitWidth ?? 0)
    property real animatedLength: root.targetLength

    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    visible: speed.shown
    hoverEnabled: true
    opacity: speed.online ? 1 : 0.5
    implicitWidth: !speed.shown ? 0 : (root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength)
    implicitHeight: !speed.shown ? 0 : (root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight)

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Loader {
        id: content

        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.animatedLength
        height: root.vertical ? root.animatedLength : root.thickness

        sourceComponent: {
            if (root.variant === "split")
                return splitDesign;
            if (root.variant === "graph")
                return graphDesign;
            if (root.variant === "rows")
                return rowsDesign;
            return capsuleDesign;
        }
    }

    Component {
        id: capsuleDesign

        NetworkSpeedCapsule {
            net: speed
            palette: scheme
            vertical: root.vertical
            thickness: root.thickness
            pillRadius: root.pillRadius
            hovered: root.containsMouse
        }
    }

    Component {
        id: splitDesign

        NetworkSpeedSplit {
            net: speed
            palette: scheme
            vertical: root.vertical
            thickness: root.thickness
            pillRadius: root.pillRadius
            hovered: root.containsMouse
        }
    }

    Component {
        id: rowsDesign

        NetworkSpeedRows {
            net: speed
            palette: scheme
            vertical: root.vertical
            thickness: root.thickness
            pillRadius: root.pillRadius
            hovered: root.containsMouse
        }
    }

    Component {
        id: graphDesign

        NetworkSpeedGraph {
            net: speed
            palette: scheme
            vertical: root.vertical
            thickness: root.thickness
            pillRadius: root.pillRadius
            hovered: root.containsMouse
        }
    }

    StyledToolTip {
        requireOverlay: false
        text: speed.tooltipText
    }
}
