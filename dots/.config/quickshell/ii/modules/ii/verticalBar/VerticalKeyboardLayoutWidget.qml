import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    property bool uppercaseLayout: Config.options.bar.keyboardLayout.uppercaseLayout

    readonly property bool hasMultipleLayouts: HyprlandXkb.layoutCodes.length > 1

    visible: HyprlandXkb.layoutCodes.length >= 1

    implicitWidth: Appearance.sizes.baseVerticalBarWidth
    implicitHeight: visible ? layout.implicitHeight + 12 : 0

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

    Bar.KeyboardLayoutPopup {
        id: popup
        hoverTarget: root
    }
}
