import QtQuick
import qs.services

/**
 * One XKB option, as a switch.
 *
 * `input:kb_options` is a single comma-separated string, so a switch here is really "is this
 * word in that list" - and toggling it has to rewrite the whole list without disturbing
 * anything else that happens to be in it, including options this page does not offer.
 */
HyprToggle {
    id: root

    /// An XKB option code, e.g. "caps:escape".
    required property string option

    readonly property var current: String(HyprlandGui.displayValue("input:kb_options", "") ?? "")
        .split(",").map(entry => entry.trim()).filter(entry => entry.length > 0)

    switchOn: root.current.indexOf(root.option) >= 0
    // The whole list has one owner, but a row is about its own word: an off row says nothing
    // about who set the other words.
    badgeText: root.switchOn ? HyprOrigin.label("input:kb_options") : ""
    onRequested: wanted => {
        const next = wanted ? root.current.concat([root.option])
            : root.current.filter(entry => entry !== root.option);
        HyprlandGui.setKey("input:kb_options", next.join(","));
    }

    Component.onCompleted: HyprlandGui.watch(["input:kb_options"])
}
