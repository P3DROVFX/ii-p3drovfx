import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Putting a preset on GitHub for the first time.
 *
 * Two things here are deliberate. The repository is created public and topped
 * with the store's topic in one go, so nothing has to be done in a browser
 * afterwards; and the checklist spells out what is about to leave this
 * machine, because "publish" is the one button in the shell that makes a file
 * of yours permanently readable by strangers.
 */
WindowDialog {
    id: dialog

    property string presetName: ""
    property var shots: []
    property bool capturing: false
    property string captureError: ""

    readonly property bool signedIn: PresetStore.auth.authenticated === true
    readonly property bool working: PresetStore.busyFor(dialog.presetName)
    readonly property string shotDirectory:
        FileUtils.trimFileProtocol(`${Directories.state}/preset-screenshots`)

    preferredDialogWidth: 620
    onDismiss: dialog.show = false

    function openFor(name) {
        dialog.presetName = name;
        dialog.shots = [];
        dialog.captureError = "";
        repoField.text = dialog.suggestedRepoName(name);
        descriptionField.text = "";
        notesField.text = "";
        privateSwitch.checked = false;
        dialog.show = true;
        PresetStore.refreshAuth();
    }

    // Mirrors what the store itself would pick, so the field starts on the
    // name that will be used rather than on an empty box.
    function suggestedRepoName(name) {
        let slug = String(name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        return slug.length > 0 ? `ii-preset-${slug}` : "ii-preset";
    }

    function capture() {
        if (dialog.capturing)
            return;
        dialog.capturing = true;
        dialog.captureError = "";
        // The settings window is in front of everything worth photographing.
        // Hiding it keeps the page and this dialog alive — the window is only
        // unloaded seconds later, and reopening stops that timer.
        GlobalStates.settingsOpen = false;
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        // Long enough for the window to be gone from the screen before grim
        // reads it, short enough not to feel like a countdown.
        interval: 500
        repeat: false
        onTriggered: {
            let monitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            let target = `${dialog.shotDirectory}/${Date.now()}.png`;
            // Without a monitor grim composites every output into one huge
            // picture, which is nobody's idea of a screenshot.
            let onScreen = monitor.length > 0
                ? `-o '${StringUtils.shellSingleQuoteEscape(monitor)}' ` : "";
            captureProc.target = target;
            captureProc.command = ["bash", "-c",
                `mkdir -p '${StringUtils.shellSingleQuoteEscape(dialog.shotDirectory)}' && `
                + `exec grim ${onScreen}'${StringUtils.shellSingleQuoteEscape(target)}'`];
            captureProc.running = true;
        }
    }

    Process {
        id: captureProc
        property string target: ""

        stderr: StdioCollector {}

        onExited: (code, status) => {
            dialog.capturing = false;
            GlobalStates.settingsOpen = true;
            if (code !== 0) {
                dialog.captureError = Translation.tr("The screenshot could not be taken. Is grim installed?");
                return;
            }
            dialog.shots = dialog.shots.concat([captureProc.target]);
        }
    }

    WindowDialogTitle {
        Layout.fillWidth: true
        text: Translation.tr('Publish "%1"').arg(dialog.presetName)
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("This creates a repository on your GitHub account, tags it so the store can find it, and pushes the preset. Anyone will be able to install it.")
    }

    GithubSignInPanel {
        Layout.fillWidth: true
    }

    MaterialTextField {
        id: repoField
        Layout.fillWidth: true
        visible: dialog.signedIn
        placeholderText: Translation.tr("Repository name")
        error: repoField.text.length > 0 && !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(repoField.text)
    }

    MaterialTextField {
        id: descriptionField
        Layout.fillWidth: true
        visible: dialog.signedIn
        placeholderText: Translation.tr("What does it look like? (optional)")
    }

    MaterialTextField {
        id: notesField
        Layout.fillWidth: true
        visible: dialog.signedIn
        placeholderText: Translation.tr("Release notes (optional)")
    }

    // ── Screenshots ──────────────────────────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: dialog.signedIn

        WindowDialogSectionHeader {
            Layout.fillWidth: true
            text: Translation.tr("Screenshots")
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Taking one hides this window, photographs your screen and brings it back. They are the only pictures people see before installing.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }

        Row {
            Layout.fillWidth: true
            spacing: 8
            visible: dialog.shots.length > 0

            Repeater {
                model: dialog.shots

                delegate: Rectangle {
                    id: shotFrame
                    required property string modelData
                    required property int index

                    width: 120
                    height: 72
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh

                    StyledImage {
                        id: shotImage
                        anchors.fill: parent
                        source: `file://${shotFrame.modelData}`
                        fillMode: Image.PreserveAspectCrop
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: shotImage.width
                                height: shotImage.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }

                    RippleButton {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        colRipple: Appearance.colors.colErrorActive

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colOnError
                        }

                        onClicked: dialog.shots = dialog.shots.filter((path, i) => i !== shotFrame.index)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "photo_camera"
                mainText: dialog.capturing ? Translation.tr("Hold still…")
                    : (dialog.shots.length === 0 ? Translation.tr("Take a screenshot")
                        : Translation.tr("Take another"))
                enabled: !dialog.capturing && dialog.shots.length < 6
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: dialog.capture()
            }

            StyledText {
                Layout.fillWidth: true
                visible: dialog.captureError.length > 0
                text: dialog.captureError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
        }
    }

    // ── What actually leaves this machine ────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: dialog.signedIn

        WindowDialogSectionHeader {
            Layout.fillWidth: true
            text: Translation.tr("What gets published")
        }

        Repeater {
            model: [
                { "ok": true, "label": Translation.tr("Your settings, with keys, tokens, folders and monitor names stripped out") },
                { "ok": true, "label": Translation.tr("The wallpaper and the sidebar banner, if this preset has them") },
                { "ok": true, "label": Translation.tr("The screenshots you took above") },
                { "ok": false, "label": Translation.tr("Your profile picture, name and greeting — never") },
                { "ok": false, "label": Translation.tr("API keys, saved networks, paired devices and contacts — never") }
            ]

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: modelData.ok ? "check" : "block"
                    iconSize: 15
                    color: modelData.ok ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: modelData.label
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: dialog.signedIn
        spacing: 8

        StyledSwitch {
            id: privateSwitch
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Keep the repository private. Nobody can install it, including you on another machine.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: dialog.show = false
        }

        DialogButton {
            buttonText: dialog.working ? Translation.tr("Publishing…") : Translation.tr("Publish")
            enabled: dialog.signedIn && !dialog.working && !dialog.capturing
                && repoField.text.length > 0 && !repoField.error
            onClicked: {
                PresetStore.publish(dialog.presetName, repoField.text, descriptionField.text,
                    notesField.text, privateSwitch.checked, dialog.shots);
                dialog.show = false;
            }
        }
    }
}
