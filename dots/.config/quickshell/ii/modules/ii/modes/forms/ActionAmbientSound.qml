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
 * Parameters of the `ambientSound` action: a catalog of YouTube ambient tracks by
 * kind, or any URL, played in the browser or as audio only. `row` is the ActionRow
 * this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    readonly property string currentId: String(row.obj.id ?? "custom")
    readonly property string player: row.obj.player === "audio" ? "audio" : "browser"
    readonly property bool custom: ModeSchema.ambientSoundById(form.currentId) === null

    function groupLabel(group) {
        switch (group) {
        case "binaural":
            return Translation.tr("Binaural beats");
        case "nature":
            return Translation.tr("Nature");
        case "noise":
            return Translation.tr("Noise");
        case "music":
            return Translation.tr("Music & radios");
        }
        return group;
    }

    function pick(id) {
        if (id === "custom") {
            row.patchValue({ id: "custom", label: "" });
            return;
        }
        row.setValue(ModeSchema.ambientSoundValue(id, form.player));
    }

    spacing: 10

    Repeater {
        model: ModeSchema.AMBIENT_GROUPS

        ColumnLayout {
            id: group
            required property string modelData
            Layout.fillWidth: true
            spacing: 4

            FormLabel {
                text: form.groupLabel(group.modelData)
            }

            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapTiny + 2

                Repeater {
                    model: ModeSchema.AMBIENT_SOUNDS.filter(s => s.group === group.modelData)

                    ClockChip {
                        required property var modelData
                        height_: 34
                        symbol: modelData.icon
                        label: modelData.label
                        selected: form.currentId === modelData.id
                        onClicked: form.pick(modelData.id)
                    }
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapTiny + 2

        ClockChip {
            height_: 34
            symbol: "link"
            label: Translation.tr("Your own link")
            selected: form.custom
            onClicked: form.pick("custom")
        }
    }

    // A link of the user's own: any page the browser (or yt-dlp) can play.
    ColumnLayout {
        Layout.fillWidth: true
        visible: form.custom
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            FormLabel {
                Layout.preferredWidth: 60
                text: Translation.tr("Link")
            }
            PlainField {
                Layout.fillWidth: true
                monospace: true
                value: String(row.obj.url ?? "")
                placeholder: "https://music.youtube.com/watch?v=…"
                onCommitted: v => row.patchValue({ url: v.trim() })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            FormLabel {
                Layout.preferredWidth: 60
                text: Translation.tr("Title")
            }
            PlainField {
                Layout.fillWidth: true
                value: String(row.obj.title ?? "")
                placeholder: Translation.tr("Words of the video title")
                onCommitted: v => row.patchValue({ title: v.trim(), label: v.trim() })
            }
        }
    }

    FormChoice {
        current: form.player
        options: [
            { displayName: Translation.tr("Open in the browser"), value: "browser" },
            { displayName: Translation.tr("Audio only"), value: "audio" }
        ]
        onPicked: v => row.patchValue({ player: v })
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SmallButton {
            buttonText: Translation.tr("Listen now")
            enabled: /^https?:\/\//i.test(String(row.obj.url ?? ""))
            onClicked: form.player === "audio"
                ? FocusTools.startAmbientAudio(row.obj.url, String(row.obj.title || row.obj.label || ""))
                : FocusTools.openAmbient(row.obj.url)
        }

        SmallButton {
            visible: form.player === "audio"
            buttonText: Translation.tr("Stop")
            onClicked: FocusTools.stopAmbientAudio()
        }
    }

    FormHint {
        text: form.player === "audio"
            ? Translation.tr("Plays in the background with mpv and yt-dlp (both must be installed), no page to wander off from. Stops when the mode ends.")
            : Translation.tr("Opens in your default browser and pauses when the mode ends. The media guard always lets it play. Binaural beats need headphones.")
    }
}
