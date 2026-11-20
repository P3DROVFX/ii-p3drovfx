pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `mediaGuard` action: what may keep playing while the mode is
 * on. `row` is the ActionRow this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    readonly property var playerSuggestions: {
        const out = ModeSchema.DEFAULT_ALLOWED_PLAYERS.map(n => ({ label: n, value: n }));
        for (const p of Array.from(Mpris.players?.values ?? [])) {
            const name = String(p?.identity ?? "");
            if (name.length > 0 && !out.some(o => o.value === name))
                out.push({ label: name, value: name });
        }
        return out;
    }

    spacing: 8

    FormLabel {
        text: Translation.tr("Players that may play")
    }

    ChipInput {
        Layout.fillWidth: true
        values: ModeSchema.stringList(row.obj.allowPlayers)
        placeholder: Translation.tr("Player name, as in the media controls")
        suggestions: form.playerSuggestions
        pickTitle: Translation.tr("Players")
        onChanged: list => row.patchValue({ allowPlayers: list })
    }

    FormLabel {
        text: Translation.tr("Tracks that may play")
    }

    ChipInput {
        Layout.fillWidth: true
        values: ModeSchema.stringList(row.obj.allowTitles)
        placeholder: Translation.tr("Words of a track or video title")
        onChanged: list => row.patchValue({ allowTitles: list })
    }

    FormHint {
        text: Translation.tr("Anything else that starts playing is paused with a notification. The mode's ambient sound always plays. A browser counts as a player: allow it by name and every tab may play.")
    }
}
