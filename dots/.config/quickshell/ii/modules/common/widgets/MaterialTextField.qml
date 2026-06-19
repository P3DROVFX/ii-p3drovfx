import qs.modules.common
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 styled TextField (filled style)
 * https://m3.material.io/components/text-fields/overview
 * Note: We don't use NativeRendering because it makes the small placeholder text look weird
 */
TextField {
    id: root
    Material.theme: Material.System
    Material.accent: Appearance.m3colors.m3primary
    Material.primary: Appearance.m3colors.m3primary
    Material.background: Appearance.m3colors.m3surface
    Material.foreground: Appearance.m3colors.m3onSurface
    Material.containerStyle: Material.Outlined
    renderType: Text.QtRendering

    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline
    clip: true

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap

    background: Rectangle {
        implicitHeight: 56
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surface
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.m3colors.m3primary : 
                       root.hovered ? Appearance.m3colors.m3outline : Appearance.m3colors.m3outlineVariant

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.width {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }
}
