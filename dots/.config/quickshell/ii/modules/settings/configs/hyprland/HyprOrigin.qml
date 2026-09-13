pragma Singleton

import QtQuick
import qs.services

/**
 * Who set an option, as the word a row's pill shows.
 *
 * Reads the three ownership maps by identity - HyprlandGui replaces them only when their content
 * changes - so a binding on `label()` moves when ownership moves and at no other time. That is
 * the difference from binding to `resolve()`, which hands back a fresh object on every edit
 * anywhere in the config.
 */
QtObject {
    id: root

    /// `keys` is one key or a list of them; a chooser that writes several keys asks about all of
    /// them at once and gets the first thing worth saying.
    function label(keys: var): string {
        const list = typeof keys === "string" ? [keys] : Array.from(keys ?? []);
        const managed = HyprlandGui.managedConfig;
        const inherited = HyprlandGui.inheritedConfig;
        const shadowed = HyprlandGui.shadowed;
        // Shadowed first: it is the one case where the value on the row is not what Hyprland is
        // doing, which matters more than who wrote the row's value.
        for (const key of list)
            if (shadowed[key] !== undefined) return Translation.tr("Overridden");
        for (const key of list)
            if (managed.hasOwnProperty(key)) return Translation.tr("Set here");
        for (const key of list)
            if (inherited[key] !== undefined) return Translation.tr("Set by hand");
        return "";
    }

    /// How many of `keys` this page or a hand-written line sets: what a door's badge counts.
    function changedCount(keys: var): int {
        const managed = HyprlandGui.managedConfig;
        const inherited = HyprlandGui.inheritedConfig;
        let count = 0;
        for (const key of Array.from(keys ?? []))
            if (managed.hasOwnProperty(key) || inherited[key] !== undefined) count++;
        return count;
    }
}
