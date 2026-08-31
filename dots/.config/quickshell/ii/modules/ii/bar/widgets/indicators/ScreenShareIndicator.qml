import qs
import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell.Io
import "../../shared/cards"

MouseArea {
    id: indicator

    property bool vertical: false
    property bool activelyScreenSharing: false

    // Edit Mode has to be able to reach a widget that is currently showing
    // nothing: with nothing to show this takes no room at all, so there would
    // be nothing to grab, drag or place. While the mode is on it is drawn as
    // though it were active. Rendering only - the stored visibility flag stays
    // on the real condition, and the bar ORs the mode in on its side.
    readonly property bool shown: indicator.activelyScreenSharing || GlobalStates.editMode

    visible: shown
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : 40) : 0
    implicitHeight: shown ? (vertical ? 40 : Appearance.sizes.baseBarHeight) : 0
    hoverEnabled: true
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
            let txt = stateFile.text().trim()
            indicator.activelyScreenSharing = txt.length > 0 && txt.toLowerCase() !== "none" && !txt.toLowerCase().includes("none")
            rootItem.toggleVisible(indicator.activelyScreenSharing)
        }
    }

    MaterialShape {
        id: indicatorShape
        implicitSize: 32
        shapeString: "Cookie9Sided"
        color: indicator.containsMouse
            ? Appearance.colors.colPrimaryContainerHover
            : Appearance.colors.colPrimaryContainer
        anchors.centerIn: parent

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "cast"
            iconSize: 20
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    StyledPopup {
        id: sharePopup
        hoverTarget: indicator
        animate: false
        contentItem: HeroCard {
            startAnim: sharePopup.opened && sharePopup.popupOpenProgress > 0.6
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