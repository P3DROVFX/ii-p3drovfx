import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()
    property string triggerDraft: ""
    property string nameDraft: ""
    property string urlDraft: ""
    property string validationMessage: ""
    readonly property string addedMessage: Translation.tr("Shortcut added")

    function addShortcut() {
        const trigger = root.triggerDraft.trim().toLowerCase();
        const url = root.urlDraft.trim();
        if (trigger.length === 0 || /\s/.test(trigger)) {
            root.validationMessage = Translation.tr("The trigger is one word, without spaces");
            return;
        }
        if (!/^https?:\/\//i.test(url)) {
            root.validationMessage = Translation.tr("The URL must start with http:// or https://");
            return;
        }
        const entries = Array.from(Config.options.search.engineShortcuts.entries ?? []);
        if (entries.some(entry => String(entry?.trigger ?? "").toLowerCase() === trigger)) {
            root.validationMessage = Translation.tr("This trigger is already in use");
            return;
        }
        if (SearchPanelRegistry.activePrefixes.includes(trigger)) {
            root.validationMessage = Translation.tr("This trigger conflicts with an active Search prefix");
            return;
        }
        entries.push({
            trigger: trigger,
            name: root.nameDraft.trim() || trigger,
            icon: "travel_explore",
            url: url
        });
        Config.options.search.engineShortcuts.entries = entries;
        root.triggerDraft = "";
        root.nameDraft = "";
        root.urlDraft = "";
        root.validationMessage = root.addedMessage;
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton { implicitWidth: Appearance.sizes.elevationMargin * 4; implicitHeight: implicitWidth; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSecondaryContainer; colBackgroundHover: Appearance.colors.colSecondaryContainerHover; colRipple: Appearance.colors.colSecondaryContainerActive; onClicked: root.goBack(); MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer } }
            StyledText { text: Translation.tr("Web search"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }
        ContentSection {
            icon: "travel_explore"
            title: Translation.tr("Browser integration")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "language"; text: Translation.tr("Open addresses"); description: Translation.tr("Text like github.com/foo or localhost:3000 gets an “Open address” row first instead of a web search."); checked: Config.options.search.openAddress; onCheckedChanged: Config.options.search.openAddress = checked }
                ConfigSwitch { buttonIcon: "tab"; text: Translation.tr("Focus open tabs"); description: Translation.tr("Enter on an open tab raises the browser window already showing it. Only the selected tab of a window can be found; others open the page normally."); checked: Config.options.search.browserSites.focusOpenTabs; onCheckedChanged: Config.options.search.browserSites.focusOpenTabs = checked }
            }
        }
        ContentSection {
            icon: "auto_awesome"
            title: Translation.tr("Live suggestions")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "search"; text: Translation.tr("Suggest while typing"); description: Translation.tr("Asks your search engine for autocomplete. What you type is sent to it, so this only runs for web-like queries."); checked: Config.options.search.webSuggestions.enable; onCheckedChanged: Config.options.search.webSuggestions.enable = checked }
                ConfigSwitch { buttonIcon: "apps"; text: Translation.tr("Skip when an app matches"); description: Translation.tr("Typing the name of an installed application never leaves your machine."); checked: Config.options.search.webSuggestions.onlyWithoutLocalMatch; onCheckedChanged: Config.options.search.webSuggestions.onlyWithoutLocalMatch = checked }
                ConfigTextField { text: Translation.tr("Custom suggestions URL (optional)"); icon: "link"; inputText: Config.options.search.webSuggestions.customUrl; textField.onTextChanged: Config.options.search.webSuggestions.customUrl = textField.text }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: WebSuggest.endpoint.length > 0
                        ? Translation.tr("Using: %1").arg(WebSuggest.endpoint)
                        : Translation.tr("Your search engine has no known autocomplete endpoint. Set a custom URL that answers OpenSearch JSON; the query is appended.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
        ContentSection {
            icon: "bolt"
            title: Translation.tr("Engine shortcuts")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "bolt"; text: Translation.tr("Enable engine shortcuts"); description: Translation.tr("Type a trigger, a space, then your terms: “yt lofi” searches YouTube."); checked: Config.options.search.engineShortcuts.enable; onCheckedChanged: Config.options.search.engineShortcuts.enable = checked }
                ConfigTextField { text: Translation.tr("Trigger"); icon: "alternate_email"; inputText: root.triggerDraft; textField.onTextChanged: root.triggerDraft = textField.text }
                ConfigTextField { text: Translation.tr("Name"); icon: "label"; inputText: root.nameDraft; textField.onTextChanged: root.nameDraft = textField.text }
                ConfigTextField { text: Translation.tr("URL, with %s where the terms go"); icon: "link"; inputText: root.urlDraft; textField.onTextChanged: root.urlDraft = textField.text }
                RippleButton {
                    implicitWidth: addLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: addLabel.implicitHeight + Appearance.sizes.elevationMargin
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.addShortcut()
                    StyledText { id: addLabel; anchors.centerIn: parent; text: Translation.tr("Add shortcut"); color: Appearance.colors.colOnPrimaryContainer }
                }
                StyledText {
                    visible: root.validationMessage.length > 0
                    text: root.validationMessage
                    color: root.validationMessage === root.addedMessage ? Appearance.colors.colPrimary : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
        ContentSection {
            icon: "format_list_bulleted"
            title: Translation.tr("Saved shortcuts")
            Repeater {
                model: Config.options.search.engineShortcuts.entries
                delegate: ConfigSwitch {
                    required property int index
                    required property var modelData
                    buttonIcon: String(modelData.icon ?? "") || "travel_explore"
                    text: String(modelData.trigger ?? "") + " · " + String(modelData.name ?? "")
                    description: String(modelData.url ?? "")
                    checked: true
                    onCheckedChanged: if (!checked) {
                        const entries = Array.from(Config.options.search.engineShortcuts.entries ?? []);
                        entries.splice(index, 1);
                        Config.options.search.engineShortcuts.entries = entries;
                    }
                }
            }
        }
    }
}
