pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the desktop's "weather typography" widget: Apple-style typographic
 * sentences describing current conditions.
 *
 * Adaptive Freeform:
 * - Content density and typography scale dynamically with available tile size.
 * - Small tiles display only the essential sentence elements (temp + now).
 * - Larger tiles progressively reveal city, feels-like, condition icon, and full summary.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property var currentData: Weather.data
    readonly property color boldTextColor: Appearance.colors.colOnLayer2
    readonly property color mutedTextColor: Appearance.colors.colSubtext

    readonly property string tempString: (root.currentData?.temp ?? "").replace("°C", "°").replace("°F", "°")
    readonly property string feelsLikeString: (root.currentData?.tempFeelsLike ?? "").replace("°C", "°").replace("°F", "°")
    readonly property string cityName: root.currentData?.city || ""
    readonly property string conditionText: (root.currentData?.wDesc || "").toLowerCase()

    readonly property bool is1Col: root.effectiveSizeW === 1 || root.surface.width < 110
    readonly property bool is1Row: root.effectiveSizeH === 1 || root.surface.height < 75

    // ── 1. NARROW 1-COLUMN TILES (1x1, 1x2, 1x3, 1x4) ────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 8
        visible: root.is1Col

        // 1x1 Compact: "23° now"
        Row {
            anchors.centerIn: parent
            spacing: 4
            visible: root.is1Row

            StyledText {
                text: root.tempString
                color: root.boldTextColor
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
            }

            StyledText {
                text: Translation.tr("now")
                color: root.mutedTextColor
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                anchors.baseline: parent.children[0].baseline
            }
        }

        // 1x2, 1x3, 1x4 Vertical: Stacked lines
        ColumnLayout {
            anchors.fill: parent
            spacing: 2
            visible: !root.is1Row

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                StyledText {
                    text: root.tempString
                    color: root.boldTextColor
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Bold
                }

                StyledText {
                    text: Translation.tr("now")
                    color: root.mutedTextColor
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width - 4
                spacing: 4
                visible: root.cityName !== ""

                StyledText {
                    text: Translation.tr("in")
                    color: root.mutedTextColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                }

                StyledText {
                    text: root.cityName
                    color: root.boldTextColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: root.effectiveSizeH >= 2 && root.conditionText !== ""

                Image {
                    source: WeatherIcons.getWeatherIcon(root.currentData?.wCode ?? 113, false)
                    sourceSize: Qt.size(16, 16)
                }

                StyledText {
                    text: root.conditionText
                    color: root.boldTextColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.parent.width - 24
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: root.effectiveSizeH >= 3 && root.feelsLikeString !== ""

                StyledText {
                    text: Translation.tr("feels")
                    color: root.mutedTextColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                }

                StyledText {
                    text: root.feelsLikeString
                    color: root.boldTextColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ── 2. MULTI-COLUMN 1-ROW TILES (2x1, 3x1, 4x1) ───────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 8
        visible: !root.is1Col && root.is1Row

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            StyledText {
                text: root.tempString
                color: root.boldTextColor
                font.pixelSize: Appearance.font.pixelSize.huge * 1.2
                font.weight: Font.Bold
            }

            StyledText {
                text: Translation.tr("now")
                color: root.mutedTextColor
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
            }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 6
            visible: root.conditionText !== ""

            Image {
                source: WeatherIcons.getWeatherIcon(root.currentData?.wCode ?? 113, false)
                sourceSize: Qt.size(20, 20)
            }

            StyledText {
                text: root.conditionText
                color: root.boldTextColor
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.maximumWidth: root.surface.width * 0.40
            }
        }
    }

    // ── 3. STANDARD & MULTI-ROW TILES (2x2, 2x3, 2x4, 3x2, 3x3, 4x2, 4x4) ────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2
        visible: !root.is1Col && !root.is1Row

        readonly property bool isShortGrid: root.surface.height < 140

        Item { Layout.fillHeight: true }

        // Line 1: "23° now"
        RowLayout {
            spacing: 6

            StyledText {
                text: root.tempString
                color: root.boldTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.huge * 1.15 : Appearance.font.pixelSize.huge * 1.35
                font.weight: Font.Bold
            }

            StyledText {
                text: Translation.tr("now")
                color: root.mutedTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignBaseline
            }
        }

        // Line 2: "in City"
        RowLayout {
            spacing: 6
            Layout.maximumWidth: root.surface.width - 24
            visible: root.cityName !== ""

            StyledText {
                text: Translation.tr("in")
                color: root.mutedTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                font.weight: Font.Bold
            }

            StyledText {
                text: root.cityName
                color: root.boldTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        // Line 3 (Only when height >= 3): "feels 24°"
        RowLayout {
            spacing: 6
            visible: !parent.isShortGrid && root.feelsLikeString !== ""

            StyledText {
                text: Translation.tr("feels")
                color: root.mutedTextColor
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
            }

            StyledText {
                text: root.feelsLikeString
                color: root.boldTextColor
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
            }
        }

        // Line 4 (or Line 3 when height=2): "[Icon] Clear today"
        RowLayout {
            spacing: 6
            Layout.maximumWidth: root.surface.width - 24

            Image {
                source: WeatherIcons.getWeatherIcon(root.currentData?.wCode ?? 113, false)
                readonly property real iconSize: parent.parent.isShortGrid ? 16 : 18
                sourceSize: Qt.size(iconSize, iconSize)
                Layout.preferredWidth: iconSize
                Layout.preferredHeight: iconSize
            }

            StyledText {
                text: root.conditionText
                color: root.boldTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledText {
                text: Translation.tr("today")
                color: root.mutedTextColor
                font.pixelSize: parent.parent.isShortGrid ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
            }
        }

        Item { Layout.fillHeight: true }
    }
}
