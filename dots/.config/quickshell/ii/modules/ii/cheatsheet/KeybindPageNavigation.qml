pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    // Groups are ordered exactly as the rail, including Hyprland's empty ID.
    property var groups: []
    property string currentPageId: ""
    readonly property var nonemptyGroups: groups.filter(group => group.length > 0)
    readonly property var pages: nonemptyGroups.reduce((all, group) => all.concat(group), [])
    signal pageRequested(string pageId)

    function step(direction, byGroup = false) {
        if (!root.enabled || !root.pages.length) return;
        const choices = byGroup ? root.nonemptyGroups : root.pages;
        const current = byGroup ? choices.findIndex(group => group.includes(root.currentPageId))
                                : choices.indexOf(root.currentPageId);
        const index = (Math.max(0, current) + direction + choices.length) % choices.length;
        root.pageRequested(byGroup ? choices[index][0] : choices[index]);
    }
    Shortcut { sequence: "Up"; context: Qt.WindowShortcut; enabled: root.enabled && root.visible; onActivated: root.step(-1) }
    Shortcut { sequence: "Down"; context: Qt.WindowShortcut; enabled: root.enabled && root.visible; onActivated: root.step(1) }
    Shortcut { sequence: "Ctrl+Up"; context: Qt.WindowShortcut; enabled: root.enabled && root.visible; onActivated: root.step(-1, true) }
    Shortcut { sequence: "Ctrl+Down"; context: Qt.WindowShortcut; enabled: root.enabled && root.visible; onActivated: root.step(1, true) }
}
