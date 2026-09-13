import QtQuick
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    required property var birthdayData
    property bool compact: false

    signal activated(var birthday)

    buttonRadius: Appearance.rounding.verysmall
    colBackground: Appearance.colors.colTertiaryContainer
    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
    onClicked: root.activated(root.birthdayData)

    contentItem: Row {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 7
        spacing: 4

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "cake"
            iconSize: root.compact ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
            color: Appearance.colors.colOnTertiaryContainer
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x)
            text: root.birthdayData?.content ?? ""
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: root.compact ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnTertiaryContainer
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.hovered
        text: root.birthdayData?.content ?? ""
    }
}
