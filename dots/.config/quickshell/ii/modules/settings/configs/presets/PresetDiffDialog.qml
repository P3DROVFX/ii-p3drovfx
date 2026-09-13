import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What a release would publish, or what an update would bring in.
 *
 * Both directions are the same list read from opposite ends, so one dialog
 * serves both and only the wording changes.
 */
WindowDialog {
    id: dialog

    property string presetName: ""
    property bool incoming: false
    property var result: null
    property bool loading: false

    readonly property var changes: dialog.result && dialog.result.ok === true
        ? (dialog.result.changes ?? []) : []
    readonly property int total: dialog.result && dialog.result.ok === true
        ? (dialog.result.total ?? 0) : 0

    preferredDialogWidth: 620
    onDismiss: dialog.show = false

    function openFor(name, wantIncoming) {
        dialog.presetName = name;
        dialog.incoming = wantIncoming === true;
        dialog.result = null;
        dialog.loading = true;
        dialog.show = true;
        PresetStore.diff(name, dialog.incoming);
    }

    Connections {
        target: PresetStore

        function onDiffReady(name, result): void {
            if (name !== dialog.presetName)
                return;
            dialog.loading = false;
            dialog.result = result;
        }
    }

    WindowDialogTitle {
        Layout.fillWidth: true
        text: dialog.incoming
            ? Translation.tr('What the update to "%1" changes').arg(dialog.presetName)
            : Translation.tr('What publishing "%1" would change').arg(dialog.presetName)
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: dialog.loading
        text: Translation.tr("Comparing…")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: !dialog.loading && dialog.result !== null && dialog.result.ok !== true
        text: dialog.result ? (dialog.result.error ?? "") : ""
        color: Appearance.colors.colError
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: !dialog.loading && dialog.result !== null && dialog.result.ok === true && dialog.total === 0
        text: dialog.incoming
            ? Translation.tr("Nothing in your settings would change.")
            : Translation.tr("Nothing has changed since the last release.")
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(320, changeColumn.implicitHeight)
        visible: dialog.total > 0
        contentHeight: changeColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: changeColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: dialog.changes

                delegate: ColumnLayout {
                    id: changeRow
                    required property var modelData
                    readonly property bool removed: changeRow.modelData.kind === "removed"
                    readonly property bool added: changeRow.modelData.kind === "added"

                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: changeRow.added ? "add" : (changeRow.removed ? "remove" : "edit")
                            iconSize: 14
                            color: changeRow.removed ? Appearance.colors.colError
                                : Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: changeRow.modelData.path
                            elide: Text.ElideLeft
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        text: {
                            if (changeRow.added)
                                return Translation.tr("added as %1").arg(changeRow.modelData.to);
                            if (changeRow.removed)
                                return Translation.tr("was %1, now gone").arg(changeRow.modelData.from);
                            return `${changeRow.modelData.from} → ${changeRow.modelData.to}`;
                        }
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: dialog.result !== null && (dialog.result.truncated ?? 0) > 0
        text: Translation.tr("and %1 more").arg(dialog.result ? dialog.result.truncated : 0)
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Close")
            onClicked: dialog.show = false
        }
    }
}
