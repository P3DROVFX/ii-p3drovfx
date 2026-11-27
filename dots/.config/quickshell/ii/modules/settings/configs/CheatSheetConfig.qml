import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.cheatsheet
import qs.services

/**
 * Settings → Cheat Sheet.
 *
 * Leads with the shortcut that opens the cheatsheet (two keycaps) and a rail of the pages
 * it holds, then every page as a tile or a compact toggle, and the memory switch in its
 * original section. Search indexes sections/CheatSheetOptionsSection.qml for everything
 * drawn here.
 */
Item {
    id: root

    readonly property real sectionGap: 12

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    anchors.fill: parent

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        CheatsheetHero {
            Layout.fillWidth: true
            pages: pagesGrid.pages
            onPageToggled: (key, value) => Config.options.cheatsheet[key] = value
        }

        ContentSection {
            Layout.topMargin: root.sectionGap
            title: Translation.tr("Cheatsheet Widgets")
            icon: "widgets"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                isLast: false
                materialIcon: "apps"
                text: Translation.tr("Timetable (now Calendar) and Email moved to Settings → Apps & Overlays as standalone apps. You can now launch them directly from Search.")

                RippleButtonWithIcon {
                    implicitHeight: 34
                    materialIcon: "arrow_forward"
                    mainText: Translation.tr("Apps & Overlays")
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    colText: Appearance.colors.colOnSecondaryContainer
                    onClicked: GlobalStates.openSettingsPage("overlays")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                isFirst: false
                isLast: true
                materialIcon: "settings"
                text: Translation.tr("Each page's own options live inside the Cheatsheet, behind the gear next to its close button: key symbols and font sizes for Keybinds, the Amino acids classification and the Commands layout.")
            }

            CheatsheetPages {
                id: pagesGrid
            }
        }

        ContentSection {
            title: Translation.tr("Performance")
            icon: "bolt"

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Keep last tab ready")
                checked: Config.options.cheatsheet.keepLastTabLoaded
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.cheatsheet.keepLastTabLoaded)
                        Config.options.cheatsheet.keepLastTabLoaded = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keep only the last opened tab in memory for quick reopening. Switching tabs releases the previous one.")
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
