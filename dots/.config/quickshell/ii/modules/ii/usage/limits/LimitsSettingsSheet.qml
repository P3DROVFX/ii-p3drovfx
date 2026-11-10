pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * How the limits behave: warnings, reminders, the block screen, the PIN and the apps
 * that are never blocked. Every row applies at once — there is nothing to save.
 */
ClockSheet {
    id: root

    readonly property var opts: Config.options.screenTime
    property bool pickingAllowed: false
    property string pinMessage: ""

    title: Translation.tr("Limit settings")
    subtitle: Translation.tr("Counts focused time from App usage")

    component Caption: StyledText {
        Layout.topMargin: 4
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    component ChoiceRow: Flow {
        id: choiceRow
        property var choices: []
        property int value: 0
        signal chosen(int value)

        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: choiceRow.choices

            ClockFormChip {
                required property var modelData
                label: modelData.label
                selected: choiceRow.value === modelData.value
                onTriggered: choiceRow.chosen(modelData.value)
            }
        }
    }

    function setPin(): void {
        const pin = pinField.text.trim();
        if (pin.length < 4) {
            root.pinMessage = Translation.tr("Use at least 4 digits");
            return;
        }
        ScreenTimeLimits.setPin(pin);
        pinField.text = "";
        root.pinMessage = Translation.tr("PIN saved");
    }

    function toggleAllowed(key: string): void {
        const next = Array.from(ScreenTimeLimits.alwaysAllowed);
        const index = next.indexOf(key);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(key);
        ScreenTimeLimits.setAlwaysAllowed(next);
    }

    ClockFormToggle {
        symbol: "hourglass_top"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        label: Translation.tr("Daily limits")
        description: Translation.tr("Count, warn and block")
        checked: root.opts.enable
        onToggled: checked => Config.options.screenTime.enable = checked
    }

    Caption {
        text: Translation.tr("Warn before time is up")
    }
    ChoiceRow {
        value: root.opts.warnMinutes
        choices: [
            { label: Translation.tr("Off"), value: 0 },
            { label: Translation.tr("%1 min").arg("1"), value: 1 },
            { label: Translation.tr("%1 min").arg("5"), value: 5 },
            { label: Translation.tr("%1 min").arg("10"), value: 10 },
            { label: Translation.tr("%1 min").arg("15"), value: 15 }
        ]
        onChosen: value => Config.options.screenTime.warnMinutes = value
    }

    ClockFormToggle {
        symbol: "timer_10_alt_1"
        shapeKind: MaterialShape.Shape.Cookie6Sided
        label: Translation.tr("Last-minute warning")
        description: Translation.tr("One more when a minute is left")
        checked: root.opts.warnLastMinute
        onToggled: checked => Config.options.screenTime.warnLastMinute = checked
    }

    ClockFormToggle {
        symbol: "notifications_active"
        shapeKind: MaterialShape.Shape.Sunny
        label: Translation.tr("Notify when time is up")
        description: Translation.tr("And when a limit is ignored")
        checked: root.opts.notifyOnLimit
        onToggled: checked => Config.options.screenTime.notifyOnLimit = checked
    }

    Caption {
        text: Translation.tr("Remind me while over a limit")
    }
    ChoiceRow {
        value: root.opts.overdueReminderMinutes
        choices: [
            { label: Translation.tr("Off"), value: 0 },
            { label: Translation.tr("Every %1 min").arg("5"), value: 5 },
            { label: Translation.tr("Every %1 min").arg("15"), value: 15 },
            { label: Translation.tr("Every %1 min").arg("30"), value: 30 }
        ]
        onChosen: value => Config.options.screenTime.overdueReminderMinutes = value
    }

    Caption {
        text: Translation.tr("Close the app on its own after")
    }
    ChoiceRow {
        value: root.opts.autoCloseSeconds
        choices: [
            { label: Translation.tr("Never"), value: 0 },
            { label: Translation.tr("%1 s").arg("10"), value: 10 },
            { label: Translation.tr("%1 s").arg("30"), value: 30 },
            { label: Translation.tr("%1 min").arg("1"), value: 60 }
        ]
        onChosen: value => Config.options.screenTime.autoCloseSeconds = value
    }

    // ── PIN ─────────────────────────────────────────────────────────────
    Caption {
        text: ScreenTimeLimits.hasPin ? Translation.tr("PIN") : Translation.tr("PIN (optional)")
    }

    ClockFormField {
        id: pinField
        symbol: "password"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        caption: ScreenTimeLimits.hasPin ? Translation.tr("New PIN") : Translation.tr("Choose a PIN")
        placeholder: Translation.tr("4 or more digits")
        input.echoMode: TextInput.Password
        input.validator: RegularExpressionValidator {
            regularExpression: /[0-9]{0,12}/
        }
        onAccepted: root.setPin()
    }

    StyledText {
        visible: root.pinMessage.length > 0
        Layout.fillWidth: true
        text: root.pinMessage
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ClockSheetAction {
            visible: ScreenTimeLimits.hasPin
            label: Translation.tr("Remove PIN")
            danger: true
            onClicked: {
                ScreenTimeLimits.setPin("");
                Config.options.screenTime.pinForEdits = false;
                root.pinMessage = Translation.tr("PIN removed");
            }
        }

        ClockSheetAction {
            primary: true
            symbol: "key"
            label: ScreenTimeLimits.hasPin ? Translation.tr("Change PIN") : Translation.tr("Set PIN")
            enabled: pinField.text.length > 0
            onClicked: root.setPin()
        }
    }

    ClockFormToggle {
        visible: ScreenTimeLimits.hasPin
        symbol: "edit_off"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        label: Translation.tr("PIN protects changes")
        description: Translation.tr("Editing, removing and pausing limits")
        checked: root.opts.pinForEdits
        onToggled: checked => Config.options.screenTime.pinForEdits = checked
    }

    // ── Always allowed ──────────────────────────────────────────────────
    ClockFormPicker {
        Layout.topMargin: 4
        symbol: "verified"
        shapeKind: MaterialShape.Shape.Clover4Leaf
        caption: Translation.tr("Always allowed")
        value: ScreenTimeLimits.alwaysAllowed.length === 0 ? Translation.tr("None")
            : ScreenTimeLimits.alwaysAllowed.map(k => AppStats.displayName(k)).join(", ")
        expanded: root.pickingAllowed
        onTriggered: root.pickingAllowed = !root.pickingAllowed
    }

    StyledText {
        visible: root.pickingAllowed
        Layout.fillWidth: true
        text: Translation.tr("Never blocked by the total limit or an all-apps schedule, and not counted toward the total.")
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }

    LimitsAppPicker {
        visible: root.pickingAllowed
        Layout.fillWidth: true
        selected: ScreenTimeLimits.alwaysAllowed
        onToggled: key => root.toggleAllowed(key)
    }
}
