pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `appVolume` action: which app, and what to do to its
 * streams. `row` is the ActionRow this form unfolds from; every change
 * goes back through it.
 */
ColumnLayout {
    id: appCol
    required property var row

    spacing: 10

    readonly property bool setsLevel: row.obj.level !== null && row.obj.level !== undefined
    // Apps with a stream open right now, as quick picks.
    readonly property var playing: {
        const names = new Set();
        for (const n of Array.from(Audio.outputAppNodes)) {
            const name = Audio.appNodeDisplayName(n);
            if (name)
                names.add(name);
        }
        return Array.from(names).sort();
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        FormLabel {
            text: Translation.tr("App")
        }

        PlainField {
            Layout.fillWidth: true
            value: String(row.obj.app ?? "")
            placeholder: Translation.tr("part of its name, e.g. spotify")
            onCommitted: v => row.patchValue({ app: v })
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: appCol.playing.length > 0
        spacing: 6

        Repeater {
            model: appCol.playing

            delegate: SmallButton {
                required property string modelData
                buttonText: modelData
                onClicked: row.patchValue({ app: modelData })
            }
        }
    }

    RowLayout {
        spacing: 12

        StyledSwitch {
            checked: appCol.setsLevel
            onClicked: row.patchValue({ level: checked ? 40 : null })
        }

        StyledText {
            text: Translation.tr("Set level")
            color: Appearance.colors.colOnLayer2
        }

        StyledSlider {
            id: levelSlider
            Layout.fillWidth: true
            enabled: appCol.setsLevel
            opacity: enabled ? 1 : 0.4
            from: 0
            to: 100
            stepSize: 1
            value: Number(row.obj.level) || 0
            onPressedChanged: {
                if (!pressed)
                    row.patchValue({ level: Math.round(value) });
            }
        }

        StyledText {
            visible: appCol.setsLevel
            text: `${Math.round(levelSlider.value)} %`
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer2
        }
    }

    FormChoice {
        current: row.obj.muted === true ? "mute" : (row.obj.muted === false ? "unmute" : "keep")
        onPicked: v => row.patchValue({ muted: v === "keep" ? null : v === "mute" })
        options: [
            { displayName: Translation.tr("Leave mute as is"), value: "keep" },
            { displayName: Translation.tr("Mute"), value: "mute" },
            { displayName: Translation.tr("Unmute"), value: "unmute" }
        ]
    }

    FormHint {
        text: Translation.tr("Applies to every stream of the app that is open when the action runs; "
            + "skipped when it is not playing")
    }
}
