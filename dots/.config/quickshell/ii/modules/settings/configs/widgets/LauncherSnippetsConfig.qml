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
    property string aliasDraft: ""
    property string textDraft: ""

    function addSnippet() {
        const alias = root.aliasDraft.trim();
        const text = root.textDraft.trim();
        if (alias.length === 0 || text.length === 0)
            return;
        const items = Array.from(Config.options.search.modules.snippets.items ?? []).filter(item => String(item?.alias ?? "") !== alias);
        items.push({ alias: alias, name: alias, text: text });
        Config.options.search.modules.snippets.items = items;
        root.aliasDraft = "";
        root.textDraft = "";
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton { implicitWidth: Appearance.sizes.elevationMargin * 4; implicitHeight: implicitWidth; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSecondaryContainer; colBackgroundHover: Appearance.colors.colSecondaryContainerHover; colRipple: Appearance.colors.colSecondaryContainerActive; onClicked: root.goBack(); MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer } }
            StyledText { text: Translation.tr("Text snippets"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }
        ContentSection {
            icon: "content_cut"
            title: Translation.tr("Text snippets")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "content_cut"; text: Translation.tr("Enable text snippets"); checked: Config.options.search.modules.snippets.enable; onCheckedChanged: Config.options.search.modules.snippets.enable = checked }
                StyledText { Layout.fillWidth: true; text: Translation.tr("Tokens: {clipboard}, {date}, and {cursor}."); wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                ConfigTextField { text: Translation.tr("Alias"); icon: "alternate_email"; inputText: root.aliasDraft; textField.onTextChanged: root.aliasDraft = textField.text }
                ConfigTextField { text: Translation.tr("Text"); icon: "notes"; inputText: root.textDraft; textField.onTextChanged: root.textDraft = textField.text }
                RippleButton {
                    implicitWidth: addLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: addLabel.implicitHeight + Appearance.sizes.elevationMargin
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.addSnippet()
                    StyledText { id: addLabel; anchors.centerIn: parent; text: Translation.tr("Add snippet"); color: Appearance.colors.colOnPrimaryContainer }
                }
            }
        }
        ContentSection {
            icon: "format_list_bulleted"
            title: Translation.tr("Saved snippets")
            Repeater {
                model: Config.options.search.modules.snippets.items
                delegate: ConfigSwitch {
                    required property int index
                    required property var modelData
                    buttonIcon: "content_copy"
                    text: String(modelData.alias ?? "") + " · " + String(modelData.text ?? "")
                    checked: true
                    onCheckedChanged: if (!checked) {
                        const items = Array.from(Config.options.search.modules.snippets.items ?? []);
                        items.splice(index, 1);
                        Config.options.search.modules.snippets.items = items;
                    }
                }
            }
        }
    }
}
