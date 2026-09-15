pragma ComponentBehavior: Bound

import "../../../ii/bar/shared/cards"

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var shelf
    signal closeRequested()

    property bool startAnim: false

    readonly property var active:
        root.shelf ? root.shelf.weatherOpen : false
    onActiveChanged: {
        root.startAnim = root.active;
    }

    readonly property string city: Config.options.bar.weather.city
    onCityChanged: {
        if (Config.options.bar.weather.city)
            Weather.getData();
    }

    function fetchForecast() {
        Weather.getData();
    }

    Component.onCompleted: fetchForecast()

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 24

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        HeroCard {
            id: weatherHero
            compactMode: true
            Layout.fillWidth: true
            iconUrl: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
            pillText: Weather.data.city || "--"
            pillIcon: Weather.data.city ? "location_on" : ""
            title: Weather.data.temp
            subtitle: Weather.data.wDesc
            startAnim: root.startAnim
        }

        MetricsGrid {
            id: metricsGrid
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            uniformCellWidths: true
            startAnim: root.startAnim
        }
    }
}
