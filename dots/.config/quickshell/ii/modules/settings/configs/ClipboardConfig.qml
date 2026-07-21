import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    ContentSection {
        icon: "content_paste"
        title: Translation.tr("Content detectors")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Detected content types get their own colour and preview in the launcher's clipboard mode.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Hex color detector")
                checked: Config.options.search.clipboard.detectors.hexColor
                onCheckedChanged: Config.options.search.clipboard.detectors.hexColor = checked
            }

            ConfigSwitch {
                buttonIcon: "link"
                text: Translation.tr("URL detector")
                checked: Config.options.search.clipboard.detectors.url
                onCheckedChanged: Config.options.search.clipboard.detectors.url = checked
            }

            ConfigSwitch {
                buttonIcon: "alternate_email"
                text: Translation.tr("Email detector")
                checked: Config.options.search.clipboard.detectors.email
                onCheckedChanged: Config.options.search.clipboard.detectors.email = checked
            }

            ConfigSwitch {
                buttonIcon: "phone"
                text: Translation.tr("Phone detector")
                checked: Config.options.search.clipboard.detectors.phone
                onCheckedChanged: Config.options.search.clipboard.detectors.phone = checked
            }

            ConfigSwitch {
                buttonIcon: "data_object"
                text: Translation.tr("JSON detector")
                checked: Config.options.search.clipboard.detectors.json
                onCheckedChanged: Config.options.search.clipboard.detectors.json = checked
            }

            ConfigSwitch {
                buttonIcon: "notes"
                text: Translation.tr("Multiline detector")
                checked: Config.options.search.clipboard.detectors.multiline
                onCheckedChanged: Config.options.search.clipboard.detectors.multiline = checked
            }

            ConfigSwitch {
                buttonIcon: "tag"
                text: Translation.tr("Number detector")
                checked: Config.options.search.clipboard.detectors.number
                onCheckedChanged: Config.options.search.clipboard.detectors.number = checked
            }

            ConfigSwitch {
                buttonIcon: "markdown"
                text: Translation.tr("Markdown detector")
                checked: Config.options.search.clipboard.detectors.markdown
                onCheckedChanged: Config.options.search.clipboard.detectors.markdown = checked
            }

            ConfigSwitch {
                buttonIcon: "folder_open"
                text: Translation.tr("File path detector")
                checked: Config.options.search.clipboard.detectors.filePath
                onCheckedChanged: Config.options.search.clipboard.detectors.filePath = checked
            }

        }

    }

    ContentSection {
        icon: "dashboard"
        title: Translation.tr("Panel layout")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Item {
                Layout.preferredHeight: 8
            }

            ConfigSlider {
                buttonIcon: "width"
                text: Translation.tr("Panel width (px)")
                value: Config.options.search.clipboard.panelWidth
                from: 600
                to: 1200
                stepSize: 10
                usePercentTooltip: false
                onValueChanged: Config.options.search.clipboard.panelWidth = value
            }

            ConfigSlider {
                buttonIcon: "vertical_split"
                text: Translation.tr("List column ratio")
                value: Config.options.search.clipboard.listColumnRatio * 100
                from: 25
                to: 60
                stepSize: 5
                usePercentTooltip: true
                onValueChanged: Config.options.search.clipboard.listColumnRatio = value / 100
            }

            ConfigSlider {
                buttonIcon: "image_aspect_ratio"
                text: Translation.tr("Image preview height (px)")
                value: Config.options.search.clipboard.imageHeight
                from: 100
                to: 400
                stepSize: 10
                usePercentTooltip: false
                onValueChanged: Config.options.search.clipboard.imageHeight = value
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Text preview font size (pt)")
                value: Config.options.search.clipboard.previewFontSize
                from: 9
                to: 20
                stepSize: 1
                usePercentTooltip: false
                onValueChanged: Config.options.search.clipboard.previewFontSize = value
            }

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr("Show metadata panel")
                checked: Config.options.search.clipboard.showMetadata
                onCheckedChanged: Config.options.search.clipboard.showMetadata = checked
            }

            ConfigSwitch {
                buttonIcon: "travel_explore"
                text: Translation.tr("Fuzzy search for clipboard")
                checked: Config.options.search.clipboard.enableSloppySearch
                onCheckedChanged: Config.options.search.clipboard.enableSloppySearch = checked
            }

        }

    }


    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "privacy"
                label: Translation.tr("Hide clipboard images")
                sectionHighlight: Translation.tr("Work Safety & Policies")
            }
        }
    }
}
