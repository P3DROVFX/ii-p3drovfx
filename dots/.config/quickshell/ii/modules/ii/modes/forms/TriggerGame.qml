pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `game` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.when
        onPicked: v => row.set({ when: v })
        options: [
            { displayName: Translation.tr("Is running"), value: "running" },
            { displayName: Translation.tr("Is focused"), value: "focused" }
        ]
    }

    // How long it keeps counting once the game is gone: survives a game
    // restarting or an alt-tab, at the cost of ending the mode later.
    RowLayout {
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            FormLabel {
                text: row.trigger.when === "focused"
                    ? Translation.tr("Ends after the game loses focus for")
                    : Translation.tr("Ends after the game is closed for")
            }

            FormHint {
                text: ModeSchema.gameOffSec(row.trigger) === 0
                    ? Translation.tr("Ends the moment the game is gone")
                    : Translation.tr("A game restarting or a quick alt-tab within that time keeps it going")
            }
        }

        DurationField {
            seconds: ModeSchema.gameOffSec(row.trigger)
            minimum: 0
            maximumHours: 1
            onCommitted: sec => row.set({ offSec: sec })
        }
    }

    FormHint {
        text: GameDetector.gameRunning
            ? Translation.tr("Detected now: %1").arg(GameDetector.reason)
            : Translation.tr("Detects Steam, Heroic, Lutris, Bottles, Prism, desktop entries in the Game "
                + "category, fullscreen Windows executables and fullscreen windows that keep the GPU busy.")
    }

    ChipInput {
        Layout.fillWidth: true
        values: Config.options.modes.game.extraClasses
        placeholder: Translation.tr("Also treat this window class as a game")
        suggestions: ModeUi.windowSuggestions()
        onChanged: list => Config.options.modes.game.extraClasses = list
    }
}
