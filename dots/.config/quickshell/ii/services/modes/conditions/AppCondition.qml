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

    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property string focusedAddress: {
        const a = root.activeToplevel?.HyprlandToplevel?.address;
        return a ? `0x${a}` : "";
    }
    // The focused window's title straight from the compositor: a tab switch
    // or page load shows here well before the client list is re-read.
    readonly property string focusedTitle: String(root.activeToplevel?.title ?? "")
    readonly property var windows: HyprlandData.windowList ?? []
    readonly property var matching: root.windows.filter(w => ModeSchema.windowMatches(w, root.regexes, root.titleRe))
    readonly property var focusedWindow: root.windows.find(w => w.address === root.focusedAddress) ?? null
    readonly property var focusedMatch: {
        const w = root.focusedWindow;
        if (!w)
            return null;
        const live = root.titleRe && root.focusedTitle.length
            ? Object.assign({}, w, { title: root.focusedTitle }) : w;
        return ModeSchema.windowMatches(live, root.regexes, root.titleRe) ? live : null;
    }

    satisfied: (root.regexes.length > 0 || root.titleRe !== null)
        && (root.wantFocused ? root.focusedMatch !== null
            : (root.matching.length > 0 || root.focusedMatch !== null))
    reason: {
        const w = root.focusedMatch ?? root.matching[0];
        if (!w)
            return "";
        const cls = String(w["class"] || w.initialClass || "");
        return root.titleRe ? `${cls}: ${String(w.title || "").slice(0, 40)}` : cls;
    }
}
