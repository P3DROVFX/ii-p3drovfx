pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The apps the feature tour presents, two pages of them.
 *
 * Each entry pairs with an action of the same id in `WelcomeKeybindRegistry`,
 * which is where its key comes from; this file only carries the wording and
 * the way in. Opening goes through the same `GlobalStates` entry points the
 * keybinds use, so the button works even when the reader unbound the key.
 *
 * An app the user switched off disappears from its page, the same way a
 * disabled panel disappears from the Search step.
 */
QtObject {
    id: root

    readonly property var features: [{
        "id": "clock",
        "page": "apps",
        "titleKey": "Clock",
        "descriptionKey": "Alarms, timers, a stopwatch, pomodoro, bedtime and reminders in one app.",
        "icon": "alarm",
        "shape": MaterialShape.Shape.Cookie9Sided,
        "enabled": () => true
    }, {
        "id": "notes",
        "page": "apps",
        "titleKey": "Notes",
        "descriptionKey": "Write things down without leaving what you were doing.",
        "icon": "edit_note",
        "shape": MaterialShape.Shape.Clover4Leaf,
        "enabled": () => true
    }, {
        "id": "limits",
        "page": "apps",
        "titleKey": "Daily limits",
        "descriptionKey": "Give an app a daily budget, and II steps in when it runs out.",
        "icon": "hourglass_top",
        "shape": MaterialShape.Shape.PuffyDiamond,
        "enabled": () => Config.options.screenTime?.enable ?? true
    }, {
        "id": "modes",
        "page": "apps",
        "titleKey": "Modes & routines",
        "descriptionKey": "Change how the whole shell behaves in one tap, or let a routine do it for you.",
        "icon": "auto_mode",
        "shape": MaterialShape.Shape.SoftBurst,
        "enabled": () => true
    }, {
        "id": "mediaMode",
        "page": "system",
        "titleKey": "Media mode",
        "descriptionKey": "Turns the desktop into a full-screen player for whatever is playing, lyrics included.",
        "icon": "music_note",
        "shape": MaterialShape.Shape.Sunny,
        "enabled": () => true
    }, {
        "id": "health",
        "page": "system",
        "titleKey": "System health",
        "descriptionKey": "Failed services, crashes, the journal and your hardware, read in plain words.",
        "icon": "monitor_heart",
        "shape": MaterialShape.Shape.Heart,
        "enabled": () => true
    }, {
        "id": "easyEffects",
        "page": "system",
        "titleKey": "EasyEffects",
        "descriptionKey": "Equalizer, presets and effects for your speakers and your microphone.",
        "icon": "instant_mix",
        "shape": MaterialShape.Shape.Pentagon,
        "enabled": () => Config.options.easyEffects?.appEnable ?? true
    }]

    function featuresFor(pageId: string): var {
        return root.features.filter(feature => feature.page === pageId && feature.enabled());
    }

    /**
     * A note in place of the description, for an app that opens but has
     * nothing to work with yet. Empty when there is nothing to say.
     */
    function noteFor(featureId: string): string {
        if (featureId === "easyEffects" && !EasyEffects.available)
            return Translation.tr("Needs the EasyEffects package, which isn't installed yet.");
        return "";
    }

    function open(featureId: string): void {
        switch (featureId) {
        case "clock":
            GlobalStates.openClockApp();
            break;
        case "notes":
            GlobalStates.openNotes();
            break;
        case "limits":
            GlobalStates.openUsageApp("limits");
            break;
        case "modes":
            GlobalStates.openModesApp();
            break;
        case "mediaMode":
            GlobalStates.requestMediaMode("open");
            break;
        case "health":
            GlobalStates.openHealthApp();
            break;
        case "easyEffects":
            GlobalStates.openEasyEffectsApp();
            break;
        default:
            return;
        }
        // Ticked here as well as by the watcher: having opened it from the
        // row is exactly as true as having pressed the key.
        WelcomeKeybindRegistry.markPerformed(featureId);
    }
}
