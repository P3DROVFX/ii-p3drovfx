import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Full-screen hint shown while a file drag hovers the desktop (set as wallpaper
// vs add to shelf). Lives on its own surface so the compositor blur behind the
// widgets surface (quickshell:backgroundWidgets) keeps frosting the desktop
// widgets while this tint is up, while this overlay itself has blur disabled in
// the layer rules and stays razor sharp.
PanelWindow {
    id: dropOverlayPanel

    visible: GlobalStates.desktopDragActive
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dropOverlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    // No clickable area: every click and the drag itself pass through to the
    // widgets surface underneath, which owns the DropArea.
    mask: Region {
        item: clickThroughAnchor
    }
    Item {
        id: clickThroughAnchor
        width: 0
        height: 0
        visible: false
    }

    screen: {
        const monName = GlobalStates.desktopDragMonitorName;
        if (!monName)
            return Quickshell.primaryScreen;
        return Quickshell.screens.find(s => s.name === monName) ?? Quickshell.primaryScreen;
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property bool isSingleImage: GlobalStates.desktopDragUrls.length === 1
        && /\.(png|jpe?g|webp|bmp|gif)$/i.test(
            CF.FileUtils.trimFileProtocol(GlobalStates.desktopDragUrls[0].toString())
        )

    Rectangle {
        id: dropOverlay
        anchors.fill: parent
        color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: dropOverlayPanel.isSingleImage ? "wallpaper" : "stacks"
                iconSize: 64
                color: Appearance.colors.colOnPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: dropOverlayPanel.isSingleImage
                    ? Translation.tr("Drop to set as wallpaper")
                    : Translation.tr("Drop to add to shelf")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}