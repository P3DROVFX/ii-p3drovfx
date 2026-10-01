pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

// Compatibility-first facade. Touch gestures keep their public API while the
// Search consumes this shell-wide registry as its single action source.
Singleton {
    id: root
    function keywordsFor(action) {
        const base = [action.id, action.name.toLowerCase()];
        const extras = {
            usage: ["app usage", "usage", "uso", "stats", "statistics", "screen time", "tempo de tela", "daily limits",
                "app limits", "limites", "battery usage", "battery history", "bateria", "energy", "digital wellbeing"],
            modes: ["modes and routines", "modes & routines", "modes", "modos", "routines", "rotinas", "automation",
                "automacao", "automação", "focus mode", "work mode", "do not disturb"],
            colorPicker: ["color picker", "cor", "hex"], wallpaperSelector: ["wallpaper", "papel de parede"],
            overlay: ["overlay", "widgets"], osk: ["osk", "teclado"],
            session: ["session", "logout", "desligar"], regionOcr: ["ocr", "texto da tela"],
            screenTranslate: ["translate screen", "traduzir tela"], regionRecord: ["record", "gravar"],
            regionScreenshot: ["screenshot", "print", "snip"], localSend: ["localsend", "enviar arquivo"],
            videoEditor: ["video editor", "editar video"], notes: ["notes", "notas", "quick notes"], scratchpad: ["scratchpad"],
            clock: ["clock", "relogio", "relógio", "alarm", "alarme", "despertador", "world clock", "fuso", "timer", "temporizador", "stopwatch", "cronometro", "cronômetro", "pomodoro"],
            easyEffects: ["easyeffects", "easy effects", "equalizer", "equalizador", "eq", "audio preset", "preset", "sound effects", "efeitos"],
            mediaControls: ["media controls", "player"], barToggle: ["bar", "barra"],
            hubMode: ["hub mode", "dock", "display", "relogio", "clock", "ambient"],
            liveDraw: ["draw", "desenhar", "desenho", "sketch", "pen", "caneta", "stylus", "annotate", "anotar"]
        };
        return base.concat(extras[action.id] ?? []);
    }

    readonly property var extraActions: [
        { id: "notes", name: "Notes", icon: "note_stack", category: "shell", searchable: true, enabled: () => true },
        { id: "clock", name: "Clock", icon: "alarm", category: "shell", searchable: true, enabled: () => Config.options.clockApp?.enable ?? true },
        { id: "easyEffects", name: "EasyEffects", icon: "graphic_eq", category: "shell", searchable: true, enabled: () => Config.options.easyEffects?.appEnable ?? true }
    ]

    /// The shell's own windowed apps. Search lists them as apps rather than as actions.
    readonly property var appIds: ["notes", "clock", "easyEffects", "usage", "modes"]

    readonly property var actions: TouchGestureActionRegistry.actions.concat(root.extraActions).map(action => Object.assign({}, action, {
        keywords: action.keywords ?? root.keywordsFor(action),
        app: root.appIds.includes(action.id),
        prominent: action.prominent === true,
        category: action.category ?? "shell",
        searchable: action.searchable !== false,
        enabled: action.enabled ?? (() => true)
    }))

    function actionById(actionId) {
        return actions.find(action => action.id === actionId) ?? actions[0];
    }

    function trigger(actionId, screenName) {
        if (actionId === "notes") {
            GlobalStates.openNotes();
            return;
        }
        if (actionId === "clock") {
            GlobalStates.openClockApp("");
            return;
        }
        if (actionId === "easyEffects") {
            GlobalStates.openEasyEffectsApp("");
            return;
        }
        // Opening from search must not close an app that is already open behind it; the
        // gesture registry toggles, which is right for a swipe and wrong here.
        if (actionId === "usage" && !PanelFamily.nativeAppWindows) {
            GlobalStates.openUsageApp("");
            return;
        }
        if (actionId === "modes" && !PanelFamily.nativeAppWindows) {
            GlobalStates.openModesApp("");
            return;
        }
        TouchGestureActionRegistry.trigger(actionId, screenName);
    }
}
