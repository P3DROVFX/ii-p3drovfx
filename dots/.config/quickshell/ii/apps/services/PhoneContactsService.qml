pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim PhoneContactsService stand-in for standalone apps: reads the iilink
 * contacts snapshot only when birthdays are enabled.
 */
Singleton {
    id: root

    readonly property bool _wanted: Config.options?.calendar?.timetable?.birthdays?.enable ?? false
    property var contacts: []

    function contactById(id) {
        const target = String(id ?? "");
        if (!target)
            return null;
        return root.contacts.find(c => String(c?.id ?? "") === target) ?? null;
    }

    function openDialer(number) {
        const clean = String(number ?? "").trim();
        if (!clean)
            return;
        Quickshell.execDetached(["xdg-open", "tel:" + clean]);
    }

    FileView {
        id: contactsFile
        path: root._wanted ? Directories.phoneContactsPath : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(contactsFile.text());
                root.contacts = Array.isArray(parsed) ? parsed : (Array.isArray(parsed?.contacts) ? parsed.contacts : []);
            } catch (e) {
                root.contacts = [];
            }
        }
        onLoadFailed: root.contacts = []
    }
}
