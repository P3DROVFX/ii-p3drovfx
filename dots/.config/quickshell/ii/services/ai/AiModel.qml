import QtQuick;

/**
 * A single AI model, as served by one provider.
 *
 * Identity
 * - id: Catalog id, always "provider:value". Unique across the whole catalog.
 * - providerId: Id of the provider serving this model
 * - value: Bare model name as the user picks it (what gets persisted)
 * - model: Model name as the API wants it. Same as `value` except where the
 *   provider namespaces it, e.g. OpenRouter's "google/gemini-2.5-flash".
 * - modelProvider: Namespace prefix used to build `model`, when the provider
 *   needs one.
 * - title: Short display name, e.g. "Gemini 2.5 Flash"
 * - name: Fully qualified display name, e.g. "Google - Gemini 2.5 Flash"
 *
 * Connection (inherited from the provider unless overridden)
 * - endpoint, api_format, requires_key, key_id, key_get_link,
 *   key_get_description, homepage, icon, description
 * - extraParams: Extra JSON merged into the request body
 *
 * Capabilities. Everything the UI needs to know about what a model can do
 * lives here, so no part of the shell has to test endpoints or provider names
 * for substrings.
 * - thinking: Model can produce reasoning/thought output
 * - thinkingKind: Which knob turns it on — "gemini-level" (3.x), a
 *   "gemini-budget" (2.5), "anthropic-adaptive", "anthropic-budget" or
 *   "effort"
 * - thinkingAlwaysOn: Reasoning cannot be turned off for this model
 * - attachments: Model accepts file uploads
 * - vision: Model can read images
 * - tools: Model supports function calling / built-in tools
 * - builtinSearch: Provider offers a server-side web search tool
 * - samplingParams: Model still honours temperature/top_p. Newer reasoning
 *   models ignore or reject them.
 * - maxTemperature: Top of the temperature range this API accepts
 * - contextWindow / maxOutput: Token limits, 0 when unknown
 *
 * Quirks. Deviations from the dialect a model otherwise speaks, so one
 * strategy can serve every OpenAI-compatible provider without knowing their
 * names. Read as `model.quirks.<key>`, always with a default.
 */

QtObject {
    property string id
    property string providerId
    property string value
    property string title
    property string modelProvider

    property string name
    property string icon
    property string materialIcon
    property string description
    property string homepage
    property string endpoint
    property string model
    property bool requires_key: true
    property string key_id
    property string key_get_link
    property string key_get_description
    property string api_format: "openai"
    property var extraParams: ({})

    property bool thinking: false
    property string thinkingKind: ""
    property bool thinkingAlwaysOn: false
    property bool attachments: false
    property bool vision: false
    property bool embeddings: false
    /** detected | knownCatalog | userOverride | unavailable */
    property string capabilitySource: "knownCatalog"
    property bool tools: true
    property bool builtinSearch: false
    property bool samplingParams: true
    property real maxTemperature: 2.0
    property int contextWindow: 0
    property int maxOutput: 0
    /** OpenRouter's USD price per million input tokens, empty when unknown. */
    property string promptPrice: ""
    /** OpenRouter's USD price per million output tokens, empty when unknown. */
    property string completionPrice: ""
    property bool promptPriceIsFree: false
    property bool completionPriceIsFree: false
    property var quirks: ({})
}
