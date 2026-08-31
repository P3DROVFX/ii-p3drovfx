import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
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
            text: Translation.tr("Privacy pill")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "shield_lock"
        title: Translation.tr("Indicator")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("The pill appears when an access starts, shows what is being used, then shrinks to a small dot that stays for as long as the access lasts.")
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable the privacy indicator")
            checked: Config.options.bar.privacyPill.enabled
            onCheckedChanged: Config.options.bar.privacyPill.enabled = checked
        }

        ConfigSwitch {
            enabled: Config.options.bar.privacyPill.enabled
            buttonIcon: "compress"
            text: Translation.tr("Shrink to a dot after showing the pill")
            checked: Config.options.bar.privacyPill.collapseToDot
            onCheckedChanged: Config.options.bar.privacyPill.collapseToDot = checked
        }

        ConfigSpinBox {
            enabled: Config.options.bar.privacyPill.enabled
                && Config.options.bar.privacyPill.collapseToDot
            icon: "timer"
            text: Translation.tr("Seconds before it shrinks")
            value: Math.round(Config.options.bar.privacyPill.expandDuration / 1000)
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: Config.options.bar.privacyPill.expandDuration = value * 1000
        }

        ConfigSwitch {
            enabled: Config.options.bar.privacyPill.enabled
            buttonIcon: "badge"
            text: Translation.tr("Name the apps in the popup")
            checked: Config.options.bar.privacyPill.showAppNames
            onCheckedChanged: Config.options.bar.privacyPill.showAppNames = checked
        }
    }

    ContentSection {
        icon: "sensors"
        title: Translation.tr("What triggers it")

        ConfigSwitch {
            buttonIcon: "photo_camera"
            text: Translation.tr("Camera")
            checked: Config.options.bar.privacyPill.watchCamera
            onCheckedChanged: Config.options.bar.privacyPill.watchCamera = checked
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Microphone")
            checked: Config.options.bar.privacyPill.watchMicrophone
            onCheckedChanged: Config.options.bar.privacyPill.watchMicrophone = checked
        }

        ConfigSwitch {
            buttonIcon: "screen_share"
            text: Translation.tr("Screen sharing")
            checked: Config.options.bar.privacyPill.watchScreen
            onCheckedChanged: Config.options.bar.privacyPill.watchScreen = checked
        }

        ConfigSwitch {
            buttonIcon: "location_on"
            text: Translation.tr("Location")
            checked: Config.options.bar.privacyPill.watchLocation
            onCheckedChanged: Config.options.bar.privacyPill.watchLocation = checked
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "warning"
            text: Translation.tr("Location is off by default. GeoClue reports only whether a position is in use, never which app asked, and it stays latched while the weather widget's GPS is enabled — so the pill would never go away.")
        }
    }

    ContentSection {
        icon: "filter_alt"
        title: Translation.tr("Exclusions")

        ConfigTextField {
            icon: "apps_outage"
            text: Translation.tr("Never report these apps")
            placeholderText: Translation.tr("Comma separated, for example: obs, zoom")
            inputText: Config.options.bar.privacyPill.ignoreApps
            onInputTextChanged: Config.options.bar.privacyPill.ignoreApps = inputText
        }
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Detection")

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Check interval (milliseconds)")
            value: Config.options.bar.privacyPill.pollInterval
            from: 400
            to: 5000
            stepSize: 100
            onValueChanged: Config.options.bar.privacyPill.pollInterval = value
        }
    }

    ContentSection {
        icon: "monitoring"
        title: Translation.tr("Right now")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    radius: Appearance.rounding.full
                    color: Privacy.active
                        ? Appearance.colors.colTertiary
                        : Appearance.colors.colOutlineVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Privacy.active
                        ? Translation.tr("%1 in use").arg(Privacy.summaryTitle())
                        : Translation.tr("Nothing is being accessed")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: !Privacy.available
                    text: Translation.tr("Probe offline")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
            }
        }
    }
}
