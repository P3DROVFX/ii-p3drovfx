pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/clock"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property string style: Config.options.bar.styles.clock ?? "default"
    readonly property bool styled: root.style === "neural" || root.style === "relief"

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
            text: Translation.tr("Clock widget")
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
                        if (root.style === "neural")
                            return neuralHorizontalPreview;
                        if (root.style === "relief")
                            return reliefHorizontalPreview;
                        return null;
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.styled
                    text: Translation.tr("Preview available for Neural and Relief")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.6
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
                        if (root.style === "neural")
                            return neuralVerticalPreview;
                        if (root.style === "relief")
                            return reliefVerticalPreview;
                        return null;
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "content_cut"
            text: Translation.tr("Relief draws by subtraction: the shapes you read are the gaps where one layer has been cut out of another, not strokes around it.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.clock
                onSelected: newValue => Config.options.bar.styles.clock = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Material"), icon: "interests", value: "material" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Neural"), icon: "neurology", value: "neural" },
                    { displayName: Translation.tr("Relief"), icon: "content_cut", value: "relief" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "neural"
            title: Translation.tr("Neural variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.clockWidget.neuralVariant
                onSelected: newValue => Config.options.bar.clockWidget.neuralVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Orbit"), icon: "target", value: "orbit" },
                    { displayName: Translation.tr("Bloom"), icon: "filter_vintage", value: "bloom" },
                    { displayName: Translation.tr("Dial"), icon: "schedule", value: "dial" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "relief"
            title: Translation.tr("Relief variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.clockWidget.reliefVariant
                onSelected: newValue => Config.options.bar.clockWidget.reliefVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Split"), icon: "join_inner", value: "split" },
                    { displayName: Translation.tr("Seam"), icon: "horizontal_rule", value: "seam" },
                    { displayName: Translation.tr("Outline"), icon: "format_shapes", value: "outline" }
                ]
            }
        }

        ContentSubsection {
            visible: root.styled
            title: Translation.tr("Colour treatment")

            ConfigSelectionArray {
                currentValue: Config.options.bar.clockWidget.colorMode
                onSelected: newValue => Config.options.bar.clockWidget.colorMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Tonal"), icon: "colors", value: "tonal" },
                    { displayName: Translation.tr("Vibrant"), icon: "auto_awesome", value: "vibrant" },
                    { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" }
                ]
            }
        }

        ConfigSwitch {
            // Only Orbit and Inlay have a slot to put it in; the rest are two
            // numerals and nothing else, by design.
            visible: root.styled
                && (root.style === "neural"
                    ? Config.options.bar.clockWidget.neuralVariant === "orbit"
                    : Config.options.bar.clockWidget.reliefVariant === "seam")
            buttonIcon: "schedule"
            text: Translation.tr("Show AM/PM when the clock is 12-hour")
            checked: Config.options.bar.clockWidget.showMeridiem
            onCheckedChanged: Config.options.bar.clockWidget.showMeridiem = checked
        }
    }

    // Carried over from the old shared Clock & Date page, which the clock no
    // longer routes to: the Material style keeps its own primary/secondary
    // layout controls, and losing them would be a silent regression.
    MaterialWidgetLayoutSection {
        enabled: root.style === "material"
        config: Config.options.bar.clock
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Formats & alarms")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Clock format, world clocks and alarms live in Language & Time. Switching that format between 12- and 24-hour is what these designs read to decide whether AM/PM exists at all.")
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
        id: neuralHorizontalPreview
        NeuralClockWidget {
            vertical: false
        }
    }

    Component {
        id: neuralVerticalPreview
        NeuralClockWidget {
            vertical: true
        }
    }

    Component {
        id: reliefHorizontalPreview
        ReliefClockWidget {
            vertical: false
        }
    }

    Component {
        id: reliefVerticalPreview
        ReliefClockWidget {
            vertical: true
        }
    }
}
