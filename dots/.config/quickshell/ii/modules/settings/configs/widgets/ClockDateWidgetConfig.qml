import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    signal goBack()

    forceWidth: false

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
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
            text: Translation.tr("Clock & Date widget")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

    }

    MaterialWidgetLayoutSection {
        enabled: Config.options.bar.styles.clock === "material"
        config: Config.options.bar.clock
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Formats & alarms")

        StyledText {
            text: Translation.tr("Clock and date formats, world clocks and alarm settings live in Language & Time.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        RelatedChip {
            pageId: "languageTime"
            label: Translation.tr("Open Language & Time")
            sectionHighlight: Translation.tr("Time & Date Formats")
        }

    }

}
