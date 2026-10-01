import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Settings for Modes & Routines: only whether automatic starts happen and
 * whether the app (Super + Y) loads. Everything else lives in the app's
 * own settings, at the foot of its rail.
 */
ContentPage {
    id: page
    forceWidth: false

    readonly property var opts: Config.options.modes

    // The shortcut is bound in the Hyprland config, which the shell's own
    // update never touches — so it can be missing on an otherwise current
    // install and the app simply never opens.
    property bool keybindChecked: false
    property bool keybindFound: true

    Process {
        id: keybindProbe
        running: true
        // `hyprctl binds` shows "__lua" for every bind under the Lua config,
        // so the config text is read instead; -s keeps a missing dir quiet.
        command: ["grep", "-rqsF", "quickshell:modesToggle", `${FileUtils.trimFileProtocol(Directories.config)}/hypr`]
        onExited: (code, status) => {
            page.keybindFound = (code === 0);
            page.keybindChecked = true;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        WarningBox {
            Layout.fillWidth: true
            visible: page.opts.overlayEnabled && page.keybindChecked && !page.keybindFound
            materialIcon: "keyboard_off"
            text: Translation.tr("Hyprland has no binding for the app, so Super + Y does nothing. "
                + "Re-run the setup script with --hypr to install the Hyprland config, "
                + "or bind quickshell:modesToggle yourself.")
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            visible: page.opts.overlayEnabled
            text: Translation.tr("Open the Modes & Routines manager")
            keys: ["Super", "Y"]
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "tune"
            text: {
                const modes = Modes.modes.length;
                const routines = Modes.routines.length;
                const line = Translation.tr("%1 mode(s) and %2 routine(s) set up.").arg(modes).arg(routines);
                if (Modes.active)
                    return line + " " + Translation.tr("%1 is on right now.").arg((Modes.activeMode && Modes.activeMode.name) ? Modes.activeMode.name : "");
                return line + " " + Translation.tr("Nothing is on right now.");
            }

            RippleButton {
                id: openButton
                implicitHeight: 34
                horizontalPadding: 16
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                enabled: page.opts.overlayEnabled
                opacity: enabled ? 1 : 0.5
                onClicked: GlobalStates.openModesApp("")

                contentItem: StyledText {
                    text: Translation.tr("Open the app")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("General")
        icon: "tune"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Start and end things automatically")
                checked: page.opts.enable
                onCheckedChanged: {
                    Config.options.modes.enable = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Off: conditions are ignored everywhere. Modes and routines still work "
                        + "when you start them yourself, and whatever is on stays on")
                }
            }

            ConfigSwitch {
                buttonIcon: "dashboard"
                text: Translation.tr("Load the Modes & Routines app")
                checked: page.opts.overlayEnabled
                onCheckedChanged: {
                    Config.options.modes.overlayEnabled = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Super + Y, the bar pill and the sidebar toggle all open it. "
                        + "Off saves a little memory; the engine keeps running")
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "settings"
        text: Translation.tr("Everything else lives in the manager, behind the gear next to its close button: where the active mode shows, automatic ends, game detection, presets and the activity log.")
    }
}
