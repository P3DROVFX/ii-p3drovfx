import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Hero tile of Startup & Services: one half of the page, its live count in huge condensed
 * digits, and the way to show it. The chosen half fills with the primary container and its
 * icon morphs into its shape; the other stays on the pane colour.
 */
RippleButton {
    id: root

    property string symbol: ""
    property var shape: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string count: ""
    property string caption: ""
    property string alert: ""
    property bool chosen: false

    readonly property color colContent: root.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

    implicitHeight: 132
    buttonRadius: Appearance.rounding.verylarge
    colBackground: root.chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.chosen ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.92) : Appearance.colors.colLayer1Hover
    colRipple: root.chosen ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.8) : Appearance.colors.colLayer1Active

    contentItem: Item {
        MaterialShapeWrappedMaterialSymbol {
            id: icon
            anchors {
                left: parent.left
                top: parent.top
                leftMargin: 18
                topMargin: 18
            }
            text: root.symbol
            iconSize: 22
            padding: 11
            fill: root.chosen ? 1 : 0
            shape: root.chosen ? root.shape : MaterialShape.Shape.Circle
            color: root.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colSymbol: root.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        StyledText {
            anchors {
                left: icon.right
                leftMargin: 12
                verticalCenter: icon.verticalCenter
                right: countText.left
                rightMargin: 8
            }
            text: root.title
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: root.colContent
            elide: Text.ElideRight
        }

        StyledText {
            id: countText
            anchors {
                right: parent.right
                rightMargin: 20
                top: parent.top
                topMargin: 6
            }
            text: root.count
            // main, not title: StyledText swaps pure digits to the numbers face and drops axes
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 780, "wdth": 35, "ROND": 100 })
            font.pixelSize: 56
            color: root.colContent
        }

        StyledText {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 18
                bottomMargin: 16
            }
            text: root.alert !== "" ? root.alert : root.caption
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: root.alert !== "" ? Font.DemiBold : Font.Normal
            color: root.alert !== "" ? (root.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colError) : root.colContent
            opacity: root.alert !== "" ? 1 : 0.8
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
