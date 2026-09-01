pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs

/**
 * Capability-aware response profiles shared by Search and sidebar hosts.
 *
 * A profile is a request for intent, not a promise that every model can
 * honour it. Reconciliation happens at the model boundary and returns the
 * effective values plus an explanation for any downgrade.
 */
Singleton {
    id: root

    readonly property list<string> responseModes: ["fast", "balanced", "deep"]
    readonly property list<string> webModes: ["off", "auto", "on"]
    readonly property list<string> functionExposures: ["none", "safe", "all"]

    function normalizeResponseMode(value) {
        const mode = String(value ?? "balanced").trim().toLowerCase();
        return root.responseModes.indexOf(mode) >= 0 ? mode : "balanced";
    }

    function normalizeWebMode(value) {
        const mode = String(value ?? "auto").trim().toLowerCase();
        return root.webModes.indexOf(mode) >= 0 ? mode : "auto";
    }

    function normalizeFunctionExposure(value) {
        const mode = String(value ?? "all").trim().toLowerCase();
        return root.functionExposures.indexOf(mode) >= 0 ? mode : "all";
    }

    function responseModeForThinking(level) {
        const value = String(level ?? "medium").toLowerCase();
        if (value === "off" || value === "low")
            return "fast";
        if (value === "high")
            return "deep";
        return "balanced";
    }

    function thinkingLevelFor(mode, model, requestedLevel) {
        if (!model?.thinking)
            return "off";
        const explicit = String(requestedLevel ?? "").trim().toLowerCase();
        if (explicit.length > 0) {
            if (model.thinkingAlwaysOn && explicit === "off")
                return "low";
            return ["off", "low", "medium", "high"].indexOf(explicit) >= 0 ? explicit : "medium";
        }
        const requested = root.normalizeResponseMode(mode);
        if (model.thinkingAlwaysOn && requested === "fast")
            return "low";
        if (requested === "fast")
            return "off";
        if (requested === "deep")
            return "high";
        return "medium";
    }

    /** Server-side search is exposed only when the catalog guarantees it. */
    function canForceWeb(model, onlineAllowed) {
        return !!model && !!onlineAllowed && !!model.builtinSearch && ["gemini", "anthropic"].indexOf(String(model.api_format ?? "")) >= 0;
    }

    function reconcile(model, requested, onlineAllowed, configuredTool) {
        const input = requested ?? ({});
        const responseMode = root.normalizeResponseMode(input.responseMode);
        const canWeb = root.canForceWeb(model, onlineAllowed);
        let webMode = root.normalizeWebMode(input.webMode);
        let functionExposure = root.normalizeFunctionExposure(input.functionExposure);
        const fallbackReasons = [];

        if (!onlineAllowed && webMode !== "off") {
            webMode = "off";
            fallbackReasons.push("web-policy");
        } else if (webMode === "on" && !canWeb) {
            webMode = "off";
            fallbackReasons.push("web-capability");
        }

        if (!model?.tools && functionExposure !== "none") {
            functionExposure = "none";
            fallbackReasons.push("function-capability");
        }

        let toolMode = String(configuredTool ?? "functions");
        if (webMode === "on")
            toolMode = "search";
        else if (toolMode === "search")
            toolMode = "functions";
        if (functionExposure === "none")
            toolMode = webMode === "on" ? "search" : "none";

        return {
            responseMode: responseMode,
            thinkingLevel: root.thinkingLevelFor(responseMode, model, input.thinkingLevel),
            webMode: webMode,
            functionExposure: functionExposure,
            toolMode: toolMode,
            canForceWeb: canWeb,
            fallbackReasons: fallbackReasons,
            fallbackReason: fallbackReasons.join(",")
        };
    }
}
