pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * Read-only OpenRouter model catalogue used by the model picker.
 *
 * The catalogue is intentionally kept separate from ModelCatalog: it is a
 * remote, changing index, while ModelCatalog contains the small set of model
 * definitions the shell can actually select. The page imports a model into
 * Config.options.ai.customModels only after the user explicitly chooses it.
 */
Singleton {
    id: root

    readonly property string endpoint: "https://openrouter.ai/api/v1/models?output_modalities=text&sort=most-popular"
    readonly property int cacheTtlMs: 300000
    readonly property int requestTimeoutMs: 15000

    property var models: []
    property bool loading: false
    property string error: ""
    property double fetchedAt: 0
    property var activeRequest: null
    // Local brand artwork for providers returned in the model ID prefix. The
    // API does not currently ship logo URLs, and local images are faster and
    // remain available when browsing from the cache.
    readonly property var brandProviderIcons: ({
        deepseek: "DeepSeek.png",
        google: "GoogleGemini.svg",
        minimax: "MiniMax.png",
        moonshotai: "MoonshotAI.png",
        nvidia: "Nvidia.jpg",
        openai: "OpenAI.svg",
        qwen: "Qwen.png",
        tencent: "Tencent.png",
        "x-ai": "SpaceXAI.png",
        xiaomi: "Xioami.png",
        "z-ai": "Zai.png"
    })

    function refresh(force = false) {
        if (!Ai.onlineAllowed) {
            root.error = Translation.tr("Online AI is disabled by the current policy.");
            return;
        }
        const now = Date.now();
        if (root.loading)
            return;
        if (!force && root.models.length > 0 && (now - root.fetchedAt) < root.cacheTtlMs)
            return;

        root.error = "";
        root.loading = true;

        const xhr = new XMLHttpRequest();
        root.activeRequest = xhr;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.activeRequest !== xhr)
                return;

            root.activeRequest = null;
            requestTimeout.stop();
            root.loading = false;
            if (xhr.status !== 200) {
                root.error = xhr.status > 0
                    ? Translation.tr("OpenRouter returned HTTP %1.").arg(String(xhr.status))
                    : Translation.tr("OpenRouter could not be reached.");
                return;
            }

            try {
                const payload = JSON.parse(xhr.responseText ?? "{}");
                const source = Array.isArray(payload.data) ? payload.data : [];
                const normalized = [];
                for (let i = 0; i < source.length; i++) {
                    const model = root.normalize(source[i]);
                    if (model)
                        normalized.push(model);
                }
                root.models = normalized;
                root.fetchedAt = Date.now();
            } catch (error) {
                root.error = Translation.tr("OpenRouter returned an invalid model list.");
                console.warn("[OpenRouterModels] Failed to parse model list:", error);
            }
        };

        xhr.open("GET", root.endpoint);
        xhr.setRequestHeader("Accept", "application/json");
        const apiKey = String(Ai.apiKeys?.openrouter ?? "").trim();
        if (apiKey.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.send();
        requestTimeout.restart();
    }

    function normalize(raw): var {
        if (!raw)
            return null;
        const id = String(raw.id ?? "").trim();
        if (id.length === 0)
            return null;

        const architecture = raw.architecture ?? ({});
        const inputModalities = Array.from(architecture.input_modalities ?? []);
        const outputModalities = Array.from(architecture.output_modalities ?? []);
        const supportedParameters = Array.from(raw.supported_parameters ?? []);
        const pricing = raw.pricing ?? ({});
        const providerIcon = root.providerIconFor(raw, id);

        return {
            id: id,
            title: String(raw.name ?? id),
            description: String(raw.description ?? ""),
            providerIcon: providerIcon,
            providerIconIsRemote: providerIcon.startsWith("http://") || providerIcon.startsWith("https://"),
            providerIconUsesNaturalColors: root.providerIconUsesNaturalColors(providerIcon),
            contextWindow: Number(raw.context_length ?? 0),
            maxOutput: Number(raw.top_provider?.max_completion_tokens ?? 0),
            inputModalities: inputModalities,
            outputModalities: outputModalities,
            supportsVision: inputModalities.indexOf("image") >= 0,
            supportsFiles: inputModalities.indexOf("file") >= 0,
            supportsTools: supportedParameters.indexOf("tools") >= 0,
            supportsReasoning: supportedParameters.indexOf("reasoning") >= 0
                || supportedParameters.indexOf("include_reasoning") >= 0,
            supportsSampling: supportedParameters.indexOf("temperature") >= 0
                || supportedParameters.indexOf("top_p") >= 0,
            promptPrice: root.pricePerMillion(pricing.prompt),
            completionPrice: root.pricePerMillion(pricing.completion),
            promptPriceIsFree: root.isFreePrice(pricing.prompt),
            completionPriceIsFree: root.isFreePrice(pricing.completion)
        };
    }

    function providerIconFor(raw, modelId: string): string {
        const providerId = root.providerIdFor(raw, modelId);
        const brandIcon = String(root.brandProviderIcons[providerId] ?? "");
        if (brandIcon.length > 0)
            return brandIcon;

        // Keep a future API-provided image available for providers without a
        // saved local asset.
        const provided = root.firstIconValue(raw);
        if (provided.length > 0)
            return provided;

        const localIcons = {
            anthropic: "bootstrap_claude.svg",
            deepseek: "deepseek-symbolic.svg",
            google: "simple-icons_googlegemini.svg",
            mistral: "mistral-symbolic.svg",
            mistralai: "mistral-symbolic.svg",
            ollama: "ollama-symbolic.svg",
            openai: "openai-symbolic.svg"
        };
        return localIcons[providerId] ?? "";
    }

    function providerIdFor(raw, modelId: string): string {
        return String(raw?.author ?? raw?.provider ?? modelId.split("/")[0] ?? "")
            .trim()
            .toLowerCase()
            .replace(/^~/, "");
    }

    function providerIconUsesNaturalColors(iconSource: string): bool {
        const source = String(iconSource ?? "");
        if (source.startsWith("http://") || source.startsWith("https://"))
            return true;
        for (const providerId in root.brandProviderIcons) {
            if (root.brandProviderIcons[providerId] === source)
                return true;
        }
        return false;
    }

    function firstIconValue(raw): string {
        const candidates = [raw?.icon, raw?.provider_icon, raw?.logo];
        for (let i = 0; i < candidates.length; i++) {
            const value = candidates[i];
            if (typeof value === "string" && value.trim().length > 0)
                return value.trim();
        }
        return "";
    }

    function isFreePrice(value): bool {
        return Number(value) === 0;
    }

    function pricePerMillion(value): string {
        const price = Number(value);
        if (!isFinite(price) || price < 0)
            return "";
        const perMillion = price * 1000000;
        if (perMillion === 0)
            return "0";
        if (perMillion >= 100)
            return "$" + perMillion.toFixed(0);
        if (perMillion >= 1)
            return "$" + perMillion.toFixed(2);
        if (perMillion >= 0.01)
            return "$" + perMillion.toFixed(4);
        return "$" + perMillion.toFixed(6);
    }

    Timer {
        id: requestTimeout
        interval: root.requestTimeoutMs
        repeat: false
        onTriggered: {
            const xhr = root.activeRequest;
            if (!xhr)
                return;
            root.activeRequest = null;
            root.loading = false;
            root.error = Translation.tr("OpenRouter request timed out.");
            xhr.abort();
        }
    }
}
