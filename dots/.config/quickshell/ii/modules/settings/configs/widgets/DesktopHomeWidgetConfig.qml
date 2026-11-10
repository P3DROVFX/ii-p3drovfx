pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * The Home widget (1x2): the smart lights of the Smart Devices quick toggle.
 * The devices themselves are set up there; here only the widget's size.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.home_devices

    WidgetPageHeader {
        title: Translation.tr("Home Widget Options")
        onBack: root.goBack()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        WidgetPreviewStage {
            Layout.fillWidth: false
            Layout.preferredWidth: 240 + 40
            Layout.alignment: Qt.AlignTop
            columns: 1
            rows: 2
            boardScaleOverride: 1

            WidgetPreviewSlot {
                rowSpan: 2
                HomeDevicesWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.height / Math.max(1, implicitHeight)
                }
            }
        }

        ContentSection {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: Translation.tr("Home (1x2)")
            icon: "home_iot_device"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                WidgetPlacementNote { widgetId: "home_devices" }
                WidgetSizeSlider { options: root.options }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Click a light to switch it, scroll over it to dim, or step it with − and +. The power key switches every light. Lights are added in the Smart Devices quick toggle.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                }
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
