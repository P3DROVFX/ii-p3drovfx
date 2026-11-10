import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * An overlay pill on a picture, opaque on the surface ladder. Icon and label sit in one
 * centred row with the same padding on both sides; without its label it is a circle. The
 * chosen one turns primary container.
 */
RippleButton {
    id: root

    readonly property real pillHeight: 40
    readonly property real sidePadding: 16
    readonly property real labelGap: 8

    property string symbol: ""
    property string label: ""
    property bool chosen: false
    property bool showLabel: root.chosen
    // 0 → 1 as the label unfolds.
    property real reveal: root.showLabel ? 1 : 0
    readonly property real revealClamped: Math.max(0, Math.min(1, root.reveal))
    Behavior on reveal {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    implicitHeight: root.pillHeight
    implicitWidth: Math.max(root.pillHeight, root.sidePadding * 2 + iconSlot.implicitWidth + root.reveal * (root.labelGap + labelText.implicitWidth))
    buttonRadius: height / 2
    buttonRadiusPressed: Appearance.rounding.small
    toggled: root.chosen
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
    colRipple: Appearance.colors.colSurfaceContainerHighestHover
    colBackgroundToggled: Appearance.colors.colPrimaryContainer
    colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
    colBackgroundToggledActive: Appearance.colors.colPrimaryContainerActive
    colRippleToggled: Appearance.colors.colPrimaryContainerActive

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 0

            Item {
                id: iconSlot
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: iconGlyph.implicitWidth
                implicitHeight: iconGlyph.implicitHeight
                width: implicitWidth
                height: implicitHeight

                MaterialSymbol {
                    id: iconGlyph
                    anchors.centerIn: parent
                    text: root.symbol
                    iconSize: Appearance.font.pixelSize.larger
                    fill: root.chosen ? 1 : 0
                    color: root.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.reveal * (root.labelGap + labelText.implicitWidth)
                height: labelText.implicitHeight
                clip: true

                StyledText {
                    id: labelText
                    anchors {
                        left: parent.left
                        leftMargin: root.labelGap
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    opacity: root.revealClamped
                }
            }
        }
    }
}
