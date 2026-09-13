import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * Circular action button sized for fingers rather than cursors: the caller gives it a
 * diameter and everything inside follows from that, so the same button works on a 10"
 * tablet and on a large scaled monitor.
 */
RippleButton {
    id: root

    property real diameter: 56
    property string buttonIcon: ""
    property real iconRatio: 0.42
    // Emphasised buttons (the power button in Android's shade) invert to the primary colour.
    property bool accent: false

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.large

    colBackground: root.accent ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
    colBackgroundHover: root.accent ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
    colBackgroundActive: root.accent ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
    colRipple: root.accent ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    readonly property color colIcon: {
        if (root.toggled)
            return Appearance.colors.colOnSecondaryContainer;
        return root.accent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1;
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.buttonIcon
        iconSize: Math.round(root.diameter * root.iconRatio)
        fill: root.toggled ? 1 : 0
        color: root.colIcon
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
