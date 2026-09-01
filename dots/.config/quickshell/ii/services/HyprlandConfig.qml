pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root
    signal reloaded()
    signal welcomeKeyboardLayoutPersisted(bool success, string message)
    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string welcomeKeyboardPersistenceScriptPath: Quickshell.shellPath("scripts/hyprland/persist_welcome_keyboard_layout.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)
    readonly property string customInputPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/input.lua`)
    property var configWriteQueue: []

    function set(key: string, value: var) {
        root._queueShellOverridesCommand(`${root.configuratorScriptPath} --file ${root.shellOverridesPath} --set "${key}" "${value}"`);
    }
    function setMany(entries: var, extras: var) {
        let args = ""
        for (let key in entries) args += `--set "${key}" "${entries[key]}" `
        args += root._extraArgs(extras)
        root._queueShellOverridesCommand(`${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}`);
    }
    // This is deliberately separate from set/setMany: the latter belongs to
    // transient shellOverrides, while Welcome owns only its marker-delimited
    // block in custom/input.lua.
    function persistWelcomeKeyboardLayout(layout: string, variant: string): bool {
        if (layout.length === 0)
            return false;

        root._applyKeyboardLayoutRuntime(layout, variant);
        root._queueConfigWrite({
            kind: "welcomeKeyboard",
            layout: layout,
            variant: variant,
            command: [
                "python3",
                root.welcomeKeyboardPersistenceScriptPath,
                "--custom-input", root.customInputPath,
                "--shell-overrides", root.shellOverridesPath,
                "--layout", layout,
                "--variant", variant
            ]
        });
        return true;
    }
    function _applyKeyboardLayoutRuntime(layout: string, variant: string) {
        Quickshell.execDetached(["hyprctl", "keyword", "input:kb_layout", layout]);
        Quickshell.execDetached(["hyprctl", "keyword", "input:kb_variant", variant]);
    }
    function _queueShellOverridesCommand(command: string) {
        root._queueConfigWrite({
            kind: "shellOverrides",
            command: ["bash", "-c", command]
        });
    }
    function _queueConfigWrite(operation: var) {
        root.configWriteQueue = root.configWriteQueue.concat([operation]);
        root._startNextConfigWrite();
    }
    function _startNextConfigWrite() {
        if (configWriterProcess.running || configWriterProcess.activeOperation || root.configWriteQueue.length === 0)
            return;

        configWriterProcess.activeOperation = root.configWriteQueue[0];
        root.configWriteQueue = root.configWriteQueue.slice(1);
        configWriterProcess.command = configWriterProcess.activeOperation.command;
        configWriterProcess.running = true;
    }
    function reset(key: string) {
        root._queueShellOverridesCommand(`${root.configuratorScriptPath} --file ${root.shellOverridesPath} --reset "${key}"`);
    }
    function resetMany(keys: list<string>, extras: var) {
        let args = ""
        for (let i = 0; i < keys.length; i++) args += `--reset "${keys[i]}" `
        args += root._extraArgs(extras)
        root._queueShellOverridesCommand(`${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}`);
    }
    function _extraArgs(extras: var): string {
        if (!extras) return ""
        let args = ""
        const addLines = extras.addLines ?? []
        const removeMatching = extras.removeMatching ?? []
        for (let i = 0; i < addLines.length; i++)
            args += `--add-line ${root._shellQuote(addLines[i])} `
        for (let i = 0; i < removeMatching.length; i++)
            args += `--remove-matching ${root._shellQuote(removeMatching[i])} `
        return args
    }
    function _shellQuote(value: string): string {
        return `'${String(value).replace(/'/g, `'\\''`)}'`
    }
    function _finishConfigWrite(success: bool, errorMessage: string) {
        const operation = configWriterProcess.activeOperation;
        if (!operation)
            return;

        configWriterProcess.activeOperation = null;
        if (operation.kind === "welcomeKeyboard") {
            if (success) {
                root._applyKeyboardLayoutRuntime(operation.layout, operation.variant);
                root.welcomeKeyboardLayoutPersisted(true, "");
            } else {
                root.welcomeKeyboardLayoutPersisted(false, errorMessage || "Could not save keyboard layout.");
            }
        }
        Qt.callLater(root._startNextConfigWrite);
    }
    Process {
        id: configWriterProcess
        property var activeOperation: null
        stderr: StdioCollector {
            id: configWriterErrors
        }
        onExited: (exitCode, exitStatus) => {
            root._finishConfigWrite(exitCode === 0, configWriterErrors.text.trim());
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(root._startNextConfigWrite);
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name == "configreloaded") root.reloaded() }
    }
}
