pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Squircle {
    id: notifRow
    required property var panel
    readonly property bool on: panel.activeDialog === "notifications"
    readonly property var iconEntries: {
        const seen = new Set();
        const out = [];
        const l = Notifications.list;
        for (let i = l.length - 1; i >= 0 && out.length < 4; i--) {
            const n = l[i];
            if (seen.has(n.appName))
                continue;
            seen.add(n.appName);
            out.push({ appIcon: n.appIcon, appName: n.appName });
        }
        return out;
    }

    implicitHeight: 54
    radius: 18
    smoothing: AkebonoAppearance.squircleSmoothing
    color: on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    Behavior on color { ColorAnimation { duration: 240; easing.type: Easing.OutCubic } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10

        MaterialSymbol {
            text: Notifications.silent ? "notifications_paused" : "notifications"
            iconSize: 23
            fill: notifRow.on ? 1 : 0
            color: notifRow.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            Behavior on color { ColorAnimation { duration: 240 } }
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("%1 notifications").arg(Notifications.list.length)
            font.pixelSize: Appearance.font.pixelSize.small
            color: notifRow.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: 240 } }
        }
        Row {
            spacing: -8

            Repeater {
                model: notifRow.iconEntries
                delegate: Rectangle {
                    id: stackIcon
                    required property var modelData
                    width: 28
                    height: 28
                    radius: 14
                    color: Appearance.colors.colLayer1

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 20
                        source: Quickshell.iconPath(
                            stackIcon.modelData.appIcon !== "" ? stackIcon.modelData.appIcon : AppSearch.guessIcon(stackIcon.modelData.appName),
                            "dialog-information")
                    }
                }
            }
        }
    }
    RippleArea {
        shapeRadius: 18
        squircleMask: true
        rippleColor: notifRow.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        onClicked: notifRow.panel.activeDialog = notifRow.on ? "" : "notifications"
    }
}
