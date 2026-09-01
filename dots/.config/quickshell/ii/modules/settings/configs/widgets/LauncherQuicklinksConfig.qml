import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()
    property string aliasDraft: ""
    property string urlDraft: ""
    property string iconPathDraft: ""
    property string validationMessage: ""

    function addLink() {
        const alias = root.aliasDraft.trim();
        const url = root.urlDraft.trim();
        if (alias.length === 0) {
            root.validationMessage = Translation.tr("Enter a short alias first");
            return;
        }
        if (!/^https?:\/\//.test(url)) {
            root.validationMessage = Translation.tr("The URL must start with http:// or https://");
            return;
        }
        const links = Array.from(Config.options.search.modules.quicklinks.links ?? []);
        if (links.some(link => String(link?.alias ?? "").toLocaleLowerCase() === alias.toLocaleLowerCase())) {
            root.validationMessage = Translation.tr("This alias is already in use");
            return;
        }
        if (SearchPanelRegistry.activePrefixes.includes(alias)) {
            root.validationMessage = Translation.tr("This alias conflicts with an active Search prefix");
            return;
        }
        links.push({
            alias: alias,
            name: alias,
            url: url,
            icon: "link",
            iconPath: root.iconPathDraft.trim(),
            openWith: "default"
        });
        Config.options.search.modules.quicklinks.links = links;
        root.aliasDraft = "";
        root.urlDraft = "";
        root.iconPathDraft = "";
        root.validationMessage = Translation.tr("Quicklink added");
    }

    FileDialog {
        id: quicklinkImageDialog
        title: Translation.tr("Choose a Quicklink image")
        currentFolder: "file://" + Quickshell.env("HOME")
        nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.svg *.gif)"), Translation.tr("All files (*)")]
        onAccepted: root.iconPathDraft = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton { implicitWidth: Appearance.sizes.elevationMargin * 4; implicitHeight: implicitWidth; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSecondaryContainer; colBackgroundHover: Appearance.colors.colSecondaryContainerHover; colRipple: Appearance.colors.colSecondaryContainerActive; onClicked: root.goBack(); MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer } }
            StyledText { text: Translation.tr("Quicklinks"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }
        ContentSection {
            icon: "link"
            title: Translation.tr("Quicklinks")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "link"; text: Translation.tr("Enable quicklinks"); description: Translation.tr("Type a saved alias in Search to open its URL. Text after the alias replaces {query} in parameterized links."); checked: Config.options.search.modules.quicklinks.enable; onCheckedChanged: Config.options.search.modules.quicklinks.enable = checked }
                ConfigSwitch { buttonIcon: "content_copy"; text: Translation.tr("Copy instead of open on Enter"); description: Translation.tr("Enter copies the resolved URL and keeps Search open; the action menu can still open it."); checked: Config.options.search.modules.quicklinks.copyOnEnter; onCheckedChanged: Config.options.search.modules.quicklinks.copyOnEnter = checked }
                ConfigSwitch { buttonIcon: "image"; text: Translation.tr("Fetch website icons"); description: Translation.tr("Uses the site favicon when a Quicklink has no custom image. Disable this to keep the default Material link icon."); checked: Config.options.search.modules.quicklinks.fetchFavicons; onCheckedChanged: Config.options.search.modules.quicklinks.fetchFavicons = checked }
                ConfigTextField { text: Translation.tr("Alias"); icon: "alternate_email"; inputText: root.aliasDraft; textField.onTextChanged: root.aliasDraft = textField.text }
                ConfigTextField { text: Translation.tr("URL"); icon: "link"; inputText: root.urlDraft; textField.onTextChanged: root.urlDraft = textField.text }
                ConfigTextField { text: Translation.tr("Custom image path or URL (optional)"); icon: "image"; inputText: root.iconPathDraft; textField.onTextChanged: root.iconPathDraft = textField.text }
                RippleButton {
                    implicitWidth: imagePickerLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: imagePickerLabel.implicitHeight + Appearance.sizes.elevationMargin
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: quicklinkImageDialog.open()
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialSymbol { text: "image_search"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSecondaryContainer }
                        StyledText { id: imagePickerLabel; text: Translation.tr("Choose image"); color: Appearance.colors.colOnSecondaryContainer }
                    }
                }
                RippleButton {
                    implicitWidth: addLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: addLabel.implicitHeight + Appearance.sizes.elevationMargin
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.addLink()
                    StyledText { id: addLabel; anchors.centerIn: parent; text: Translation.tr("Add quicklink"); color: Appearance.colors.colOnPrimaryContainer }
                }
                StyledText {
                    visible: root.validationMessage.length > 0
                    text: root.validationMessage
                    color: root.validationMessage === Translation.tr("Quicklink added")
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
        ContentSection {
            icon: "format_list_bulleted"
            title: Translation.tr("Saved links")
            Repeater {
                model: Config.options.search.modules.quicklinks.links
                delegate: ConfigSwitch {
                    required property int index
                    required property var modelData
                    buttonIcon: "link"
                    text: String(modelData.alias ?? modelData.name ?? "") + " · " + String(modelData.url ?? "")
                    description: String(modelData.iconPath ?? "").length > 0
                        ? Translation.tr("Custom image: ") + String(modelData.iconPath)
                        : Translation.tr("Uses the default link icon")
                    checked: true
                    onCheckedChanged: if (!checked) {
                        const links = Array.from(Config.options.search.modules.quicklinks.links ?? []);
                        links.splice(index, 1);
                        Config.options.search.modules.quicklinks.links = links;
                    }
                }
            }
        }
    }
}
