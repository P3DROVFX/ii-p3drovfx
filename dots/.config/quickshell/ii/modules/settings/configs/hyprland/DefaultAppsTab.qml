pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Default apps.
 *
 * Shortcut targets and desktop defaults answer adjacent but different questions: a shortcut can
 * have portable command fallbacks, while an XDG association is a desktop-file id consumed by
 * xdg-open and portals. Keeping both here makes the relationship clear without pretending that
 * changing one silently changes the other.
 */
ContentPage {
    id: tab

    forceWidth: false

    readonly property bool advanced: Config.options.hyprland.advancedSettings

    readonly property var shellApps: [
        { "key": "terminal", "icon": "terminal", "label": Translation.tr("Terminal for shell actions") },
        { "key": "network", "icon": "wifi", "label": Translation.tr("Network settings") },
        { "key": "networkEthernet", "icon": "settings_ethernet", "label": Translation.tr("Wired network settings") },
        { "key": "bluetooth", "icon": "bluetooth", "label": Translation.tr("Bluetooth settings") },
        { "key": "volumeMixer", "icon": "volume_up", "label": Translation.tr("Volume mixer") },
        { "key": "taskManager", "icon": "monitoring", "label": Translation.tr("Task manager") },
        { "key": "manageUser", "icon": "person", "label": Translation.tr("User accounts") },
        { "key": "changePassword", "icon": "password", "label": Translation.tr("Change password") },
        { "key": "update", "icon": "system_update", "label": Translation.tr("System update") }
    ]

    function openSubPage(page: url) {
        let node = tab.parent;
        while (node) {
            if (typeof node.activeSubPage !== "undefined") {
                node.activeSubPage = page;
                return;
            }
            node = node.parent;
        }
    }

    function editShortcutApp(name: string) {
        HyprlandBinds.beginEditApp(name);
        tab.openSubPage(Qt.resolvedUrl("HyprAppChainPage.qml"));
    }

    function editSystemApp(id: string) {
        DefaultApps.beginEdit(id);
        tab.openSubPage(Qt.resolvedUrl("DefaultAppPickerPage.qml"));
    }

    Component.onCompleted: DefaultApps.refresh()

    // ── Shortcut targets ─────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Apps these shortcuts open")
        icon: "apps"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Shortcuts try these commands in order. The first one installed is the one that opens, so your config still works when a preferred app is unavailable.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: HyprlandBinds.appVariables

            delegate: HyprNavRow {
                required property var modelData

                readonly property var chain: HyprlandBinds.readChain(HyprlandBinds.appValue(modelData.name))
                readonly property string winner: HyprlandBinds.winningCandidate(chain.candidates)
                readonly property string selectedCommand: chain.chain ? winner : chain.plain

                buttonIcon: modelData.icon
                appIcon: selectedCommand === "" ? "" : AppSearch.guessIcon(HyprlandBinds.probeWord(selectedCommand))
                text: modelData.label
                value: {
                    if (!chain.chain)
                        return chain.plain;
                    if (winner !== "")
                        return winner;
                    return chain.candidates.length === 0 ? Translation.tr("Empty")
                        : Translation.tr("None installed");
                }
                onOpenSubPage: tab.editShortcutApp(modelData.name)
            }
        }

        HyprOptionNote {
            notes: {
                const out = [];
                const changed = HyprlandBinds.appVariables
                    .filter(variable => HyprlandBinds.appSource(variable.name) === "managed");
                if (changed.length > 0)
                    out.push({ "icon": "edit", "text": Translation.tr("%1 of these are set by this page.").arg(String(changed.length)) });
                const unavailable = HyprlandBinds.appVariables.filter(variable => {
                    const chain = HyprlandBinds.readChain(HyprlandBinds.appValue(variable.name));
                    return chain.chain && HyprlandBinds.winningCandidate(chain.candidates) === "";
                });
                if (unavailable.length > 0)
                    out.push({ "icon": "warning", "text": Translation.tr("%1 of them have nothing installed, so their shortcut does nothing when pressed.").arg(String(unavailable.length)) });
                return out;
            }
        }
    }

    // ── XDG defaults ─────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("System default applications")
        icon: "app_settings_alt"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("These are the applications the rest of your desktop opens for links and files. Choose a row to select any installed application.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DefaultApps.errorMessage !== ""
            materialIcon: "error"
            text: DefaultApps.errorMessage
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DefaultApps.statusMessage !== ""
            materialIcon: "check_circle"
            text: DefaultApps.statusMessage
        }

        Repeater {
            model: DefaultApps.categories

            delegate: HyprNavRow {
                required property var modelData

                buttonIcon: modelData.icon
                appIcon: DefaultApps.appIcon(modelData.id)
                text: modelData.label
                description: modelData.description
                value: DefaultApps.appName(modelData.id)
                enabled: !DefaultApps.updating
                onOpenSubPage: tab.editSystemApp(modelData.id)
            }
        }

        HyprOptionNote {
            notes: [{ "icon": "info", "text": Translation.tr("Changes are made with the XDG desktop association, so they apply immediately to xdg-open, file managers, portals and other desktop applications.") }]
        }
    }

    // ── Shell actions ────────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Apps the shell opens")
        icon: "widgets"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("These are the commands behind buttons in the shell, such as the Wi-Fi settings link and the volume mixer. They are separate from XDG defaults and take effect as soon as they are changed.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: tab.shellApps

            delegate: ConfigTextField {
                id: shellAppField

                required property var modelData

                Layout.fillWidth: true
                textField.wrapMode: TextInput.NoWrap
                icon: modelData.icon
                text: modelData.label
                inputText: String(Config.options.apps[modelData.key] ?? "")
                textField.onEditingFinished: Config.options.apps[shellAppField.modelData.key]
                    = shellAppField.textField.text
            }
        }
    }

    ContentSection {
        title: Translation.tr("Related settings")
        icon: "link"

        Flow {
            Layout.fillWidth: true
            spacing: 6

            RelatedChip {
                pageId: "cheatSheet"
                label: Translation.tr("Cheatsheet")
            }
        }
    }
}
