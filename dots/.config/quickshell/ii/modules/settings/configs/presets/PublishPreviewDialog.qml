import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything publishing a preset would upload, before anything is created.
 *
 * A published repository is public from the moment the topic lands on it, and
 * the list of stripped settings is a promise that has been wrong before. So
 * the promise is made checkable here instead of described: the files, what the
 * sanitiser took out, the values that still read like an address or a command,
 * and every setting that would ship, searchable.
 */
WindowDialog {
    id: dialog

    property string presetName: ""
    property var result: null
    property bool loading: false

    readonly property bool loaded: dialog.result !== null && dialog.result.ok === true
    readonly property var entries: dialog.loaded ? (dialog.result.entries ?? []) : []
    readonly property var flagged: dialog.loaded ? (dialog.result.flagged ?? []) : []
    readonly property var dropped: dialog.loaded ? (dialog.result.dropped ?? []) : []
    readonly property var files: dialog.loaded ? (dialog.result.files ?? []) : []
    readonly property var risks: dialog.loaded ? (dialog.result.risks ?? []) : []

    // A config holds around two thousand settings. Drawing them all costs more
    // than reading them ever would, so the list is a search with a window on
    // it rather than a wall.
    readonly property int rowLimit: 200
    readonly property var matches: {
        const needle = searchField.text.trim().toLowerCase();
        if (needle.length === 0)
            return dialog.entries;
        return dialog.entries.filter(entry => entry.path.toLowerCase().includes(needle)
            || String(entry.value).toLowerCase().includes(needle));
    }
    readonly property var shownRows: dialog.matches.slice(0, dialog.rowLimit)

    // The settings window is shorter than this list on any screen, and a
    // dialog that overflows puts Close where nothing can reach it.
    readonly property real availableBodyHeight: Math.max(160, dialog.height - 200)

    preferredDialogWidth: 660
    onDismiss: dialog.show = false

    function humanSize(bytes: int): string {
        if (bytes >= 1024 * 1024)
            return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
        if (bytes >= 1024)
            return `${Math.round(bytes / 1024)} KB`;
        return `${bytes} B`;
    }

    function openFor(name) {
        dialog.presetName = name;
        dialog.result = null;
        dialog.loading = true;
        searchField.text = "";
        dialog.show = true;
        PresetStore.preview(name);
    }

    Connections {
        target: PresetStore

        function onPreviewReady(name, result): void {
            if (name !== dialog.presetName)
                return;
            dialog.loading = false;
            dialog.result = result;
        }
    }

    component SectionRow: RowLayout {
        property alias icon: rowIcon.text
        property alias iconColor: rowIcon.color
        property alias label: rowLabel.text

        Layout.fillWidth: true
        spacing: 6

        MaterialSymbol {
            id: rowIcon
            iconSize: 14
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            id: rowLabel
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    WindowDialogTitle {
        Layout.fillWidth: true
        text: Translation.tr('What publishing "%1" uploads').arg(dialog.presetName)
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: dialog.loading
        text: Translation.tr("Reading the preset…")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: !dialog.loading && dialog.result !== null && !dialog.loaded
        text: dialog.result ? (dialog.result.error ?? "") : ""
        color: Appearance.colors.colError
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(previewBody.implicitHeight, dialog.availableBodyHeight)
        visible: dialog.loaded
        contentWidth: width
        contentHeight: previewBody.implicitHeight
        clip: true

        ColumnLayout {
            id: previewBody
            width: parent.width
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                WindowDialogSectionHeader {
                    Layout.fillWidth: true
                    text: Translation.tr("Files")
                }

                Repeater {
                    model: dialog.files

                    delegate: SectionRow {
                        required property var modelData

                        icon: modelData.kind === "config" ? "description" : "image"
                        iconColor: Appearance.colors.colPrimary
                        label: `${modelData.name} — ${dialog.humanSize(modelData.bytes)}`
                    }
                }

                SectionRow {
                    icon: "photo_library"
                    label: Translation.tr("The screenshots picked in the publish window")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: dialog.dropped.length > 0

                WindowDialogSectionHeader {
                    Layout.fillWidth: true
                    text: Translation.tr("Taken out, and not uploaded")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: dialog.dropped.join("\n")
                    wrapMode: Text.Wrap
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: dialog.flagged.length > 0

                WindowDialogSectionHeader {
                    Layout.fillWidth: true
                    text: Translation.tr("Worth a second look")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("These are published as they are, and they read like "
                        + "an address, an account or a command.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: dialog.flagged

                    delegate: ColumnLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 0

                        SectionRow {
                            icon: "visibility"
                            iconColor: Appearance.colors.colOnLayer1
                            label: modelData.path
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            text: modelData.value
                            wrapMode: Text.Wrap
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: dialog.risks.length > 0

                WindowDialogSectionHeader {
                    Layout.fillWidth: true
                    text: Translation.tr("What people are warned about when they install it")
                }

                Repeater {
                    model: dialog.risks

                    delegate: SectionRow {
                        required property var modelData

                        icon: modelData.severity === "high" ? "warning" : "info"
                        iconColor: modelData.severity === "high" ? Appearance.colors.colError
                            : Appearance.colors.colOnSurfaceVariant
                        label: {
                            const names = modelData.items.map(item => item.label).join(", ");
                            return `${modelData.count} — ${names}`;
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                WindowDialogSectionHeader {
                    Layout.fillWidth: true
                    text: Translation.tr("Every setting (%1)").arg(dialog.entries.length)
                }

                MaterialTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search for a value — a city, a name, a folder…")
                }

                Repeater {
                    model: dialog.shownRows

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.preferredWidth: previewBody.width * 0.45
                            text: modelData.path
                            elide: Text.ElideLeft
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: modelData.flagged ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.value
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: dialog.matches.length === 0
                    text: Translation.tr("Nothing published matches that. Which is the answer you want.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: dialog.matches.length > dialog.rowLimit
                    text: Translation.tr("and %1 more — search to narrow it down")
                        .arg(dialog.matches.length - dialog.rowLimit)
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Close")
            onClicked: dialog.show = false
        }
    }
}
