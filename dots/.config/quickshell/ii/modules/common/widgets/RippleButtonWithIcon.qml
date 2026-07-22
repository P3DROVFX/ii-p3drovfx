import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: buttonWithIconRoot
    property string nerdIcon
    property string materialIcon
    property bool materialIconFill: true
    property string mainText: "Button text"
    property color colText: Appearance.colors.colOnSecondaryContainer
    property Component mainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: buttonWithIconRoot.colText
        }
    }
    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: RowLayout {
        spacing: buttonWithIconRoot.mainText !== "" ? 6 : 0
        Item {
            Layout.fillWidth: buttonWithIconRoot.mainText === ""
            Layout.alignment: Qt.AlignCenter
            implicitWidth: Math.max(materialIconLoader.implicitWidth, nerdIconLoader.implicitWidth)
            implicitHeight: Math.max(materialIconLoader.implicitHeight, nerdIconLoader.implicitHeight)
            Loader {
                id: materialIconLoader
                anchors.centerIn: parent
                active: !buttonWithIconRoot.nerdIcon
                sourceComponent: MaterialSymbol {
                    text: buttonWithIconRoot.materialIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: buttonWithIconRoot.colText
                    fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                }
            }
            Loader {
                id: nerdIconLoader
                anchors.centerIn: parent
                active: !!buttonWithIconRoot.nerdIcon
                sourceComponent: StyledText {
                    text: buttonWithIconRoot.nerdIcon
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.family: Appearance.font.family.iconNerd
                    color: buttonWithIconRoot.colText
                }
            }
        }
        Loader {
            visible: buttonWithIconRoot.mainText !== ""
            Layout.fillWidth: buttonWithIconRoot.mainText !== ""
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: buttonWithIconRoot.mainContentComponent
        }
    }
}
