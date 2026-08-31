pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.weather
import qs.services

MouseArea {
    id: root

    property bool vertical: false
    property bool hovered: false

    readonly property string variant: Config.options.bar.weatherWidget.tesseraVariant ?? "paired"
    readonly property string colorMode: Config.options.bar.weatherWidget.colorMode ?? "tonal"
    readonly property bool contrast: root.variant === "contrast"
    readonly property bool bare: root.variant === "bare"
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    readonly property real weatherTileSize: root.bare
        ? root.thickness * 0.76
        : root.thickness
    readonly property int weatherTileShape: root.contrast
        ? MaterialShape.Shape.ClamShell
        : root.bare
            ? MaterialShape.Shape.Bun
            : MaterialShape.Shape.PuffyDiamond
    readonly property real targetLength: root.vertical
        ? tesseraLayout.implicitHeight
        : tesseraLayout.implicitWidth

    property real animatedLength: root.targetLength

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    clip: true

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton)
            Weather.refreshManually();
    }

    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    BarWidgetPalette {
        id: palette
        colorMode: root.colorMode
    }

    GridLayout {
        id: tesseraLayout

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        rows: root.vertical ? 2 : 1
        rowSpacing: root.bare
            ? Appearance.sizes.elevationMargin / 3
            : Appearance.sizes.elevationMargin / 2
        columnSpacing: root.bare
            ? Appearance.sizes.elevationMargin / 3
            : Appearance.sizes.elevationMargin / 2

        MaterialShape {
            Layout.alignment: Qt.AlignCenter
            implicitSize: root.weatherTileSize
            shape: root.weatherTileShape
            color: root.contrast ? palette.container : palette.accent

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(
                    root.bare ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large,
                    root.bare ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
                )
            }
        }

        Item {
            id: temperatureTile

            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.vertical
                ? root.thickness * 0.72
                : temperatureText.implicitWidth + Appearance.sizes.elevationMargin * (root.bare ? 0.5 : 0.9)
            implicitHeight: root.vertical
                ? temperatureText.implicitWidth + Appearance.sizes.elevationMargin * 1.6
                : root.thickness

            Rectangle {
                anchors.fill: parent
                visible: !root.bare
                radius: Appearance.rounding.full
                color: palette.container
            }

            StyledText {
                id: temperatureText

                anchors.centerIn: parent
                rotation: root.contentRotation
                text: Weather.data?.temp ?? "--°"
                font.family: Appearance.font.family.title
                font.pixelSize: root.bare
                    ? Appearance.font.pixelSize.small
                    : Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: root.bare
                    ? palette.bare
                    : ColorUtils.categoryOnColor(palette.container)
            }
        }
    }

    WeatherPopup {
        compact: Config.options.bar.tooltips.compactPopups
        hoverTarget: root
    }
}
