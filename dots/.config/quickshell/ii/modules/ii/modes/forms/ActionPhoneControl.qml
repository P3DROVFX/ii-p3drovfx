pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `phoneControl` action: something the phone does by itself, over ii
 * tools. `row` is the ActionRow this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: ctl
    required property var row

    spacing: 10

    readonly property string kind: String(row.obj.kind ?? "dnd")

    FormChoice {
        current: ctl.kind
        onPicked: v => row.setValue(ModeUi.phoneControlDefault(v))
        options: [
            { displayName: Translation.tr("Do Not Disturb"), value: "dnd" },
            { displayName: Translation.tr("Ringer"), value: "ringer" },
            { displayName: Translation.tr("Volume"), value: "volume" },
            { displayName: Translation.tr("Flashlight"), value: "torch" },
            { displayName: Translation.tr("Brightness"), value: "brightness" },
            { displayName: Translation.tr("Auto-rotate"), value: "rotate" },
            { displayName: Translation.tr("Media"), value: "media" },
            { displayName: Translation.tr("Notification"), value: "notify" },
            { displayName: Translation.tr("Speak"), value: "speak" },
            { displayName: Translation.tr("Vibrate"), value: "vibrate" },
            { displayName: Translation.tr("Make it ring"), value: "ring" }
        ]
    }

    FormChoice {
        visible: ["dnd", "torch"].indexOf(ctl.kind) !== -1
        current: row.obj.on === false ? "off" : "on"
        onPicked: v => row.patchValue({ on: v === "on" })
        options: [
            { displayName: Translation.tr("On"), value: "on" },
            { displayName: Translation.tr("Off"), value: "off" }
        ]
    }

    FormChoice {
        visible: ctl.kind === "rotate"
        current: row.obj.auto === false ? "off" : "on"
        onPicked: v => row.patchValue({ auto: v === "on" })
        options: [
            { displayName: Translation.tr("Rotate with the phone"), value: "on" },
            { displayName: Translation.tr("Lock to portrait"), value: "off" }
        ]
    }

    FormChoice {
        visible: ctl.kind === "ringer"
        current: String(row.obj.mode ?? "normal")
        onPicked: v => row.patchValue({ mode: v })
        options: [
            { displayName: Translation.tr("Sound"), value: "normal" },
            { displayName: Translation.tr("Vibrate"), value: "vibrate" },
            { displayName: Translation.tr("Silent"), value: "silent" }
        ]
    }

    FormChoice {
        visible: ctl.kind === "volume"
        current: String(row.obj.stream ?? "media")
        onPicked: v => row.patchValue({ stream: v })
        options: [
            { displayName: Translation.tr("Media"), value: "media" },
            { displayName: Translation.tr("Ringtone"), value: "ring" },
            { displayName: Translation.tr("Alarm"), value: "alarm" },
            { displayName: Translation.tr("Calls"), value: "call" }
        ]
    }

    RowLayout {
        visible: ctl.kind === "volume" || (ctl.kind === "brightness" && row.obj.auto !== true)
        spacing: 10

        FormLabel {
            text: ctl.kind === "volume" ? Translation.tr("Volume") : Translation.tr("Brightness")
        }

        PercentField {
            value: row.obj.level ?? 50
            onCommitted: v => row.patchValue({ level: v === null ? 50 : v })
        }
    }

    FormChoice {
        visible: ctl.kind === "brightness"
        current: row.obj.auto === true ? "auto" : "manual"
        onPicked: v => row.patchValue({ auto: v === "auto" })
        options: [
            { displayName: Translation.tr("A level"), value: "manual" },
            { displayName: Translation.tr("Adaptive"), value: "auto" }
        ]
    }

    FormChoice {
        visible: ctl.kind === "media"
        current: String(row.obj.cmd ?? "pause")
        onPicked: v => row.patchValue({ cmd: v })
        options: [
            { displayName: Translation.tr("Pause"), value: "pause" },
            { displayName: Translation.tr("Play"), value: "play" },
            { displayName: Translation.tr("Next"), value: "next" },
            { displayName: Translation.tr("Previous"), value: "previous" }
        ]
    }

    PlainField {
        Layout.fillWidth: true
        visible: ctl.kind === "notify"
        value: String(row.obj.title ?? "")
        placeholder: Translation.tr("Title")
        onCommitted: v => row.patchValue({ title: v })
    }

    PlainField {
        Layout.fillWidth: true
        visible: ctl.kind === "notify" || ctl.kind === "speak"
        value: String(row.obj.text ?? "")
        placeholder: ctl.kind === "speak" ? Translation.tr("What the phone says") : Translation.tr("Text")
        onCommitted: v => row.patchValue({ text: v })
    }

    FormHint {
        text: IiLinkService.phoneControlDev !== ""
            ? Translation.tr("Done by the ii tools app on the phone, within the permissions you gave it.")
            : Translation.tr("Needs an ii tools phone that is reachable; skipped otherwise.")
    }
}
