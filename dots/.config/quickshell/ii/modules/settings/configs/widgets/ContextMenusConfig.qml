import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.background
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.contextMenus
import qs.modules.settings.configs.interface
import qs.modules.settings.configs.island
import qs.modules.settings.configs.windows
import qs.modules.settings.configs.workspaces
import qs.services

/**
 * Settings → Background → Context menus (a sub-page; the desktop's own menu is the
 * one most people meet first).
 *
 * Leads with the menu being edited, live, drawn by the shell's own menu pieces over the
 * wallpaper. Under it: the style every ii right-click menu shares (comfortable or
 * compact), how submenus open (inside the menu or as a card beside it), which menu to
 * edit, and that menu's entries - their order, the compact icon bar, hidden entries,
 * separators and the user's own commands. Search indexes
 * sections/ContextMenusOptionsSection.qml for everything drawn here.
 */
Item {
    id: menusRoot
    anchors.fill: parent

    readonly property real sectionGap: 12
    readonly property var cfg: Config.options.contextMenu
    property string menuId: "desktop"

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        BackgroundSubPageHeader {
            visible: menusRoot.showBackButton
            title: Translation.tr("Context menus")
            onBackRequested: menusRoot.goBack()
        }

        ContextMenusStage {
            Layout.fillWidth: true
            Layout.preferredHeight: preferredHeight
            menuId: menusRoot.menuId
        }

        // ── Style ─────────────────────────────────────────────────────────
        WorkspacesPane {
            Layout.fillWidth: true
            Layout.topMargin: menusRoot.sectionGap
            symbol: "density_small"
            title: Translation.tr("Style")
            subtitle: ContextMenus.compact
                ? Translation.tr("Compact: an icon bar, 34 px rows, as narrow as the entries allow")
                : Translation.tr("Comfortable: large rows in grouped pills")

            WindowsChoiceCards {
                Layout.fillWidth: true
                cardHeight: 120
                currentValue: menusRoot.cfg.style
                onSelected: value => menusRoot.cfg.style = value
                options: [
                    { value: "comfortable", title: Translation.tr("Comfortable"), icon: "view_agenda", shape: MaterialShape.Shape.Cookie9Sided,
                      summary: Translation.tr("Every entry a large row with a circled icon") },
                    { value: "compact", title: Translation.tr("Compact"), icon: "density_small", shape: MaterialShape.Shape.Cookie4Sided,
                      summary: Translation.tr("Chosen entries as icons on top, the rest as short rows") }
                ]
            }

            InterfaceSliderCard {
                Layout.fillWidth: true
                symbol: "zoom_in"
                title: Translation.tr("Menu size")
                hint: Translation.tr("Scales every right-click menu, on top of the style")
                valueText: Math.round(ContextMenus.scale * 100) + "%"
                markers: ["50%", "100%", "150%", "200%"]
                from: 0.5
                to: 2
                stepSize: 0.05
                stopIndicatorValues: [1]
                value: ContextMenus.scale
                onMoved: next => menusRoot.cfg.scale = Math.round(next * 100) / 100
            }
        }

        // ── Submenus ──────────────────────────────────────────────────────
        WorkspacesPane {
            Layout.fillWidth: true
            Layout.topMargin: menusRoot.sectionGap
            symbol: "subdirectory_arrow_right"
            title: Translation.tr("Submenus")
            subtitle: ContextMenus.cascade
                ? Translation.tr("Open on a card beside the menu, level with their row")
                : Translation.tr("Open inside the menu, with a way back")

            IslandSegmentedToggle {
                Layout.fillWidth: true
                options: [
                    { value: "inline", label: Translation.tr("Inside the menu"), icon: "low_priority", shape: "Cookie9Sided" },
                    { value: "cascade", label: Translation.tr("Beside the menu"), icon: "splitscreen_right", shape: "Cookie4Sided" }
                ]
                currentValue: menusRoot.cfg.submenus
                onSelected: value => menusRoot.cfg.submenus = value
            }

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("Edit Mode's widget menu always opens its lock-screen and options panels beside it.")
            }
        }

        // ── Which menu ────────────────────────────────────────────────────
        WorkspacesPane {
            Layout.fillWidth: true
            Layout.topMargin: menusRoot.sectionGap
            symbol: "menu_open"
            title: Translation.tr("Menu")
            subtitle: Translation.tr(ContextMenus.definition(menusRoot.menuId)?.description ?? "")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: ContextMenus.menus
                    delegate: ColorsChip {
                        required property var modelData
                        symbol: modelData.icon
                        label: Translation.tr(modelData.name)
                        chosen: modelData.id === menusRoot.menuId
                        onClicked: menusRoot.menuId = modelData.id
                    }
                }
            }
        }

        ContextMenusEditor {
            Layout.fillWidth: true
            Layout.topMargin: menusRoot.sectionGap
            menuId: menusRoot.menuId
            flick: page.flickable
        }

        // ── Related ───────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: menusRoot.sectionGap
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "interfaceFonts"
                    label: Translation.tr("Animation speed")
                }
                RelatedChip {
                    pageId: "dock"
                    label: Translation.tr("Dock")
                }
                RelatedChip {
                    pageId: "overview"
                    label: Translation.tr("Overview window cards")
                }
            }
        }
    }
}
