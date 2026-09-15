pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../ii/bar/shared/cards"

// Shelf-hosted popup for the screen-share chip. The bar's own share popup is a
// separate PanelWindow anchored to the full-width bar, so the shelf renders the
// same card inline between the two windows instead; the state file is the same
// one the bar indicator watches.
Item {
    id: root

    property var shelf

    implicitWidth: 394
    implicitHeight: 170

    FileView {
        id: stateFile
        path: Directories.screenshareStatePath
        watchChanges: true
        onFileChanged: this.reload()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 14
        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHigh
    }

    HeroCard {
        id: card
        anchors.centerIn: parent
        compactMode: true
        implicitWidth: 360
        implicitHeight: 132
        icon: "cast_connected"
        title: stateFile.text().trim()
        subtitle: Translation.tr("is using your screen")
        pillText: Translation.tr("Sharing..")
        pillIcon: "screen_share"
    }
}