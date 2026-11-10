pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 * Resolve the configured code by active_layout_index, not by the display name:
 * custom kb_file keymaps can name their groups outside the standard XKB catalogue.
 *
 * It only reports. It used to also write the layout into the on-screen keyboard's config on every
 * switch, which meant the keyboard could never be pinned to a layout and the config file carried a
 * value nobody chose; the keyboard reads this service directly instead.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property list<string> layoutVariants: []
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    /**
     * The keyboard Hyprland reports as main, set before `currentLayoutName`. The main one is
     * whichever was added or used last, so a headset's AVRCP device taking it changes the
     * layout name without anyone switching layouts.
     */
    property string mainKeyboardName: ""
    readonly property string currentLayoutCode: activeLayoutCode || cachedLayoutCodes[currentLayoutName] || ""
    property string activeLayoutCode: ""
    property int activeLayoutIndex: -1
    /**
     * "code|variant" -> base.lst description for the configured layouts. Empty until a UI asks
     * with `requestLayoutDescriptions()`; the bar indicator never needs it.
     */
    property var layoutDescriptions: ({})
    property string _describedKey: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool needsLayoutRefresh: false

    // Older Hyprland versions omit active_layout_index; only those need the name lookup.
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (!root.activeLayoutCode && root.currentLayoutName
                && !Object.prototype.hasOwnProperty.call(root.cachedLayoutCodes, root.currentLayoutName))
            getLayoutProc.running = true;
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes = Object.assign({}, root.cachedLayoutCodes, { [targetDescription]: matchLayout[1] });
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes = Object.assign({}, root.cachedLayoutCodes, { [targetDescription]: complexLayout });
                        return true;
                    }
                    
                    return false;
                });
            }
        }
    }

    // Read one coherent snapshot: events from another keyboard must not overwrite the main layout.
    Process {
        id: fetchLayoutsProc
        running: true
        command: ["hyprctl", "-j", "devices"]
        onExited: {
            if (root.needsLayoutRefresh)
                layoutRefresh.restart();
        }

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                let parsedOutput;
                try {
                    parsedOutput = JSON.parse(devicesCollector.text);
                } catch (error) {
                    console.warn("[HyprlandXkb] Could not parse Hyprland devices:", error);
                    return;
                }

                const hyprlandKeyboard = (parsedOutput["keyboards"] ?? [])
                    .find(kb => kb.main === true);
                const layoutValue = String(hyprlandKeyboard?.layout ?? "");
                const variantValue = String(hyprlandKeyboard?.variant ?? "");
                root.layoutCodes = layoutValue.length > 0 ? layoutValue.split(",").map(code => code.trim()) : [];
                root.layoutVariants = variantValue.length > 0 ? variantValue.split(",").map(variant => variant.trim()) : [];
                const index = hyprlandKeyboard?.active_layout_index;
                root.activeLayoutIndex = Number.isInteger(index) && index >= 0 ? index : -1;
                root.activeLayoutCode = root.activeLayoutIndex >= 0 ? (root.layoutCodes[index] ?? "") : "";
                root.mainKeyboardName = String(hyprlandKeyboard?.name ?? "");
                root.currentLayoutName = String(hyprlandKeyboard?.active_keymap ?? "");
                root.updateLayoutCode();
            }
        }
    }

    function descriptionFor(index) {
        const key = (root.layoutCodes[index] ?? "") + "|" + (root.layoutVariants[index] ?? "");
        return root.layoutDescriptions[key] ?? "";
    }

    function requestLayoutDescriptions() {
        const key = root.layoutCodes.join(",") + "/" + root.layoutVariants.join(",");
        if (root.layoutCodes.length === 0 || key === root._describedKey || describeProc.running)
            return;
        root._describedKey = key;
        describeProc.running = true;
    }

    // One read of base.lst, keeping only the configured layouts. Layout lines are "  br  Portuguese
    // (Brazil)", variant lines "  intl  us: English (US, intl., with dead keys)".
    Process {
        id: describeProc
        command: ["cat", root.baseLayoutFilePath]
        stdout: StdioCollector {
            id: describeCollector
            onStreamFinished: {
                const wanted = {};
                for (let i = 0; i < root.layoutCodes.length; i++)
                    wanted[root.layoutCodes[i] + "|" + (root.layoutVariants[i] ?? "")] = true;
                const found = {};
                let section = "";
                for (const line of describeCollector.text.split("\n")) {
                    if (line.startsWith("!")) {
                        section = line.slice(1).trim();
                        continue;
                    }
                    if (section === "layout") {
                        const m = line.match(/^\s*(\S+)\s+(.+)$/);
                        if (m && wanted[m[1] + "|"])
                            found[m[1] + "|"] = m[2].trim();
                    } else if (section === "variant") {
                        const m = line.match(/^\s*(\S+)\s+(\S+):\s+(.+)$/);
                        if (m && wanted[m[2] + "|" + m[1]])
                            found[m[2] + "|" + m[1]] = m[3].trim();
                    }
                }
                root.layoutDescriptions = found;
            }
        }
    }

    // Coalesce switchxkblayout all's per-device events. No polling or persistent process.
    Timer {
        id: layoutRefresh
        interval: 50
        onTriggered: {
            if (fetchLayoutsProc.running)
                return;
            root.needsLayoutRefresh = false;
            fetchLayoutsProc.running = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout" || event.name === "configreloaded") {
                root.needsLayoutRefresh = true;
                layoutRefresh.restart();
            }
        }
    }
}
