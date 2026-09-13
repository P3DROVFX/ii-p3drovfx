import QtQuick
import qs.services

/**
 * A group of XKB options that are alternatives to each other, as one chooser.
 *
 * "Caps Lock acts as Escape" and "swap Caps Lock and Escape" are two switches that cannot both
 * be on, which makes them one question with three answers. `group` lists every option code the
 * row offers; the option value "" is the answer "none of them", and picking any answer takes the
 * other members of the group out of the string without touching whatever else is in it.
 */
HyprSelect {
    id: root

    /// The XKB option codes this row chooses between, e.g. every caps:* it offers.
    required property var group

    readonly property var current: String(HyprlandGui.displayValue("input:kb_options", "") ?? "")
        .split(",").map(entry => entry.trim()).filter(entry => entry.length > 0)
    readonly property var members: Array.from(root.group ?? [])
    readonly property string chosen: root.members.find(code => root.current.indexOf(code) >= 0) ?? ""

    keys: ["input:kb_options"]
    currentOverride: root.chosen
    // The list has one owner, but this row is about its own words: with none of them present it
    // says nothing about who set the rest.
    showOrigin: root.chosen !== ""

    onSelected: newValue => {
        const rest = root.current.filter(entry => root.members.indexOf(entry) < 0);
        const next = String(newValue ?? "") === "" ? rest : rest.concat([String(newValue)]);
        HyprlandGui.setKey("input:kb_options", next.join(","));
    }
}
