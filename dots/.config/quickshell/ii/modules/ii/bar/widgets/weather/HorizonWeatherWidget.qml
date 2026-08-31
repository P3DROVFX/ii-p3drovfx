pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.weather
import qs.services

MouseArea {
    id: root

    property bool vertical: false
    property bool hovered: false

    readonly property string variant: Config.options.bar.weatherWidget.horizonVariant ?? "balanced"
    readonly property string colorMode: Config.options.bar.weatherWidget.colorMode ?? "tonal"
    readonly property bool inverted: root.variant === "inverted"
    readonly property bool minimal: root.variant === "minimal"
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    readonly property real weatherPlateSize: root.minimal
        ? root.thickness * 0.62
        : root.thickness * 0.78
    readonly property int weatherPlateShape: root.inverted
        ? MaterialShape.Shape.Slanted
        : MaterialShape.Shape.Arch
    readonly property real targetLength: root.vertical
        ? horizonContent.implicitHeight + Appearance.sizes.elevationMargin * 0.6
        : horizonContent.implicitWidth + Appearance.sizes.elevationMargin * 0.6

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
        id: horizonContent

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 3
        rows: root.vertical ? 3 : 1
        rowSpacing: root.minimal
            ? Appearance.sizes.elevationMargin / 4
            : Appearance.sizes.elevationMargin / 2
        columnSpacing: root.minimal
            ? Appearance.sizes.elevationMargin / 4
            : Appearance.sizes.elevationMargin / 2

        Item {
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.weatherPlateSize
            implicitHeight: root.weatherPlateSize

            MaterialShape {
                anchors.fill: parent
                visible: !root.minimal
                implicitSize: root.weatherPlateSize
                shape: root.weatherPlateShape
                color: root.inverted ? palette.accent : palette.container
            }

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(
                    root.minimal ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large,
                    root.minimal ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
                )
            }
        }

        Item {
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.vertical ? temperatureText.implicitHeight : temperatureText.implicitWidth
            implicitHeight: root.vertical ? temperatureText.implicitWidth : temperatureText.implicitHeight

            StyledText {
                id: temperatureText

                anchors.centerIn: parent
                rotation: root.contentRotation
                text: Weather.data?.temp ?? "--°"
                font.family: Appearance.font.family.title
                font.pixelSize: root.minimal
                    ? Appearance.font.pixelSize.small
                    : Appearance.font.pixelSize.large
                font.weight: root.minimal ? Font.DemiBold : Font.Bold
                color: root.inverted ? palette.bareAccent : palette.bare
            }
        }

        Rectangle {
            id: horizonRail

            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.vertical
                ? root.thickness * (root.minimal ? 0.34 : 0.52)
                : Appearance.sizes.elevationMargin / 3
            implicitHeight: root.vertical
                ? Appearance.sizes.elevationMargin / 3
                : root.thickness * (root.minimal ? 0.34 : 0.52)
            radius: Appearance.rounding.full
            color: root.inverted ? palette.bare : palette.bareAccent
            opacity: root.minimal ? 0.55 : 1
        }
    }

    WeatherPopup {
        compact: Config.options.bar.tooltips.compactPopups
        hoverTarget: root
    }
}
