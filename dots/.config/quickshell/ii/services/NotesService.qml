pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/**
 * The single owner of notes.json.
 *
 * UI components may keep a local view of `tabsData`, but they never open the
 * file or write JSON themselves. This matters when the notes overlay is open:
 * an AI append and a text-editor debounce must be merged by one writer rather
 * than racing two FileViews against each other.
 */
Singleton {
    id: root

    readonly property var defaultTabs: [
        { title: "Tab 1", icon: "article", content: "" },
        { title: "Tab 2", icon: "article", content: "" },
        { title: "Tab 3", icon: "article", content: "" }
    ]
    property var tabsData: ({ tabs: root.defaultTabs })
    property bool ready: false
    property bool writing: false
    property string lastError: ""
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500
    property var pendingData: null

    signal dataChanged()
    signal writeFinished(bool success, string error)

    function cloneTabs(value): var {
        const source = Array.isArray(value?.tabs) ? value.tabs : root.defaultTabs;
        return source.map(tab => ({
            title: String(tab?.title ?? "Tab"),
            icon: String(tab?.icon ?? "article"),
            content: String(tab?.content ?? "")
        }));
    }

    function normalized(value): var {
        const tabs = root.cloneTabs(value);
        return { tabs: tabs.length > 0 ? tabs : root.cloneTabs({ tabs: root.defaultTabs }) };
    }

    function parseText(text): var {
        try {
            const parsed = JSON.parse(String(text ?? ""));
            return root.normalized(parsed);
        } catch (error) {
            root.lastError = "Could not parse notes.json";
            return root.normalized({ tabs: root.defaultTabs });
        }
    }

    function publish(value): void {
        root.tabsData = root.normalized(value);
        root.dataChanged();
    }

    function loadFromDisk(): void {
        if (!noteFile)
            return;
        root.ready = true;
        // A reload triggered by our own write must not clobber newer in-memory edits.
        if (root.writing || root.pendingData !== null) {
            if (root.pendingData !== null)
                writeDebounce.restart();
            return;
        }
        root.publish(root.parseText(noteFile.text()));
    }

    function scheduleWrite(value): bool {
        if (!root.ready) {
            root.pendingData = root.normalized(value);
            return false;
        }
        root.pendingData = root.normalized(value);
        writeDebounce.restart();
        return true;
    }

    function replaceTabs(value): bool {
        return root.scheduleWrite(value);
    }

    function flush(): bool {
        if (!root.ready || root.pendingData === null)
            return false;
        root.publish(root.pendingData);
        root.pendingData = null;
        const payload = JSON.stringify(root.tabsData, null, 2);
        // FileView silently drops a setText that matches what it already holds, and
        // emits no signal for it — so treat it as done instead of waiting forever.
        if (payload === noteFile.text()) {
            root.writing = false;
            writeWatchdog.stop();
            root.writeFinished(true, "");
            return true;
        }
        root.writing = true;
        writeWatchdog.restart();
        noteFile.setText(payload);
        return true;
    }

    function reload(): void {
        noteFile.reload();
    }

    function snapshot(): var {
        return root.normalized(root.tabsData);
    }

    function updateTab(index: int, content: string): bool {
        const tabs = root.cloneTabs(root.tabsData);
        if (index < 0 || index >= tabs.length)
            return false;
        tabs[index].content = String(content ?? "");
        return root.scheduleWrite({ tabs: tabs });
    }

    function updateTabMetadata(index: int, title: string, icon: string): bool {
        const tabs = root.cloneTabs(root.tabsData);
        if (index < 0 || index >= tabs.length)
            return false;
        tabs[index].title = String(title ?? "").split("\n")[0] || "Tab";
        tabs[index].icon = String(icon ?? "article").split("\n")[0] || "article";
        return root.scheduleWrite({ tabs: tabs });
    }

    function append(index: int, text: string, provenance = null): var {
        const tabs = root.cloneTabs(root.tabsData);
        if (index < 0 || index >= tabs.length)
            return { ok: false, error: "unknownNote" };
        const addition = String(text ?? "").trim();
        if (addition.length === 0)
            return { ok: false, error: "emptyText" };
        const previous = String(tabs[index].content ?? "").trimEnd();
        tabs[index].content = previous.length > 0 ? `${previous}\n\n${addition}` : addition;
        if (!root.scheduleWrite({ tabs: tabs }))
            return { ok: false, error: "notReady" };
        return {
            ok: true,
            index: index,
            title: tabs[index].title,
            content: tabs[index].content,
            provenance: root.safeProvenance(provenance)
        };
    }

    function create(title: string, content: string, provenance = null): var {
        const noteTitle = String(title ?? "").trim() || "AI note";
        const noteContent = String(content ?? "").trim();
        if (noteContent.length === 0)
            return { ok: false, error: "emptyText" };
        const tabs = root.cloneTabs(root.tabsData);
        const tab = { title: noteTitle.slice(0, 120), icon: "article", content: noteContent };
        tabs.push(tab);
        if (!root.scheduleWrite({ tabs: tabs }))
            return { ok: false, error: "notReady" };
        return {
            ok: true,
            index: tabs.length - 1,
            title: tab.title,
            content: tab.content,
            provenance: root.safeProvenance(provenance)
        };
    }

    function deleteTab(index: int): bool {
        const tabs = root.cloneTabs(root.tabsData);
        if (index < 0 || index >= tabs.length)
            return false;
        tabs.splice(index, 1);
        if (tabs.length === 0)
            tabs.push({ title: "Tab 1", icon: "article", content: "" });
        return root.scheduleWrite({ tabs: tabs });
    }

    function safeProvenance(value): var {
        const candidate = value ?? ({});
        return {
            sessionId: String(candidate.sessionId ?? "").slice(0, 120),
            messageId: String(candidate.messageId ?? "").slice(0, 120)
        };
    }

    Timer {
        id: writeDebounce
        interval: 150
        repeat: false
        onTriggered: root.flush()
    }

    Timer {
        id: writeWatchdog
        interval: 2000
        repeat: false
        onTriggered: {
            root.writing = false;
            if (root.pendingData !== null)
                writeDebounce.restart();
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: root.reload()
    }

    FileView {
        id: noteFile
        path: Qt.resolvedUrl(Directories.notesPath)
        watchChanges: true
        atomicWrites: true
        onLoaded: root.loadFromDisk()
        onSaved: {
            writeWatchdog.stop();
            root.writing = false;
            root.writeFinished(true, "");
            if (root.pendingData !== null)
                writeDebounce.restart();
        }
        onSaveFailed: error => {
            writeWatchdog.stop();
            root.writing = false;
            root.lastError = `notes.json save failed: ${error}`;
            root.writeFinished(false, root.lastError);
        }
        onLoadFailed: error => {
            root.writing = false;
            if (error !== FileViewError.FileNotFound) {
                root.lastError = `notes.json load failed: ${error}`;
                root.writeFinished(false, root.lastError);
                return;
            }
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                root.ready = true;
                root.publish({ tabs: root.defaultTabs });
                root.pendingData = root.tabsData;
                root.flush();
            } else {
                missingFileRetryTimer.restart();
            }
        }
    }

    Component.onCompleted: root.reload()
}
