import QtQuick;

/**
 * A service that serves AI models: a base endpoint, one API dialect, one API
 * key, and the list of models reachable through it.
 *
 * - id: Provider key, e.g. "google". Also the first half of every model id.
 * - icon: CustomIcon asset name. Providers without an asset use materialIcon.
 * - materialIcon: Material symbol name, used when `icon` is empty.
 * - endpoint: May contain "{model}", substituted per model.
 * - local: Endpoint lives on this machine. Online-only policies filter on it.
 * - models: AiModel objects, in display order. The first one is the default.
 */

QtObject {
    property string id
    property string name
    property string icon
    property string materialIcon
    property string description
    property string homepage
    property string endpoint
    property string api_format: "openai"
    property bool requires_key: true
    property string key_id
    property string key_get_link
    property string key_get_description
    property bool local: false
    property var models: []

    readonly property var defaultModel: models.length > 0 ? models[0] : null

    function modelFor(value): var {
        for (let i = 0; i < models.length; i++) {
            if (models[i].value === value)
                return models[i];
        }
        return null;
    }
}
