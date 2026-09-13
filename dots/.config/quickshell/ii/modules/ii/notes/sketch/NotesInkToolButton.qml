import QtQuick

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * One tool on the ink tray.
 *
 * A `TapHandler` restricted to tablet devices sits alongside the ordinary click, because
 * **a MouseArea never sees a tablet event**: Qt synthesises a mouse event from a stylus
 * one only if nobody accepted the stylus event first, and the drawing surface is a
 * `PointHandler`, which accepts them natively. Without this, every pen tap on a tool
 * became a stroke while the same tap from a mouse worked. Including mouse or touch in the
 * handler's `acceptedDevices` would fire the button twice.
 */
RippleButton {
    id: root

    property string symbol: "edit"
    property bool active: false
    property string tooltipText: ""
    property real size: 46

    signal triggered()

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: NotesMetrics.pillRadius(root.size)
    toggled: root.active

    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover

    onClicked: root.triggered()

    // The active tool grows. Shape and size carry the state, which survives a theme where
    // the container colour is quiet.
    scale: root.active ? 1.08 : (root.down ? 0.94 : 1.0)
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.symbol
        iconSize: 22
        fill: root.active ? 1 : 0
        color: root.active
            ? Appearance.m3colors.m3onSecondaryContainer
            : Appearance.colors.colOnLayer1

        Behavior on fill {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    TapHandler {
        acceptedDevices: PointerDevice.Stylus | PointerDevice.Puck | PointerDevice.Airbrush
        onTapped: root.triggered()
    }

    StyledToolTip {
        text: root.tooltipText
        extraVisibleCondition: root.tooltipText.length > 0
    }
}
