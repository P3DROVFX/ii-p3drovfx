pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets
import "../../../ii/dock/utilities/UnitConverter.js" as Units

/*
 * The Converter widget (2x1): the dock Converter's units on the desktop. The
 * category, the pair and the value are picked on the widget itself; this page
 * sets where it starts.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.converter_2x1

    WidgetPageHeader {
        title: Translation.tr("Converter Widget Options")
        onBack: root.goBack()
    }

    WidgetPreviewStage {
        columns: 2
        rows: 1

        WidgetPreviewSlot {
            columnSpan: 2
            ConverterWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Converter (2x1)")
        icon: "swap_horiz"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "converter_2x1" }
            WidgetSizeSlider { options: root.options }

            ContentSubsectionLabel { text: Translation.tr("Category") }

            ConfigSelectionArray {
                currentValue: Units.category(root.options.category ?? "length").id
                onSelected: newValue => {
                    const pair = Units.defaultPair(newValue);
                    root.options.category = newValue;
                    root.options.from = pair.from;
                    root.options.to = pair.to;
                }
                options: Units.categories.map(c => ({ displayName: Translation.tr(c.title), icon: c.symbol, value: c.id }))
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Click the left value to type; each side's unit chip lists its units, and a click on the result copies it. The dock's Converter uses the same units.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
