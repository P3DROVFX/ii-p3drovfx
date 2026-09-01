import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * A window whose class (or initial class) matches one of `classes` — and,
 * with `title`, whose title matches too — is open (`when: running`) or
 * focused (`when: focused`). A title alone works as well ("YouTube" in any
 * browser).
 */
ModeCondition {
    id: root
    readonly property var regexes: ModeSchema.classRegexes(root.params?.classes)
    readonly property var titleRe: ModeSchema.titleRegex(root.params?.title)
    readonly property bool wantFocused: root.params?.when === "focused"

    readonly property string focusedAddress: {
        const a = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        return a ? `0x${a}` : "";
    }
    readonly property var windows: HyprlandData.windowList ?? []
    readonly property var matching: root.windows.filter(w => ModeSchema.windowMatches(w, root.regexes, root.titleRe))
    readonly property var focusedMatch: root.matching.find(w => w.address === root.focusedAddress) ?? null

    satisfied: (root.regexes.length > 0 || root.titleRe !== null)
        && (root.wantFocused ? root.focusedMatch !== null : root.matching.length > 0)
    reason: {
        const w = root.focusedMatch ?? root.matching[0];
        if (!w)
            return "";
        const cls = String(w["class"] || w.initialClass || "");
        return root.titleRe ? `${cls}: ${String(w.title || "").slice(0, 40)}` : cls;
    }
}
