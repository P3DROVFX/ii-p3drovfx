import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The dock's search pill.
 *
 * Both end buttons are chosen from the same small set, including the shell's own search
 * panels, so "clipboard on the dock" is a setting rather than a feature request.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var actionOptions: [
        { displayName: Translation.tr("None"), icon: "block", value: "none" },
        { displayName: Translation.tr("Search"), icon: "search", value: "search" },
        { displayName: Translation.tr("App drawer"), icon: "apps", value: "apps" },
        { displayName: Translation.tr("Clipboard"), icon: "content_paste", value: "tool:clipboard" },
        { displayName: Translation.tr("Files"), icon: "folder_data", value: "tool:fileBrowser" },
        { displayName: Translation.tr("Emojis"), icon: "mood", value: "tool:emojis" },
        { displayName: Translation.tr("Translator"), icon: "translate", value: "tool:translator" }
    ]

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
                text: Translation.tr("Dock search")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Search pill")
            icon: "search"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("The pill does not search on its own. It opens the app drawer, where the results are.")
            }

            ConfigSwitch {
                buttonIcon: "search"
                text: Translation.tr("Show the search pill")
                checked: Config.options.tablet.dock.showSearchBar
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showSearchBar)
                        Config.options.tablet.dock.showSearchBar = checked;
                }
            }

            ConfigSpinBox {
                icon: "width"
                text: Translation.tr("Pill width (px)")
                visible: Config.options.tablet.dock.showSearchBar
                    && Config.options.tablet.dock.searchBarStyle === "extended"
                value: Config.options.tablet.dock.searchBarWidth
                from: 180
                to: 640
                stepSize: 20
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.searchBarWidth)
                        Config.options.tablet.dock.searchBarWidth = value;
                }
                StyledToolTip {
                    text: Translation.tr("A ceiling, not a fixed size: the pill never takes more than a third of the dock, so the app row keeps the middle.")
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Shape")
                icon: "aspect_ratio"
                visible: Config.options.tablet.dock.showSearchBar

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.dock.searchBarStyle
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.searchBarStyle = String(newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Extended pill"), icon: "search", value: "extended" },
                        { displayName: Translation.tr("Compact circle"), icon: "circle", value: "compact" }
                    ]
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Leading button")
                icon: "chevron_left"
                visible: Config.options.tablet.dock.showSearchBar

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.dock.searchLeadingAction
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.searchLeadingAction = String(newValue);
                    }
                    options: root.actionOptions
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Trailing button")
                icon: "chevron_right"
                visible: Config.options.tablet.dock.showSearchBar
                    && Config.options.tablet.dock.searchBarStyle === "extended"

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.dock.searchTrailingAction
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.searchTrailingAction = String(newValue);
                    }
                    options: root.actionOptions
                }
            }
        }
    }
}
