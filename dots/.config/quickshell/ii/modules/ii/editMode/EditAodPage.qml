import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Edit Mode's "Always On" page, on the AOD tab: which clock the Always On Display
 * draws (oledSaver.clockStyle) and how it behaves. The card beside it is the live
 * preview - the real faces, or the lock's widgets in grey to drag where the AOD
 * (and the lock) should keep them. Every control writes Config.options.oledSaver
 * straight away: preferences, not layout edits, so no history entry.
 */
StyledFlickable {
    id: root

    readonly property var aod: Config.options.oledSaver
    readonly property string style: root.aod.clockStyle ?? "widgets"
    readonly property bool aodOn: root.aod.enable ?? true

    readonly property var styles: [
        { "displayName": Translation.tr("Widgets"), "value": "widgets", "icon": "widgets",
          "blurb": Translation.tr("The lock screen's widgets, in grey. Drag them on the card.") },
        { "displayName": Translation.tr("Flip"), "value": "flip", "icon": "view_agenda",
          "blurb": Translation.tr("Big split-flap cards that fall over each minute.") },
        { "displayName": Translation.tr("Dial"), "value": "dial", "icon": "timelapse",
          "blurb": Translation.tr("Dials on the left edge turn until the time lines up.") },
        { "displayName": Translation.tr("Expressive"), "value": "expressive", "icon": "music_note",
          "blurb": Translation.tr("One line of time and date, with what is playing.") },
        { "displayName": Translation.tr("Dot matrix"), "value": "dots", "icon": "grid_on",
          "blurb": Translation.tr("The time in lit dots; a row of sixty walks with the seconds.") },
        { "displayName": Translation.tr("Analog"), "value": "analog", "icon": "schedule",
          "blurb": Translation.tr("Two hands on an outlined shape that changes every hour.") },
        { "displayName": Translation.tr("Info"), "value": "info", "icon": "notifications",
          "blurb": Translation.tr("Battery, next alarm, weather and the apps waiting for you.") }
    ]
    readonly property var current: root.styles.find(s => s.value === root.style) ?? root.styles[0]

    // Idle timeout steps, in minutes; 0 = shortcut only.
    readonly property var timeoutSteps: [0, 1, 2, 5, 10, 15, 20, 30]
    function stepTimeout(direction) {
        const now = root.aod.lockTimeout ?? 10;
        const steps = root.timeoutSteps;
        let at = steps.findIndex(v => v >= now);
        if (at < 0)
            at = steps.length - 1;
        if (direction > 0 && steps[at] === now)
            at += 1;
        else if (direction < 0)
            at -= 1;
        root.aod.lockTimeout = steps[Math.max(0, Math.min(steps.length - 1, at))];
    }

    contentHeight: column.implicitHeight
    clip: true

    ColumnLayout {
        id: column
        width: root.width
        spacing: 6

        // The style by name, in the type that carries the page: wide and heavy for
        // the name, narrow and light for what it does.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 4
            Layout.bottomMargin: 6
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.current.displayName
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 760, "wdth": 120, "ROND": 100 })
                font.pixelSize: Appearance.font.pixelSize.huge + 12
            }
            StyledText {
                Layout.fillWidth: true
                text: root.current.blurb
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnSurfaceVariant
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 420, "wdth": 88, "ROND": 100 })
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Clock")
            currentValue: root.style
            options: root.styles
            onSelected: value => root.aod.clockStyle = value
        }

        EditPanelSectionLabel {
            text: Translation.tr("Behaviour")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "dark_mode"
            title: Translation.tr("Always On Display")
            subtitle: Translation.tr("Super + R, and the lock screen's timeout")
            trailingKind: "switch"
            switchChecked: root.aodOn
            onActivated: {
                root.aod.enable = !root.aodOn;
                if (!root.aod.enable)
                    GlobalStates.oledSaverMonitors = [];
            }
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: root.aodOn
            symbol: "motion_photos_on"
            title: Translation.tr("Anti burn-in pixel shift")
            subtitle: Translation.tr("Moves everything a little every minute")
            trailingKind: "switch"
            switchChecked: root.aod.antiBurnIn ?? true
            onActivated: root.aod.antiBurnIn = !(root.aod.antiBurnIn ?? true)
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: root.aodOn
            symbol: "lock_clock"
            title: Translation.tr("Idle on the lock screen")
            trailingKind: "stepper"
            valueText: (root.aod.lockTimeout ?? 10) === 0
                ? Translation.tr("Never")
                : Translation.tr("%1 min").arg(root.aod.lockTimeout ?? 10)
            stepDownEnabled: (root.aod.lockTimeout ?? 10) > 0
            stepUpEnabled: (root.aod.lockTimeout ?? 10) < root.timeoutSteps[root.timeoutSteps.length - 1]
            onStepUp: root.stepTimeout(1)
            onStepDown: root.stepTimeout(-1)
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            rowEnabled: root.aodOn
            symbol: "mouse"
            title: Translation.tr("Hide the cursor after")
            trailingKind: "stepper"
            valueText: Translation.tr("%1 s").arg(root.aod.cursorHideDelay ?? 5)
            stepDownEnabled: (root.aod.cursorHideDelay ?? 5) > 1
            stepUpEnabled: (root.aod.cursorHideDelay ?? 5) < 30
            onStepUp: root.aod.cursorHideDelay = Math.min(30, (root.aod.cursorHideDelay ?? 5) + 1)
            onStepDown: root.aod.cursorHideDelay = Math.max(1, (root.aod.cursorHideDelay ?? 5) - 1)
        }

        // The real thing, full screen: the mode closes under it.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            first: true
            last: false
            rowEnabled: root.aodOn
            symbol: "play_circle"
            title: Translation.tr("Try it now")
            subtitle: Translation.tr("Leaves Edit Mode; a click or a key wakes the screen")
            trailingKind: "none"
            onActivated: {
                GlobalStates.closeEditMode();
                GlobalStates.toggleOledSaver();
            }
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "settings"
            title: Translation.tr("All lock screen settings")
            subtitle: Translation.tr("Leaves Edit Mode")
            trailingKind: "chevron"
            onActivated: GlobalStates.openSettingsFromEditMode("lockScreen")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
