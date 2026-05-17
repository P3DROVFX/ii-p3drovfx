import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property bool vertical: false
    
    readonly property bool hasMultipleLayouts: HyprlandXkb.layoutCodes.length > 1
    visible: HyprlandXkb.layoutCodes.length >= 1

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : (rowLoader.item?.implicitWidth ?? 0) + 28
    implicitHeight: vertical ? (colLoader.item?.implicitHeight ?? 0) + 12 : Appearance.sizes.barHeight - 8
    
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    function abbreviateLayoutCode(fullCode) {
        if (!fullCode) return "";
        const firstLayout = fullCode.split(':')[0].split('-')[0];
        return firstLayout.slice(0, 2).toUpperCase();
    }

    Process {
        id: switchProc
        command: ["bash", "-c", "hyprctl switchxkblayout all next"]
    }

    onClicked: {
        if (hasMultipleLayouts) {
            switchProc.running = false;
            switchProc.running = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colSecondary

        Loader {
            id: rowLoader
            active: !root.vertical
            visible: active
            anchors.centerIn: parent
            sourceComponent: RowLayout {
                spacing: 6
                MaterialSymbol {
                    text: "keyboard"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    animateChange: true
                }
            }
        }

        Loader {
            id: colLoader
            active: root.vertical
            visible: active
            anchors.centerIn: parent
            sourceComponent: ColumnLayout {
                spacing: 2
                MaterialShape {
                    Layout.alignment: Qt.AlignHCenter
                    shapeString: "Cookie12Sided"
                    color: Appearance.colors.colPrimary
                    implicitSize: Appearance.sizes.verticalBarWidth - 8
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "keyboard"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                    font.pixelSize: 10
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    animateChange: true
                }
            }
        }
    }

    KeyboardLayoutPopup {
        id: popup
        hoverTarget: root
    }
}
