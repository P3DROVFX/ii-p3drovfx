// Copies the theme matugen renders (template: matugen/templates/vscode)
// into this extension's themes/ folder. The theme contributions are `_watch`ed,
// so VS Code repaints as soon as the file changes, no reload needed.
const fs = require("fs");
const os = require("os");
const path = require("path");
const vscode = require("vscode");

const LABELS = { dark: "ii Material You Dark", light: "ii Material You Light" };
const stateHome = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
const source = path.join(stateHome, "quickshell", "user", "generated", "vscode", "theme.json");

function sync() {
    let text;
    try {
        text = fs.readFileSync(source, "utf8");
    } catch {
        return;
    }
    let mode;
    try {
        mode = JSON.parse(text).type === "light" ? "light" : "dark";
    } catch {
        return; // half-written file, the next change event brings the full one
    }
    const target = path.join(__dirname, "themes", `${mode}.json`);
    let current = "";
    try {
        current = fs.readFileSync(target, "utf8");
    } catch {}
    if (current !== text) fs.writeFileSync(target, text);

    // Follow the shell's light/dark switch while one of our themes is active
    const config = vscode.workspace.getConfiguration("workbench");
    if (vscode.workspace.getConfiguration("window").get("autoDetectColorScheme")) return;
    const active = config.get("colorTheme");
    const other = mode === "dark" ? LABELS.light : LABELS.dark;
    if (active === other) config.update("colorTheme", LABELS[mode], vscode.ConfigurationTarget.Global);
}

function activate(context) {
    sync();
    let timer = null;
    const schedule = () => {
        clearTimeout(timer);
        timer = setTimeout(sync, 150);
    };
    // Watch the directory: matugen may replace the file, which kills a file watch
    fs.mkdirSync(path.dirname(source), { recursive: true });
    const watcher = fs.watch(path.dirname(source), (_event, name) => {
        if (!name || name === path.basename(source)) schedule();
    });
    context.subscriptions.push({ dispose: () => { watcher.close(); clearTimeout(timer); } });
}

module.exports = { activate, deactivate() {} };
