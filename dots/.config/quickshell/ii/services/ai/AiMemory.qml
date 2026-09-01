pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * What the assistant is allowed to remember between conversations.
 *
 * A persona says how to answer; this says what is already known — the distro,
 * the editor, how someone likes their code reviewed. Every fact is a line the
 * user can read, edit and delete, kept in its own file rather than buried in
 * the system prompt, and nothing is written without the user seeing it: the
 * model can only propose a fact through a tool that asks first.
 *
 * The file is a plain JSON list so it can be edited by hand, and it is
 * separate from config.json and from the sessions, both of which have their
 * own lifetimes.
 */
Singleton {
    id: root

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/memory.json`)
    property bool loaded: false
    /** Facts, newest last: {id, text, at, source}. */
    property var facts: []

    readonly property bool enabled: Config.options?.ai?.memory?.enabled ?? true
    readonly property int limit: Math.max(1, Config.options?.ai?.memory?.limit ?? 40)

    /** The block that goes into the system prompt, empty when there is nothing. */
    readonly property string promptBlock: {
        if (!root.enabled || root.facts.length === 0)
            return "";
        const lines = root.facts.map(fact => `- ${fact.text}`).join("\n");
        return `## What you already know about this user\n${lines}`;
    }

    signal factAdded(string text)

    function newId(): string {
        return `m${Date.now().toString(36)}${Math.floor(Math.random() * 1000).toString(36)}`;
    }

    function remember(text: string, source = "user"): bool {
        const value = String(text ?? "").trim();
        if (!root.enabled || value.length === 0)
            return false;
        if (root.facts.some(fact => String(fact.text).toLowerCase() === value.toLowerCase()))
            return false;
        root.facts = [...root.facts, {
                id: root.newId(),
                text: value,
                at: Date.now(),
                source: String(source)
            }].slice(-root.limit);
        root.save();
        root.factAdded(value);
        return true;
    }

    function forget(id: string): bool {
        const before = root.facts.length;
        root.facts = root.facts.filter(fact => String(fact.id) !== String(id));
        if (root.facts.length === before)
            return false;
        root.save();
        return true;
    }

    function edit(id: string, text: string): bool {
        const value = String(text ?? "").trim();
        if (value.length === 0)
            return root.forget(id);
        root.facts = root.facts.map(fact => String(fact.id) === String(id) ? Object.assign({}, fact, {
                    text: value
                }) : fact);
        root.save();
        return true;
    }

    function forgetAll() {
        root.facts = [];
        root.save();
    }

    function save() {
        if (!root.loaded)
            return;
        memoryFile.setText(JSON.stringify({
            schema: 1,
            facts: root.facts
        }, null, 2));
    }

    Component.onCompleted: {
        // The state directory may not exist yet on a fresh install, and a
        // write into a missing directory fails silently.
        Quickshell.execDetached(["mkdir", "-p", FileUtils.parentDirectory(root.path)]);
    }

    FileView {
        id: memoryFile
        path: root.path
        watchChanges: true
        onFileChanged: memoryFile.reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(memoryFile.text());
                root.facts = Array.isArray(parsed?.facts) ? parsed.facts : [];
            } catch (e) {
                root.facts = [];
            }
            root.loaded = true;
        }
        onLoadFailed: error => {
            // No file yet is the normal first run, not a fault.
            root.facts = [];
            root.loaded = true;
        }
    }
}
