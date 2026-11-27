#pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.ii.bar.popups.weather
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool hovered: false
    property bool vertical: BarPlacement.vertical
    property bool isMaterial: true

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (contentLoader.item ? (root.isMaterial ? contentLoader.item.implicitWidth : contentLoader.item.implicitWidth + 6) : 0)
    implicitHeight: vertical
        ? (contentLoader.item ? (root.isMaterial ? contentLoader.item.implicitHeight : contentLoader.item.implicitHeight + 6) : 0)
        : Appearance.sizes.baseBarHeight

    width: implicitWidth
    height: implicitHeight

    hoverEnabled: !BarInteraction.clickToShow

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: Weather.refreshManually()
    }

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.weatherWidget.colorMode
    }

    // Load only the single active orientation/style (avoids decoding 4 copies of
    // the weather icon and allocating 4 parallel visual trees).
    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.isMaterial
            ? (root.vertical ? materialPillVertComp : materialPillHorizComp)
            : (root.vertical ? defaultColComp : defaultRowComp)
    }

    Component {
        id: defaultRowComp
        RowLayout {
            Image {
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: Weather.data?.temp ?? "--°"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Component {
        id: defaultColComp
        ColumnLayout {
            Image {
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                text: (Weather.data?.temp ?? "--°").replace(/[CF]$/, "")
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Component {
        id: materialPillHorizComp
        Rectangle {
            color: root.containsMouse ? widgetPalette.colBackgroundHover : widgetPalette.colBackground
            radius: Appearance.rounding.full
            implicitHeight: Appearance.sizes.baseBarHeight - 8
            height: implicitHeight
            implicitWidth: tempText.implicitWidth + iconCircle.width + 20
            width: implicitWidth

            StyledText {
                id: tempText
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1
                font.pixelSize: Appearance.font.pixelSize.small
                color: widgetPalette.colOnBackground
                text: Weather.data?.temp ?? "--°"
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                id: iconCircle
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 8
                height: width
                radius: Appearance.rounding.full
                color: root.containsMouse ? widgetPalette.colBackgroundVariantHover : widgetPalette.colBackgroundVariant

                Image {
                    anchors.centerIn: parent
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    sourceSize: Qt.size(Appearance.font.pixelSize.normal, Appearance.font.pixelSize.normal)
                }
            }
        }
    }

    Component {
        id: materialPillVertComp
        Rectangle {
            color: root.containsMouse ? widgetPalette.colBackgroundHover : widgetPalette.colBackground
            radius: Appearance.rounding.full
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            width: implicitWidth
            implicitHeight: tempTextVert.implicitHeight + iconCircleVert.height + 16
            height: implicitHeight

            StyledText {
                id: tempTextVert
                anchors.top: parent.top
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: widgetPalette.colOnBackground
                text: (Weather.data?.temp ?? "--°").replace(/[CF]$/, "")
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                id: iconCircleVert
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 4
                height: width
                radius: Appearance.rounding.full
                color: root.containsMouse ? widgetPalette.colBackgroundVariantHover : widgetPalette.colBackgroundVariant

                Image {
                    anchors.centerIn: parent
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    sourceSize: Qt.size(Appearance.font.pixelSize.normal, Appearance.font.pixelSize.normal)
                }
            }
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        sourceComponent: WeatherPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: root
        }
    }
}
