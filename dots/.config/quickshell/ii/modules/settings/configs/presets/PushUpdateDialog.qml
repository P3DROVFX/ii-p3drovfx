import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Releasing what your settings have become.
 *
 * The preset is re-exported from the live configuration on the way out, so
 * there is nothing to save first — which also means the honest question before
 * pressing this is what actually changed, and that is one button away.
 */
WindowDialog {
    id: dialog

    property string presetName: ""
    property string bump: "patch"
    readonly property bool working: PresetStore.busyFor(dialog.presetName)
    readonly property var link: PresetStore.linkFor(dialog.presetName)

    signal diffRequested(string name)

    preferredDialogWidth: 560
    onDismiss: dialog.show = false

    function openFor(name) {
        dialog.presetName = name;
        dialog.bump = "patch";
        notesField.text = "";
        dialog.show = true;
    }

    WindowDialogTitle {
        Layout.fillWidth: true
        text: Translation.tr('Release an update to "%1"').arg(dialog.presetName)
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: dialog.link
            ? Translation.tr("Published as %1, currently at version %2. Your settings are exported again, stripped of anything personal, and pushed.")
                .arg(dialog.link.repo).arg(dialog.link.version)
            : Translation.tr("Your settings are exported again, stripped of anything personal, and pushed.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        WindowDialogSectionHeader {
            Layout.fillWidth: true
            text: Translation.tr("How big a change is it?")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { "id": "patch", "label": Translation.tr("A fix") },
                    { "id": "minor", "label": Translation.tr("Something new") },
                    { "id": "major", "label": Translation.tr("A different look") }
                ]

                delegate: RippleButtonWithIcon {
                    required property var modelData
                    readonly property bool picked: dialog.bump === modelData.id

                    materialIcon: picked ? "radio_button_checked" : "radio_button_unchecked"
                    mainText: modelData.label
                    colBackground: picked ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2
                    colBackgroundHover: picked ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer2Hover
                    colRipple: picked ? Appearance.colors.colPrimaryContainerActive
                        : Appearance.colors.colLayer2Active
                    colText: picked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                    onClicked: dialog.bump = modelData.id
                }
            }
        }
    }

    MaterialTextField {
        id: notesField
        Layout.fillWidth: true
        placeholderText: Translation.tr("What changed? (optional)")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("Leaving this empty is fine — the version and the date are already recorded.")
        font.italic: true
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Show diff")
            onClicked: dialog.diffRequested(dialog.presetName)
        }

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: dialog.show = false
        }

        DialogButton {
            buttonText: dialog.working ? Translation.tr("Pushing…") : Translation.tr("Push update")
            enabled: !dialog.working
            onClicked: {
                PresetStore.pushUpdate(dialog.presetName, dialog.bump, notesField.text, "");
                dialog.show = false;
            }
        }
    }
}
