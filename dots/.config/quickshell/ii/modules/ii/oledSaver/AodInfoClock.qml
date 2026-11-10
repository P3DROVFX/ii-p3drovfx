pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * AOD face: the time with what is waiting, in the manner of a Samsung AOD. A
 * compact clock and the date, then a line of status - battery, the next alarm,
 * the weather - and the apps that have notifications waiting, as their icons in
 * grey. Each part only shows when it has something to say.
 */
Item {
    id: root

    property bool running: true

    readonly property color brightColor: "#ededed"
    readonly property color midColor: "#9a9a9a"

    readonly property real unit: Math.min(root.height * 0.1, root.width * 0.06)

    readonly property var nextAlarm: AlarmService.nextAlarm(DateTime.clock.date)
    readonly property string alarmText: root.nextAlarm
        ? Qt.locale().toString(root.nextAlarm.at, Config.options?.time.format ?? "hh:mm") : ""
    readonly property bool showWeather: (Config.options.lock.showWeather ?? true) && Weather.data !== null && Weather.data.wCode !== undefined

    // One icon per app with notifications, newest first.
    readonly property var notifyingApps: {
        const seen = [];
        const apps = [];
        const list = Notifications.list;
        for (let i = list.length - 1; i >= 0; i--) {
            const n = list[i];
            if (!n)
                continue;
            const key = n.appName || n.appIcon || "";
            if (seen.includes(key))
                continue;
            seen.push(key);
            apps.push(n.appIcon || n.appName || "");
        }
        return apps;
    }
    readonly property int maxIcons: 6

    Column {
        anchors.centerIn: parent
        spacing: root.unit * 0.45

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.time
            color: root.brightColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.unit * 1.9)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.dayNameLong + ", " + DateTime.dayOfMonth + " " + DateTime.monthNameLong
            color: root.midColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 450, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.unit * 0.34)
        }

        // Status.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: root.unit * 0.2
            spacing: root.unit * 0.6

            Status {
                visible: Battery.available
                symbol: Battery.isCharging ? "bolt" : Icons.getBatteryIcon(Battery.percent)
                label: Battery.percent + "%"
            }
            Status {
                visible: root.alarmText !== ""
                symbol: "alarm"
                label: root.alarmText
            }
            Status {
                visible: root.showWeather
                symbol: root.showWeather ? Icons.getWeatherIcon(Weather.data.wCode) : "cloud"
                label: root.showWeather ? (Weather.data.temp ?? "") : ""
            }
        }

        // Waiting notifications.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.notifyingApps.length > 0
            topPadding: root.unit * 0.15
            spacing: root.unit * 0.25
            layer.enabled: visible
            layer.effect: MultiEffect {
                saturation: -1
            }

            Repeater {
                model: root.notifyingApps.slice(0, root.maxIcons)
                delegate: IconImage {
                    required property string modelData
                    implicitSize: Math.round(root.unit * 0.42)
                    source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                    opacity: 0.8
                }
            }
            Text {
                visible: root.notifyingApps.length > root.maxIcons
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (root.notifyingApps.length - root.maxIcons)
                color: root.midColor
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                font.pixelSize: Math.round(root.unit * 0.3)
            }
        }
    }

    component Status: Row {
        id: status
        property string symbol: ""
        property string label: ""
        spacing: root.unit * 0.12

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: status.symbol
            fill: 1
            iconSize: Math.round(root.unit * 0.38)
            color: root.midColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: status.label
            color: root.brightColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 550, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.unit * 0.32)
        }
    }
}
