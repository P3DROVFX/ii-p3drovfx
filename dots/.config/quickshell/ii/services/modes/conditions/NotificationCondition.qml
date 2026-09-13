import QtQuick
import qs.services
import ".."

/**
 * Event: a desktop notification arrives, optionally only from an app whose
 * name contains `app` and/or whose title or body contains `text`.
 * Notifications the routines themselves send are ignored, so a routine
 * cannot trip on its own output.
 */
ModeCondition {
    id: root
    readonly property string app: String(root.params?.app ?? "").toLowerCase()
    readonly property string text: String(root.params?.text ?? "").toLowerCase()

    readonly property Connections link: Connections {
        target: Notifications
        function onNotify(n) {
            if (!n)
                return;
            const appName = String(n.appName ?? "");
            if (appName === "Modes & Routines")
                return;
            const who = `${appName} ${n.desktopEntry ?? ""}`.toLowerCase();
            if (root.app.length && who.indexOf(root.app) === -1)
                return;
            const what = `${n.summary ?? ""} ${n.body ?? ""}`.toLowerCase();
            if (root.text.length && what.indexOf(root.text) === -1)
                return;
            root.pulse(`${appName}: ${String(n.summary ?? "").slice(0, 40)}`);
        }
    }
}
