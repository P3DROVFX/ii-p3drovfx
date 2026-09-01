pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    property bool available: false
    property bool ready: false
    property string sourcePath: ""
    property string lastError: ""

    Connections {
        target: KdeConnectService
        ignoreUnknownSignals: true
        function onActiveDeviceIdChanged() {
            root.refresh()
        }
    }

    property var contacts: []
    property string searchQuery: ""
    property var filteredContacts: []

    readonly property int count: contacts ? contacts.length : 0
    // Contacts dropped by the nameless filter, so the UI can say why the list is short
    property int hiddenCount: 0

    readonly property bool hideUnnamed: Config.options?.phone?.contacts?.hideUnnamed ?? true
    onHideUnnamedChanged: root._updateFilteredContacts()

    function refresh(): void {
        // Mirrors the old daemon-restart semantics: a restart reset its dedup hash, so an explicit
        // refresh always re-published the list, and a refresh while no contact source existed did
        // nothing at all.
        if (!root._watching) return
        root._forceEmit = true
        root._readOnce()
    }

    function setSearchQuery(query: string): void {
        root.searchQuery = query
        root._updateFilteredContacts()
    }

    function contactById(id: string): var {
        if (!contacts) return null
        for (let i = 0; i < contacts.length; i++) {
            if (contacts[i].id === id) return contacts[i]
        }
        return null
    }

    function copyPhone(number: string): void {
        if (!number) return
        Quickshell.clipboardText = number
        KdeConnectService.dispatchActionFeedback(Translation.tr("Phone number copied"), true)
    }

    function openDialer(number: string): void {
        if (!number) return
        if (!KdeConnectService.activeReachable) {
            KdeConnectService.dispatchActionFeedback(Translation.tr("Phone is not connected or reachable"), false)
            return
        }
        if (!KdeConnectService.adbReachable) {
            KdeConnectService.dispatchActionFeedback(Translation.tr("ADB is not reachable. Enable Wireless Debugging / USB Debugging."), false)
            return
        }
        root._startIntent("android.intent.action.DIAL", "tel:" + encodeURIComponent(number),
            Translation.tr("Opening dialer for %1…").arg(number))
    }

    function composeSms(number: string): void {
        if (!number) return
        if (!KdeConnectService.activeReachable) {
            KdeConnectService.dispatchActionFeedback(Translation.tr("Phone is not connected or reachable"), false)
            return
        }
        if (!KdeConnectService.adbReachable) {
            KdeConnectService.dispatchActionFeedback(Translation.tr("ADB is not reachable. Enable Wireless Debugging / USB Debugging."), false)
            return
        }
        root._startIntent("android.intent.action.SENDTO", "sms:" + encodeURIComponent(number),
            Translation.tr("Opening SMS for %1…").arg(number))
    }

    /** Fires an `am start` on the phone. The ADB target is re-resolved first
     *  because the wireless-debugging port changes on every toggle/reboot,
     *  and a stale serial makes the intent vanish with no error. */
    function _startIntent(action: string, uri: string, feedback: string): void {
        KdeConnectService.withAdbTarget(targetArgs => {
            const cmd = ["adb"].concat(targetArgs || [])
            cmd.push("shell", "am", "start", "-a", action, "-d", uri)
            Quickshell.execDetached(cmd)
            KdeConnectService.dispatchActionFeedback(feedback, true)
        })
    }

    function toggleFavorite(contactId: string): void {
        if (!contactId) return
        let currentFavs = (Config.options?.phone?.contacts?.favoriteIds || []).slice()
        const idx = currentFavs.indexOf(contactId)
        if (idx >= 0) {
            currentFavs.splice(idx, 1)
        } else {
            currentFavs.push(contactId)
        }
        Config.options.phone.contacts.favoriteIds = currentFavs
        root._updateFilteredContacts()
    }

    function isFavorite(contactId: string): bool {
        if (!contactId) return false
        const favs = Config.options?.phone?.contacts?.favoriteIds || []
        return favs.indexOf(contactId) >= 0
    }

    // A contact is nameless when the vCard had no name, organization, or any
    // other human-readable field — only a number. Favorites are always kept:
    // starring one is an explicit statement that it matters.
    function _isNameless(contact: var): bool {
        if (!contact || contact.nameless !== true) return false
        return !root.isFavorite(contact.id)
    }

    function _updateFilteredContacts(): void {
        if (!contacts) {
            filteredContacts = []
            root.hiddenCount = 0
            return
        }
        const base = root.hideUnnamed ? contacts.filter(c => !root._isNameless(c)) : contacts
        root.hiddenCount = contacts.length - base.length

        const q = searchQuery.trim().toLowerCase()
        if (!q) {
            filteredContacts = base
            return
        }
        const cleanQ = q.replace(/[\s\-\(\)\.]/g, "")
        filteredContacts = base.filter(c => {
            if (!c) return false
            if (c.displayName && c.displayName.toLowerCase().includes(q)) return true
            if (c.organization && c.organization.toLowerCase().includes(q)) return true

            if (c.phones) {
                for (let i = 0; i < c.phones.length; i++) {
                    const p = c.phones[i]
                    if (p.value && p.value.toLowerCase().includes(q)) return true
                    if (p.normalized && cleanQ && p.normalized.includes(cleanQ)) return true
                }
            }
            if (c.emails) {
                for (let i = 0; i < c.emails.length; i++) {
                    if (c.emails[i].value && c.emails[i].value.toLowerCase().includes(q)) return true
                }
            }
            return false
        })
    }

    onContactsChanged: root._updateFilteredContacts()

    IpcHandler {
        target: "phoneContacts"
        function refresh() {
            root.refresh()
        }
        function search(query: string) {
            root.setSearchQuery(query)
        }
    }

    // The contacts monitor used to run as a permanently resident Python interpreter whose only job
    // was to sit in a GLib main loop and re-read a directory of .vcf files. `gio monitor` is that
    // exact same GFileMonitor (glib2, already a hard Qt dependency) at a fraction of the memory,
    // and the script's own --once mode produces byte-identical `ready` + `snapshot` output. The
    // 250 ms debounce and the "only publish when the payload changed" rule are the daemon's.
    readonly property bool _enabled: Config.options?.phone?.contacts?.enabled ?? true
    property bool _watching: false
    property bool _forceEmit: false
    property string _lastSnapshot: ""
    property bool _usePolling: false

    function _readOnce(): void {
        readProcess.running = false
        readProcess.running = true
    }

    on_EnabledChanged: {
        if (root._enabled) {
            root._readOnce()
        } else {
            root._watching = false
            root._usePolling = false
        }
    }

    Component.onCompleted: {
        if (root._enabled)
            root._readOnce()
    }

    Timer {
        // Debounce bursts of writes the same way the daemon's GLib timeout did.
        id: changeDebounce
        interval: 250
        repeat: false
        onTriggered: root._readOnce()
    }

    Timer {
        // The script falls back to a 3 s poll when it cannot watch; so does this.
        id: pollTimer
        interval: 3000
        repeat: true
        running: root._enabled && root._usePolling
        onTriggered: root._readOnce()
    }

    Timer {
        // gio ships with glib2 and should always be there, but if it is not, poll instead of
        // silently never noticing a contact change again.
        id: watchStartCheck
        interval: 1000
        repeat: false
        onTriggered: {
            if (root._watching && !watchProcess.running)
                root._usePolling = true
        }
    }

    Process {
        id: watchProcess
        command: ProcUtils.pdeath(["gio", "monitor", "-d", root.sourcePath])
        running: root._enabled && root._watching && !root._usePolling && root.sourcePath !== ""

        onRunningChanged: {
            if (running)
                root._usePolling = false
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.trim().length > 0)
                    changeDebounce.restart()
            }
        }
    }

    Process {
        id: readProcess
        command: [
            "python3",
            Quickshell.shellPath("scripts/kdeconnect/contacts_monitor.py"),
            "--device", KdeConnectService.activeDeviceId || "",
            "--once"
        ]
        running: false

        onExited: root._forceEmit = false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data)
                    if (msg.event === "ready") {
                        root.available = true
                        root.ready = true
                        root.sourcePath = msg.sourcePath || ""
                        root.lastError = ""
                        if (!root._watching) {
                            root._watching = true
                            watchStartCheck.restart()
                        }
                    } else if (msg.event === "snapshot") {
                        const payload = JSON.stringify(msg.contacts || [])
                        if (root._forceEmit || payload !== root._lastSnapshot) {
                            root._lastSnapshot = payload
                            root.contacts = msg.contacts || []
                        }
                    } else if (msg.event === "error") {
                        root.lastError = msg.message || "Unknown contacts error"
                        if (msg.code === "no_contact_source") {
                            root.ready = false
                        }
                    }
                } catch (e) {
                    console.warn("[PhoneContactsService] JSON parse error:", e, "Line:", data)
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) {
                    console.warn("[PhoneContactsService stderr]", data)
                }
            }
        }
    }
}
