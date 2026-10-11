import QtQuick
import Qt5Compat.GraphicalEffects

/**
 * The lock's Android 16 battery: a primary button holding a rounded bar with
 * the percentage cut out of it, and a bolt (or check when full) on its tip.
 *
 * The greeter has no UPower, so the battery is read from sysfs. That needs
 * QML_XHR_ALLOW_FILE_READ=1 in the greeter's environment (set by the theme's
 * sddm.conf.d file); without it, or without a battery, the button hides.
 */
IslandButton {
    id: root

    property real percentage: 0
    property string status: ""
    property bool available: false
    property string supply: ""
    readonly property var candidates: ["BAT0", "BAT1", "BAT2", "BAT", "BATT", "CMB0"]

    readonly property bool effectivelyCharging: status !== "" && status !== "Discharging"
    readonly property bool showCheck: status === "Full" || status === "Not charging"
    readonly property bool isLow: percentage <= Theme.num("battery_low", 20) / 100
    readonly property bool isCritical: percentage <= Theme.num("battery_critical", 5) / 100
    readonly property color colHighlight: (isCritical || isLow) && !effectivelyCharging ? Theme.m3error : Theme.m3onPrimary
    readonly property color colTrack: Theme.transparentize(colHighlight, 0.7)

    visible: available
    implicitWidth: height
    pointingHandCursor: false
    colBackground: Theme.m3primary
    colBackgroundHover: Theme.colPrimaryHover
    colRipple: Theme.colPrimaryActive

    function readFile(path, callback) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                callback(xhr.status === 200 || xhr.status === 0 ? String(xhr.responseText ?? "").trim() : "");
        };
        try {
            xhr.open("GET", "file://" + path);
            xhr.send();
        } catch (e) {
            callback("");
        }
    }
    function probe(index) {
        if (index >= root.candidates.length)
            return;
        const dir = "/sys/class/power_supply/" + root.candidates[index];
        root.readFile(dir + "/capacity", text => {
            if (text !== "" && !isNaN(parseInt(text))) {
                root.supply = dir;
                root.refresh();
            } else {
                root.probe(index + 1);
            }
        });
    }
    function refresh() {
        if (root.supply === "")
            return;
        root.readFile(root.supply + "/capacity", text => {
            const value = parseInt(text);
            root.available = !isNaN(value);
            if (root.available)
                root.percentage = Math.max(0, Math.min(100, value)) / 100;
        });
        root.readFile(root.supply + "/status", text => root.status = text);
    }
    Component.onCompleted: root.probe(0)
    Timer {
        running: root.supply !== ""
        interval: 20000
        repeat: true
        onTriggered: root.refresh()
    }

    contentItem: Item {
        Item {
            id: battery
            anchors.centerIn: parent
            width: 29
            height: 14

            Row {
                anchors.centerIn: parent
                spacing: 1

                Item {
                    id: bar
                    width: 26
                    height: 14

                    Rectangle {
                        id: track
                        anchors.fill: parent
                        radius: 4.5
                        color: root.colTrack
                        visible: false
                        Rectangle {
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                left: parent.left
                            }
                            width: parent.width * root.percentage
                            radius: Math.round(2 * Theme.roundingScale)
                            color: root.colHighlight
                        }
                    }
                    OpacityMask {
                        id: rounded
                        anchors.fill: parent
                        source: track
                        visible: false
                        maskSource: Rectangle {
                            width: track.width
                            height: track.height
                            radius: track.radius
                        }
                    }
                    Item {
                        id: textMask
                        anchors.fill: parent
                        visible: false
                        StyledText {
                            anchors.centerIn: parent
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            text: Math.round(root.percentage * 100)
                        }
                    }
                    OpacityMask {
                        anchors.fill: parent
                        source: rounded
                        maskSource: textMask
                        invert: true
                    }
                }

                Rectangle {
                    width: 2
                    height: 6
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 1
                    color: root.percentage >= 0.98 ? root.colHighlight : root.colTrack
                }
            }

            MaterialSymbol {
                visible: root.effectivelyCharging || root.showCheck
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.right
                anchors.horizontalCenterOffset: -1
                text: root.showCheck ? "check" : "bolt"
                iconSize: 17
                fill: 1
                color: Theme.m3primary
                z: 2
            }
            MaterialSymbol {
                visible: root.effectivelyCharging || root.showCheck
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.right
                anchors.horizontalCenterOffset: -1
                text: root.showCheck ? "check" : "bolt"
                iconSize: 16
                fill: 1
                color: root.colHighlight
                z: 3
            }
        }
    }
}
