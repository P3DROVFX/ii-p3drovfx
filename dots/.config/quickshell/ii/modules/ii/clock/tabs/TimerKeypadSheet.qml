import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A new timer while others are running: the keypad in the side sheet, so the running
 * timers stay on screen instead of being swapped out for the keypad.
 */
ClockSheet {
    id: root

    signal startRequested(int seconds)

    title: Translation.tr("New timer")
    subtitle: Translation.tr("Type the digits, or pick a preset")

    TimerKeypad {
        id: keypad
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        compact: true
        showStartRow: false
        fixedKeySize: Math.max(ClockStyle.keypadKeyMin, Math.min(62, (root.width - 28 - ClockStyle.gap * 2) / 3.4))
        onStartRequested: seconds => {
            root.startRequested(seconds);
            root.close();
        }
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Save as preset")
            symbol: "bookmark_add"
            enabled: keypad.totalSeconds > 0 && !keypad.presets.includes(keypad.totalSeconds)
            onClicked: keypad.savePreset()
        },
        ClockSheetAction {
            primary: true
            label: Translation.tr("Start timer")
            symbol: "play_arrow"
            enabled: keypad.totalSeconds > 0
            onClicked: keypad.start()
        }
    ]
}
