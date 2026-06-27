pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * WorkspaceProfileService
 *
 * Manages per-file workspace profiles stored in
 * ~/.config/illogical-impulse/workspace_profiles/<slug>.json
 *
 * Each public function delegates to the workspace_profile_manager Rust binary.
 */
Singleton {
    id: root

    // ── public state ────────────────────────────────────────────────────────
    property ListModel profilesModel: ListModel {}
    property bool loading:  false
    property bool restoring: false
    property string restoringSlug: ""
    property string activeMutationSlug: ""
    onBusyChanged: if (!busy) activeMutationSlug = ""
    property bool binaryExists: true

    // Expose a public busy state when any process is active
    readonly property bool busy: (
        listProc.running ||
        snapshotProc.running ||
        restoreProc.running ||
        deleteProc.running ||
        renameProc.running ||
        updateEmojiProc.running ||
        updateDescProc.running ||
        updateWindowProc.running ||
        updateProfileProc.running ||
        addWindowProc.running ||
        deleteWindowProc.running ||
        updateWindowWorkspaceProc.running ||
        togglePinProc.running
    )

    // ── signals ─────────────────────────────────────────────────────────────
    signal snapshotFinished(bool success, string slug)
    signal restoreStarted(string profileName)
    signal restoreFinished(bool success, int errors)
    signal renameFinished(bool success, string newSlug)
    signal updateDescriptionFinished(bool success)
    signal updateEmojiFinished(bool success)
    signal deleteFinished(bool success)

    // ── paths ────────────────────────────────────────────────────────────────
    readonly property string scriptPath: `${Directories.scriptPath}/hyprland/workspace_profile_manager`

    readonly property var presetEmojis: [
        "🗂️","📚","💻","🎮","🎵","🎬","📝","🔬","🎨","🏋️",
        "☕","🌙","🚀","🏠","🌊","🔧","📊","✉️","🎓","🧠"
    ]

    // ── public API ───────────────────────────────────────────────────────────

    function refresh() {
        listProc.command = [root.scriptPath, "list"];
        listProc.running = true;
    }

    function snapshot(name, emoji, description, windowOverrides) {
        if (root.busy) return;
        const meta = JSON.stringify({
            name,
            emoji:          emoji       || "🗂️",
            description:    description || "",
            windowOverrides: windowOverrides || {}
        });
        snapshotProc.command = [root.scriptPath, "snapshot", meta];
        snapshotProc.running = true;
    }

    function restoreProfile(slug) {
        if (root.busy) return;
        
        // Find the name for the signal
        for (let i = 0; i < root.profilesModel.count; i++) {
            if (root.profilesModel.get(i).slug === slug) {
                root.restoreStarted(root.profilesModel.get(i).name);
                break;
            }
        }
        root.restoringSlug = slug;
        root.restoring = true;
        restoreProc.command = [root.scriptPath, "restore", slug];
        restoreProc.running = true;
    }

    function deleteProfile(slug) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        deleteProc.command = [root.scriptPath, "delete", slug];
        deleteProc.running = true;
    }

    function renameProfile(oldSlug, newName) {
        if (root.busy) return;
        root.activeMutationSlug = oldSlug;
        renameProc.command = [root.scriptPath, "rename", oldSlug, newName];
        renameProc.running = true;
    }

    function updateEmoji(slug, newEmoji) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        updateEmojiProc.command = [root.scriptPath, "update_emoji", slug, newEmoji];
        updateEmojiProc.running = true;
    }

    function updateDescription(slug, newDescription) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        updateDescProc.command = [root.scriptPath, "update_description", slug, newDescription];
        updateDescProc.running = true;
    }

    function updateWindowOptions(slug, index, autolaunch, launchCmd) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        updateWindowProc.command = [
            root.scriptPath, "update_window",
            slug, index.toString(), autolaunch ? "true" : "false", launchCmd || ""
        ];
        updateWindowProc.running = true;
    }

    function updateProfileOptions(slug, closeOthers, killOthers) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        updateProfileProc.command = [
            root.scriptPath, "update_profile",
            slug, closeOthers ? "true" : "false", killOthers ? "true" : "false"
        ];
        updateProfileProc.running = true;
    }

    // addWindow handles inserting a new window config helper
    function addWindow(slug, className, workspace, autolaunch, launchCmd) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        addWindowProc.command = [
            root.scriptPath, "add_window",
            slug, className, workspace.toString(), autolaunch ? "true" : "false", launchCmd || ""
        ];
        addWindowProc.running = true;
    }

    // deleteWindow deletes a specific window config helper
    function deleteWindow(slug, index) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        deleteWindowProc.command = [
            root.scriptPath, "delete_window",
            slug, index.toString()
        ];
        deleteWindowProc.running = true;
    }

    // updateWindowWorkspace updates a window's workspace destination
    function updateWindowWorkspace(slug, index, workspace) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        updateWindowWorkspaceProc.command = [
            root.scriptPath, "update_window_workspace",
            slug, index.toString(), workspace.toString()
        ];
        updateWindowWorkspaceProc.running = true;
    }

    // togglePin toggles pinned state for the profile
    function togglePin(slug) {
        if (root.busy) return;
        root.activeMutationSlug = slug;
        togglePinProc.command = [
            root.scriptPath, "toggle_pin",
            slug
        ];
        togglePinProc.running = true;
    }

    // ── internal processes ───────────────────────────────────────────────────

    // list
    Process {
        id: listProc
        onRunningChanged: if (running) root.loading = true
        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                root.loading = false;
                try {
                    const arr = JSON.parse(listCollector.text);
                    let oldSlugs = [];
                    for (let i = 0; i < root.profilesModel.count; i++) {
                        oldSlugs.push(root.profilesModel.get(i).slug);
                    }
                    
                    let identicalSet = false;
                    if (arr.length === oldSlugs.length) {
                        let newSlugsArr = arr.map(p => p.slug);
                        identicalSet = oldSlugs.every(s => newSlugsArr.indexOf(s) !== -1);
                    }
                    
                    if (identicalSet) {
                        let newSlugsArr = arr.map(p => p.slug);
                        for (let i = 0; i < newSlugsArr.length; i++) {
                            let targetSlug = newSlugsArr[i];
                            let currentIndex = -1;
                            for (let j = i; j < root.profilesModel.count; j++) {
                                if (root.profilesModel.get(j).slug === targetSlug) {
                                    currentIndex = j;
                                    break;
                                }
                            }
                            if (currentIndex > i) {
                                root.profilesModel.move(currentIndex, i, 1);
                            }
                            root.profilesModel.set(i, arr[i]);
                        }
                    } else {
                        root.profilesModel.clear();
                        for (const p of arr) {
                            root.profilesModel.append(p);
                        }
                    }
                } catch (e) {
                    console.warn("[WorkspaceProfileService] list parse error:", e,
                                 listCollector.text.substring(0, 200));
                }
            }
        }
        stderr: StdioCollector {
            id: listStderr
            onStreamFinished: {
                const err = listStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] list error:", err);
            }
        }
    }

    // snapshot
    Process {
        id: snapshotProc
        stdout: StdioCollector {
            id: snapshotCollector
            onStreamFinished: {
                const slug = snapshotCollector.text.trim();
                if (slug && !slug.startsWith("[error]")) {
                    root.snapshotFinished(true, slug);
                    root.refresh();
                } else {
                    root.snapshotFinished(false, "");
                }
            }
        }
        stderr: StdioCollector {
            id: snapshotStderr
            onStreamFinished: {
                const err = snapshotStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] snapshot error:", err);
            }
        }
    }

    // restore
    Process {
        id: restoreProc
        stdout: StdioCollector {
            id: restoreCollector
            onStreamFinished: {
                root.restoringSlug = "";
                root.restoring = false;
                const out = restoreCollector.text.trim();
                if (out === "ok") {
                    root.restoreFinished(true, 0);
                } else if (out.startsWith("partial:")) {
                    root.restoreFinished(false, parseInt(out.split(":")[1]) || 1);
                } else {
                    root.restoreFinished(false, -1);
                }
            }
        }
        stderr: StdioCollector {
            id: restoreStderr
            onStreamFinished: {
                const err = restoreStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] restore error:", err);
            }
        }
    }

    // delete
    Process {
        id: deleteProc
        stdout: StdioCollector {
            id: deleteCollector
            onStreamFinished: {
                const out = deleteCollector.text.trim();
                const ok = (out === "ok");
                root.deleteFinished(ok);
                if (ok) root.refresh();
            }
        }
        stderr: StdioCollector {
            id: deleteStderr
            onStreamFinished: {
                const err = deleteStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] delete error:", err);
            }
        }
    }

    // rename
    Process {
        id: renameProc
        stdout: StdioCollector {
            id: renameCollector
            onStreamFinished: {
                const newSlug = renameCollector.text.trim();
                const ok = newSlug.length > 0 && !newSlug.startsWith("[error]");
                root.renameFinished(ok, ok ? newSlug : "");
                if (ok) root.refresh();
            }
        }
        stderr: StdioCollector {
            id: renameStderr
            onStreamFinished: {
                const err = renameStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] rename error:", err);
            }
        }
    }

    // update emoji
    Process {
        id: updateEmojiProc
        stdout: StdioCollector {
            id: updateEmojiCollector
            onStreamFinished: {
                const out = updateEmojiCollector.text.trim();
                const ok = (out === "ok");
                if (ok) {
                    root.refresh();
                }
                root.updateEmojiFinished(ok);
            }
        }
        stderr: StdioCollector {
            id: updateEmojiStderr
            onStreamFinished: {
                const err = updateEmojiStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] update emoji error:", err);
            }
        }
    }

    // update description
    Process {
        id: updateDescProc
        stdout: StdioCollector {
            id: updateDescCollector
            onStreamFinished: {
                const out = updateDescCollector.text.trim();
                const ok = (out === "ok");
                if (ok) {
                    root.refresh();
                }
                root.updateDescriptionFinished(ok);
            }
        }
        stderr: StdioCollector {
            id: updateDescStderr
            onStreamFinished: {
                const err = updateDescStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] update description error:", err);
            }
        }
    }

    // update window
    Process {
        id: updateWindowProc
        stdout: StdioCollector {
            id: updateWindowCollector
            onStreamFinished: {
                const out = updateWindowCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: updateWindowStderr
            onStreamFinished: {
                const err = updateWindowStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] update window error:", err);
            }
        }
    }

    // update profile
    Process {
        id: updateProfileProc
        stdout: StdioCollector {
            id: updateProfileCollector
            onStreamFinished: {
                const out = updateProfileCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: updateProfileStderr
            onStreamFinished: {
                const err = updateProfileStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] update profile error:", err);
            }
        }
    }

    // add window
    Process {
        id: addWindowProc
        stdout: StdioCollector {
            id: addWindowCollector
            onStreamFinished: {
                const out = addWindowCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: addWindowStderr
            onStreamFinished: {
                const err = addWindowStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] add window error:", err);
            }
        }
    }

    // delete window
    Process {
        id: deleteWindowProc
        stdout: StdioCollector {
            id: deleteWindowCollector
            onStreamFinished: {
                const out = deleteWindowCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: deleteWindowStderr
            onStreamFinished: {
                const err = deleteWindowStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] delete window error:", err);
            }
        }
    }

    // update window workspace
    Process {
        id: updateWindowWorkspaceProc
        stdout: StdioCollector {
            id: updateWindowWorkspaceCollector
            onStreamFinished: {
                const out = updateWindowWorkspaceCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: updateWindowWorkspaceStderr
            onStreamFinished: {
                const err = updateWindowWorkspaceStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] update window workspace error:", err);
            }
        }
    }

    // toggle pin
    Process {
        id: togglePinProc
        stdout: StdioCollector {
            id: togglePinCollector
            onStreamFinished: {
                const out = togglePinCollector.text.trim();
                if (out === "ok") {
                    root.refresh();
                }
            }
        }
        stderr: StdioCollector {
            id: togglePinStderr
            onStreamFinished: {
                const err = togglePinStderr.text.trim();
                if (err) console.warn("[WorkspaceProfileService] toggle pin error:", err);
            }
        }
    }

    Process {
        id: checkBinaryProc
        command: ["test", "-x", root.scriptPath]
        onExited: (exitCode, exitStatus) => {
            root.binaryExists = (exitCode === 0);
        }
    }

    // ── init ─────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        // Ensure profiles directory exists
        Quickshell.execDetached(["mkdir", "-p",
            `${Directories.home}/.config/illogical-impulse/workspace_profiles`]);
        checkBinaryProc.running = true;
        Qt.callLater(root.refresh);
    }
}
