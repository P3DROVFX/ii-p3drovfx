import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Quick toggle for Modes & Routines. The pill toggles the last used mode;
 * the body / right-click opens the picker. With no mode ever used the pill
 * opens the picker too, since there is nothing to toggle yet.
 */
QuickToggleModel {
    name: Translation.tr("Modes")
    statusText: Modes.active ? Modes.activeMode.name : Translation.tr("Off")

    toggled: Modes.active
    icon: Modes.active ? Modes.activeMode.icon : "tune"
    mainAction: () => {
        if (Modes.active || Modes.lastUsedMode) {
            Modes.toggleLast();
            return;
        }
        // Nothing to toggle yet: the picker is the only sensible answer.
        altAction?.();
    }
    hasMenu: true
    tooltipText: Modes.active
        ? Translation.tr("%1 mode is on | Click to turn off, right-click to choose").arg(Modes.activeMode.name)
        : Translation.tr("Modes | Click to start the last mode, right-click to choose")
}
