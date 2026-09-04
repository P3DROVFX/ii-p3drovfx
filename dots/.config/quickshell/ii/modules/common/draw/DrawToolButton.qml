import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/**
 * One round control in a drawing toolbar, at a size a pen tip can hit without aiming.
 *
 * Carries a `TapHandler` as well as the ripple button's own `MouseArea`, and that is not
 * belt and braces — it is the only thing that makes these buttons work with a graphics
 * tablet.
 *
 * A `MouseArea` never sees a tablet event. Qt synthesises a mouse event from one only if
 * nothing accepted the tablet event first, and the drawing surface underneath is a
 * `PointHandler`, which accepts them natively. So every tap on this button with a pen was
 * being swallowed by the canvas behind it and arriving as a stroke, while the same tap
 * with a mouse worked perfectly — which is exactly how it was reported.
 *
 * The canvas now declines points over the toolbar (see DrawSurface.excludeItem), and this
 * handler is what picks them up.
 */
RippleButton {
    id: root

    property string symbol: ""
    property bool active: false
    property bool emphasised: false
    property string tooltipText: ""

    signal triggered

    implicitWidth: Appearance.sizes.minimumTouchTarget
    implicitHeight: Appearance.sizes.minimumTouchTarget
    buttonRadius: Appearance.rounding.full
    colBackground: root.active
        ? Appearance.colors.colPrimary
        : (root.emphasised ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1)
    colBackgroundHover: root.active
        ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    /**
     * The pen's path to this button.
     *
     * `exclusiveSignals: TapHandler.SingleTap` keeps it from also firing on the second
     * press of a double tap. It does not double up with the ripple button's own
     * MouseArea: a pointer event reaches one or the other, never both — the handler takes
     * tablet events, which the MouseArea cannot see, and the MouseArea takes the
     * synthesised mouse events, which the handler declines by the time they arrive.
     */
    TapHandler {
        enabled: root.enabled
        // Tablet devices only, and that exclusion is load-bearing. A mouse click and a
        // touch tap both reach the ripple button's MouseArea as ordinary (or synthesised)
        // mouse events, so accepting those here would fire the button twice. A tablet
        // event is the one kind a MouseArea can never see.
        acceptedDevices: PointerDevice.Stylus | PointerDevice.Puck | PointerDevice.Airbrush
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.triggered()
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: Appearance.font.pixelSize.larger
        fill: root.active ? 1 : 0
        color: root.active
            ? Appearance.m3colors.m3onPrimary
            : (root.emphasised ? Appearance.colors.colOnSecondaryContainer
                               : Appearance.colors.colOnLayer1)
        opacity: root.enabled ? 1 : 0.4
    }

    StyledToolTip {
        text: root.tooltipText
    }
}
