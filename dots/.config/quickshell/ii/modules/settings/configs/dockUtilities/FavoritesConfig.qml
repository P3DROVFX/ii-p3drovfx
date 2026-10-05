import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/dock/utilities"

/**
 * The favorite sites: the list in dock order (move, remove), a form to add
 * one, and the sites the browser visits most as one-click suggestions.
 */
UtilityConfigPage {
    id: page
    title: Translation.tr("Favorites")

    readonly property var sites: Array.from(Config.options.dock.utilities.favorites.sites ?? [])
    readonly property var suggestions: (BrowserSites.sites ?? [])
        .filter(site => site?.url && !page.sites.some(saved => saved.url === site.url))
        .slice()
        .sort((a, b) => Number(b.frecency ?? 0) - Number(a.frecency ?? 0))
        .slice(0, 8)

    function save(list) {
        Config.options.dock.utilities.favorites.sites = list;
    }
    function add(title, url) {
        let clean = String(url ?? "").trim();
        if (clean.length === 0)
            return;
        if (!/^[a-z][a-z0-9+.-]*:/i.test(clean))
            clean = "https://" + clean;
        if (page.sites.some(site => site.url === clean))
            return;
        const name = String(title ?? "").trim() || clean.replace(/^https?:\/\/(www\.)?/, "").split("/")[0];
        page.save(page.sites.concat([{ title: name, url: clean }]));
    }
    function move(index, delta) {
        const list = page.sites.slice();
        const target = index + delta;
        if (target < 0 || target >= list.length)
            return;
        const item = list.splice(index, 1)[0];
        list.splice(target, 0, item);
        page.save(list);
    }
    function remove(index) {
        const list = page.sites.slice();
        list.splice(index, 1);
        page.save(list);
    }

    ContentSection {
        title: Translation.tr("Your sites")
        icon: "bookmarks"
        tooltip: Translation.tr("In the order the widget shows them")

        Repeater {
            model: page.sites
            delegate: RowLayout {
                id: siteRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 10
                SiteIcon {
                    implicitWidth: 32
                    implicitHeight: 32
                    url: siteRow.modelData.url
                    title: siteRow.modelData.title ?? ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: siteRow.modelData.title || siteRow.modelData.url
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: siteRow.modelData.url
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    enabled: siteRow.index > 0
                    onClicked: page.move(siteRow.index, -1)
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "arrow_upward"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    enabled: siteRow.index < page.sites.length - 1
                    onClicked: page.move(siteRow.index, 1)
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "arrow_downward"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    onClicked: page.remove(siteRow.index)
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "delete"; iconSize: 18; color: Appearance.colors.colOnErrorContainer }
                }
            }
        }
        StyledText {
            visible: page.sites.length === 0
            text: Translation.tr("No favorites yet. Add one below.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    ContentSection {
        title: Translation.tr("Add a site")
        icon: "bookmark_add"

        ConfigTextField {
            id: titleField
            icon: "title"
            text: Translation.tr("Name")
            placeholderText: Translation.tr("Optional")
        }
        ConfigTextField {
            id: urlField
            icon: "link"
            text: Translation.tr("Address")
            placeholderText: "github.com"
            textField.onAccepted: addButton.clicked()
        }
        RippleButtonWithIcon {
            id: addButton
            Layout.alignment: Qt.AlignRight
            materialIcon: "add"
            mainText: Translation.tr("Add")
            enabled: urlField.textField.text.trim().length > 0
            onClicked: {
                page.add(titleField.textField.text, urlField.textField.text);
                titleField.textField.text = "";
                urlField.textField.text = "";
            }
        }
    }

    ContentSection {
        visible: page.suggestions.length > 0
        title: Translation.tr("From your browser")
        icon: "travel_explore"
        tooltip: Translation.tr("The sites you visit most")

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: page.suggestions
                delegate: RippleButton {
                    id: suggestion
                    required property var modelData
                    implicitHeight: 40
                    implicitWidth: suggestionRow.implicitWidth + 24
                    buttonRadius: 20
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: page.add(suggestion.modelData.title, suggestion.modelData.url)
                    contentItem: Item {
                        RowLayout {
                            id: suggestionRow
                            anchors.centerIn: parent
                            spacing: 8
                            SiteIcon {
                                implicitWidth: 24
                                implicitHeight: 24
                                url: suggestion.modelData.url
                                title: suggestion.modelData.title ?? ""
                            }
                            StyledText {
                                text: suggestion.modelData.title || suggestion.modelData.host
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                                Layout.maximumWidth: 200
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: "add"
                                iconSize: 16
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }
        }
    }
}
