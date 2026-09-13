import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Custom models sub-page.
 *
 * The raw JSON array editor lived on the main AI page and asked the user to
 * know the entry schema by heart. Here the same `ai.customModels` list is
 * edited through forms: the fields below are the JSON keys, the user only
 * fills in values, and "Add model" assembles and appends the entry. One form
 * covers entries that extend a built-in provider, the other covers standalone
 * endpoints that land under "Others".
 */
ContentPage {
    id: page

    property bool showBackButton: false
    signal goBack()

    forceWidth: false

    // ── Form state ─────────────────────────────────────────────────────────
    property string addMode: "provider"
    property string providerDraft: providerOptions.length > 0 ? providerOptions[0].value : ""
    property string providerValueDraft: ""
    property string providerTitleDraft: ""
    property string providerNamespaceDraft: ""
    property string ownNameDraft: ""
    property string ownModelDraft: ""
    property string ownEndpointDraft: ""
    property string ownApiFormat: "openai"
    property bool ownRequiresKey: true
    property string ownKeyIdDraft: ""
    property bool ownAttachments: false
    property bool ownVision: false
    property bool ownTools: true
    property int ownContextWindow: 0
    property int ownMaxOutput: 0
    property string formError: ""
    property string formSuccess: ""

    readonly property var providerOptions: {
        const result = [];
        const ids = Ai.providerIds;
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            if (id === "others")
                continue;
            const provider = Ai.providers[id];
            if (!provider)
                continue;
            const option = { displayName: provider.name, value: id };
            if (provider.icon && provider.icon.length > 0)
                option.symbol = provider.icon;
            else if (provider.materialIcon && provider.materialIcon.length > 0)
                option.icon = provider.materialIcon;
            result.push(option);
        }
        return result;
    }

    readonly property var apiFormatOptions: [
        {
            displayName: Translation.tr("OpenAI-compatible"),
            icon: "api",
            value: "openai"
        },
        {
            displayName: Translation.tr("Gemini"),
            icon: "auto_awesome",
            value: "gemini"
        },
        {
            displayName: Translation.tr("Anthropic"),
            icon: "forum",
            value: "anthropic"
        }
    ]

    function modelList(): var {
        return Array.from(Config.options.ai.customModels ?? []);
    }

    function saveModelList(list) {
        Config.options.ai.customModels = list;
    }

    function slugFromName(name: string): string {
        const slug = String(name ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "");
        return slug.length > 0 ? slug : "custom";
    }

    function removeModel(index: int) {
        const list = modelList();
        if (index < 0 || index >= list.length)
            return;
        list.splice(index, 1);
        saveModelList(list);
    }

    function submitModel() {
        if (page.addMode === "provider")
            submitProviderModel();
        else
            submitStandaloneModel();
    }

    function submitProviderModel() {
        page.formError = "";
        page.formSuccess = "";
        const provider = String(page.providerDraft ?? "");
        const value = page.providerValueDraft.trim();
        if (provider.length === 0) {
            page.formError = Translation.tr("Pick a provider for the model first.");
            return;
        }
        if (value.length === 0) {
            page.formError = Translation.tr("The model id cannot be empty.");
            return;
        }
        const list = page.modelList();
        for (let i = 0; i < list.length; i++) {
            const entry = list[i];
            if ((entry.provider ?? "") === provider
                    && (entry.value === value || entry.model === value)) {
                page.formError = Translation.tr("That model is already in the list.");
                return;
            }
        }
        const entry = { provider: provider, value: value };
        const title = page.providerTitleDraft.trim();
        if (title.length > 0)
            entry.title = title;
        const namespace = page.providerNamespaceDraft.trim();
        if (namespace.length > 0)
            entry.modelProvider = namespace;
        list.push(entry);
        saveModelList(list);
        page.providerValueDraft = "";
        page.providerTitleDraft = "";
        page.providerNamespaceDraft = "";
        page.formSuccess = Translation.tr("Model added. It appears in the model picker right away.");
        successClearTimer.restart();
    }

    function submitStandaloneModel() {
        page.formError = "";
        page.formSuccess = "";
        const name = page.ownNameDraft.trim();
        const model = page.ownModelDraft.trim();
        const endpoint = page.ownEndpointDraft.trim();
        if (name.length === 0) {
            page.formError = Translation.tr("The display name cannot be empty.");
            return;
        }
        if (model.length === 0) {
            page.formError = Translation.tr("The model id cannot be empty.");
            return;
        }
        if (!/^https?:\/\/.+/.test(endpoint)) {
            page.formError = Translation.tr("The endpoint must be a http(s) URL, like https://example.com/v1/chat/completions.");
            return;
        }
        const keyId = page.ownKeyIdDraft.trim();
        if (page.ownRequiresKey && keyId.length === 0 && page.slugFromName(name) === "custom") {
            page.formError = Translation.tr("Give the key a short id, made of letters and numbers.");
            return;
        }
        const list = page.modelList();
        for (let i = 0; i < list.length; i++) {
            const entry = list[i];
            if ((entry.name ?? "") === name && (entry.endpoint ?? "") === endpoint) {
                page.formError = Translation.tr("That model is already in the list.");
                return;
            }
        }
        const entry = {
            name: name,
            model: model,
            endpoint: endpoint,
            api_format: page.ownApiFormat
        };
        if (page.ownRequiresKey) {
            entry.requires_key = true;
            entry.key_id = keyId.length > 0 ? keyId : page.slugFromName(name);
        } else {
            entry.requires_key = false;
        }
        // Only write the capability keys that differ from what an undeclared
        // entry already defaults to, keeping the stored JSON small.
        if (page.ownAttachments)
            entry.attachments = true;
        if (page.ownVision)
            entry.vision = true;
        if (!page.ownTools)
            entry.tools = false;
        if (page.ownContextWindow > 0)
            entry.contextWindow = page.ownContextWindow;
        if (page.ownMaxOutput > 0)
            entry.maxOutput = page.ownMaxOutput;
        list.push(entry);
        saveModelList(list);
        page.ownNameDraft = "";
        page.ownModelDraft = "";
        page.ownEndpointDraft = "";
        page.ownKeyIdDraft = "";
        page.ownAttachments = false;
        page.ownVision = false;
        page.ownTools = true;
        page.ownContextWindow = 0;
        page.ownMaxOutput = 0;
        page.formSuccess = Translation.tr("Model added. It appears under Others in the model picker.");
        successClearTimer.restart();
    }

    Timer {
        id: successClearTimer
        interval: 4000
        onTriggered: page.formSuccess = ""
    }

    RowLayout {
        visible: page.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: page.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Custom Models")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "extension"
        title: Translation.tr("Your models")

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("OpenRouter Models")
            text: Translation.tr("Explore thousands of AI models available on OpenRouter.")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Browse OpenRouter Models")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://openrouter.ai/models");
                }
            }
        }

        Repeater {
            model: page.modelList()

            Rectangle {
                id: modelRow
                required property var modelData
                required property int index

                readonly property string providerId: modelData.provider ?? ""
                readonly property var provider: providerId.length > 0 ? (Ai.providers[providerId] ?? null) : null
                readonly property string titleText: modelData.title ?? modelData.name ?? modelData.value ?? modelData.model ?? ""
                readonly property string subtitleText: {
                    if (modelRow.provider)
                        return modelRow.provider.name + " · " + (modelData.value ?? modelData.model ?? "");
                    return (modelData.endpoint ?? "") + " · " + (modelData.model ?? modelData.value ?? "");
                }
                readonly property string assetIcon: {
                    if ((modelData.icon ?? "").length > 0)
                        return modelData.icon;
                    return modelRow.provider ? (modelRow.provider.icon ?? "") : "";
                }
                readonly property string fallbackSymbol: {
                    if (modelRow.assetIcon.length > 0)
                        return "";
                    if (modelRow.provider && (modelRow.provider.materialIcon ?? "").length > 0)
                        return modelRow.provider.materialIcon;
                    return "smart_toy";
                }

                readonly property bool isFirstRow: modelRow.index === 0
                readonly property bool isLastRow: modelRow.index === page.modelList().length - 1
                readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(implicitHeight / 2, Appearance.rounding.large)

                Layout.fillWidth: true
                implicitHeight: rowLayout.implicitHeight + 20
                topLeftRadius: modelRow.isFirstRow ? modelRow.rFull : Appearance.rounding.verysmall
                topRightRadius: modelRow.isFirstRow ? modelRow.rFull : Appearance.rounding.verysmall
                bottomLeftRadius: modelRow.isLastRow ? modelRow.rFull : Appearance.rounding.verysmall
                bottomRightRadius: modelRow.isLastRow ? modelRow.rFull : Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 12

                    Loader {
                        active: modelRow.assetIcon.length > 0
                        visible: active
                        Layout.alignment: Qt.AlignVCenter
                        sourceComponent: CustomIcon {
                            source: modelRow.assetIcon
                            width: 26
                            height: 26
                            colorize: true
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Loader {
                        active: modelRow.fallbackSymbol.length > 0
                        visible: active
                        Layout.alignment: Qt.AlignVCenter
                        sourceComponent: MaterialSymbol {
                            text: modelRow.fallbackSymbol
                            iconSize: 26
                            color: Appearance.colors.colSubtext
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: modelRow.titleText
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelRow.subtitleText
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: implicitHeight
                        implicitHeight: 36
                        topLeftRadius: Appearance.rounding.full
                        topRightRadius: Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2Active
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        onClicked: page.removeModel(modelRow.index)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        // Empty state — keeps the section from collapsing into just the helper.
        ColumnLayout {
            visible: page.modelList().length === 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "browse"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("No custom models yet. Add one below — it shows up in the chat's model picker right away.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentSection {
        icon: "add_circle"
        title: Translation.tr("Add a model")

        TipBox {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            text: Translation.tr("A built-in provider entry reuses a provider the shell already knows — its endpoint, key and dialect. An own endpoint entry brings a model from any URL, listed under Others in the model picker.")
        }

        ContentSubsectionLabel {
            text: Translation.tr("Entry type")
        }

        ConfigSelectionArray {
            Layout.fillWidth: true
            currentValue: page.addMode
            onSelected: newValue => {
                page.addMode = newValue;
                page.formError = "";
            }
            options: [
                {
                    displayName: Translation.tr("Built-in provider"),
                    icon: "playlist_add",
                    value: "provider"
                },
                {
                    displayName: Translation.tr("Own endpoint"),
                    icon: "dns",
                    value: "standalone"
                }
            ]
        }

        ContentSubsectionLabel {
            visible: page.addMode === "provider"
            text: Translation.tr("Provider")
        }

        ConfigSelectionArray {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: page.addMode === "provider"
            currentValue: page.providerDraft
            onSelected: newValue => {
                page.providerDraft = newValue;
            }
            options: page.providerOptions
        }

        ConfigTextField {
            visible: page.addMode === "provider"
            Layout.fillWidth: true
            text: Translation.tr("Model id")
            icon: "badge"
            placeholderText: Translation.tr("e.g. deepseek-v4-flash")
            tooltip: Translation.tr("The id the provider expects, exactly as it appears in its model list.")
            inputText: page.providerValueDraft
            textField.onTextChanged: page.providerValueDraft = textField.text
        }

        ConfigTextField {
            visible: page.addMode === "provider"
            Layout.fillWidth: true
            text: Translation.tr("Display name")
            icon: "label"
            placeholderText: Translation.tr("Optional — shown in the picker")
            tooltip: Translation.tr("A friendly name for the model. Left empty, the model id is used.")
            inputText: page.providerTitleDraft
            textField.onTextChanged: page.providerTitleDraft = textField.text
        }

        ConfigTextField {
            visible: page.addMode === "provider"
            Layout.fillWidth: true
            text: Translation.tr("Vendor namespace")
            icon: "alt_route"
            placeholderText: Translation.tr("Optional — e.g. deepseek")
            tooltip: Translation.tr("Only needed where the provider routes by vendor, like OpenRouter's 'deepseek/model' paths.")
            inputText: page.providerNamespaceDraft
            textField.onTextChanged: page.providerNamespaceDraft = textField.text
        }

        ConfigTextField {
            visible: page.addMode === "standalone"
            Layout.fillWidth: true
            text: Translation.tr("Display name")
            icon: "label"
            placeholderText: Translation.tr("e.g. My Server")
            inputText: page.ownNameDraft
            textField.onTextChanged: page.ownNameDraft = textField.text
        }

        ConfigTextField {
            visible: page.addMode === "standalone"
            Layout.fillWidth: true
            text: Translation.tr("Model id")
            icon: "badge"
            placeholderText: Translation.tr("e.g. llama-4-70b")
            inputText: page.ownModelDraft
            textField.onTextChanged: page.ownModelDraft = textField.text
        }

        ConfigTextField {
            visible: page.addMode === "standalone"
            Layout.fillWidth: true
            text: Translation.tr("Endpoint URL")
            icon: "link"
            placeholderText: Translation.tr("https://example.com/v1/chat/completions")
            inputText: page.ownEndpointDraft
            textField.onTextChanged: page.ownEndpointDraft = textField.text
        }

        ContentSubsectionLabel {
            visible: page.addMode === "standalone"
            text: Translation.tr("API dialect")
        }

        ConfigSelectionArray {
            visible: page.addMode === "standalone"
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            currentValue: page.ownApiFormat
            onSelected: newValue => {
                page.ownApiFormat = newValue;
            }
            options: page.apiFormatOptions
        }

        ConfigSwitch {
            visible: page.addMode === "standalone"
            buttonIcon: "key"
            text: Translation.tr("Requires an API key")
            checked: page.ownRequiresKey
            onCheckedChanged: {
                if (checked !== page.ownRequiresKey)
                    page.ownRequiresKey = checked;
            }
        }

        ConfigTextField {
            visible: page.addMode === "standalone" && page.ownRequiresKey
            Layout.fillWidth: true
            text: Translation.tr("Key id")
            icon: "vpn_key"
            placeholderText: Translation.tr("Optional — derived from the name")
            tooltip: Translation.tr("Which entry of the key panel this model reads. Left empty, a short id is derived from the display name.")
            inputText: page.ownKeyIdDraft
            textField.onTextChanged: page.ownKeyIdDraft = textField.text
        }

        ContentSubsectionLabel {
            visible: page.addMode === "standalone"
            Layout.topMargin: 4
            text: Translation.tr("Capabilities")
        }

        ConfigSwitch {
            visible: page.addMode === "standalone"
            buttonIcon: "attach_file"
            text: Translation.tr("Accepts file attachments")
            checked: page.ownAttachments
            onCheckedChanged: {
                if (checked !== page.ownAttachments)
                    page.ownAttachments = checked;
            }
            StyledToolTip {
                text: Translation.tr("Only turn on what the model really handles — otherwise the chat sends files it cannot read.")
            }
        }

        ConfigSwitch {
            visible: page.addMode === "standalone"
            buttonIcon: "image"
            text: Translation.tr("Understands images")
            checked: page.ownVision
            onCheckedChanged: {
                if (checked !== page.ownVision)
                    page.ownVision = checked;
            }
            StyledToolTip {
                text: Translation.tr("Only turn on what the model really handles — otherwise the chat sends images it cannot read.")
            }
        }

        ConfigSwitch {
            visible: page.addMode === "standalone"
            buttonIcon: "build"
            text: Translation.tr("Supports tool calls")
            checked: page.ownTools
            onCheckedChanged: {
                if (checked !== page.ownTools)
                    page.ownTools = checked;
            }
            StyledToolTip {
                text: Translation.tr("Whether the model can run the assistant's tools when asked.")
            }
        }

        ContentSubsectionLabel {
            visible: page.addMode === "standalone"
            Layout.topMargin: 4
            text: Translation.tr("Limits")
        }

        ConfigSpinBox {
            visible: page.addMode === "standalone"
            icon: "crop_free"
            text: Translation.tr("Context window, in tokens (0 = unknown)")
            value: page.ownContextWindow
            from: 0
            to: 4000000
            stepSize: 32768
            onValueChanged: {
                if (value !== page.ownContextWindow)
                    page.ownContextWindow = value;
            }
        }

        ConfigSpinBox {
            visible: page.addMode === "standalone"
            icon: "notes"
            text: Translation.tr("Longest answer, in tokens (0 = the model's own limit)")
            value: page.ownMaxOutput
            from: 0
            to: 200000
            stepSize: 1024
            onValueChanged: {
                if (value !== page.ownMaxOutput)
                    page.ownMaxOutput = value;
            }
        }

        WarningBox {
            Layout.fillWidth: true
            visible: page.formError !== ""
            text: page.formError
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.formSuccess !== ""
            text: page.formSuccess
        }

        RippleButton {
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: 48
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colBackgroundActive: Appearance.colors.colPrimaryContainerActive
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: page.submitModel()

            contentItem: RowLayout {
                width: implicitWidth
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "add_circle"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Add model")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
