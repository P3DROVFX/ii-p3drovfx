import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The app drawer: how its grid is ordered, how big its tiles are, and what its search
 * reaches beyond applications.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("App drawer")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Grid")
            icon: "grid_view"

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Order")
                icon: "sort"

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "search"
                    text: Translation.tr("Applies to the unsearched grid. While you are typing, the order is how well each app matches, which is what rearranges as you narrow the query.")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.appDrawer.sortMode
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.appDrawer.sortMode = String(newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Name (A–Z)"), icon: "sort_by_alpha", value: "name" },
                        { displayName: Translation.tr("Name (Z–A)"), icon: "sort_by_alpha", value: "nameDesc" },
                        { displayName: Translation.tr("Category"), icon: "category", value: "category" },
                        { displayName: Translation.tr("Most used"), icon: "trending_up", value: "usage" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "sort"
                text: Translation.tr("Show the sort button")
                checked: Config.options.tablet.appDrawer.showSortButton
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.showSortButton)
                        Config.options.tablet.appDrawer.showSortButton = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "category"
                text: Translation.tr("Show category filter chips")
                checked: Config.options.tablet.appDrawer.showCategoryFilter
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.showCategoryFilter)
                        Config.options.tablet.appDrawer.showCategoryFilter = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Categories come from the .desktop files. Without them the only way through a few thousand applications is scrolling.")
                }
            }

            ConfigSwitch {
                buttonIcon: "trending_up"
                text: Translation.tr("Show a \"Most used\" row above the grid")
                checked: Config.options.tablet.appDrawer.showSuggestions
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.showSuggestions)
                        Config.options.tablet.appDrawer.showSuggestions = checked;
                }
                StyledToolTip {
                    text: Translation.tr("The apps you actually open, from the same launch history the \"Most used\" sort reads. Hides itself when that sort is already on, or while you are searching.")
                }
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Long-press opens a menu")
                checked: Config.options.tablet.appDrawer.longPressMenu
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.longPressMenu)
                        Config.options.tablet.appDrawer.longPressMenu = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Off makes a long press drop the app on the home screen immediately, which is what it used to do.")
                }
            }

            ConfigSpinBox {
                icon: "swipe_up"
                text: Translation.tr("Bottom swipe edge height (px)")
                value: Config.options.tablet.appDrawer.edgeDragHeight
                from: 2
                to: 48
                stepSize: 2
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.appDrawer.edgeDragHeight)
                        Config.options.tablet.appDrawer.edgeDragHeight = value;
                }
                StyledToolTip {
                    text: Translation.tr("How far up from the bottom of the screen a drag can start. This strip is what makes the gesture work with a pen or a mouse; touch reaches the drawer through the gesture service either way.")
                }
            }

            ConfigSpinBox {
                icon: "width"
                text: Translation.tr("Tile width (px, 0 fits the screen)")
                value: Config.options.tablet.appDrawer.tileWidth
                from: 0
                to: 240
                stepSize: 4
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.appDrawer.tileWidth)
                        Config.options.tablet.appDrawer.tileWidth = value;
                }
            }

            ConfigSpinBox {
                icon: "photo_size_select_large"
                text: Translation.tr("Icon size (px, 0 follows the tile)")
                value: Config.options.tablet.appDrawer.iconSize
                from: 0
                to: 128
                stepSize: 4
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.appDrawer.iconSize)
                        Config.options.tablet.appDrawer.iconSize = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Search results")
            icon: "search"

            ConfigSwitch {
                buttonIcon: "content_paste"
                text: Translation.tr("Show clipboard matches")
                checked: Config.options.tablet.appDrawer.showClipboardResults
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.showClipboardResults)
                        Config.options.tablet.appDrawer.showClipboardResults = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Reaching the clipboard otherwise means typing its name, finding a chip, and hitting a small target — three deliberate acts for something people want constantly.")
                }
            }

            ConfigSwitch {
                buttonIcon: "description"
                text: Translation.tr("Show file matches")
                checked: Config.options.tablet.appDrawer.showFileResults
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.appDrawer.showFileResults)
                        Config.options.tablet.appDrawer.showFileResults = checked;
                }
            }

            ConfigSpinBox {
                icon: "format_list_numbered"
                text: Translation.tr("Results per group")
                value: Config.options.tablet.appDrawer.sideResultLimit
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.appDrawer.sideResultLimit)
                        Config.options.tablet.appDrawer.sideResultLimit = value;
                }
            }
        }
    }
}
