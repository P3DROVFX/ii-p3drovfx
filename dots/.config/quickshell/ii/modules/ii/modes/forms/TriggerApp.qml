pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `app` condition. `row` is the TriggerRow this form
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

    ChipInput {
        Layout.fillWidth: true
        values: row.trigger.classes
        placeholder: Translation.tr("Window class, e.g. zen or steam_app_.*")
        suggestions: ModeUi.windowSuggestions()
        onChanged: list => row.set({ classes: list })
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            text: Translation.tr("Title contains")
        }

        PlainField {
            Layout.fillWidth: true
            value: row.trigger.title ?? ""
            placeholder: Translation.tr("Optional — \"YouTube\" catches it in any browser")
            onCommitted: v => row.set({ title: v })
        }
    }

    FormHint {
        text: Translation.tr("A plain name matches the class exactly (case-insensitive); "
            + "anything with regex characters is a regular expression. "
            + "With no class, the title alone decides.")
    }
}
