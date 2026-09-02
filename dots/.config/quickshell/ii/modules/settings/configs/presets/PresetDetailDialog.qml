import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything a repository says about itself, before anything is installed.
 *
 * The search result is shown the moment it opens and the manifest fills the
 * rest in when it arrives — a sheet that waited for the network would be blank
 * for as long as GitHub takes to answer.
 */
WindowDialog {
    id: dialog

    property var entry: null
    property var manifest: null
    property var compatibility: null
    property string loadError: ""
    property bool loading: false

    readonly property string repo: dialog.entry ? (dialog.entry.repo ?? "") : ""
    readonly property string installedAs: dialog.entry ? (dialog.entry.installedAs ?? "") : ""
    readonly property bool blocked: dialog.compatibility !== null && dialog.compatibility.ok === false
    // The card that opened this dialog offers an update; the dialog has to be
    // able to act on it, or the store advertises something with no way to take
    // it. `updateFor` reads git, so it stays right even while the raw manifest
    // GitHub serves is still a few minutes out of date.
    readonly property var pending: dialog.installedAs.length > 0
        ? PresetStore.updateFor(dialog.installedAs) : null
    readonly property bool hasUpdate: dialog.pending !== null

    signal installRequested(string repo)
    signal updateRequested(string name)

    preferredDialogWidth: 620
    onDismiss: dialog.show = false

    function openFor(result) {
        dialog.entry = result;
        dialog.manifest = null;
        dialog.compatibility = null;
        dialog.loadError = "";
        dialog.loading = true;
        dialog.show = true;
        PresetStore.fetchManifest(result.repo);
    }

    Connections {
        target: PresetStore

        function onManifestReady(repo, result): void {
            if (repo !== dialog.repo)
                return;
            dialog.loading = false;
            if (result.ok !== true) {
                dialog.loadError = result.error ?? "";
                return;
            }
            dialog.manifest = result.manifest;
            dialog.compatibility = result.compatibility;
        }
    }

    WindowDialogTitle {
        Layout.fillWidth: true
        // The manifest names the preset; the search result only knows what the
        // repository is called. Prefer the name once it has been read.
        text: (dialog.manifest && (dialog.manifest.name ?? "").length > 0)
            ? dialog.manifest.name : (dialog.entry ? (dialog.entry.name ?? "") : "")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            text: Translation.tr("by %1").arg(dialog.entry ? (dialog.entry.author ?? "") : "")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            visible: dialog.manifest !== null
            // The manifest comes from GitHub's raw CDN, which lags a few minutes
            // behind a fresh release; the pending entry was read from git.
            text: dialog.hasUpdate
                ? Translation.tr("version %1").arg(dialog.pending.availableVersion ?? "")
                : (dialog.manifest ? Translation.tr("version %1").arg(dialog.manifest.version) : "")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            text: Translation.tr("%1 ★").arg(dialog.entry ? (dialog.entry.stars ?? 0) : 0)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }

        Item { Layout.fillWidth: true }

        StyledText {
            visible: dialog.loading
            text: Translation.tr("Reading the preset…")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: {
            if (dialog.manifest && (dialog.manifest.description ?? "").length > 0)
                return dialog.manifest.description;
            if (dialog.entry && (dialog.entry.description ?? "").length > 0)
                return dialog.entry.description;
            return Translation.tr("No description.");
        }
    }

    // Screenshots come from the repository over the network, so the strip is
    // only there once at least one of them has actually been named.
    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: 170
        visible: dialog.manifest !== null && (dialog.manifest.screenshotUrls ?? []).length > 0
        contentWidth: shotRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        Row {
            id: shotRow
            height: parent.height
            spacing: 10

            Repeater {
                model: dialog.manifest ? (dialog.manifest.screenshotUrls ?? []) : []

                delegate: Rectangle {
                    id: shotFrame
                    required property string modelData

                    width: 270
                    height: 160
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh

                    StyledImage {
                        id: shot
                        anchors.fill: parent
                        source: shotFrame.modelData
                        fillMode: Image.PreserveAspectCrop
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: shot.width
                                height: shot.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: dialog.blocked
        materialIcon: "block"
        text: dialog.compatibility && dialog.compatibility.reason
            ? dialog.compatibility.reason
            : Translation.tr("This preset was made for a newer version of the shell.")
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: dialog.loadError.length > 0
        materialIcon: "error"
        text: dialog.loadError
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: dialog.manifest !== null && (dialog.manifest.changelog ?? []).length > 0

        WindowDialogSectionHeader {
            Layout.fillWidth: true
            text: Translation.tr("What changed")
        }

        Repeater {
            // What is actually coming, when something is: the pending entry
            // holds only the releases newer than the installed one.
            model: dialog.hasUpdate ? (dialog.pending.changelog ?? []).slice(0, 3)
                : (dialog.manifest ? (dialog.manifest.changelog ?? []).slice(0, 3) : [])

            delegate: StyledText {
                required property var modelData

                Layout.fillWidth: true
                text: (modelData.notes ?? "").length > 0
                    ? `${modelData.version} — ${modelData.notes}`
                    : Translation.tr("%1 — no notes given").arg(modelData.version)
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("Installing only puts the preset in your list. Nothing changes until you apply it.")
        font.italic: true
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Open on GitHub")
            onClicked: {
                let url = dialog.entry ? (dialog.entry.repoUrl ?? "") : "";
                if (url.length > 0)
                    Quickshell.execDetached(["xdg-open", url]);
            }
        }

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Close")
            onClicked: dialog.show = false
        }

        DialogButton {
            buttonText: dialog.hasUpdate ? Translation.tr("Update")
                : (dialog.installedAs.length > 0 ? Translation.tr("Installed") : Translation.tr("Install"))
            enabled: !dialog.blocked && !PresetStore.busyFor(dialog.repo)
                && !PresetStore.busyFor(dialog.installedAs)
                && (dialog.installedAs.length === 0 || dialog.hasUpdate)
            onClicked: {
                if (dialog.hasUpdate)
                    dialog.updateRequested(dialog.installedAs);
                else
                    dialog.installRequested(dialog.repo);
                dialog.show = false;
            }
        }
    }
}
