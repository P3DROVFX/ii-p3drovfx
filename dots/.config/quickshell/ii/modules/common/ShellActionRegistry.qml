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
            usage: ["usage", "uso", "stats"], modes: ["modes", "routines", "rotinas"],
            colorPicker: ["color picker", "cor", "hex"], wallpaperSelector: ["wallpaper", "papel de parede"],
            overlay: ["overlay", "widgets"], osk: ["osk", "teclado"],
            session: ["session", "logout", "desligar"], regionOcr: ["ocr", "texto da tela"],
            screenTranslate: ["translate screen", "traduzir tela"], regionRecord: ["record", "gravar"],
            regionScreenshot: ["screenshot", "print", "snip"], localSend: ["localsend", "enviar arquivo"],
            videoEditor: ["video editor", "editar video"], notes: ["notes", "notas", "quick notes"], scratchpad: ["scratchpad"],
            mediaControls: ["media controls", "player"], barToggle: ["bar", "barra"]
        };
        return base.concat(extras[action.id] ?? []);
    }

    readonly property var extraActions: [
        { id: "notes", name: "Notes", icon: "note_stack", category: "shell", searchable: true, enabled: () => true }
    ]

    readonly property var actions: TouchGestureActionRegistry.actions.concat(root.extraActions).map(action => Object.assign({}, action, {
        keywords: action.keywords ?? root.keywordsFor(action),
        category: action.category ?? "shell",
        searchable: action.searchable !== false,
        enabled: action.enabled ?? (() => true)
    }))

    function actionById(actionId) {
        return actions.find(action => action.id === actionId) ?? actions[0];
    }

    function trigger(actionId, screenName) {
        if (actionId === "notes") {
            GlobalStates.notesOpen = true;
            return;
        }
        TouchGestureActionRegistry.trigger(actionId, screenName);
    }
}
