import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root

    property string cardIcon: ""
    property real cardHue: 210
    property string cardShape: "Circle"
    property string title: ""
    property string description: ""

    signal openCard()

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + 32
    font.pixelSize: Appearance.font.pixelSize.small
    useDynamicRadius: true
    buttonRadius: Appearance.rounding.large

    isFirst: root.groupPosition?.isFirst ?? true
    isLast: root.groupPosition?.isLast ?? true

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    onClicked: root.openCard()

    property bool usePrimaryContainer: false
    property color shapeColorOverride: "transparent"
    property color symbolColorOverride: "transparent"

    property color normalColor: Appearance.colors.colLayer2

    colBackground: normalColor
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    readonly property color _tint: shapeColorOverride !== "transparent" && shapeColorOverride.a > 0
        ? shapeColorOverride
        : (usePrimaryContainer ? Appearance.colors.colPrimaryContainer : ColorUtils.categoryContainer(root.cardHue, Appearance.m3colors.m3primaryFixed, 0.5))

    readonly property color _onTint: symbolColorOverride !== "transparent" && symbolColorOverride.a > 0
        ? symbolColorOverride
        : (usePrimaryContainer ? Appearance.colors.colOnPrimaryContainer : ColorUtils.categoryOnColor(root._tint, root.cardHue))

    ScrollAnimate {}

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            MaterialShape {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 44
                shapeString: root.cardShape
                color: root._tint

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.cardIcon
                    iconSize: 24
                    color: root._onTint
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    text: root.title
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
