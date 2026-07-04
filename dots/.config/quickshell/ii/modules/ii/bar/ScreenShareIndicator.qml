import "./cards"
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

MouseArea {
    id: indicator

    property bool vertical: false
    property bool activelyScreenSharing: false

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : 40
    implicitHeight: vertical ? 40 : Appearance.sizes.baseBarHeight
    hoverEnabled: true
    Component.onCompleted: rootItem.toggleHighlight(true)

    Process {
        id: screenShareProc

        running: true
        command: ["bash", "-c", Directories.screenshareStateScript]
    }

    FileView {
        id: stateFile

        path: Directories.screenshareStatePath
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            indicator.activelyScreenSharing = !stateFile.text().trim().toLowerCase().includes("none");
            rootItem.toggleVisible(indicator.activelyScreenSharing);
        }
    }

    MaterialSymbol {
        id: iconIndicator

        z: 1
        text: "cast"
        color: Appearance.colors.colOnPrimary
        font.pixelSize: Appearance.font.pixelSize.huge

        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }

    }

    StyledPopup {
        hoverTarget: indicator
        animate: false

        contentItem: HeroCard {
            compactMode: true
            anchors.centerIn: parent
            icon: "cast_connected"
            title: stateFile.text().trim()
            subtitle: Translation.tr("is using your screen")
            pillText: Translation.tr("Sharing..")
            pillIcon: "screen_share"
        }

    }

}
