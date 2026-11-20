pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `blockApps` action: the block screen covers these apps (or
 * everything but them) while the mode is on. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    readonly property bool allowOnly: row.obj.allowOnly === true

    spacing: 8

    FormChoice {
        current: form.allowOnly ? "allowOnly" : "list"
        options: [
            { displayName: Translation.tr("Block these apps"), value: "list" },
            { displayName: Translation.tr("Block all but these"), value: "allowOnly" }
        ]
        onPicked: v => row.patchValue({ allowOnly: v === "allowOnly" })
    }

    ChipInput {
        Layout.fillWidth: true
        values: ModeSchema.stringList(form.allowOnly ? row.obj.allow : row.obj.apps)
        placeholder: form.allowOnly ? Translation.tr("Window class that stays usable") : Translation.tr("Window class to block")
        suggestions: ModeUi.windowSuggestions()
        display: v => AppStats.displayName(v) || v
        onChanged: list => row.patchValue(form.allowOnly ? { allow: list } : { apps: list })
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledSwitch {
            checked: row.obj.strict === true
            onClicked: row.patchValue({ strict: checked })
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Ask for the PIN to get through")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ScreenTimeLimits.hasPin ? Translation.tr("Taking more time or ending the mode from the block screen needs it.")
                    : Translation.tr("No PIN yet: set one in App usage → Daily limits.")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colOnSurfaceVariant
            }
        }
    }

    FormHint {
        text: form.allowOnly
            ? Translation.tr("Any other app that opens gets the block screen until the mode ends.")
            : Translation.tr("While the mode is on, these apps get the block screen: close them, take a few minutes, or end the mode.")
    }
}
