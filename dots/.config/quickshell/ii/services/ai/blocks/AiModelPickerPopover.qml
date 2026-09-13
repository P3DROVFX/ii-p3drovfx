pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The model list, grouped by provider.
 *
 * Every model says what it can do before it is picked — reasoning, images,
 * attachments, server-side search, tools — and how much it can hold, so
 * choosing does not mean remembering. A model whose key is missing is shown
 * rather than hidden: not knowing why a model is absent is worse than seeing
 * it greyed with a reason.
 */
Item {
    id: root

    signal picked(modelId: string)

    property string query: ""
    property bool openRouterModelsOpen: false
    property bool ollamaModelsOpen: false
    // Canvas hosts already provide the title and back action. OpenRouter also
    // receives the canvas refresh action; other hosts retain a standalone
    // catalogue header by default.
    property bool hostOwnsCatalogueHeader: false
    // Only canvas hosts have a deliberate full-height viewport for this page.
    // Small popovers still size naturally to their catalogue content.
    property bool fillOpenRouterAvailableHeight: false

    function closeOpenRouterModels() {
        root.openRouterModelsOpen = false;
    }

    function refreshOpenRouterModels() {
        openRouterModelsPage.refresh();
    }

    function closeOllamaModels() {
        root.ollamaModelsOpen = false;
    }

    function refreshOllamaModels() {
        Ai.refreshOllamaModels();
    }

    readonly property bool modelCatalogueOpen: root.openRouterModelsOpen || root.ollamaModelsOpen
    readonly property bool modelCatalogueCanRefresh: root.openRouterModelsOpen
    readonly property string modelCatalogueTitle: root.openRouterModelsOpen
        ? Translation.tr("OpenRouter models")
        : Translation.tr("Ollama models")

    function closeModelCatalogue() {
        if (root.openRouterModelsOpen)
            root.closeOpenRouterModels();
        else if (root.ollamaModelsOpen)
            root.closeOllamaModels();
    }

    function refreshModelCatalogue() {
        if (root.openRouterModelsOpen)
            root.refreshOpenRouterModels();
        else if (root.ollamaModelsOpen)
            root.refreshOllamaModels();
    }

    readonly property var badgeDefs: [
        {
            key: "thinking",
            symbol: "neurology",
            label: Translation.tr("Thinks")
        },
        {
            key: "vision",
            symbol: "visibility",
            label: Translation.tr("Reads images")
        },
        {
            key: "attachments",
            symbol: "attach_file",
            label: Translation.tr("Takes attachments")
        },
        {
            key: "builtinSearch",
            symbol: "travel_explore",
            label: Translation.tr("Searches the web")
        },
        {
            key: "tools",
            symbol: "service_toolbox",
            label: Translation.tr("Calls tools")
        }
    ]

    function matches(model, provider, needle: string): bool {
        if (needle.length === 0)
            return true;
        return model.title.toLowerCase().includes(needle) || model.value.toLowerCase().includes(needle) || provider.name.toLowerCase().includes(needle);
    }

    function hasKey(model): bool {
        if (!model?.requires_key)
            return true;
        return (Ai.apiKeys[model.key_id]?.length ?? 0) > 0;
    }

    function formatContext(tokens: int): string {
        if (tokens >= 1000000)
            return Translation.tr("%1M context").arg((tokens / 1000000).toFixed(tokens % 1000000 === 0 ? 0 : 1));
        if (tokens >= 1000)
            return Translation.tr("%1K context").arg(Math.round(tokens / 1000));
        return "";
    }

    function isPinned(modelId: string): bool {
        return Array.from(Config.options.sidebar.ai.pinnedModels ?? []).indexOf(modelId) >= 0;
    }

    function togglePinned(modelId: string) {
        const id = String(modelId ?? "");
        if (id.length === 0)
            return;
        const pinned = Array.from(Config.options.sidebar.ai.pinnedModels ?? []);
        Config.options.sidebar.ai.pinnedModels = pinned.indexOf(id) >= 0
            ? pinned.filter(candidate => candidate !== id)
            : pinned.concat([id]);
    }

    function pinnedModelShortcut(modelId: string): string {
        const index = Array.from(Config.options.sidebar.ai.pinnedModels ?? []).indexOf(modelId);
        return index >= 0 && index < 9 ? "Ctrl+" + String(index + 1) : "";
    }

    function modelSelectionTooltip(model): string {
        const title = String(model?.title ?? "");
        const shortcut = root.pinnedModelShortcut(String(model?.id ?? ""));
        if (shortcut.length > 0)
            return Translation.tr("Select %1\nShortcut: %2").arg(title).arg(shortcut);
        return Translation.tr("Select %1").arg(title);
    }

    function modelPinTooltip(model): string {
        const title = String(model?.title ?? "");
        const shortcut = root.pinnedModelShortcut(String(model?.id ?? ""));
        if (shortcut.length > 0)
            return Translation.tr("Unpin %1\nShortcut: %2").arg(title).arg(shortcut);
        return Translation.tr("Pin %1 for Ctrl+1 … Ctrl+9").arg(title);
    }

    /**
     * Headers and models in one flat list, so a single view draws both.
     *
     * A group folded by its header keeps only the header, and says how many
     * models it is hiding. A search folds nothing: a match that stayed hidden
     * behind a header would read as no match at all.
     */
    readonly property var rows: {
        const needle = root.query.trim().toLowerCase();
        const folded = needle.length > 0 ? [] : Ai.collapsedModelGroups;
        const rows = [];
        const pinnedIds = Array.from(Config.options.sidebar.ai.pinnedModels ?? [])
            .filter(id => Ai.catalog.models[id]);
        const pinnedModels = [];

        for (let i = 0; i < pinnedIds.length; i++) {
            const model = Ai.catalog.models[pinnedIds[i]];
            const provider = Ai.providers[model.providerId];
            if (provider && root.matches(model, provider, needle))
                pinnedModels.push(model);
        }

        if (pinnedModels.length > 0) {
            const pinnedFolded = folded.includes("pinned");
            rows.push({
                kind: "header",
                groupId: "pinned",
                label: Translation.tr("Pinned"),
                symbol: "keep",
                collapsed: pinnedFolded,
                count: pinnedModels.length
            });
            for (let i = 0; !pinnedFolded && i < pinnedModels.length; i++) {
                rows.push({
                    kind: "model",
                    model: pinnedModels[i]
                });
            }
        }

        if (needle.length === 0) {
            const recent = Ai.recentModelIds.filter(id =>
                !pinnedIds.includes(id) && !!Ai.catalog.models[id]);
            if (recent.length > 0) {
                const recentFolded = folded.includes("recent");
                rows.push({
                    kind: "header",
                    groupId: "recent",
                    label: Translation.tr("Recently used"),
                    collapsed: recentFolded,
                    count: recent.length
                });
                for (let i = 0; !recentFolded && i < recent.length; i++) {
                    rows.push({
                        kind: "model",
                        model: Ai.catalog.models[recent[i]]
                    });
                }
            }
        }

        const providerIds = Ai.providerIds;
        for (let i = 0; i < providerIds.length; i++) {
            const provider = Ai.providers[providerIds[i]];
            if (!provider)
                continue;
            const models = Array.from(provider.models).filter(model =>
                !pinnedIds.includes(model.id) && root.matches(model, provider, needle));
            const hasCatalogueEntry = providerIds[i] === "openrouter" || providerIds[i] === "ollama";
            // A fresh Ollama install has no local models yet; keeping the
            // provider visible is what makes its first pull discoverable.
            if (models.length === 0 && !hasCatalogueEntry)
                continue;
            const providerFolded = folded.includes(providerIds[i]);
            rows.push({
                kind: "header",
                groupId: providerIds[i],
                label: provider.name,
                symbol: provider.materialIcon,
                iconSource: provider.icon,
                collapsed: providerFolded,
                count: models.length
            });
            for (let j = 0; !providerFolded && j < models.length; j++) {
                rows.push({
                    kind: "model",
                    model: models[j]
                });
            }
            if (providerIds[i] === "openrouter" && !providerFolded) {
                rows.push({
                    kind: "openrouter-catalog"
                });
            }
            if (providerIds[i] === "ollama" && !providerFolded) {
                rows.push({
                    kind: "ollama-catalog"
                });
            }
        }
        return rows;
    }

    // The list already anchors to the bottom of whatever it is given, so the
    // implicit height is only the fallback for a host that has none. The old
    // 340px cap was a panel's worth of room, not a view's.
    implicitHeight: root.modelCatalogueOpen
        ? (root.openRouterModelsOpen ? openRouterModelsPage.implicitHeight : ollamaModelsPage.implicitHeight)
        : searchBox.implicitHeight + root.gap + Math.max(root.rowHeight, modelListView.contentHeight)

    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 2.5)
    readonly property real gap: Appearance.rounding.unsharpenmore
    readonly property real inset: Appearance.rounding.large

    AiOpenRouterModelsPage {
        id: openRouterModelsPage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.openRouterModelsOpen
        active: root.openRouterModelsOpen
        showHeader: !root.hostOwnsCatalogueHeader
        fillAvailableHeight: root.fillOpenRouterAvailableHeight
        onBackRequested: root.closeOpenRouterModels()
        onModelAdded: modelId => {
            // Keep the provider list live while the user adds several models.
            root.query = "";
        }
    }

    AiOllamaModelsPage {
        id: ollamaModelsPage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.ollamaModelsOpen
        active: root.ollamaModelsOpen
        showHeader: !root.hostOwnsCatalogueHeader
        fillAvailableHeight: root.fillOpenRouterAvailableHeight
        onBackRequested: root.closeOllamaModels()
    }

    component CapabilityBadge: Item {
        id: badge

        property string symbol: ""
        property string label: ""

        property color tint: Appearance.colors.colSubtext

        implicitWidth: Appearance.font.pixelSize.larger
        implicitHeight: Appearance.font.pixelSize.larger

        MaterialSymbol {
            anchors.centerIn: parent
            text: badge.symbol
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: badge.tint
        }

        MouseArea {
            id: badgeMouseArea
            anchors.fill: parent
            hoverEnabled: true
        }

        StyledToolTip {
            text: badge.label
            extraVisibleCondition: false
            alternativeVisibleCondition: badgeMouseArea.containsMouse
        }
    }

    Rectangle {
        id: searchBox
        visible: !root.modelCatalogueOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: Math.round(Appearance.font.pixelSize.huge * 2)
        radius: height / 2
        color: Appearance.colors.colLayer2

        MouseArea {
            // The whole field is a text target, not just the glyphs in it.
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            acceptedButtons: Qt.LeftButton
            onClicked: searchInput.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.inset
            anchors.rightMargin: root.gap
            spacing: root.gap

            MaterialSymbol {
                text: "search"
                fill: 1
                iconSize: 24
                color: Appearance.colors.colSubtext
            }

            StyledTextInput {
                id: searchInput
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.normal
                onTextChanged: root.query = text

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    acceptedButtons: Qt.NoButton
                }
                Component.onCompleted: forceActiveFocus()

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: Translation.tr("Search models")
                    color: Appearance.colors.colSubtext
                    font: searchInput.font
                }
            }

            RippleButton {
                visible: searchInput.text.length > 0
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: height / 2
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: searchInput.clear()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    StyledListView {
        id: modelListView
        visible: !root.modelCatalogueOpen
        // The canvas slides this whole view in; rows used to be held
        // back because entering all at once read as a second, competing
        // entrance. Staggered they read as one motion instead — the page
        // filling top-down behind the slide — so they enter again.
        staggerStep: 22
        anchors {
            top: searchBox.bottom
            topMargin: root.gap
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        spacing: root.gap
        model: root.rows

        delegate: Item {
            id: rowItem
            required property var modelData

            width: modelListView.width
            implicitHeight: rowItem.modelData.kind === "header" ? headerLoader.implicitHeight
                : rowItem.modelData.kind === "openrouter-catalog" ? catalogLoader.implicitHeight
                : rowItem.modelData.kind === "ollama-catalog" ? ollamaCatalogLoader.implicitHeight
                : modelLoader.implicitHeight

            Loader {
                id: headerLoader
                anchors.left: parent.left
                anchors.right: parent.right
                active: rowItem.modelData.kind === "header"
                visible: active

                sourceComponent: RippleButton {
                    id: headerButton

                    topPadding: root.inset
                    bottomPadding: root.gap
                    leftPadding: root.gap
                    rightPadding: root.gap
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: Ai.toggleModelGroupCollapsed(rowItem.modelData.groupId)

                    contentItem: RowLayout {
                        spacing: 12

                        Loader {
                            active: (rowItem.modelData.iconSource ?? "").length > 0
                            visible: active
                            sourceComponent: CustomIcon {
                                source: rowItem.modelData.iconSource
                                width: Appearance.font.pixelSize.larger
                                height: Appearance.font.pixelSize.larger
                                colorize: true
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        Loader {
                            active: (rowItem.modelData.iconSource ?? "").length === 0 && (rowItem.modelData.symbol ?? "").length > 0
                            visible: active
                            sourceComponent: MaterialSymbol {
                                text: rowItem.modelData.symbol
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: rowItem.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        StyledText {
                            // Only worth saying while the models themselves
                            // are out of sight.
                            visible: rowItem.modelData.collapsed ?? false
                            text: rowItem.modelData.count ?? 0
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colSubtext
                        }

                        MaterialSymbol {
                            text: "expand_more"
                            fill: 1
                            iconSize: 24
                            color: Appearance.colors.colOnLayer1
                            rotation: (rowItem.modelData.collapsed ?? false) ? -90 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animationCurves.standard
                                }
                            }
                        }
                    }

                    StyledToolTip {
                        text: (rowItem.modelData.collapsed ?? false) ? Translation.tr("Show these models") : Translation.tr("Fold this group away")
                    }
                }
            }

            Loader {
                id: modelLoader
                anchors.left: parent.left
                anchors.right: parent.right
                active: rowItem.modelData.kind === "model" && !!rowItem.modelData.model
                visible: active

                sourceComponent: RowLayout {
                    id: modelRow
                    readonly property var entry: rowItem.modelData.model
                    readonly property bool keyed: root.hasKey(modelRow.entry)
                    readonly property bool selected: modelRow.entry.id === Ai.currentModelId
                    readonly property bool pinned: root.isPinned(modelRow.entry.id)

                    spacing: root.gap

                    RippleButton {
                        id: modelSelectButton

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(root.rowHeight, modelColumn.implicitHeight + root.gap * 2)
                        leftPadding: root.inset
                        rightPadding: root.inset
                        topPadding: root.gap
                        bottomPadding: root.gap
                        buttonRadius: Appearance.rounding.large
                        toggled: modelRow.selected
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        colBackgroundToggled: Appearance.colors.colPrimary
                        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                        colRippleToggled: Appearance.colors.colPrimaryActive
                        onClicked: root.picked(modelRow.entry.id)

                        Accessible.name: root.modelSelectionTooltip(modelRow.entry)

                        readonly property color colOn: modelSelectButton.toggled
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurface

                        contentItem: ColumnLayout {
                            id: modelColumn
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: modelRow.entry.title
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.bold: true
                                elide: Text.ElideRight
                                color: modelSelectButton.colOn
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.gap

                                Repeater {
                                    model: root.badgeDefs.filter(badge => modelRow.entry[badge.key] === true)

                                    delegate: CapabilityBadge {
                                        required property var modelData

                                        symbol: modelData.symbol
                                        label: modelData.label
                                        tint: modelSelectButton.colOn
                                        opacity: 0.75
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                // A model with no key can still be read about;
                                // it just cannot be picked yet, and says so.
                                MaterialSymbol {
                                    visible: !modelRow.keyed
                                    text: "key_off"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: modelSelectButton.colOn
                                    opacity: 0.75
                                }

                                StyledText {
                                    visible: text.length > 0
                                    text: modelRow.keyed
                                        ? root.formatContext(modelRow.entry.contextWindow)
                                        : Translation.tr("No API key yet")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: modelSelectButton.colOn
                                    opacity: 0.75
                                }
                            }
                        }

                        StyledToolTip {
                            text: root.modelSelectionTooltip(modelRow.entry)
                        }
                    }

                    Rectangle {
                        id: modelActionCircle
                        Layout.preferredWidth: root.rowHeight
                        Layout.preferredHeight: root.rowHeight
                        Layout.alignment: Qt.AlignVCenter
                        radius: height / 2
                        visible: modelRow.selected
                        color: modelActionMouse.containsPress
                            ? Appearance.colors.colPrimaryContainerActive
                            : modelActionMouse.containsMouse
                                ? Appearance.colors.colPrimaryContainerHover
                                : Appearance.colors.colPrimaryContainer

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        MouseArea {
                            id: modelActionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePinned(modelRow.entry.id)
                        }

                        Accessible.name: root.modelPinTooltip(modelRow.entry)

                        Item {
                            anchors.centerIn: parent
                            width: 24
                            height: 24

                            MaterialSymbol {
                                id: modelCheckIcon
                                anchors.centerIn: parent
                                text: "check"
                                fill: 1
                                iconSize: 24
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: modelActionMouse.containsMouse ? 0 : 1
                                scale: modelActionMouse.containsMouse ? 0.5 : 1

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }
                            }

                            MaterialSymbol {
                                id: modelPinIcon
                                anchors.centerIn: parent
                                text: modelRow.pinned ? "keep_off" : "keep"
                                fill: 1
                                iconSize: 24
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: modelActionMouse.containsMouse ? 1 : 0
                                scale: modelActionMouse.containsMouse ? 1 : 0.5

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: modelActionMouse.containsMouse
                            text: root.modelPinTooltip(modelRow.entry)
                        }
                    }
                }
            }

            Loader {
                id: catalogLoader
                anchors.left: parent.left
                anchors.right: parent.right
                active: rowItem.modelData.kind === "openrouter-catalog"
                visible: active

                sourceComponent: RippleButton {
                    id: catalogButton
                    implicitHeight: root.rowHeight
                    buttonRadius: Appearance.rounding.large
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.openRouterModelsOpen = true

                    Accessible.name: Translation.tr("Browse OpenRouter models")

                    contentItem: RowLayout {
                        spacing: root.gap

                        MaterialSymbol {
                            text: "add_circle"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Browse and add OpenRouter models")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            Loader {
                id: ollamaCatalogLoader
                anchors.left: parent.left
                anchors.right: parent.right
                active: rowItem.modelData.kind === "ollama-catalog"
                visible: active

                sourceComponent: RippleButton {
                    id: ollamaCatalogButton
                    implicitHeight: root.rowHeight
                    buttonRadius: Appearance.rounding.large
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.ollamaModelsOpen = true

                    Accessible.name: Translation.tr("Browse Ollama models")

                    contentItem: RowLayout {
                        spacing: root.gap

                        MaterialSymbol {
                            text: "download"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Browse and pull Ollama models")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: modelListView
        visible: !root.modelCatalogueOpen && root.rows.length === 0
        text: Translation.tr("Nothing matches “%1”").arg(root.query)
        color: Appearance.colors.colSubtext
    }
}
