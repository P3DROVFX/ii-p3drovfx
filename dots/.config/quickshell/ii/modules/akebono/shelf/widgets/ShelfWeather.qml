pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ii/bar/widgets/weather"

// Weather chip on the shelf. Renders the same bar widget variant the bar uses
// for the configured weather style; only the "default" style sits inside a
// shelf pill (the expressive/horizon/tessera widgets paint their own surface).
// Left-click opens the shelf's weather panel; right-click still passes through
// to the bar widget, which offers a manual refresh.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "horizon" | "tessera"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (weatherHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 16)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: weatherMouse.containsMouse || (root.shelf?.weatherOpen ?? false)

        Component.onCompleted: root.shelf.registerWeatherAnchor(pill)
        Component.onDestruction: root.shelf.unregisterWeatherAnchor(pill)
        onXChanged: root.shelf.publishWeather()
    }

    Loader {
        id: weatherHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? weatherExpressive
            : root.style === "horizon" ? weatherHorizon
            : root.style === "tessera" ? weatherTessera
            : weatherDefault
    }

    Component {
        id: weatherDefault
        WeatherBar {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: weatherExpressive
        ExpressiveWeatherBar {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: weatherHorizon
        HorizonWeatherWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: weatherTessera
        TesseraWeatherWidget {
            vertical: false
            disablePopup: true
        }
    }

    MouseArea {
        id: weatherMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.shelf?.toggleWeather()
    }

    StyledToolTip {
        extraVisibleCondition: (Weather.data?.city ?? "") !== "" && !(root.shelf?.weatherOpen ?? false)
        text: `${Weather.data?.city ?? ""} • ${Translation.tr("Feels like %1").arg(Weather.data?.tempFeelsLike ?? "--°")}`
    }
}