import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.system
import qs.modules.settings.configs.widgets

/*
 * The Session widget (1x1): lock, power off, restart and log out, each run by
 * a second press. The preview shows it but never runs anything.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.session_grid

    WidgetPageHeader {
        title: Translation.tr("Session Widget Options")
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
            rows: 1
            boardScaleOverride: 1

            WidgetPreviewSlot {
                SessionGridWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    text: "touch_app"
                    iconSize: 24
                    padding: 12
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: Translation.tr("Press twice")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The first press only arms a tile: it fills and asks again, with a bar running out along its foot. A second press within three seconds runs it; otherwise it settles back. Lock uses the shell's own lock screen.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Session (1x1)")
        icon: "power_settings_new"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "session_grid" }
            WidgetSizeSlider { options: root.options }
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
