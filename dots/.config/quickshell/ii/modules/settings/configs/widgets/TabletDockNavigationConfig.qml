import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Tablet-only navigation controls. The order is represented by a small, complete set of
 * layouts instead of a second mutable model, so the three system actions can never be lost.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property string orderValue: Array.from(Config.options.tablet.dock.navigationOrder).join(",")

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
                text: Translation.tr("Tablet navigation")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Navigation buttons")
            icon: "navigation"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "align_horizontal_right"
                text: Translation.tr("Back, Home, and Recents stay on the right side of the dock and share the app-icon touch target.")
            }

            ConfigSwitch {
                buttonIcon: "navigation"
                text: Translation.tr("Show navigation buttons")
                checked: Config.options.tablet.dock.showNavigation
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showNavigation)
                        Config.options.tablet.dock.showNavigation = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Keep navigation visible when apps hide")
                visible: Config.options.tablet.dock.showNavigation
                checked: Config.options.tablet.dock.keepNavigationVisible
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.keepNavigationVisible)
                        Config.options.tablet.dock.keepNavigationVisible = checked;
                }
                StyledToolTip {
                    text: Translation.tr("When disabled, automatic hiding releases the whole dock and all of its reserved space.")
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Button order")
                icon: "swap_horiz"

                ConfigSelectionArray {
                    currentValue: root.orderValue
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.navigationOrder = String(newValue).split(",");
                    }
                    options: [
                        { displayName: Translation.tr("Back · Home · Recents"), icon: "arrow_back", value: "back,home,recents" },
                        { displayName: Translation.tr("Back · Recents · Home"), icon: "arrow_back", value: "back,recents,home" },
                        { displayName: Translation.tr("Home · Back · Recents"), icon: "home", value: "home,back,recents" },
                        { displayName: Translation.tr("Home · Recents · Back"), icon: "home", value: "home,recents,back" },
                        { displayName: Translation.tr("Recents · Back · Home"), icon: "overview", value: "recents,back,home" },
                        { displayName: Translation.tr("Recents · Home · Back"), icon: "overview", value: "recents,home,back" }
                    ]
                }
            }
        }
    }
}
