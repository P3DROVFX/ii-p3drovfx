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
    // Producer/observer pattern fixed 2026-09-10: the pw-dump loop still runs
    // per widget instance, but `screensharestate.sh` now holds a non-blocking
    // flock with a pid heartbeat and exits when reparented, so the instances
    // the bar spawns (per section, per monitor, survivors of every hot-reload
    // or kill -9 — the 2026-09-08 audit measured eight coexisting) collapse
    // to exactly one live producer per machine. See the script header.
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

    // The producer loop lives here, but the script holds a non-blocking flock
    // with a heartbeat, so the several instances this widget spawns (per bar
    // section, per monitor, per reload) collapse into ONE live pw-dump loop —
    // the 2026-09-08 audit measured eight coexisting, unkillable producers.
    //
    // Restart backoff: `running: true` alone re-spawned a loser the instant it
    // exited — a continuous bash spawn loop per hidden instance, since a loser
    // only ever exits when a live holder is beating. Retrying every 15 s keeps
    // takeover of a dead holder bounded while idle instances spawn nothing.
    property bool producerWanted: true
    Process {
        id: screenShareProc
        running: producerWanted
        command: ["bash", Directories.screenshareStateScript]
        onExited: {
            if (producerWanted) {
                producerWanted = false;
                producerBackoff.restart();
            }
        }
    }
    Timer {
        id: producerBackoff
        interval: 15000
        onTriggered: indicator.producerWanted = true
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

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    Loader {
        active: BarInteraction.enablePopups && (BarInteraction.clickToShow || indicator.containsMouse || (item?.active ?? false))
        sourceComponent: StyledPopup {
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
    } // end Loader
    }
}