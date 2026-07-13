import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.popups.keyboard

MouseArea {
    id: root
    property bool uppercaseLayout: Config.options.bar.keyboardLayout.uppercaseLayout

    readonly property bool hasMultipleLayouts: HyprlandXkb.layoutCodes.length > 1
    property bool isMaterial: Config.options.bar.styles.keyboard === "material"
    property bool vertical: Config.options.bar.vertical
    
    visible: HyprlandXkb.layoutCodes.length >= 1

    implicitWidth: Appearance.sizes.baseVerticalBarWidth
    implicitHeight: visible ? colLoader.item?.implicitHeight + (root.isMaterial ? 0 : 12) : 0

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    function abbreviateLayoutCode(fullCode) {
        if (!fullCode)
            return "";
        // Only take the first layout if multiple exist, or just take the first 2 letters of the primary one
        const firstLayout = fullCode.split(':')[0].split('-')[0];
        let abbr = firstLayout.slice(0, 2);
        return root.uppercaseLayout ? abbr.toUpperCase() : abbr.toLowerCase();
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
    
    Loader {
        id: colLoader
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? colMaterial : colDefault

        Component {
            id: colDefault

            ColumnLayout {
                id: layout
                anchors.centerIn: parent
                width: parent.width
                spacing: 0

                MaterialSymbol {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.large
                    text: "keyboard"
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                    font.pixelSize: 10
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Black
                    animateChange: true
                }
            }
        }
    
        Component {
            id: colMaterial

            VerticalMaterialBarWidget {
                primaryComponent: keyboardIcon
                secondaryComponent: keyboardLayout
                primaryIsCircle: true
                
                showSecondary: Config.options.bar.keyboardLayout.showSecondary
                secondaryOpposite: Config.options.bar.keyboardLayout.secondaryOpposite
                swapPrimaryWithSecondary: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
                showPrimary: Config.options.bar.keyboardLayout.showPrimary

                Component {
                    id: keyboardIcon                
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 0
                        text: "keyboard"
                        iconSize: 20
                        color: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnPrimary
                    }
                }

                Component {
                    id: keyboardLayout
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode).replace(/\n/g, ' ')
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.title
                        color: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        animateChange: true
                    }
                }
            }
        }
    }

    KeyboardLayoutPopup {
        id: popup
        hoverTarget: root
    }
}
