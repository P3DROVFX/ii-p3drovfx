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

    // Set to show the M3 error state (red outline + red caret/selection accent)
    property bool error: false

    // The label that rises onto the outline once the field is focused or filled.
    // It belongs to the Material style, which offers no handle on it, so it is
    // picked out of the children by the one property only it has.
    property Item floatingLabel: null
    readonly property bool labelFloating: root.placeholderText.length > 0
        && (root.activeFocus || root.length > 0)
    // Mirrors how the Material container measures the gap it cuts for the label.
    readonly property real floatingLabelWidth: root.floatingLabel
        ? Math.min(root.floatingLabel.width, root.floatingLabel.implicitWidth) * root.floatingLabel.scale
        : 0

    Material.theme: Material.System
    Material.accent: root.error ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary
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
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap

    background: Rectangle {
        implicitHeight: 56
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surface
        border.width: root.activeFocus ? 2 : 1
        border.color: root.error ? Appearance.m3colors.m3error : root.activeFocus ? Appearance.m3colors.m3primary :
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

        // Material's own outlined container breaks its outline where the floating
        // label sits. A plain Rectangle has no such break, so without this the
        // border is drawn straight through the label. Painted in the fill colour
        // over the top border only, and faded with the label that raised it.
        Rectangle {
            x: (root.floatingLabel?.x ?? 0) - 4
            y: -1
            implicitWidth: root.floatingLabelWidth + 8
            implicitHeight: parent.border.width + 2
            color: parent.color
            opacity: root.labelFloating ? 1 : 0

            // Not on the field itself: a call site declaring its own
            // Component.onCompleted would replace that one and quietly leave the
            // label unfound.
            Component.onCompleted: {
                for (let i = 0; i < root.children.length; i++) {
                    const child = root.children[i];
                    if (child.largestHeight === undefined)
                        continue;
                    root.floatingLabel = child;
                    return;
                }
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    StyledTextContextMenuLoader {
        id: contextMenu
        targetField: root
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.forceActiveFocus();
                contextMenu.popup(mouse.x, mouse.y);
            }
        }
    }
}
