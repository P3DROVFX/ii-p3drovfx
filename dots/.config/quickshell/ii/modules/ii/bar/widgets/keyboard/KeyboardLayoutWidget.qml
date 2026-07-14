import qs.modules.ii.bar.popups.keyboard
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
    property bool uppercaseLayout: Config.options.bar.keyboardLayout.uppercaseLayout
    property bool isMaterial: Config.options.bar.styles.keyboard === "material"

    readonly property bool hasMultipleLayouts: HyprlandXkb.layoutCodes.length > 1

    // Visible if there is at least 1 layout registered
    visible: HyprlandXkb.layoutCodes.length >= 1

    implicitWidth: visible ? rowLoader.item?.implicitWidth + (root.isMaterial ? 0 : 16) : 0
    implicitHeight: visible ? Appearance.sizes.baseBarHeight : 0

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    function abbreviateLayoutCode(fullCode) {
        if (!fullCode)
            return "";
        let abbr = fullCode.split(':').map(layout => {
            const baseLayout = layout.split('-')[0];
            return baseLayout.slice(0, 2);
        }).join('\n')
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
        id: rowLoader
        active: !root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? rowMaterial : rowDefault

        Component {
            id: rowDefault

            RowLayout {
                id: layout
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: "keyboard"
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode).replace(/\n/g, ' ')
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                    animateChange: true
                }
            }
        }
    
        Component {
            id: rowMaterial
            
            MaterialBarWidget {
                primaryComponent: iconComponent
                secondaryComponent: keyboardLayoutComponent
                primaryIsCircle: true
                secondaryExtraMargin: 4
                componentsPadding: 6

                showSecondary: Config.options.bar.keyboardLayout.showSecondary
                secondaryOpposite: Config.options.bar.keyboardLayout.secondaryOpposite
                swapPrimaryWithSecondary: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
                showPrimary: Config.options.bar.keyboardLayout.showPrimary

                Component {
                    id: iconComponent
                    MaterialSymbol {
                        id: timeText
                        anchors.verticalCenter: parent.verticalCenter
                        fill: 0
                        text: "keyboard"
                        iconSize: 20
                        color: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnPrimary
                    }
                }

                Component {
                    id: keyboardLayoutComponent
                    Item {
                        width: metrics.width
                        height: keyboardText.implicitHeight
                        implicitWidth: width
                        implicitHeight: height
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1

                        StyledText {
                            id: keyboardText
                            anchors.centerIn: parent
                            color: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colPrimary
                            text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode).replace(/\n/g, ' ')
                            font.pixelSize: Appearance.font.pixelSize.small
                            animateChange: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        TextMetrics {
                            id: metrics
                            font: keyboardText.font
                            text: root.uppercaseLayout ? "UU UU" : "uu uu"
                        }
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
