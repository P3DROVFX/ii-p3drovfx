pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/date"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property string style: Config.options.bar.styles.date ?? "default"

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
            text: Translation.tr("Date widget")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "expressive")
                            return expressiveHorizontalPreview;
                        if (root.style === "neural")
                            return neuralHorizontalPreview;
                        return defaultHorizontalPreview;
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + 28
                Layout.fillHeight: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "expressive")
                            return expressiveVerticalPreview;
                        if (root.style === "neural")
                            return neuralVerticalPreview;
                        return defaultVerticalPreview;
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "swap_horiz"
            text: Translation.tr("Left is the horizontal bar, right is the vertical one. Every variant is drawn for both — the vertical form re-stacks rather than rotating the numbers.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.date
                onSelected: newValue => Config.options.bar.styles.date = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Neural"), icon: "neurology", value: "neural" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "expressive"
            title: Translation.tr("Expressive variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.dateWidget.expressiveVariant
                onSelected: newValue => Config.options.bar.dateWidget.expressiveVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Stack"), icon: "layers", value: "stack" },
                    { displayName: Translation.tr("Badge"), icon: "workspace_premium", value: "badge" },
                    { displayName: Translation.tr("Ribbon"), icon: "view_week", value: "ribbon" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "neural"
            title: Translation.tr("Neural variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.dateWidget.neuralVariant
                onSelected: newValue => Config.options.bar.dateWidget.neuralVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Orbit"), icon: "target", value: "orbit" },
                    { displayName: Translation.tr("Glyph"), icon: "text_fields", value: "glyph" },
                    { displayName: Translation.tr("Inlay"), icon: "content_cut", value: "inlay" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style !== "default"
            title: Translation.tr("Colour treatment")

            ConfigSelectionArray {
                currentValue: Config.options.bar.dateWidget.colorMode
                onSelected: newValue => Config.options.bar.dateWidget.colorMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Tonal"), icon: "colors", value: "tonal" },
                    { displayName: Translation.tr("Vibrant"), icon: "auto_awesome", value: "vibrant" },
                    { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" }
                ]
            }
        }

        ConfigSwitch {
            visible: root.style !== "default"
            buttonIcon: "text_format"
            text: Translation.tr("Set weekday and month in capitals")
            checked: Config.options.bar.dateWidget.uppercase
            onCheckedChanged: Config.options.bar.dateWidget.uppercase = checked
        }

        ConfigSwitch {
            // Hidden for the two variants that carry no month label to append
            // it to: `ribbon` shows the weekday strip, `glyph` shows the day
            // inside the weekday.
            visible: root.style !== "default"
                && (root.style === "neural"
                    ? Config.options.bar.dateWidget.neuralVariant !== "glyph"
                    : Config.options.bar.dateWidget.expressiveVariant !== "ribbon")
            buttonIcon: "calendar_month"
            text: Translation.tr("Append the two-digit year")
            checked: Config.options.bar.dateWidget.showYear
            onCheckedChanged: Config.options.bar.dateWidget.showYear = checked
        }
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Formats")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The widget reads the weekday, month and day names from the system locale. Clock and date format strings live in Language & Time.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        RelatedChip {
            pageId: "languageTime"
            label: Translation.tr("Open Language & Time")
            sectionHighlight: Translation.tr("Time & Date Formats")
        }
    }

    Component {
        id: defaultHorizontalPreview
        DateWidget {
            vertical: false
        }
    }

    Component {
        id: defaultVerticalPreview
        DateWidget {
            vertical: true
        }
    }

    Component {
        id: expressiveHorizontalPreview
        ExpressiveDateWidget {
            vertical: false
        }
    }

    Component {
        id: expressiveVerticalPreview
        ExpressiveDateWidget {
            vertical: true
        }
    }

    Component {
        id: neuralHorizontalPreview
        NeuralDateWidget {
            vertical: false
        }
    }

    Component {
        id: neuralVerticalPreview
        NeuralDateWidget {
            vertical: true
        }
    }
}
