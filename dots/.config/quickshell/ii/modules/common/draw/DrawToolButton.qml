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
    /// A keyboard shortcut shown after the tooltip, e.g. "Ctrl+Z".
    property string shortcut: ""
    property real size: Appearance.sizes.minimumTouchTarget

    signal triggered

    implicitWidth: root.size
    implicitHeight: root.size
    // A click must not move keyboard focus off the drawing surface, or the next Space or
    // Ctrl+Z lands on this button instead of the sheet.
    focusPolicy: Qt.NoFocus
    // Round at rest, a rounded square while on: the shape is the state (Material 3
    // Expressive toggle buttons), so a lit tool reads as lit without a second cue.
    buttonRadius: root.active ? Appearance.rounding.normal : Appearance.rounding.full
    // Opaque tones: the tray floats over applications on a layer nothing blurs. See
    // DrawToolbar.
    colBackground: root.active
        ? Appearance.colors.colPrimary
        : (root.emphasised ? Appearance.colors.colSecondaryContainer : Appearance.m3colors.m3surfaceContainerHigh)
    colBackgroundHover: root.active
        ? Appearance.colors.colPrimaryHover
        : (root.emphasised ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover)
    colRipple: root.active ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

    Behavior on buttonRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
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
                               : Appearance.colors.colOnSurface)
        opacity: root.enabled ? 1 : 0.4
    }

    // Shown on hover over every surface this button lives on: the drawing layer has no
    // sidebar or overlay open, and the tooltip's default waits for one.
    StyledToolTip {
        requireOverlay: false
        extraVisibleCondition: root.tooltipText.length > 0
        text: root.shortcut.length > 0 ? `${root.tooltipText}  ·  ${root.shortcut}` : root.tooltipText
    }
}
