import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

WindowDialog {
    id: root
    property var brightnessMonitor: Brightness.getTargetMonitor()

    /**
     * A section: one expressive title carrying the whole heading — no line
     * divider — and the rows under it. Rows land in at the reference dialogs'
     * spacing (4), and the extra 2 under the title separates heading from rows.
     */
    component SectionBlock: ColumnLayout {
        property alias title: sectionTitle.text
        spacing: 4
        Layout.fillWidth: true

        StyledText {
            id: sectionTitle
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: Appearance.font.variableAxes.title
            color: Appearance.colors.colOnLayer1
        }
    }

    /**
     * A slider in the same rounded card family as the ConfigSwitch rows, one
     * size up: the label where there is one, and the fat slider below. No
     * value chrome — the reading lives in the handle's tooltip.
     */
    component SliderCard: Rectangle {
        id: card
        property alias text: sliderName.text
        property alias from: sliderWidget.from
        property alias to: sliderWidget.to
        property alias value: sliderWidget.value
        property alias stopIndicatorValues: sliderWidget.stopIndicatorValues
        property alias tooltipContent: sliderWidget.tooltipContent
        signal moved()

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cardLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 16
                rightMargin: 16
            }
            spacing: 2

            StyledText {
                id: sliderName
                visible: text.length > 0
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }

            StyledSlider {
                id: sliderWidget
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.M
                onMoved: card.moved()
            }
        }
    }

    // ── Header (margins and typography matching WifiDialog/BluetoothDialog) ──
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Eye protection")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.title
            font.variableAxes: Appearance.font.variableAxes.title
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: Hyprsunset.temperatureActive
            onToggled: Hyprsunset.toggleTemperature(checked)
        }
    }

    SectionBlock {
        title: Translation.tr("Night Light")

        ConfigSwitch {
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "night_sight_auto"
            text: Translation.tr("Automatic")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }

        SliderCard {
            text: Translation.tr("Intensity")
            from: 6500
            to: 1200
            stopIndicatorValues: [5000, to]
            value: Config.options.light.night.colorTemperature
            tooltipContent: `${Math.round(value)}K`
            onMoved: Config.options.light.night.colorTemperature = value
        }
    }

    SectionBlock {
        title: Translation.tr("Anti-flashbang (experimental)")

        ConfigSwitch {
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "filter"
            text: Translation.tr("Content adjustment")
            checked: HyprlandAntiFlashbangShader.enabled
            onCheckedChanged: {
                if (checked) HyprlandAntiFlashbangShader.enable()
                else HyprlandAntiFlashbangShader.disable()
            }
            StyledToolTip {
                text: Translation.tr("<b>Dims screen content</b> as needed.<br><br>Pros: Immediately responsive<br>Cons: Expensive and can hurt color accuracy<br><br><i>Uses a Hyprland screen shader</i>")
            }
        }

        ConfigSwitch {
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "light_mode"
            text: Translation.tr("Brightness adjustment")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: {
                Config.options.light.antiFlashbang.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Adapts the <b>display (physical screen) brightness</b><br><br>Pros: Less expensive, retains colors<br>Cons: Not immediately responsive<br><br><i>Adjusts display brightness after each Hyprland IPC event</i>")
            }
        }
    }

    SectionBlock {
        title: Translation.tr("Brightness")

        SliderCard {
            value: root.brightnessMonitor.brightness
            onMoved: root.brightnessMonitor.setBrightness(value)
        }
    }

    SectionBlock {
        title: Translation.tr("Gamma")

        SliderCard {
            from: Hyprsunset.gammaLowerLimit / 100
            value: Hyprsunset.gamma / 100
            tooltipContent: `${Math.round(value * 100)}%`
            onMoved: Hyprsunset.setGamma(value * 100)
        }
    }

    // ── Bottom buttons (WifiDialog/VolumeDialog rhythm) ───────────────────────
    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
