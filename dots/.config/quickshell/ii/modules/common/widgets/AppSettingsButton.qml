import QtQuick
import qs.modules.common
import qs.services

/**
 * The gear that opens an app's own settings, placed beside its close button.
 * Turns 60° on hover and stays filled while the settings are open.
 */
RippleButton {
    id: root

    property bool open: false
    property string label: Translation.tr("Settings")

    implicitWidth: 40
    implicitHeight: 40
    buttonRadius: Appearance.rounding.full
    toggled: root.open
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: "settings"
        fill: root.open ? 1 : 0
        iconSize: Appearance.font.pixelSize.title
        color: root.open ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
        rotation: root.hovered ? 60 : 0
        Behavior on rotation {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.hovered
        text: root.open ? Translation.tr("Back") + " (Esc)" : root.label
    }
}
