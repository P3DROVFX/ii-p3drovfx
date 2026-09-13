pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services // Translation

/**
 * Personas: a way of answering, saved whole.
 *
 * A persona is a system prompt plus the settings that go with it — which
 * model, how hard to think, how loose the sampling, what to open with. Picking
 * one sets all of them at once, which is the part that was missing: the prompt
 * was already loadable, but on its own it is only a third of what makes an
 * answer look the way somebody wanted it.
 *
 * The four shipped here are starting points, not a set: they are the shapes an
 * answer usually needs to take on a desktop like this one. Any of them can be
 * edited or deleted, and one written from scratch shadows a built-in that
 * shares its id.
 */
Scope {
    id: root

    /** Personas the user wrote, kept in the shell config next to the prompt. */
    readonly property var userPersonas: Array.from(Config.options?.ai?.personas ?? [])

    readonly property var builtIns: [
        {
            "id": "shell",
            "name": Translation.tr("Shell & Hyprland"),
            "icon": "terminal",
            "description": Translation.tr("Arch, Hyprland and the shell around them"),
            "systemPrompt": "You answer questions about an Arch Linux system running Hyprland and a Quickshell/QML desktop shell.\n\n- Give the command first, the explanation after, and only as much explanation as the command needs.\n- Prefer what is already installed. Say when something has to be installed, and with which package manager.\n- Warn plainly before anything that deletes, overwrites or needs root.\n- Context: {DISTRO}, {DE}, focused app {WINDOWCLASS}, {DATETIME}.",
            "thinking": "medium",
            "temperature": 0.3,
            "starters": [Translation.tr("Why did this unit fail to start?"), Translation.tr("Write a Hyprland bind for this"), Translation.tr("What is eating my disk space?"), Translation.tr("Explain this pacman error")]
        },
        {
            "id": "qml",
            "name": Translation.tr("QML review"),
            "icon": "code",
            "description": Translation.tr("Reads QML like someone who has to maintain it"),
            "systemPrompt": "You review QML for a Quickshell desktop shell.\n\n- Point at the specific line and say what breaks, not what could be nicer.\n- Watch for: bindings that loop, properties shadowing FINAL ones on Control subclasses, work done at load that belongs in a Loader, and anchors set on a component instead of its Loader.\n- Match the file's own style: 4-space indent, no deep nesting, early returns.\n- Code first, prose second. No praise.",
            "thinking": "high",
            "temperature": 0.2,
            "starters": [Translation.tr("Review this component"), Translation.tr("Why does this binding loop?"), Translation.tr("Make this a Loader"), Translation.tr("Is this leaking?")]
        },
        {
            "id": "study",
            "name": Translation.tr("Explain it"),
            "icon": "school",
            "description": Translation.tr("Pitched at the level you ask for, sources kept honest"),
            "systemPrompt": "You explain things to someone who wants to understand them, not to be reassured.\n\n- Match the level the question is asked at. Do not re-explain the fundamentals unless they are what was asked about.\n- Lead with the thing itself, then why it works that way, then the edge cases.\n- Say which parts are settled and which are argued over, and never invent a source: if you are not sure something exists, say so.\n- One worked example beats three paragraphs of description.",
            "thinking": "high",
            "temperature": 0.4,
            "starters": [Translation.tr("Explain this like I know the basics"), Translation.tr("What is the evidence for this claim?"), Translation.tr("Walk me through this step by step"), Translation.tr("What am I missing here?")]
        },
        {
            "id": "plain",
            "name": Translation.tr("Plain answer"),
            "icon": "chat_bubble",
            "description": Translation.tr("No headers, no bullet scaffolding"),
            "systemPrompt": "Answer in plain prose.\n\n- No headers, no bullet lists, no emoji, no bold unless a term genuinely needs it.\n- Two or three sentences unless the question needs more.\n- Say \"I don't know\" when that is the answer.",
            "thinking": "low",
            "temperature": 0.6,
            "starters": [Translation.tr("Explain this in two sentences"), Translation.tr("What is the catch here?"), Translation.tr("Is this a good idea?"), Translation.tr("Give me the short version")]
        }
    ]

    /** Every persona, the user's own last so they can shadow a built-in id. */
    readonly property var all: {
        const merged = ({});
        for (const persona of root.builtIns) {
            merged[persona.id] = persona;
        }
        for (const persona of root.userPersonas) {
            if (persona?.id)
                merged[persona.id] = Object.assign({}, merged[persona.id] ?? ({}), persona, {
                    "custom": true
                });
        }
        return Object.values(merged);
    }

    readonly property string currentId: Persistent.states?.ai?.personaId ?? ""
    readonly property var current: root.byId(root.currentId)

    function byId(id: string): var {
        if (!id || id.length === 0)
            return null;
        return root.all.find(persona => persona.id === id) ?? null;
    }

    /**
     * Whether a persona is only half in force, because something was changed
     * after it was picked. The current settings are passed in rather than read
     * from `Ai`, which holds this: nothing here reaches back up.
     */
    function modified(persona: var, modelId: string, thinking: string, temperature: real): bool {
        if (!persona)
            return false;
        if (persona.modelId && modelId !== persona.modelId)
            return true;
        if (persona.thinking && thinking !== persona.thinking)
            return true;
        if (typeof persona.temperature === "number" && Math.abs(temperature - persona.temperature) > 0.001)
            return true;
        return false;
    }

    /** True if the id names a persona the user wrote, which can be deleted. */
    function isCustom(id: string): bool {
        return root.userPersonas.some(persona => persona?.id === id);
    }

    function save(persona: var) {
        if (!persona?.id)
            return;
        const kept = root.userPersonas.filter(entry => entry?.id !== persona.id);
        kept.push(persona);
        Config.options.ai.personas = kept;
    }

    function remove(id: string) {
        Config.options.ai.personas = root.userPersonas.filter(entry => entry?.id !== id);
    }
}
