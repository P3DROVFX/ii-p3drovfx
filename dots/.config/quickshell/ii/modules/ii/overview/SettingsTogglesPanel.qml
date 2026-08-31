pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int activeSection: 0
    property int selectedIndex: 0
    signal requestSetSearchQuery(string query)

    readonly property string normalizedQuery: root.searchQuery.trim()
    readonly property var settingRows: {
        if (!Ai.settingsIntegration.ready)
            return [];
        return Ai.settingsIntegration.search(root.normalizedQuery, 100);
    }
    readonly property var pageRows: {
        if (!Config.options.search.modules.settingsToggles.showPages)
            return [];
        const tokens = root.normalizedQuery.toLocaleLowerCase().split(/\s+/).filter(token => token.length > 0);
        const output = [];
        for (const page of SettingsPageRegistry.pages) {
            const candidates = [Object.assign({}, page, {
                displayName: Translation.tr(page.name),
                subPage: "",
                parentName: ""
            })];
            for (const subPage of page.subPages ?? []) {
                candidates.push({
                    id: page.id,
                    icon: page.icon,
                    displayName: root.humanizeSubPage(subPage),
                    subPage: subPage,
                    parentName: Translation.tr(page.name),
                    aliases: page.aliases ?? []
                });
            }
            for (const candidate of candidates) {
                const haystack = [candidate.displayName, candidate.parentName, ...(candidate.aliases ?? []), candidate.id]
                    .join(" ").toLocaleLowerCase();
                if (tokens.length === 0 || tokens.every(token => haystack.includes(token)))
                    output.push(candidate);
            }
        }
        return output;
    }
    readonly property var activeRows: root.activeSection === 0 ? root.settingRows : root.pageRows
    readonly property var selectedRowData: root.selectedIndex >= 0 && root.selectedIndex < root.activeRows.length
        ? root.activeRows[root.selectedIndex]
        : null
    readonly property string primaryActionLabel: root.activeSection === 0 && String(root.selectedRowData?.type ?? "") === "bool"
        ? Translation.tr("Toggle")
        : Translation.tr("Open")
    readonly property bool indexing: !Ai.settingsIntegration.ready
    readonly property bool hasQuery: root.normalizedQuery.length > 0
    readonly property string statusText: root.indexing
        ? Translation.tr("Indexing settings…")
        : root.activeSection === 0
            ? Translation.tr("%1 controls").arg(String(root.settingRows.length))
            : Translation.tr("%1 pages").arg(String(root.pageRows.length))
    readonly property string emptyTitle: root.hasQuery
        ? Translation.tr("No setting matches \"%1\"").arg(root.normalizedQuery)
        : (root.activeSection === 0
            ? Translation.tr("Find any control in seconds")
            : Translation.tr("Jump straight to a Settings page"))
    readonly property string emptyDescription: root.hasQuery
        ? Translation.tr("Try a shorter name, a related feature, or one of the suggestions below.")
        : (root.activeSection === 0
            ? Translation.tr("Search by the visible control name — including composite choices such as Bar position.")
            : Translation.tr("Search Launcher, Appearance, Bar, Cheatsheet and every registered subpage."))
    readonly property var suggestions: root.activeSection === 0
        ? [Translation.tr("Bar position"), Translation.tr("Dark mode"), Translation.tr("Dock size"), Translation.tr("Clipboard")]
        : [Translation.tr("Launcher"), Translation.tr("Appearance"), Translation.tr("Bar"), Translation.tr("Cheatsheet")]

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function humanizeSubPage(path) {
        const raw = String(path ?? "").split("/").pop().replace(/Config\.qml$/, "");
        return raw.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/^Launcher\s+/, "");
    }

    function openPage(row): bool {
        if (!row?.id)
            return false;
        const pageId = String(row.id);
        const subPage = String(row.subPage ?? "");
        GlobalStates.overviewOpen = false;
        Qt.callLater(() => GlobalStates.openSettingsPage(pageId, subPage));
        return true;
    }

    function focusInput(): bool {
        return false;
    }

    function clampSelection() {
        if (root.activeRows.length === 0) {
            root.selectedIndex = -1;
            return;
        }
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.activeRows.length - 1));
    }

    function selectedDelegate() {
        return panelList.itemAtIndex(root.selectedIndex)?.item ?? null;
    }

    function navigateUp(): bool {
        if (root.activeRows.length === 0)
            return false;
        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
        panelList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.activeRows.length === 0)
            return false;
        root.selectedIndex = Math.min(root.activeRows.length - 1, root.selectedIndex + 1);
        panelList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateLeft(): bool {
        const row = root.selectedDelegate();
        return row && typeof row.navigateLeft === "function" ? row.navigateLeft() : false;
    }

    function navigateRight(): bool {
        const row = root.selectedDelegate();
        return row && typeof row.navigateRight === "function" ? row.navigateRight() : false;
    }

    function activateSelected(): bool {
        const row = root.selectedDelegate();
        return row && typeof row.activate === "function" ? row.activate() : false;
    }

    function secondaryActivateSelected(): bool {
        const row = root.selectedDelegate();
        if (!row)
            return false;
        if (typeof row.openInSettings === "function")
            return row.openInSettings();
        return typeof row.activate === "function" ? row.activate() : false;
    }

    function toggleSection(): bool {
        if (!Config.options.search.modules.settingsToggles.showPages)
            return false;
        root.activeSection = root.activeSection === 0 ? 1 : 0;
        root.selectedIndex = 0;
        return true;
    }

    function useSuggestion(query): void {
        root.requestSetSearchQuery(String(query ?? ""));
    }

    onActiveRowsChanged: root.clampSelection()
    onActiveSectionChanged: root.clampSelection()
    onSearchQueryChanged: root.selectedIndex = 0

    Component.onCompleted: {
        if (!Ai.settingsIntegration.ready)
            Ai.settingsIntegration.ensureIndex();
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Settings")
        icon: "settings"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: root.primaryActionLabel, actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Adjust"), keys: ["←", "→"] },
            { label: Translation.tr("Open Settings"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Section"), actionId: "section", keys: ["Tab"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin

                Repeater {
                    model: [
                        { label: Translation.tr("Controls"), supporting: Translation.tr("Change it here"), icon: "tune", shape: "Clover4Leaf", section: 0 },
                        { label: Translation.tr("Pages"), supporting: Translation.tr("Open the full page"), icon: "view_quilt", shape: "Arch", section: 1 }
                    ]

                    delegate: RippleButton {
                        id: sectionButton
                        required property var modelData
                        readonly property bool selected: root.activeSection === modelData.section

                        visible: modelData.section === 0 || Config.options.search.modules.settingsToggles.showPages
                        Layout.fillWidth: true
                        implicitHeight: sectionButtonContent.implicitHeight + Appearance.sizes.elevationMargin
                        buttonRadius: selected ? Appearance.rounding.large : Appearance.rounding.normal
                        toggled: selected
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                        colBackgroundToggled: Appearance.colors.colPrimaryContainer
                        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                        colBackgroundToggledActive: Appearance.colors.colPrimaryContainerActive
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        colRippleToggled: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.activeSection = modelData.section;
                            root.selectedIndex = 0;
                        }

                        contentItem: RowLayout {
                            id: sectionButtonContent
                            spacing: Appearance.sizes.elevationMargin * 0.75

                            MaterialShape {
                                implicitSize: Appearance.sizes.elevationMargin * 4
                                shapeString: sectionButton.modelData.shape
                                color: sectionButton.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: sectionButton.modelData.icon
                                    iconSize: Appearance.font.pixelSize.large
                                    color: sectionButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sectionButton.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: sectionButton.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sectionButton.modelData.supporting
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: sectionButton.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                    opacity: sectionButton.selected ? 0.78 : 1
                                }
                            }

                            ConfiguredKeyHint {
                                visible: sectionButton.selected && Config.options.search.appearance.showKeyHints
                                actionId: "section"
                                fallbackKeys: ["Tab"]
                                surface: Appearance.colors.colPrimaryContainer
                                onSurface: Appearance.colors.colOnPrimaryContainer
                            }

                            MaterialShape {
                                id: sectionCountShape
                                implicitSize: Appearance.sizes.elevationMargin * 3.2
                                shapeString: sectionButton.selected ? "Cookie6Sided" : "Cookie4Sided"
                                color: sectionButton.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer

                                StyledText {
                                    anchors.centerIn: parent
                                    text: String(sectionButton.modelData.section === 0 ? root.settingRows.length : root.pageRows.length)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: sectionButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.indexing && root.activeSection === 0
                    ? 0
                    : (root.activeRows.length > 0 ? 1 : 2)

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colSurfaceContainerHigh

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin

                        MaterialShape {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: Appearance.sizes.elevationMargin * 9
                            shapeString: "SoftBurst"
                            color: Appearance.colors.colSecondaryContainer

                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitWidth: Appearance.sizes.elevationMargin * 4
                                implicitHeight: implicitWidth
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Preparing your settings index…")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Control names and pages will appear here.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                ListView {
                    id: panelList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    reuseItems: true
                    cacheBuffer: height
                    spacing: Appearance.sizes.elevationMargin / 2
                    model: root.activeRows

                    delegate: Loader {
                        id: rowLoader
                        required property int index
                        required property var modelData
                        width: panelList.width
                        height: item?.implicitHeight ?? 0
                        sourceComponent: root.activeSection === 0 ? settingRow : pageRow

                        Component {
                            id: settingRow

                            AiSettingResultCard {
                                width: rowLoader.width
                                setting: rowLoader.modelData
                                compact: true
                                launcherStyle: true
                                expressiveStyle: true
                                listIndex: rowLoader.index
                                listCount: panelList.count
                                listCurrentIndex: root.selectedIndex
                            }
                        }

                        Component {
                            id: pageRow

                            RippleButton {
                                id: pageButton
                                readonly property bool selected: root.selectedIndex === rowLoader.index

                                implicitWidth: rowLoader.width
                                implicitHeight: pageRowContent.implicitHeight + Appearance.sizes.elevationMargin * 1.2
                                buttonRadius: selected ? Appearance.rounding.large : Appearance.rounding.normal
                                toggled: selected
                                colBackground: Appearance.colors.colSurfaceContainerHigh
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                                colBackgroundToggled: Appearance.colors.colPrimaryContainer
                                colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                                colBackgroundToggledActive: Appearance.colors.colPrimaryContainerActive
                                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                                colRippleToggled: Appearance.colors.colPrimaryContainerActive
                                onClicked: root.openPage(rowLoader.modelData)

                                function activate(): bool {
                                    return root.openPage(rowLoader.modelData);
                                }

                                function openInSettings(): bool {
                                    return root.openPage(rowLoader.modelData);
                                }

                                RowLayout {
                                    id: pageRowContent
                                    anchors.fill: parent
                                    anchors.margins: Appearance.sizes.elevationMargin * 0.6
                                    spacing: Appearance.sizes.elevationMargin * 0.75

                                    MaterialShape {
                                        implicitSize: Appearance.sizes.elevationMargin * 4
                                        shapeString: pageButton.selected ? "Cookie7Sided" : "Cookie4Sided"
                                        color: pageButton.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: rowLoader.modelData.icon
                                            iconSize: Appearance.font.pixelSize.large
                                            color: pageButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rowLoader.modelData.displayName
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.DemiBold
                                            color: pageButton.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rowLoader.modelData.parentName.length > 0 ? rowLoader.modelData.parentName : Translation.tr("Settings page")
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: pageButton.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                            opacity: pageButton.selected ? 0.78 : 1
                                        }
                                    }

                                    ConfiguredKeyHint {
                                        visible: pageButton.selected && Config.options.search.appearance.showKeyHints
                                        actionId: "activate"
                                        fallbackKeys: ["↵"]
                                        surface: Appearance.colors.colPrimaryContainer
                                        onSurface: Appearance.colors.colOnPrimaryContainer
                                    }

                                    RippleButton {
                                        implicitWidth: pageOpenContent.implicitWidth + Appearance.sizes.elevationMargin * 1.4
                                        implicitHeight: Appearance.sizes.elevationMargin * 3.6
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: pageButton.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: pageButton.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                        colRipple: pageButton.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                                        onClicked: root.openPage(rowLoader.modelData)
                                        Accessible.name: Translation.tr("Open in Settings")

                                        RowLayout {
                                            id: pageOpenContent
                                            anchors.centerIn: parent
                                            spacing: Appearance.sizes.elevationMargin / 2

                                            StyledText {
                                                text: Translation.tr("Open")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                                color: pageButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            }

                                            ConfiguredKeyHint {
                                                visible: Config.options.search.appearance.showKeyHints
                                                actionId: "secondary"
                                                fallbackKeys: ["Ctrl", "↵"]
                                                surface: pageButton.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                                onSurface: pageButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colSurfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin * 2
                        spacing: Appearance.sizes.elevationMargin * 2

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.maximumWidth: parent.width * 0.68
                            spacing: Appearance.sizes.elevationMargin

                            Item { Layout.fillHeight: true }

                            MaterialShape {
                                implicitSize: Appearance.sizes.elevationMargin * 7
                                shapeString: root.hasQuery ? "Ghostish" : "Flower"
                                color: root.hasQuery ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.hasQuery ? "search_off" : "settings_suggest"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: root.hasQuery ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.emptyTitle
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.emptyDescription
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin / 2

                                Repeater {
                                    model: root.suggestions

                                    delegate: RippleButton {
                                        id: suggestionButton
                                        required property string modelData
                                        implicitWidth: suggestionLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                                        implicitHeight: Appearance.sizes.elevationMargin * 4
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                                        colRipple: Appearance.colors.colSecondaryContainerActive
                                        onClicked: root.useSuggestion(modelData)

                                        StyledText {
                                            id: suggestionLabel
                                            anchors.centerIn: parent
                                            text: suggestionButton.modelData
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        MaterialShape {
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: Appearance.sizes.elevationMargin * 16
                            shapeString: root.activeSection === 0 ? "PuffyDiamond" : "Arch"
                            color: Appearance.colors.colTertiaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.activeSection === 0 ? "tune" : "view_quilt"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnTertiaryContainer
                            }
                        }
                    }
                }
            }
        }
    }
}
