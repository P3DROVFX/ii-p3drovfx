import QtQuick
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The compact style's row of icon buttons on top of a menu: the entries the
 * user placed in the bar (ContextMenus.arrange's `bar`), each one square,
 * named by a tooltip. The buttons share the card's width; the bar's natural
 * width is one row of full-size buttons, so the card can fit it. A card
 * capped narrower squeezes the row, then wraps it (ContextMenus.barLayout).
 */
Item {
    id: root

    property var entries: []
    property real hostRadius: Appearance.rounding.windowRounding
    property real hostPadding: 6
    signal activated(var entry, Item button)

    readonly property real buttonSize: ContextMenus.barButtonSize
    readonly property real spacing: ContextMenus.barSpacing
    readonly property real radius: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)
    readonly property var layout: ContextMenus.barLayout(root.entries.length, root.width)
    // Each entry's row and place in it, from the row counts.
    readonly property var slots: {
        const out = [];
        root.layout.rows.forEach((n, r) => {
            for (let c = 0; c < n; c++)
                out.push({ "row": r, "column": c, "of": n });
        });
        return out;
    }

    visible: root.entries.length > 0
    implicitHeight: root.visible ? root.layout.height : 0
    implicitWidth: ContextMenus.barNaturalWidth(root.entries.length)

    Repeater {
        model: root.entries

        delegate: Rectangle {
            id: button
            required property var modelData
            required property int index
            readonly property var slot: root.slots[button.index] ?? { "row": 0, "column": button.index, "of": root.entries.length }
            readonly property real cellWidth: (root.width - (button.slot.of - 1) * root.spacing) / button.slot.of

            x: button.slot.column * (button.cellWidth + root.spacing)
            y: button.slot.row * (root.buttonSize + root.spacing)
            width: button.cellWidth
            height: root.buttonSize
            enabled: button.modelData.enabled !== false
            opacity: button.enabled ? 1 : 0.45
            radius: mouse.pressed ? Math.max(Appearance.rounding.verysmall, root.radius - 4) : root.radius
            color: mouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                : Appearance.colors.colSurfaceContainerHigh

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on radius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Hover as a state layer, not a step to the next surface tone:
            // with transparency on, those tones land a few levels apart on
            // an opaque card (EditPanelRow's hoverLayer says why).
            Rectangle {
                id: hoverLayer
                anchors.fill: parent
                radius: button.radius
                color: Appearance.colors.colOnSurface
                opacity: mouse.containsMouse && !mouse.pressed ? 0.08 : 0

                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hoverLayer)
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !picture.visible
                text: button.modelData.symbol ?? ""
                iconSize: 19
                fill: mouse.containsMouse ? 1 : 0
                color: button.modelData.destructive ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface
            }

            // An entry with a picture of its own (an app's launcher) shows
            // it instead of the symbol; the symbol stays the fallback for a
            // theme that has no such icon. Lifted a little on hover, the
            // way the symbol fills.
            IconImage {
                id: picture
                anchors.centerIn: parent
                visible: (button.modelData.iconSource ?? "") !== ""
                implicitSize: 20
                source: button.modelData.iconSource ?? ""
                scale: mouse.containsMouse ? 1.1 : 1

                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(picture)
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(button.modelData, button)
            }

            StyledToolTip {
                requireOverlay: false
                extraVisibleCondition: mouse.containsMouse
                text: button.modelData.title ?? ""
            }
        }
    }
}
