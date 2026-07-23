import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_typography"

    readonly property bool expressive: Config.options.background.widgets.weather_typography.expressiveColors ?? false

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color boldTextColor: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
    readonly property color mutedTextColor: expressive ? ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.55) : Appearance.colors.colOnSurfaceVariant

    readonly property var currentData: Weather.data

    readonly property string cityName: currentData?.city || ""
    readonly property string conditionText: (currentData?.wDesc || "").toLowerCase()

    readonly property int cityFontSize: {
        const fullLength = 3 + cityName.length;
        if (fullLength > 18) return 22;
        if (fullLength > 14) return 25;
        if (fullLength > 10) return 28;
        return 30;
    }

    readonly property int conditionFontSize: {
        const condLength = conditionText.length;
        if (condLength > 16) return 18;
        if (condLength > 12) return 20;
        return 22;
    }

    StyledDropShadow {
        id: shadowEffect
        target: mainCard
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainCard
        anchors.fill: parent
        radius: Appearance.rounding.large + 12
        color: root.cardBgColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 3

            RowLayout {
                spacing: 10

                StyledText {
                    text: root.currentData?.temp || ""
                    color: root.boldTextColor
                    font.pixelSize: 32
                    font.weight: Font.Bold
                }

                StyledText {
                    text: Translation.tr("now")
                    color: root.mutedTextColor
                    font.pixelSize: 32
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                spacing: 10
                Layout.maximumWidth: 200

                StyledText {
                    text: Translation.tr("in")
                    color: root.mutedTextColor
                    font.pixelSize: root.cityFontSize
                    font.weight: Font.Bold
                }

                StyledText {
                    text: root.cityName
                    color: root.boldTextColor
                    font.pixelSize: root.cityFontSize
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                spacing: 10

                StyledText {
                    text: Translation.tr("feels")
                    color: root.mutedTextColor
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }

                StyledText {
                    text: root.currentData?.tempFeelsLike || ""
                    color: root.boldTextColor
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                spacing: 10
                Layout.maximumWidth: 200

                MaterialSymbol {
                    iconSize: root.conditionFontSize + 2
                    text: Icons.getWeatherIcon(root.currentData?.wCode) ?? "partly_cloudy_day"
                    color: root.boldTextColor
                    fill: 1.0
                }

                StyledText {
                    text: root.conditionText
                    color: root.boldTextColor
                    font.pixelSize: root.conditionFontSize
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            StyledText {
                text: Translation.tr("today")
                color: root.mutedTextColor
                font.pixelSize: 22
                font.weight: Font.Bold
            }
        }
    }
}
