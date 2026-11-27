pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/**
 * What the app shows while the PC has no health data: why, and the one next step. Off
 * is turned on here; every other state waits on the phone, so the step is said in
 * words, with the one button that helps from this side.
 */
VitalsPage {
    id: root

    readonly property string why: VitalsService.lastError
    readonly property var info: {
        switch (VitalsService.state) {
        case "off":
            return {
                symbol: "ecg_heart", shape: "Cookie9Sided",
                title: Translation.tr("Your phone's health data, on this PC"),
                text: Translation.tr("Steps, sleep, heart rate and workouts from Samsung Health and Health Connect, read over the ii link and kept here."),
                action: Translation.tr("Turn on"), actionSymbol: "toggle_on"
            };
        case "notPaired":
            return {
                symbol: "phonelink_off", shape: "Cookie7Sided",
                title: Translation.tr("Pair your phone first"),
                text: Translation.tr("Install ii tools on the phone and pair it with this PC. Then, on the phone, open ii tools → Vitals → Share with the PC."),
                action: Translation.tr("Pair a phone"), actionSymbol: "add_link"
            };
        case "offline":
            return {
                symbol: "phonelink_erase", shape: "Cookie7Sided",
                title: Translation.tr("The phone is not connected"),
                text: Translation.tr("Open ii tools on the phone so it connects. Once it does, its health data comes over on its own."),
                action: "", actionSymbol: ""
            };
        case "noFeature":
            return {
                symbol: "share_off", shape: "Cookie12Sided",
                title: root.why === "permission" ? Translation.tr("ii tools needs access to your health data")
                    : root.why === "unavailable" ? Translation.tr("No health data source on the phone")
                    : Translation.tr("Sharing is off on the phone"),
                text: root.why === "permission" ? Translation.tr("On the phone, open ii tools → Vitals and allow Health Connect.")
                    : root.why === "unavailable" ? Translation.tr("The phone has neither Health Connect nor a readable Samsung Health. Install Health Connect from the Play Store.")
                    : Translation.tr("On the phone, open ii tools → Vitals → Share with the PC. If there is no Vitals screen, update ii tools."),
                action: "", actionSymbol: ""
            };
        case "syncing":
            return {
                symbol: "downloading", shape: "SoftBurst",
                title: Translation.tr("Getting your history"),
                text: Translation.tr("The first sync brings every day the phone has. It takes a minute."),
                action: "", actionSymbol: ""
            };
        default:
            return {
                symbol: "hourglass_empty", shape: "Clover4Leaf",
                title: Translation.tr("Nothing recorded yet"),
                text: Translation.tr("The phone shares, but has no health data yet. Wear the watch or carry the phone, and today shows up here."),
                action: Translation.tr("Sync now"), actionSymbol: "sync"
            };
        }
    }

    function act(): void {
        switch (VitalsService.state) {
        case "off":
            Config.options.iiTools.vitals.enable = true;
            break;
        case "notPaired":
            GlobalStates.openSettingsPage("devicesPhone", "devices/IiToolsConfig.qml");
            break;
        default:
            VitalsService.syncNow();
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.gapHuge * 2, 480)
        spacing: ClockStyle.gapLarge

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            symbol: root.info.symbol
            shape: root.info.shape
            shapeSize: root.compact ? ClockStyle.emptyShapeSmall : ClockStyle.emptyShape
            colShape: ClockStyle.colPrimaryContainer
            colIcon: ClockStyle.colOnPrimaryContainer
            title: root.info.title
            subtitle: root.info.text
        }

        StyledProgressBar {
            Layout.fillWidth: true
            Layout.maximumWidth: 320
            Layout.alignment: Qt.AlignHCenter
            visible: VitalsService.state === "syncing"
            value: VitalsService.progress
            valueBarHeight: 6
        }

        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapSmall
            visible: root.info.action.length > 0
            variant: "filled"
            symbol: root.info.actionSymbol
            label: root.info.action
            onClicked: root.act()
        }
    }
}
