pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

Item {
    id: root

    property string searchQuery: ""
    property int activeSection: 0
    property int selectedIndex: 0
    signal requestSetSearchQuery(string query)

    readonly property string normalizedQuery: root.searchQuery.trim()
    readonly property var settingRows: {
        if (!AiSettingsIntegration.ready)
            return [];
        return AiSettingsIntegration.search(root.normalizedQuery, 100);
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
    readonly property bool indexing: !AiSettingsIntegration.ready
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
        GlobalStates.closeSearchSurfaces();
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
        if (!AiSettingsIntegration.ready)
            AiSettingsIntegration.ensureIndex();
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
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

            // ── Sections: one connected button group, each half carrying its count ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 3

                Repeater {
                    model: [
                        { label: Translation.tr("Controls"), supporting: Translation.tr("Change it here"), icon: "tune", section: 0 },
                        { label: Translation.tr("Pages"), supporting: Translation.tr("Open the full page"), icon: "view_quilt", section: 1 }
                    ]

                    delegate: RippleButton {
                        id: sectionButton
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.activeSection === modelData.section
                        readonly property bool alone: !Config.options.search.modules.settingsToggles.showPages
                        readonly property real outer: Appearance.rounding.full
                        readonly property real inner: sectionButton.selected ? Appearance.rounding.full : Appearance.rounding.verysmall
                        readonly property int count: modelData.section === 0 ? root.settingRows.length : root.pageRows.length
                        readonly property color colContent: selected ? ClockStyle.colOnPrimary : ClockStyle.colOnSurface

                        visible: modelData.section === 0 || !sectionButton.alone
                        Layout.fillWidth: true
                        implicitHeight: 58
                        topLeftRadius: sectionButton.index === 0 || sectionButton.alone ? sectionButton.outer : sectionButton.inner
                        bottomLeftRadius: sectionButton.topLeftRadius
                        topRightRadius: sectionButton.index === 1 || sectionButton.alone ? sectionButton.outer : sectionButton.inner
                        bottomRightRadius: sectionButton.topRightRadius
                        toggled: selected
                        colBackground: ClockStyle.colSurfaceHigh
                        colBackgroundHover: ClockStyle.colSurfaceHover
                        colBackgroundActive: ClockStyle.colSurfaceActive
                        colBackgroundToggled: ClockStyle.colPrimary
                        colBackgroundToggledHover: ClockStyle.colPrimaryHover
                        colBackgroundToggledActive: ClockStyle.colPrimaryActive
                        colRipple: ClockStyle.colSurfaceActive
                        colRippleToggled: ClockStyle.colPrimaryActive
                        onClicked: {
                            root.activeSection = modelData.section;
                            root.selectedIndex = 0;
                        }

                        contentItem: Item {
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 22
                                anchors.rightMargin: 22
                                spacing: ClockStyle.gap

                                MaterialSymbol {
                                    text: sectionButton.modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger + 3
                                    fill: sectionButton.selected ? 1 : 0
                                    color: sectionButton.colContent
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sectionButton.modelData.label
                                        font.family: ClockStyle.fontTitle
                                        font.variableAxes: ClockStyle.axesTitle
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        color: sectionButton.colContent
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sectionButton.modelData.supporting
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: sectionButton.colContent
                                        opacity: 0.72
                                    }
                                }

                                ConfiguredKeyHint {
                                    visible: sectionButton.selected && Config.options.search.appearance.showKeyHints
                                        && !sectionButton.alone
                                    actionId: "section"
                                    fallbackKeys: ["Tab"]
                                    surface: ClockStyle.colPrimary
                                    onSurface: ClockStyle.colOnPrimary
                                }

                                // The count, in the tall condensed digits.
                                StyledText {
                                    text: root.indexing && sectionButton.modelData.section === 0 ? "…" : String(sectionButton.count)
                                    font.family: ClockStyle.fontMain
                                    font.variableAxes: sectionButton.selected ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                                    font.pixelSize: 34
                                    color: sectionButton.colContent
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
                    spacing: root.activeSection === 0 ? Appearance.sizes.elevationMargin / 2 : 2
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

                            // Grouped list: outer corners large, joins tight; the selected
                            // row turns pill and its neighbours round toward it.
                            RippleButton {
                                id: pageButton
                                readonly property bool selected: root.selectedIndex === rowLoader.index
                                readonly property bool first: rowLoader.index === 0
                                readonly property bool last: rowLoader.index === panelList.count - 1
                                readonly property bool aboveSelected: root.selectedIndex === rowLoader.index + 1
                                readonly property bool belowSelected: root.selectedIndex === rowLoader.index - 1
                                readonly property real pill: Math.min(height / 2, Appearance.rounding.large)
                                readonly property real join: Appearance.rounding.verysmall
                                readonly property color colContent: selected ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

                                implicitWidth: rowLoader.width
                                implicitHeight: 60
                                topLeftRadius: pageButton.selected || pageButton.belowSelected ? pageButton.pill
                                    : (pageButton.first ? Appearance.rounding.large : pageButton.join)
                                topRightRadius: pageButton.topLeftRadius
                                bottomLeftRadius: pageButton.selected || pageButton.aboveSelected ? pageButton.pill
                                    : (pageButton.last ? Appearance.rounding.large : pageButton.join)
                                bottomRightRadius: pageButton.bottomLeftRadius
                                toggled: selected
                                colBackground: ClockStyle.colSurfaceHigh
                                colBackgroundHover: ClockStyle.colSurfaceHover
                                colBackgroundActive: ClockStyle.colSurfaceActive
                                colBackgroundToggled: ClockStyle.colPrimaryContainer
                                colBackgroundToggledHover: ClockStyle.colPrimaryContainerHover
                                colBackgroundToggledActive: ClockStyle.colPrimaryContainerActive
                                colRipple: ClockStyle.colSurfaceActive
                                colRippleToggled: ClockStyle.colPrimaryContainerActive
                                onClicked: root.openPage(rowLoader.modelData)

                                function activate(): bool {
                                    return root.openPage(rowLoader.modelData);
                                }

                                function openInSettings(): bool {
                                    return root.openPage(rowLoader.modelData);
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 14
                                    spacing: ClockStyle.gap

                                    MaterialSymbol {
                                        text: rowLoader.modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger + 3
                                        fill: pageButton.selected ? 1 : 0
                                        color: pageButton.selected ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
                                    }

                                    // Subpages read "Parent › Page"; the parent stays a quiet caption.
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: rowLoader.modelData.parentName.length > 0
                                            text: rowLoader.modelData.parentName.toUpperCase()
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.2
                                            color: pageButton.colContent
                                            opacity: 0.66
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rowLoader.modelData.displayName
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: pageButton.selected ? Font.Bold : Font.DemiBold
                                            color: pageButton.colContent
                                        }
                                    }

                                    ConfiguredKeyHint {
                                        visible: pageButton.selected && Config.options.search.appearance.showKeyHints
                                        actionId: "activate"
                                        fallbackKeys: ["↵"]
                                        surface: ClockStyle.colPrimaryContainer
                                        onSurface: ClockStyle.colOnPrimaryContainer
                                    }

                                    Rectangle {
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        radius: pageButton.selected ? Appearance.rounding.small : Appearance.rounding.full
                                        color: pageButton.selected ? ClockStyle.colPrimary : "transparent"
                                        Behavior on color {
                                            enabled: !root.animationsDisabled
                                            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                                        }
                                        Behavior on radius {
                                            enabled: !root.animationsDisabled
                                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "arrow_outward"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: pageButton.selected ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: panelList
                    }
                }

                // Empty: a typographic hero instead of a card of decoration. Wide, heavy
                // title; the suggestions as dashed chips; one big shape bleeding off the
                // right edge, cut by the pane.
                Rectangle {
                    id: emptyPane
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ClockStyle.radiusCard
                    color: root.hasQuery ? ClockStyle.colSurfaceHigh : ClockStyle.colTertiaryContainer
                    readonly property color colContent: root.hasQuery ? ClockStyle.colOnSurface : ClockStyle.colOnTertiaryContainer

                    // A plain clip would square off the rounded corners, so the shape is
                    // cut by a mask of the pane (kept in the tree, so the window can die safely).
                    Item {
                        id: emptyOrnament
                        anchors.fill: parent
                        visible: false

                        MaterialShape {
                            readonly property real size: Math.round(emptyPane.height * 1.15)
                            implicitSize: size
                            x: emptyPane.width - size * 0.62
                            anchors.verticalCenter: parent.verticalCenter
                            shapeString: root.hasQuery ? "Ghostish" : (root.activeSection === 0 ? "Clover8Leaf" : "Arch")
                            color: ColorUtils.applyAlpha(emptyPane.colContent, 0.09)

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.size * 0.2
                                text: root.hasQuery ? "search_off" : (root.activeSection === 0 ? "tune" : "view_quilt")
                                iconSize: Math.round(parent.size * 0.2)
                                fill: 1
                                color: emptyPane.colContent
                                opacity: 0.5
                            }
                        }
                    }

                    Rectangle {
                        id: emptyOrnamentMask
                        anchors.fill: parent
                        radius: emptyPane.radius
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: emptyOrnament
                        maskEnabled: true
                        maskSource: emptyOrnamentMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: ClockStyle.pagePaddingWide + 8
                        width: Math.min(parent.width * 0.6, 460)
                        spacing: ClockStyle.gap

                        StyledText {
                            Layout.fillWidth: true
                            text: root.emptyTitle
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            lineHeight: 0.92
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ({ "wght": 760, "wdth": 118, "ROND": 100 })
                            font.pixelSize: root.hasQuery ? 30 : 38
                            color: emptyPane.colContent
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.emptyDescription
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: emptyPane.colContent
                            opacity: 0.78
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: ClockStyle.gapSmall
                            spacing: ClockStyle.gapSmall

                            Repeater {
                                model: root.suggestions

                                delegate: ClockFormChip {
                                    required property string modelData
                                    label: modelData
                                    symbol: "north_west"
                                    onTriggered: root.useSuggestion(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
