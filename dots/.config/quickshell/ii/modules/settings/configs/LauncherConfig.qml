import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

Item {
    id: launcherRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Search Basics ─────────────────────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Search basics")
            tooltip: Translation.tr("Matching algorithms, result priority, and clipboard search.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "travel_explore"
                    title: Translation.tr("Search matching")
                    description: Translation.tr("Frequency-based ranking, typos, fuzzy matching and layout correction")
                    summary: (Config.options.search.typoTolerance.enable ? Translation.tr("Typo correction on") : Translation.tr("Typo correction off")) + " · " + Translation.tr("Strictness %1%").arg(Math.round(Config.options.search.typoTolerance.threshold * 100))
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherSearchMatchingConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "low_priority"
                    title: Translation.tr("Results & priority")
                    description: Translation.tr("Best Match layout and result group priority")
                    summary: Config.options.search.bestMatch.enable ? Translation.tr("Best match on") : Translation.tr("Standard layout")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherResultsConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "content_paste"
                    title: Translation.tr("Clipboard")
                    description: Translation.tr("History, previews, detectors and clipboard search")
                    summary: Translation.tr("Detectors and clipboard settings")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("ClipboardConfig.qml"))
                }
            }
        }

        // ── Search Workspace & Panels ─────────────────────────────────────────
        ContentSection {
            icon: "extension"
            title: Translation.tr("Search workspace")
            tooltip: Translation.tr("Configure every searchable panel, appearance, snippets, and shortcuts.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "dashboard_customize"
                    title: Translation.tr("Search modules")
                    description: Translation.tr("Enable panels and tune their data sources")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherModulesConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "palette"
                    title: Translation.tr("Panel appearance")
                    description: Translation.tr("Screen position, dimensions, accents, hints, and suggestions")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherAppearanceConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "link"
                    title: Translation.tr("Quicklinks")
                    description: Translation.tr("Aliases that open or copy URLs")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherQuicklinksConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "content_cut"
                    title: Translation.tr("Text snippets")
                    description: Translation.tr("Reusable text with clipboard and date tokens")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherSnippetsConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "keyboard"
                    title: Translation.tr("Search shortcuts")
                    description: Translation.tr("Keyboard reference and conflict-safe defaults")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherShortcutsConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "privacy_tip"
                    title: Translation.tr("Data & privacy")
                    description: Translation.tr("Frequency, histories, favorites and recent content")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherDataConfig.qml"))
                }
            }
        }

        // ── Advanced ──────────────────────────────────────────────────────────
        ContentSection {
            icon: "construction"
            title: Translation.tr("Advanced")
            tooltip: Translation.tr("Customize explicit prefix triggers and custom app aliases.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "tune"
                    title: Translation.tr("Prefixes")
                    description: Translation.tr("Prefix triggers and search engine behavior")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherPrefixesConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "shortcut"
                    title: Translation.tr("Aliases")
                    description: Translation.tr("Applications, commands and Search panels")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/LauncherAliasesConfig.qml"))
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
