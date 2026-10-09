import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.sidebars
import qs.services

/**
 * Settings → Sidebars.
 *
 * Leads with how many tabs the policies sidebar opens with (and a button that opens it),
 * then each tab as a tile, where the two sidebars sit, whether their panels stay cached (as
 * a word that changes weight), the quick-toggles sub-page as a card and the rest in the
 * original sections. Search indexes sections/SidebarsOptionsSection.qml for everything drawn here.
 */
Item {
    id: sidebarsRoot
    anchors.fill: parent

    readonly property real sectionGap: 12
    readonly property real cardGap: 12
    readonly property real cacheMin: 280
    readonly property var sidebar: Config.options.sidebar
    readonly property bool cornersAvailable: Config.options.panelFamily !== "tablet"

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(file) {
        sidebarsRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        SidebarsHero {
            Layout.fillWidth: true
            visibleCount: policyGrid.shown
            total: policyGrid.total
            placement: placementPane.summary
        }

        // ── The tabs ──────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: sidebarsRoot.sectionGap
            title: Translation.tr("Policies tabs")
            icon: "policy"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("Choose which tabs are available when the policies sidebar opens.")
            }

            SidebarsPolicyGrid {
                id: policyGrid
            }
        }

        SidebarsPlacementPane {
            id: placementPane
            Layout.fillWidth: true
        }

        // ── Panel cache ───────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: sidebarsRoot.sectionGap
            title: Translation.tr("Panel cache")
            icon: "memory"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("Keep a sidebar's panel cached in memory so it opens instantly, or rebuild it on every open to save memory.")
            }

            Item {
                id: cache
                Layout.fillWidth: true
                implicitHeight: cacheFlow.implicitHeight

                readonly property int columns: Math.floor((width + sidebarsRoot.cardGap) / (sidebarsRoot.cacheMin + sidebarsRoot.cardGap)) >= 2 ? 2 : 1
                readonly property int cardWidth: Math.floor((width - sidebarsRoot.cardGap * (columns - 1)) / columns)

                Flow {
                    id: cacheFlow
                    width: parent.width
                    spacing: sidebarsRoot.cardGap

                    SidebarsCacheCard {
                        width: cache.cardWidth
                        symbol: "left_panel_open"
                        shapeOn: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Left sidebar")
                        subtitle: Translation.tr("Policies panel")
                        wordOn: Translation.tr("Cached")
                        wordOff: Translation.tr("On demand")
                        summaryOn: Translation.tr("Kept in memory, so it opens instantly")
                        summaryOff: Translation.tr("Rebuilt on every open to save memory")
                        checked: sidebarsRoot.sidebar.keepLeftSidebarLoaded
                        onToggled: value => sidebarsRoot.sidebar.keepLeftSidebarLoaded = value
                    }

                    SidebarsCacheCard {
                        width: cache.cardWidth
                        symbol: "right_panel_open"
                        shapeOn: MaterialShape.Shape.Flower
                        title: Translation.tr("Right sidebar")
                        subtitle: Translation.tr("Dashboard panel")
                        wordOn: Translation.tr("Cached")
                        wordOff: Translation.tr("On demand")
                        summaryOn: Translation.tr("Kept in memory, so it opens instantly")
                        summaryOff: Translation.tr("Rebuilt on every open to save memory")
                        checked: sidebarsRoot.sidebar.keepRightSidebarLoaded
                        onToggled: value => sidebarsRoot.sidebar.keepRightSidebarLoaded = value
                    }
                }
            }
        }

        // ── Quick toggles ─────────────────────────────────────────────────
        SidebarsLinkCard {
            Layout.fillWidth: true
            Layout.topMargin: sidebarsRoot.sectionGap
            symbol: "tune"
            shapeIdle: MaterialShape.Shape.Clover4Leaf
            shapeEngaged: MaterialShape.Shape.Flower
            title: Translation.tr("Quick toggles and sliders")
            summary: Translation.tr("Toggle styles, Android column count, capsule sliders and fixed sliders")
            onClicked: sidebarsRoot.openSubPage("SidebarQuickTogglesConfig.qml")
        }

        // ── Dashboard ─────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: sidebarsRoot.sectionGap
            title: Translation.tr("Dashboard")
            icon: "dashboard"

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Dashboard entrance animations")
                checked: sidebarsRoot.sidebar.dashboardEntranceAnimations
                onCheckedChanged: {
                    if (Config.ready && checked !== sidebarsRoot.sidebar.dashboardEntranceAnimations)
                        sidebarsRoot.sidebar.dashboardEntranceAnimations = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Restores decorative staggered animations for the dashboard header, quick toggles, notifications, calendar, tasks, and timers. They begin with the sidebar opening request and may cost some opening performance.")
                }
            }

            ConfigSwitch {
                buttonIcon: "note_stack"
                text: Translation.tr("Notes tab in dashboard")
                description: Translation.tr("Show Notes in the bottom widget group alongside Calendar, Tasks, and Timer")
                checked: sidebarsRoot.sidebar.bottomGroup?.notesTab ?? true
                onCheckedChanged: {
                    if (Config.ready && sidebarsRoot.sidebar.bottomGroup)
                        sidebarsRoot.sidebar.bottomGroup.notesTab = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Dashboard header button design")
                icon: "circle"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: sidebarsRoot.sidebar.dashboardHeader.buttonsDesign
                    onSelected: newValue => sidebarsRoot.sidebar.dashboardHeader.buttonsDesign = newValue
                    options: [
                        { displayName: Translation.tr("Default"), icon: "crop_square", value: "default" },
                        { displayName: Translation.tr("Circles"), icon: "circle", value: "circles" }
                    ]
                }
            }
        }

        // ── Screen corners ────────────────────────────────────────────────
        ContentSection {
            visible: sidebarsRoot.cornersAvailable
            title: Translation.tr("Screen Corners")
            icon: "mouse"

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Enable corner open")
                checked: sidebarsRoot.sidebar.cornerOpen.enable
                configPage: Qt.resolvedUrl("widgets/ScreenCornersConfig.qml")
                property bool readyForToggle: false
                Component.onCompleted: readyForToggle = true
                onCheckedChanged: {
                    if (!readyForToggle || !Config.ready)
                        return;
                    sidebarsRoot.sidebar.cornerOpen.enable = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Toggle corner open activation. Click button text to configure hover trigger, vertical offset, and region bounds.")
                }
            }
        }

        // ── Related ───────────────────────────────────────────────────────
        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "profile"
                    label: Translation.tr("Enable Sidebar Banner")
                    sectionHighlight: Translation.tr("Right Sidebar Banner")
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
