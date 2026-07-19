import QtQuick
import qs.modules.common

/**
 * Slide-in sub-page overlay shared by settings pages that host widget config
 * sub-pages. Fill the page root with it (z above the main content) and bind
 * the main content's opacity to `slideProgress` for the cross-fade.
 * Sub-pages are expected to expose `showBackButton` and a `goBack` signal
 * (ContentPage does).
 */
Item {
    id: host

    // URL of the open sub-page; empty = closed. Resolve relative paths at the
    // call site (Qt.resolvedUrl) so they stay relative to the caller's file.
    property url activeSubPage: ""
    readonly property bool isOpen: activeSubPage.toString() !== ""
    // 1 when closed, 0 when fully open — bind the main page's opacity to this
    readonly property real slideProgress: width > 0 ? slider.x / width : 1

    function open(url) {
        activeSubPage = url;
    }

    function close() {
        activeSubPage = "";
    }

    // Disable input when off-screen
    enabled: isOpen
    onIsOpenChanged: {
        if (isOpen)
            slider.overlayActive = true;

    }

    Item {
        id: slider

        // overlayActive stays true during the close animation (until x reaches width)
        property bool overlayActive: host.isOpen

        width: parent.width
        height: parent.height
        y: 0
        onXChanged: {
            if (!host.isOpen && x >= slider.width - 1)
                overlayActive = false;

        }
        // Open: x=0. Closed: x=width (off-screen right).
        x: host.isOpen ? 0 : slider.width

        Loader {
            id: subPageLoader

            anchors.fill: parent
            source: host.activeSubPage
            active: slider.overlayActive
            onLoaded: {
                if (item.hasOwnProperty("showBackButton"))
                    item.showBackButton = true;

                item.goBack.connect(function() {
                    host.activeSubPage = "";
                });
            }
        }

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }

        }

    }

}
