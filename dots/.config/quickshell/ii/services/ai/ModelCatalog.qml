import QtQuick
import qs.services
import qs.modules.common

/**
 * The single source of truth for which AI providers and models exist.
 *
 * Everything the shell knows about a model — endpoint, API dialect, key,
 * display name and capabilities — is assembled here, from three inputs:
 *
 *   1. the built-in provider definitions below
 *   2. the user's config (`ai.customModels`, where an entry naming a
 *      `provider` is added to it and any other entry stands on its own)
 *   3. models discovered on the local Ollama daemon
 *
 * Consumers look models up by id, which is always "provider:value". Nothing
 * outside this file should special-case a provider name or sniff an endpoint
 * for substrings.
 */

QtObject {
    id: catalog

    property Component modelComponent: AiModel {}
    property Component providerComponent: AiProvider {}

    /** Capability records reported by the local Ollama daemon. Set by Ai. */
    property var ollamaModelNames: []

    /** Keys accepted from a standalone `ai.customModels` entry. */
    readonly property var customModelKeys: ["name", "title", "icon", "description", "homepage", "endpoint", "model", "value", "requires_key", "key_id", "key_get_link", "key_get_description", "api_format", "extraParams", "modelProvider", "thinking", "thinkingKind", "thinkingAlwaysOn", "quirks", "attachments", "vision", "embeddings", "tools", "builtinSearch", "samplingParams", "maxTemperature", "contextWindow", "maxOutput", "promptPrice", "completionPrice", "promptPriceIsFree", "completionPriceIsFree", "capabilitySource"]

    readonly property var providerDefs: [
        {
            id: "google",
            name: "Google",
            icon: "google-gemini-symbolic",
            description: Translation.tr("Online | Google's models, straight from AI Studio"),
            homepage: "https://aistudio.google.com",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent",
            api_format: "gemini",
            key_id: "gemini",
            key_get_link: "https://aistudio.google.com/app/apikey",
            key_get_description: Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            capabilities: {
                attachments: true,
                vision: true,
                tools: true,
                builtinSearch: true,
                contextWindow: 1048576,
                maxOutput: 65536
            },
            // Newest first: the head of the list is what a fresh install and
            // any chat with a model that no longer exists both fall back to.
            // The older entries stay so a saved chat from any era still
            // resolves to something.
            models: [
                {
                    value: "gemini-3.6-flash",
                    title: "Gemini 3.6 Flash",
                    thinking: true,
                    thinkingKind: "gemini-level",
                    samplingParams: false
                },
                {
                    value: "gemini-3-pro",
                    title: "Gemini 3 Pro",
                    thinking: true,
                    thinkingKind: "gemini-level",
                    samplingParams: false
                },
                {
                    value: "gemini-3-flash-preview",
                    title: "Gemini 3 Flash Preview",
                    thinking: true,
                    thinkingKind: "gemini-level",
                    samplingParams: false
                },
                {
                    value: "gemini-2.5-pro",
                    title: "Gemini 2.5 Pro",
                    thinking: true,
                    thinkingKind: "gemini-budget",
                    // The only model here whose reasoning cannot be turned off.
                    thinkingAlwaysOn: true
                },
                {
                    value: "gemini-2.5-flash",
                    title: "Gemini 2.5 Flash",
                    thinking: true,
                    thinkingKind: "gemini-budget",
                    maxOutput: 8192
                },
                {
                    value: "gemini-2.5-flash-lite",
                    title: "Gemini 2.5 Flash-Lite",
                    thinking: true,
                    thinkingKind: "gemini-budget",
                    maxOutput: 8192
                }
            ]
        },
        {
            id: "anthropic",
            name: "Anthropic",
            icon: "bootstrap_claude.svg",
            description: Translation.tr("Online | Claude models, from Anthropic directly"),
            homepage: "https://console.anthropic.com",
            endpoint: "https://api.anthropic.com/v1/messages",
            api_format: "anthropic",
            key_id: "anthropic",
            key_get_link: "https://console.anthropic.com/settings/keys",
            key_get_description: Translation.tr("**Pricing**: Pay-as-you-go (token based).\n\n**Instructions**: Log into the Anthropic Console, open Settings → API keys, and create a key."),
            capabilities: {
                attachments: true,
                vision: true,
                tools: true,
                builtinSearch: true,
                // Anthropic rejects anything above 1.
                maxTemperature: 1.0,
                contextWindow: 200000,
                maxOutput: 64000
            },
            models: [
                {
                    value: "claude-sonnet-5",
                    title: "Claude Sonnet 5",
                    thinking: true,
                    thinkingKind: "anthropic-adaptive",
                    samplingParams: false,
                    contextWindow: 1000000,
                    maxOutput: 131072
                },
                {
                    value: "claude-opus-5",
                    title: "Claude Opus 5",
                    thinking: true,
                    thinkingKind: "anthropic-adaptive",
                    samplingParams: false
                },
                {
                    value: "claude-haiku-4-5-20251001",
                    title: "Claude Haiku 4.5",
                    thinking: true,
                    thinkingKind: "anthropic-budget"
                }
            ]
        },
        {
            id: "openrouter",
            name: "OpenRouter",
            icon: "openrouter-symbolic",
            description: Translation.tr("Online | One key for models from many vendors"),
            homepage: "https://openrouter.ai",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            key_id: "openrouter",
            key_get_link: "https://openrouter.ai/settings/keys",
            key_get_description: Translation.tr("**Pricing**: Pay-as-you-go (token based).\n\n" + "**Instructions**: Log into your OpenRouter account, " + "go to Keys in the top-right menu, and create an API key."),
            capabilities: {
                tools: true,
                // OpenRouter passes image parts through to whatever model is
                // behind the id, and every model worth routing to today takes
                // them. A model entry that cannot may say so for itself with
                // `vision: false`; without this the composer turned every
                // attachment away before the request was ever built.
                attachments: true,
                vision: true
            },
            // Token counts are only sent if asked for.
            quirks: {
                usageInStream: true
            },
            models: [
                {
                    value: "gemini-2.5-flash-lite",
                    title: "Gemini 2.5 Flash-Lite",
                    modelProvider: "google",
                    thinking: true,
                    thinkingKind: "effort"
                },
                {
                    value: "deepseek-v4-flash",
                    title: "DeepSeek V4 Flash",
                    modelProvider: "deepseek",
                    thinking: true,
                    thinkingKind: "effort",
                    samplingParams: false,
                    contextWindow: 1000000,
                    maxOutput: 65536
                }
            ]
        },
        {
            id: "deepseek",
            name: "DeepSeek",
            icon: "deepseek-symbolic",
            description: Translation.tr("Online | DeepSeek Official API\nHigh intelligence AI models for coding and general tasks"),
            homepage: "https://platform.deepseek.com",
            endpoint: "https://api.deepseek.com/chat/completions",
            key_id: "deepseek",
            key_get_link: "https://platform.deepseek.com/api_keys",
            key_get_description: Translation.tr("**Pricing**: Pay-as-you-go.\n\n**Instructions**: Log into DeepSeek Platform, go to API Keys and create a key."),
            capabilities: {
                tools: true
            },
            quirks: {
                usageInStream: true
            },
            models: [
                {
                    value: "deepseek-v4-flash",
                    title: "DeepSeek V4 Flash",
                    thinking: true,
                    thinkingKind: "effort",
                    samplingParams: false,
                    contextWindow: 1000000,
                    maxOutput: 65536
                },
                {
                    value: "deepseek-v4-pro",
                    title: "DeepSeek V4 Pro",
                    thinking: true,
                    thinkingKind: "effort",
                    samplingParams: false,
                    contextWindow: 1000000,
                    maxOutput: 65536
                }
            ]
        },
        {
            id: "opencode",
            name: "OpenCode",
            materialIcon: "code",
            description: Translation.tr("Online | OpenCode Zen API\nPowered by DeepSeek V4 Flash"),
            homepage: "https://opencode.ai",
            endpoint: "https://api.opencode.ai/v1/chat/completions",
            key_id: "opencode",
            key_get_link: "https://opencode.ai",
            key_get_description: Translation.tr("**Pricing**: OpenCode subscription or API key.\n\n**Instructions**: Enter your OpenCode API key."),
            capabilities: {
                tools: true
            },
            models: [
                {
                    value: "deepseek-v4-flash",
                    title: "DeepSeek V4 Flash (Zen)",
                    thinking: true,
                    thinkingKind: "effort",
                    samplingParams: false,
                    contextWindow: 1000000,
                    maxOutput: 65536
                }
            ]
        },
        {
            id: "ollama",
            name: "Ollama",
            icon: "ollama-symbolic",
            description: Translation.tr("Local | Models installed on this machine"),
            homepage: "https://ollama.com",
            endpoint: "http://localhost:11434/v1/chat/completions",
            requires_key: false,
            local: true,
            capabilities: {
                // Plenty of local models do handle function calling, but the
                // daemon does not tell us which. Off unless the user opts in.
                tools: false
            },
            // The daemon accepts tool turns but not the usage option, and it
            // has no window of its own to report.
            quirks: {
                usageInStream: false
            },
            models: []
        },
        {
            id: "others",
            name: Translation.tr("Others"),
            materialIcon: "more_horiz",
            description: Translation.tr("Your own models, from the AI settings page"),
            models: []
        }
    ]

    readonly property var providers: {
        const result = {};
        const policy = Number(Config.options?.policies?.ai ?? 1);
        const extras = catalog.extraModelsByProvider;

        for (let i = 0; i < catalog.providerDefs.length; i++) {
            const def = catalog.providerDefs[i];
            if (policy === 0)
                continue;
            let entries = (def.models ?? []).slice();
            if (def.id === "ollama")
                entries = catalog.ollamaEntries;
            else if (def.id === "others")
                entries = catalog.customEntries;
            if (extras[def.id])
                entries = entries.concat(extras[def.id]);
            entries = entries.filter(entry => catalog.entryAllowed(def, entry));
            result[def.id] = catalog.buildProvider(def, entries);
        }
        return result;
    }

    /**
     * Local policy is an endpoint boundary, not a provider-name hint.
     * A custom model can be attached to the Ollama provider while pointing at
     * a remote host, so every effective endpoint is checked before it enters
     * the catalog.
     */
    function isLoopbackEndpoint(endpoint: string): bool {
        const value = String(endpoint ?? "").trim();
        if (value.startsWith("unix://"))
            return true;

        const match = /^(https?):\/\/([^\/?#]+)/i.exec(value);
        if (!match)
            return false;

        let authority = match[2];
        const at = authority.lastIndexOf("@");
        if (at >= 0)
            authority = authority.slice(at + 1);

        let host = authority;
        if (host.startsWith("[")) {
            const closing = host.indexOf("]");
            host = closing >= 0 ? host.slice(1, closing) : host;
        } else {
            host = host.split(":")[0];
        }
        host = host.toLowerCase();
        if (host === "localhost" || host === "::1")
            return true;
        if (/^127(?:\.\d{1,3}){3}$/.test(host))
            return true;
        return false;
    }

    function entryAllowed(def: var, entry: var): bool {
        const policy = Number(Config.options?.policies?.ai ?? 1);
        if (policy !== 2)
            return true;
        const endpoint = entry?.endpoint ?? def.endpoint ?? "";
        return catalog.isLoopbackEndpoint(endpoint);
    }

    function isModelLocal(model: var): bool {
        if (!model)
            return false;
        return catalog.isLoopbackEndpoint(model.endpoint);
    }

    readonly property var providerIds: Object.keys(catalog.providers)

    /** Every model in the catalog, keyed by "provider:value". */
    readonly property var models: {
        const result = {};
        const ids = catalog.providerIds;
        for (let i = 0; i < ids.length; i++) {
            const list = catalog.providers[ids[i]].models;
            for (let j = 0; j < list.length; j++) {
                result[list[j].id] = list[j];
            }
        }
        return result;
    }

    readonly property var modelIds: Object.keys(catalog.models)

    /** Every user-defined model, in config order. */
    readonly property var configuredModels: Array.from(Config.options?.ai?.customModels ?? [])

    /**
     * User models that name a built-in provider, as {providerId: [modelDef]}.
     * "others" is not one of them: an entry landing there stands on its own.
     */
    readonly property var extraModelsByProvider: {
        const result = {};
        const entries = catalog.configuredModels;
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (!entry)
                continue;
            const providerId = entry.provider ?? "";
            if (providerId.length === 0 || providerId === "others")
                continue;
            const collected = result[providerId] ?? [];
            collected.push(entry);
            result[providerId] = collected;
        }
        return result;
    }

    /** Discovered Ollama models, as model definitions. */
    readonly property var ollamaEntries: {
        const names = catalog.ollamaModelNames ?? [];
        const toolsAllowed = Config.options?.ai?.tools?.localModels ?? false;
        const result = [];
        for (let i = 0; i < names.length; i++) {
            const discovered = typeof names[i] === "object" ? names[i] : { name: names[i] };
            const modelName = String(discovered.name ?? "");
            const capabilities = Array.from(discovered.capabilities ?? []);
            const baseName = modelName.split(":")[0].toLowerCase();
            // Ollama's native chat API is the only API that exposes the
            // separate `message.thinking` and `message.content` fields. The
            // OpenAI compatibility endpoint can put the whole Qwen reasoning
            // trace in `reasoning_content`, leaving the final answer empty.
            // Keep discovered models on the native endpoint so thinking and
            // the answer arrive as two reliable streams.
            const detected = capabilities.length > 0;
            const thinkingModel = capabilities.indexOf("thinking") >= 0;
            result.push({
                value: modelName,
                title: catalog.guessModelName(modelName),
                icon: catalog.guessModelLogo(modelName),
                description: Translation.tr("Local Ollama model | %1").arg(modelName),
                homepage: `https://ollama.com/library/${modelName}`,
                endpoint: "http://localhost:11434/api/chat",
                api_format: "openai",
                quirks: {
                    nativeOllama: true
                },
                thinking: thinkingModel,
                thinkingKind: thinkingModel ? "ollama" : "",
                tools: detected ? capabilities.indexOf("tools") >= 0 : toolsAllowed,
                vision: capabilities.indexOf("vision") >= 0,
                attachments: capabilities.indexOf("vision") >= 0,
                embeddings: capabilities.indexOf("embedding") >= 0,
                contextWindow: Number(discovered.context_length ?? 0),
                capabilitySource: detected ? "detected" : "userOverride"
            });
        }
        return result;
    }

    /** Standalone user models, sanitised into model definitions. */
    readonly property var customEntries: {
        const entries = catalog.configuredModels;
        const result = [];
        for (let i = 0; i < entries.length; i++) {
            const raw = entries[i];
            if (!raw)
                continue;
            const providerId = raw.provider ?? "";
            if (providerId.length > 0 && providerId !== "others")
                continue;
            const entry = catalog.sanitizeCustomModel(raw);
            if (entry)
                result.push(entry);
        }
        return result;
    }

    /**
     * Drops unknown keys so a typo in the user's config cannot blow up object
     * creation, and settles on a stable selection key.
     */
    function sanitizeCustomModel(raw): var {
        if (!raw)
            return null;
        const entry = {};
        for (let i = 0; i < catalog.customModelKeys.length; i++) {
            const key = catalog.customModelKeys[i];
            if (raw[key] !== undefined)
                entry[key] = raw[key];
        }
        entry.value = raw.id || raw.value || raw.model || raw.name;
        if (!entry.value)
            return null;
        if (!entry.title)
            entry.title = raw.name || entry.value;
        return entry;
    }

    function buildProvider(def, entries) {
        const provider = catalog.providerComponent.createObject(catalog, {
            id: def.id,
            name: def.name,
            icon: def.icon ?? "",
            materialIcon: def.materialIcon ?? "",
            description: def.description ?? "",
            homepage: def.homepage ?? "",
            endpoint: def.endpoint ?? "",
            api_format: def.api_format ?? "openai",
            requires_key: def.requires_key ?? true,
            key_id: def.key_id ?? def.id,
            key_get_link: def.key_get_link ?? "",
            key_get_description: def.key_get_description ?? "",
            local: def.local ?? false
        });
        const models = [];
        for (let i = 0; i < entries.length; i++) {
            const model = catalog.buildModel(def, provider, entries[i]);
            if (model)
                models.push(model);
        }
        provider.models = models;
        return provider;
    }

    function buildModel(def, provider, entry) {
        const value = entry.value ?? entry.model ?? "";
        if (value.length === 0)
            return null;
        const caps = def.capabilities ?? {};
        const pick = (key, fallback) => entry[key] ?? caps[key] ?? fallback;
        const title = entry.title ?? value;
        const endpoint = (entry.endpoint ?? provider.endpoint ?? "").replace("{model}", entry.model ?? value);
        const modelProvider = entry.modelProvider ?? "";
        return catalog.modelComponent.createObject(catalog, {
            id: `${provider.id}:${value}`,
            providerId: provider.id,
            value: value,
            title: title,
            modelProvider: modelProvider,
            name: provider.id === "others" ? title : `${provider.name} - ${title}`,
            icon: entry.icon ?? provider.icon,
            materialIcon: (entry.icon ?? provider.icon).length > 0 ? "" : (provider.materialIcon.length > 0 ? provider.materialIcon : "wand_stars"),
            description: entry.description ?? provider.description,
            homepage: entry.homepage ?? provider.homepage,
            endpoint: endpoint,
            model: modelProvider.length > 0 ? `${modelProvider}/${value}` : (entry.model ?? value),
            requires_key: entry.requires_key ?? provider.requires_key,
            key_id: entry.key_id ?? provider.key_id,
            key_get_link: entry.key_get_link ?? provider.key_get_link,
            key_get_description: entry.key_get_description ?? provider.key_get_description,
            api_format: entry.api_format ?? provider.api_format,
            extraParams: entry.extraParams ?? ({}),
            thinking: pick("thinking", false),
            thinkingKind: pick("thinkingKind", ""),
            thinkingAlwaysOn: pick("thinkingAlwaysOn", false),
            attachments: pick("attachments", false),
            vision: pick("vision", false),
            embeddings: pick("embeddings", false),
            capabilitySource: pick("capabilitySource", "knownCatalog"),
            tools: pick("tools", true),
            builtinSearch: pick("builtinSearch", false),
            samplingParams: pick("samplingParams", true),
            maxTemperature: pick("maxTemperature", 2.0),
            contextWindow: pick("contextWindow", 0),
            maxOutput: pick("maxOutput", 0),
            promptPrice: pick("promptPrice", ""),
            completionPrice: pick("completionPrice", ""),
            promptPriceIsFree: pick("promptPriceIsFree", false),
            completionPriceIsFree: pick("completionPriceIsFree", false),
            // Merged, not picked: a model overrides single quirks without
            // having to restate the ones its provider already declared.
            quirks: Object.assign({}, def.quirks ?? ({}), entry.quirks ?? ({}))
        });
    }

    /** The model at "provider:value", or null. */
    function resolve(providerId, value) {
        return catalog.models[`${providerId}:${value}`] ?? null;
    }

    /** Selection entries for a provider, in the shape the model pickers want. */
    function selectionEntries(providerId: string): var {
        const provider = catalog.providers[providerId];
        if (!provider)
            return [];
        return provider.models.map(model => ({
                    title: model.title,
                    value: model.value,
                    modelProvider: model.modelProvider
                }));
    }

    function guessModelLogo(model: string): string {
        if (model.includes("llama"))
            return "ollama-symbolic";
        if (model.includes("gemma"))
            return "google-gemini-symbolic";
        if (model.includes("deepseek"))
            return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model))
            return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model: string): string {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`);
        words = words.map(word => {
            return (word.charAt(0).toUpperCase() + word.slice(1));
        });
        if (words[words.length - 1] === "Latest")
            words.pop();
        else
            words[words.length - 1] = `(${words[words.length - 1]})`;
        return words.join(' ');
    }
}
