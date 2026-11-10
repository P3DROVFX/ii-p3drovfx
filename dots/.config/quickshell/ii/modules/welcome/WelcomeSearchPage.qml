pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * What Search actually does.
 *
 * It is the densest surface in the shell — twenty panels and sixteen leading
 * symbols — and the onboarding used to mention it once, as a button on the
 * shell-mode step. Nobody discovers that a comma searches files.
 *
 * The symbols are read from `SearchPanelRegistry` and `Config.options.search`
 * rather than written out here, so a panel the user turned off disappears from
 * this page and a rebound prefix shows its new symbol. The page supplies the
 * human labels for the query modes, which are the one part of Search that has
 * no registry of its own. Panels with no symbol are listed as buttons that
 * open them, so every panel on the page can be tried from it.
 */
Item {
    id: root

    property bool nextButtonHovered: false

    signal trySearch()
    signal trySearchPanel(string panelId)

    readonly property bool compactWidth: root.width < Appearance.rounding.verylarge * 22
    // Five across once a chip still fits "Files and folders" beside its key:
    // the symbols are a row shorter, and the named panels below get it.
    readonly property bool wideWidth: root.width >= Appearance.rounding.verylarge * 24

    /** Panels that answer to a leading symbol, in the registry's own order. */
    readonly property var panelPrefixes: SearchPanelRegistry.enabledPanels
        .filter(panel => SearchPanelRegistry.prefixOf(panel).length > 0)
        .map(panel => ({
            "prefix": SearchPanelRegistry.prefixOf(panel),
            "label": panel.label,
            "icon": panel.searchIcon || panel.icon
        }));

    /**
     * The query modes. These are not panels, so they have no registry entry —
     * only a prefix in `Config.options.search.prefix` and a switch in
     * `Config.options.search.modules`. Both are read live; only the wording is
     * from here.
     */
    readonly property var queryPrefixes: {
        const prefixes = Config.options.search.prefix;
        const modules = Config.options.search.modules;
        const candidates = [
            { "key": "app", "label": Translation.tr("Applications"), "icon": "apps", "enabled": true },
            { "key": "fileSearch", "label": Translation.tr("Files and folders"), "icon": "folder_open", "enabled": modules.fileSearch },
            { "key": "windowSearch", "label": Translation.tr("Open windows"), "icon": "select_window", "enabled": modules.windowSearch },
            { "key": "webSearch", "label": Translation.tr("Search the web"), "icon": "public", "enabled": modules.webSearch },
            { "key": "math", "label": Translation.tr("Calculator"), "icon": "calculate", "enabled": modules.math },
            { "key": "shellCommand", "label": Translation.tr("Run a command"), "icon": "terminal", "enabled": modules.shellCommand },
            { "key": "action", "label": Translation.tr("Shell actions"), "icon": "bolt", "enabled": modules.shellActions }
        ];
        return candidates
            .filter(candidate => candidate.enabled && String(prefixes[candidate.key] ?? "").length > 0)
            .map(candidate => ({
                "prefix": String(prefixes[candidate.key]),
                "label": candidate.label,
                "icon": candidate.icon
            }));
    }

    readonly property var allPrefixes: [...root.queryPrefixes, ...root.panelPrefixes]

    /**
     * Panels reached by typing their name instead of a symbol. Most of the
     * panels Search has gained live here, and a single sentence listing them
     * was the one place on the page nothing could be tried from — so each is
     * a button that opens it, with the word that summons it in the tooltip.
     */
    readonly property var keywordPanels: SearchPanelRegistry.enabledPanels
        .filter(panel => SearchPanelRegistry.prefixOf(panel).length === 0)
        .map(panel => ({
            "id": panel.id,
            "label": panel.label,
            "icon": panel.searchIcon || panel.icon,
            "keyword": (panel.keywords ?? [])[0] ?? ""
        }))

    // Search has more panels than a short window has rows. The page only
    // scrolls when it has to; with room to spare it sits still like the rest.
    StyledFlickable {
        id: pageFlick

        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.implicitHeight
        interactive: contentHeight > height
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: pageColumn

            width: pageFlick.width
            height: Math.max(pageFlick.height, implicitHeight)
            spacing: Appearance.rounding.small

            // ── What a plain query already does ──────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: heroContent.implicitHeight + Appearance.rounding.normal * 2
                radius: Appearance.rounding.large
                color: Appearance.colors.colPrimaryContainer

                RowLayout {
                    id: heroContent

                    anchors.fill: parent
                    anchors.margins: Appearance.rounding.normal
                    spacing: Appearance.rounding.small

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "search"
                        shape: MaterialShape.Shape.Sunny
                        iconSize: Appearance.font.pixelSize.large
                        padding: Appearance.rounding.small
                        fill: 1
                        color: Appearance.colors.colPrimary
                        colSymbol: Appearance.colors.colOnPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Just start typing")
                            color: Appearance.colors.colOnPrimaryContainer
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Search ranks apps, files, open windows, settings and web results together, and puts the one you meant on top.")
                            color: Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.verysmall
                        centerContent: true
                        materialIcon: "play_arrow"
                        mainText: Translation.tr("Try Search")
                        textPixelSize: Appearance.font.pixelSize.small
                        iconPixelSize: Appearance.font.pixelSize.large
                        buttonRadius: Appearance.rounding.full
                        colText: Appearance.colors.colOnPrimary
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colBackgroundActive: Appearance.colors.colPrimaryActive
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.trySearch()
                    }
                }
            }

            // ── And what a leading symbol does ───────────────────────────────
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Or lead with a symbol to go straight to one place")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.compactWidth ? 2 : root.wideWidth ? 5 : 4
                columnSpacing: Appearance.rounding.verysmall
                rowSpacing: Appearance.rounding.verysmall

                Repeater {
                    model: root.allPrefixes

                    delegate: Rectangle {
                        id: prefixChip

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.verysmall
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.rounding.verysmall
                            anchors.rightMargin: Appearance.rounding.small
                            spacing: Appearance.rounding.verysmall

                            KeyboardKey {
                                Layout.alignment: Qt.AlignVCenter
                                key: prefixChip.modelData.prefix
                                pixelSize: Appearance.font.pixelSize.small
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: prefixChip.modelData.icon
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: prefixChip.modelData.label
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // ── The panels with no symbol at all ─────────────────────────────
            StyledText {
                Layout.fillWidth: true
                visible: root.keywordPanels.length > 0
                text: Translation.tr("And many more answer to their own name — type it, or open one here")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }

            Flow {
                Layout.fillWidth: true
                visible: root.keywordPanels.length > 0
                spacing: Appearance.rounding.verysmall

                Repeater {
                    model: root.keywordPanels

                    delegate: RippleButtonWithIcon {
                        id: panelPill

                        required property var modelData

                        implicitHeight: Appearance.rounding.verylarge
                        materialIcon: panelPill.modelData.icon
                        mainText: panelPill.modelData.label
                        textPixelSize: Appearance.font.pixelSize.smaller
                        iconPixelSize: Appearance.font.pixelSize.normal
                        buttonRadius: Appearance.rounding.full
                        colText: Appearance.colors.colOnLayer1
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colBackgroundActive: Appearance.colors.colLayer1Active
                        colRipple: Appearance.colors.colLayer1Active
                        Accessible.name: Translation.tr("Open %1").arg(panelPill.modelData.label)
                        onClicked: root.trySearchPanel(panelPill.modelData.id)

                        StyledToolTip {
                            extraVisibleCondition: panelPill.modelData.keyword.length > 0
                            text: Translation.tr("Type “%1” in Search").arg(panelPill.modelData.keyword)
                        }
                    }
                }
            }
        }
    }
}
