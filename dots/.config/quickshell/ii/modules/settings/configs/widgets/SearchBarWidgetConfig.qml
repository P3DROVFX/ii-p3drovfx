pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/search"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
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
            text: Translation.tr("Search widget")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.baseBarHeight + 28
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            Loader {
                id: previewLoader
                anchors.centerIn: parent
                sourceComponent: {
                    const style = Config.options.bar.styles.search ?? "default";
                    if (style === "expressive")
                        return expressivePreview;
                    if (style === "neural")
                        return neuralPreview;
                    return defaultPreview;
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "search"
            text: Translation.tr("The button always opens the launcher-only surface. Workspace cards from Overview stay hidden, even when Overview is enabled elsewhere.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.search
                onSelected: newValue => Config.options.bar.styles.search = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Neural"), icon: "neurology", value: "neural" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Width")

            ConfigSelectionArray {
                currentValue: Config.options.bar.searchWidget.sizeMode
                onSelected: newValue => Config.options.bar.searchWidget.sizeMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Compact"), icon: "compress", value: "compact" },
                    { displayName: Translation.tr("Balanced"), icon: "width_normal", value: "balanced" },
                    { displayName: Translation.tr("Extended"), icon: "expand", value: "extended" }
                ]
            }
        }

        ContentSubsection {
            visible: Config.options.bar.styles.search !== "default"
            title: Translation.tr("Colour treatment")

            ConfigSelectionArray {
                currentValue: Config.options.bar.searchWidget.colorMode
                onSelected: newValue => Config.options.bar.searchWidget.colorMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Tonal"), icon: "colors", value: "tonal" },
                    { displayName: Translation.tr("Vibrant"), icon: "auto_awesome", value: "vibrant" },
                    { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" }
                ]
            }
        }

        ConfigSwitch {
            visible: Config.options.bar.searchWidget.sizeMode === "extended"
            buttonIcon: "keyboard_command_key"
            text: Translation.tr("Show the configured Super icon")
            checked: Config.options.bar.searchWidget.showShortcutHint
            onCheckedChanged: Config.options.bar.searchWidget.showShortcutHint = checked
        }
    }

    ContentSection {
        icon: "rocket_launch"
        title: Translation.tr("Right now")

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 48
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: GlobalStates.toggleSearchOnly()

            contentItem: RowLayout {
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                MaterialSymbol {
                    text: GlobalStates.overviewOpen && GlobalStates.searchOnlyMode
                        ? "close"
                        : "search"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    text: GlobalStates.overviewOpen && GlobalStates.searchOnlyMode
                        ? Translation.tr("Close launcher")
                        : Translation.tr("Try the launcher")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    Component {
        id: defaultPreview
        SearchBarWidget {
            vertical: false
        }
    }

    Component {
        id: expressivePreview
        ExpressiveSearchBarWidget {
            vertical: false
        }
    }

    Component {
        id: neuralPreview
        NeuralSearchBarWidget {
            vertical: false
        }
    }
}
