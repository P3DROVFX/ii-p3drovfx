pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `volume` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: volumeCol
    required property var row

    spacing: 10

    readonly property bool setsLevel: row.obj.level !== null && row.obj.level !== undefined

    RowLayout {
        spacing: 12

        StyledSwitch {
            checked: volumeCol.setsLevel
            onClicked: row.patchValue({ level: checked ? 40 : null })
        }

        StyledText {
            text: Translation.tr("Set level")
            color: Appearance.colors.colOnLayer2
        }

        StyledSlider {
            id: volumeSlider
            Layout.fillWidth: true
            enabled: volumeCol.setsLevel
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
            visible: volumeCol.setsLevel
            text: `${Math.round(volumeSlider.value)} %`
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
}
