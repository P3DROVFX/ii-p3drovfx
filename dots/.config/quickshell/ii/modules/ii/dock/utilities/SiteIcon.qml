import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * A website as an icon: its favicon (BrowserSites' local cache) on a plate,
 * or its initial on a shape tinted from the domain when there is none yet.
 */
Item {
    id: icon

    property string url: ""
    property string title: ""
    property real radius: Math.round(width * 0.3)
    property real renderScale: 1
    // How much of the plate the favicon fills; small cells want it larger.
    property real iconScale: 0.62

    readonly property string host: {
        const match = String(icon.url).match(/^[a-z]+:\/\/([^\/:?#]+)/i);
        return match ? match[1].replace(/^www\./, "") : String(icon.url);
    }
    // Read in a handler, not a binding: faviconFor() may queue a fetch, and
    // that write would feed back into a binding that reads it.
    property string favicon: ""
    function refreshFavicon() {
        icon.favicon = BrowserSites.faviconFor(icon.url);
    }
    onUrlChanged: Qt.callLater(icon.refreshFavicon)
    Component.onCompleted: Qt.callLater(icon.refreshFavicon)
    Connections {
        target: BrowserSites
        function onRevisionChanged() {
            if (icon.favicon === "")
                Qt.callLater(icon.refreshFavicon);
        }
    }
    readonly property string initial: (icon.title || icon.host || "?").trim().charAt(0).toUpperCase()
    readonly property color tint: ColorUtils.mix(ColorUtils.stringToColor(icon.host), ClockStyle.colPrimaryContainer, 0.45)

    Rectangle {
        anchors.fill: parent
        radius: icon.radius
        color: faviconImage.status === Image.Ready ? ClockStyle.colSurfaceHighest : icon.tint

        Image {
            id: faviconImage
            anchors.centerIn: parent
            width: Math.round(parent.width * icon.iconScale)
            height: width
            source: icon.favicon
            sourceSize: Qt.size(Math.ceil(width * Math.max(2, icon.renderScale * 1.5)), Math.ceil(height * Math.max(2, icon.renderScale * 1.5)))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            visible: status === Image.Ready
        }
        TileText {
            anchors.centerIn: parent
            visible: faviconImage.status !== Image.Ready
            text: icon.initial
            color: ColorUtils.getContrastingTextColor(icon.tint)
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: Math.round(parent.height * 0.52)
        }
    }
}
