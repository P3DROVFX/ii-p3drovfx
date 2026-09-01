pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Searchable OpenRouter text-model catalogue.
 *
 * This page is a child view of AiModelPickerPopover. Selecting a row imports
 * only the normalized model definition into the user's custom model list;
 * browsing the remote catalogue never mutates configuration.
 */
Item {
    id: root

    signal backRequested
    signal modelAdded(string modelId)

    property bool active: false
    property bool showHeader: true
    // A canvas gives the catalogue a bounded viewport. Let its list consume
    // that viewport instead of reserving a fixed, short slice and leaving the
    // remaining canvas blank. Standalone popovers keep their content height.
    property bool fillAvailableHeight: false
    property string query: ""
    property list<string> addedModelIds: []
    readonly property real rowGap: Appearance.rounding.verysmall
    readonly property real maxListHeight: 520
    readonly property real cardActionExtent: Math.round(Appearance.font.pixelSize.huge * 2)

    implicitHeight: pageColumn.implicitHeight
    height: root.fillAvailableHeight && parent ? parent.height : implicitHeight

    component CapabilityBadge: Item {
        id: badge

        property string symbol: ""
        property string label: ""

        implicitWidth: Appearance.font.pixelSize.larger
        implicitHeight: Appearance.font.pixelSize.larger
        Accessible.name: badge.label

        MaterialSymbol {
            anchors.centerIn: parent
            text: badge.symbol
            fill: 1
            iconSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        MouseArea {
            id: badgeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        // StyledToolTip defaults to visible while its parent is hovered. This
        // badge has no hovered property of its own, so make the hover condition
        // explicit instead of leaving every capability tooltip open.
        StyledToolTip {
            text: badge.label
            extraVisibleCondition: false
            alternativeVisibleCondition: badgeMouseArea.containsMouse
        }
    }

    function formatContext(tokens: int): string {
        if (tokens >= 1000000)
            return Translation.tr("%1M context").arg((tokens / 1000000).toFixed(tokens % 1000000 === 0 ? 0 : 1));
        if (tokens >= 1000)
            return Translation.tr("%1K context").arg(String(Math.round(tokens / 1000)));
        return "";
    }

    function formatPriceWithFree(label: string, price: string, isFree: bool): string {
        if (price.length === 0)
            return "";
        return isFree
            ? label + " " + price
            : label + " " + price + "/M";
    }

    function modelMatches(model, needle: string): bool {
        if (needle.length === 0)
            return true;
        return model.title.toLowerCase().includes(needle)
            || model.id.toLowerCase().includes(needle)
            || model.description.toLowerCase().includes(needle);
    }

    readonly property var visibleModels: {
        const needle = root.query.trim().toLowerCase();
        return OpenRouterModels.models.filter(model => root.modelMatches(model, needle));
    }

    function isAdded(modelId: string): bool {
        if (root.addedModelIds.indexOf(modelId) >= 0 || !!Ai.catalog.models["openrouter:" + modelId])
            return true;
        const configured = Array.from(Config.options.ai.customModels ?? []);
        for (let i = 0; i < configured.length; i++) {
            const entry = configured[i];
            if (entry?.provider === "openrouter"
                    && (entry.value === modelId || entry.model === modelId))
                return true;
        }
        return false;
    }

    function addModel(model) {
        if (!model || root.isAdded(model.id))
            return;

        const list = Array.from(Config.options.ai.customModels ?? []);
        list.push({
            provider: "openrouter",
            value: model.id,
            title: model.title,
            description: model.description,
            thinking: model.supportsReasoning,
            thinkingKind: model.supportsReasoning ? "effort" : "",
            attachments: model.supportsFiles,
            vision: model.supportsVision,
            tools: model.supportsTools,
            samplingParams: model.supportsSampling,
            contextWindow: model.contextWindow,
            maxOutput: model.maxOutput,
            promptPrice: model.promptPrice,
            completionPrice: model.completionPrice,
            promptPriceIsFree: model.promptPriceIsFree,
            completionPriceIsFree: model.completionPriceIsFree,
            capabilitySource: "detected"
        });
        Config.options.ai.customModels = list;
        const added = Array.from(root.addedModelIds);
        added.push(model.id);
        root.addedModelIds = added;
        root.modelAdded(model.id);
    }

    function refresh() {
        OpenRouterModels.refresh(true);
    }

    onActiveChanged: {
        if (root.active) {
            OpenRouterModels.refresh();
            Qt.callLater(searchInput.forceActiveFocus);
        }
    }

    ColumnLayout {
        id: pageColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.fillAvailableHeight ? root.height : implicitHeight
        spacing: root.rowGap

        RowLayout {
            Layout.fillWidth: true
            visible: root.showHeader
            spacing: root.rowGap

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.backRequested()

                Accessible.name: Translation.tr("Back to model providers")
                contentItem: MaterialSymbol {
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("OpenRouter models")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Popular text models")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.refresh()

                Accessible.name: Translation.tr("Refresh OpenRouter models")
                contentItem: MaterialSymbol {
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip { text: Translation.tr("Refresh model list") }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.round(Appearance.font.pixelSize.huge * 2)
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.IBeamCursor
                onClicked: searchInput.forceActiveFocus()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Appearance.rounding.large
                anchors.rightMargin: Appearance.rounding.small
                spacing: root.rowGap

                MaterialSymbol {
                    text: "search"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    onTextChanged: root.query = text

                    Accessible.name: Translation.tr("Search OpenRouter models")

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: Qt.IBeamCursor
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: Translation.tr("Search OpenRouter models")
                        color: Appearance.colors.colSubtext
                        font: searchInput.font
                    }
                }

                RippleButton {
                    visible: searchInput.text.length > 0
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: searchInput.clear()

                    contentItem: MaterialSymbol {
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: OpenRouterModels.loading || OpenRouterModels.error.length > 0
            spacing: root.rowGap

            MaterialSymbol {
                text: OpenRouterModels.loading ? "progress_activity" : "error"
                iconSize: Appearance.font.pixelSize.normal
                color: OpenRouterModels.loading ? Appearance.colors.colPrimary : Appearance.colors.colError
            }

            StyledText {
                Layout.fillWidth: true
                text: OpenRouterModels.loading
                    ? Translation.tr("Loading the OpenRouter catalogue…")
                    : OpenRouterModels.error
                wrapMode: Text.Wrap
                color: OpenRouterModels.loading ? Appearance.colors.colSubtext : Appearance.colors.colError
            }

            RippleButton {
                visible: !OpenRouterModels.loading && OpenRouterModels.error.length > 0
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive
                onClicked: OpenRouterModels.refresh(true)

                Accessible.name: Translation.tr("Retry OpenRouter model list")
                contentItem: MaterialSymbol {
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }

        StyledListView {
            id: modelList
            Layout.fillWidth: true
            Layout.fillHeight: root.fillAvailableHeight
            Layout.minimumHeight: root.fillAvailableHeight ? 0 : 96
            Layout.preferredHeight: root.fillAvailableHeight
                ? 0
                : Math.min(root.maxListHeight, Math.max(96, contentHeight))
            visible: !OpenRouterModels.loading && OpenRouterModels.error.length === 0
            clip: true
            spacing: root.rowGap
            animatePopulate: false
            model: root.visibleModels

            delegate: Rectangle {
                id: modelCard
                required property var modelData

                width: modelList.width
                implicitHeight: cardColumn.implicitHeight + root.rowGap * 2
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Appearance.rounding.large
                    anchors.rightMargin: Appearance.rounding.small
                    anchors.topMargin: root.rowGap
                    anchors.bottomMargin: root.rowGap
                    spacing: root.rowGap

                    // Reserve an icon gutter for every card. That keeps titles
                    // and all metadata aligned whether a provider has an icon
                    // or not.
                    Item {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Appearance.font.pixelSize.larger
                        Layout.preferredHeight: Appearance.font.pixelSize.larger

                        Loader {
                            anchors.fill: parent
                            active: modelCard.modelData.providerIcon.length > 0
                            visible: active
                            sourceComponent: Item {
                                Image {
                                    visible: modelCard.modelData.providerIconIsRemote
                                    anchors.fill: parent
                                    source: visible ? modelCard.modelData.providerIcon : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                CustomIcon {
                                    visible: !modelCard.modelData.providerIconIsRemote
                                    anchors.fill: parent
                                    source: visible ? modelCard.modelData.providerIcon : ""
                                    colorize: !modelCard.modelData.providerIconUsesNaturalColors
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: modelDetailsColumn
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 0
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelCard.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelCard.modelData.id
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                            color: Appearance.colors.colSubtext
                        }

                        ColumnLayout {
                            id: modelMetadataColumn
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: root.rowGap

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    visible: modelCard.modelData.promptPrice.length > 0
                                    text: root.formatPriceWithFree(Translation.tr("Input"), modelCard.modelData.promptPrice, modelCard.modelData.promptPriceIsFree)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    visible: modelCard.modelData.completionPrice.length > 0
                                    text: root.formatPriceWithFree(Translation.tr("Output"), modelCard.modelData.completionPrice, modelCard.modelData.completionPriceIsFree)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: root.rowGap

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    visible: text.length > 0
                                    text: root.formatContext(modelCard.modelData.contextWindow)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                Repeater {
                                    model: [
                                        { enabled: modelCard.modelData.supportsReasoning, symbol: "neurology", label: Translation.tr("Reasoning") },
                                        { enabled: modelCard.modelData.supportsVision, symbol: "visibility", label: Translation.tr("Reads images") },
                                        { enabled: modelCard.modelData.supportsTools, symbol: "service_toolbox", label: Translation.tr("Calls tools") }
                                    ].filter(capability => capability.enabled)

                                    delegate: CapabilityBadge {
                                        required property var modelData
                                        symbol: modelData.symbol
                                        label: modelData.label
                                    }
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: addModelButton
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: root.cardActionExtent
                        Layout.preferredHeight: root.cardActionExtent
                        implicitWidth: root.cardActionExtent
                        implicitHeight: root.cardActionExtent
                        buttonRadius: Appearance.rounding.full
                        enabled: !root.isAdded(modelCard.modelData.id)
                        colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                        colBackgroundHover: enabled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3
                        colRipple: enabled ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
                        onClicked: root.addModel(modelCard.modelData)

                        Accessible.name: root.isAdded(modelCard.modelData.id)
                            ? Translation.tr("Model already added")
                            : Translation.tr("Add %1").arg(modelCard.modelData.title)
                        contentItem: MaterialSymbol {
                            text: root.isAdded(modelCard.modelData.id) ? "check" : "add"
                            iconSize: Appearance.font.pixelSize.normal
                            color: enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            visible: !OpenRouterModels.loading && OpenRouterModels.error.length === 0 && root.visibleModels.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            text: root.query.length > 0
                ? Translation.tr("No OpenRouter model matches this search.")
                : Translation.tr("No OpenRouter text models are available right now.")
            color: Appearance.colors.colSubtext
        }
    }
}
